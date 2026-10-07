#!/usr/bin/env bash
# =============================================================================
# sync_mainframe_source.sh
#
# Maintainers: see repository contributors.
#
# Synchronizes exported mainframe source into a target Git repository.
#
# Replaces the manual process:
#   1. Copy files from SOURCE_BASE_DIR/<library> to TARGET_BASE_DIR/<library>
#      for every library listed in config/libraries.conf
#   2. Detect whether the copy introduced any changes in the target git repo
#   3. git add / git commit / git push (skipped when there are no changes)
#
# Invoked by: a scheduler, JCL, BPXBATCH, or an interactive shell session
#
# Usage:
#   bash sync_mainframe_source.sh
#   ./sync_mainframe_source.sh   (if it has executable permissions)
#
# Exit codes (mainframe COND-code style):
#   0  SUCCESS               - changes committed and pushed
#   4  SUCCESS_NO_CHANGES    - no changes detected, commit/push skipped
#   8  CONFIG_ERROR          - missing/invalid configuration
#   12 PROCESSING_ERROR      - source library missing or copy failure
#   16 GIT_ERROR             - git add/commit/push failure
#   20 FATAL_ERROR           - unexpected/unhandled error
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/logging.sh
source "${REPO_ROOT}/lib/logging.sh"
# shellcheck source=../lib/error_handling.sh
source "${REPO_ROOT}/lib/error_handling.sh"
# shellcheck source=../lib/file_ops.sh
source "${REPO_ROOT}/lib/file_ops.sh"
# shellcheck source=../lib/git_ops.sh
source "${REPO_ROOT}/lib/git_ops.sh"

JOB_NAME="sync_mainframe_source"

# Always source config/app_config.txt to get PROJECT_CONFIG, regardless of
# how this script was launched (JCL/BPXBATCH STDENV or a manual/interactive
# shell) or what may already be sitting in the calling shell's environment.
# This makes behavior independent of shell history - a leftover exported
# PROJECT_CONFIG from an earlier command can never silently override this.
log_info "app_config.txt location: ${REPO_ROOT}/config/app_config.txt"
if [[ -f "${REPO_ROOT}/config/app_config.txt" ]]; then
    # shellcheck source=../config/app_config.txt
    source "${REPO_ROOT}/config/app_config.txt"
fi
log_info "Values after sourcing app_config.txt: PROJECT_WORKSPACE='${PROJECT_WORKSPACE:-<unset>}' PROJECT_NAME='${PROJECT_NAME:-<unset>}' PROJECT_CONFIG='${PROJECT_CONFIG:-<unset>}'"

# Precedence (highest wins): -c flag > $PROJECT_CONFIG (set above from
# config/app_config.txt, points at the real untracked per-environment
# sync.env) > the tracked template (fallback, local testing only).
SYNC_ENV="${PROJECT_CONFIG:-${REPO_ROOT}/config/sync.env.template}"
LIBRARIES_CONF_OVERRIDE=""
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [-c config_file] [-l libraries_file] [-n] [-h]

  -c  Path to environment config file (default: PROJECT_CONFIG from
      config/app_config.txt, falling back to config/sync.env.template)
  -l  Path to libraries list file    (default: config/libraries.conf)
  -n  Dry run - copy and detect changes, but do not commit/push
  -h  Show this help message
EOF
}

while getopts ":c:l:nh" opt; do
    case "${opt}" in
        c) SYNC_ENV="${OPTARG}" ;;
        l) LIBRARIES_CONF_OVERRIDE="${OPTARG}" ;;
        n) DRY_RUN=true ;;
        h) usage; exit "${EXIT_SUCCESS}" ;;
        *) usage; exit "${EXIT_CONFIG_ERROR}" ;;
    esac
done
shift $((OPTIND - 1))

log_info "Resolved SYNC_ENV: ${SYNC_ENV}"
if [[ ! -f "${SYNC_ENV}" ]]; then
    echo "FATAL: configuration file not found: ${SYNC_ENV}" >&2
    exit "${EXIT_CONFIG_ERROR}"
fi
# shellcheck source=../config/sync.env.template
source "${SYNC_ENV}"
validate_git_ssh_paths || die "${EXIT_CONFIG_ERROR}" "GIT_BIN and SSH_BIN must be set and executable in ${SYNC_ENV}"

LIBRARIES_CONF="${LIBRARIES_CONF_OVERRIDE:-${REPO_ROOT}/config/libraries.conf}"

trap 'on_error ${LINENO} "${BASH_COMMAND}"' ERR
trap 'on_exit' EXIT

main() {
    init_logging "${LOG_DIR}" "${JOB_NAME}"
    rotate_logs "${LOG_DIR}" "${LOG_RETENTION_DAYS}" || log_warn "Log rotation encountered an issue (non-fatal), continuing"

    log_info "=========================================================="
    log_info "Starting ${JOB_NAME}"
    log_info "Source base : ${SOURCE_BASE_DIR}"
    log_info "Target base : ${TARGET_BASE_DIR}"
    log_info "Dry run     : ${DRY_RUN}"
    log_info "=========================================================="

    [[ -d "${SOURCE_BASE_DIR}" ]] || die "${EXIT_CONFIG_ERROR}" "Source base directory does not exist: ${SOURCE_BASE_DIR}"
    [[ -d "${TARGET_BASE_DIR}" ]] || die "${EXIT_CONFIG_ERROR}" "Target base directory does not exist: ${TARGET_BASE_DIR}"
    validate_git_repo "${TARGET_BASE_DIR}" || die "${EXIT_CONFIG_ERROR}" "Target directory is not a git repository: ${TARGET_BASE_DIR}"

    # Ensure this repo has an explicit local git identity BEFORE any commit
    # is made, so Rocket Git for z/OS doesn't fall back to auto-deriving one
    # from the OS username and hostname.
    ensure_git_identity "${TARGET_BASE_DIR}" "${GIT_AUTHOR_NAME}" "${GIT_AUTHOR_EMAIL}" || \
        die "${EXIT_GIT_ERROR}" "Unable to set git identity in ${TARGET_BASE_DIR}"

    # Sync local with remote BEFORE copying any files, so the working tree
    # is up to date and the eventual push is a clean fast-forward.
    git_pull_latest "${TARGET_BASE_DIR}" "${GIT_REMOTE}" "${GIT_BRANCH}" || \
        die "${EXIT_GIT_ERROR}" "Unable to sync ${TARGET_BASE_DIR} with ${GIT_REMOTE}/${GIT_BRANCH} before copying files"

    # Ensure .gitattributes/.gitignore exist in the target repo BEFORE any
    # library files are copied/added, so Rocket Git for z/OS's
    # zos-working-tree-encoding rules are in effect from the first `git add`.
    ensure_target_bootstrap_files "${TARGET_BASE_DIR}" "${REPO_ROOT}/config/target_repo_bootstrap" || \
        die "${EXIT_GIT_ERROR}" "Unable to bootstrap .gitattributes/.gitignore in ${TARGET_BASE_DIR}"

    local -a LIBRARY_NAMES=()
    mapfile -t LIBRARY_NAMES < <(load_libraries_config "${LIBRARIES_CONF}")
    [[ "${#LIBRARY_NAMES[@]}" -gt 0 ]] || die "${EXIT_CONFIG_ERROR}" "No libraries found in ${LIBRARIES_CONF}"
    log_info "Loaded ${#LIBRARY_NAMES[@]} libraries from ${LIBRARIES_CONF}"

    local copy_failures=0
    for lib in "${LIBRARY_NAMES[@]}"; do
        if ! copy_library "${lib}" "${SOURCE_BASE_DIR}" "${TARGET_BASE_DIR}"; then
            copy_failures=$((copy_failures + 1))
        fi
    done
    if [[ "${copy_failures}" -gt 0 ]]; then
        die "${EXIT_PROCESSING_ERROR}" "${copy_failures} of ${#LIBRARY_NAMES[@]} libraries failed to copy"
    fi

    if ! has_git_changes "${TARGET_BASE_DIR}" && ! has_unpushed_commits "${TARGET_BASE_DIR}" "${GIT_REMOTE}" "${GIT_BRANCH}"; then
        log_info "No changes detected in ${TARGET_BASE_DIR}. Skipping commit/push."
        exit "${EXIT_SUCCESS_NO_CHANGES}"
    fi

    local new_changes=false
    has_git_changes "${TARGET_BASE_DIR}" && new_changes=true

    if [[ "${new_changes}" == "true" ]]; then
        log_info "Changes detected in ${TARGET_BASE_DIR}"
    else
        log_info "No new file changes, but found commit(s) from a previous run not yet pushed to ${GIT_REMOTE}/${GIT_BRANCH} - retrying push"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run enabled - skipping git add/commit/push"
        exit "${EXIT_SUCCESS}"
    fi

    if [[ "${new_changes}" == "true" ]]; then
        local commit_message="${GIT_COMMIT_MESSAGE_PREFIX}: $(date '+%Y-%m-%d %H:%M:%S')"
        if ! git_add_commit_push "${TARGET_BASE_DIR}" "${commit_message}" "${GIT_REMOTE}" "${GIT_BRANCH}" \
                "${GIT_PUSH_RETRY_COUNT}" "${GIT_PUSH_RETRY_DELAY_SECONDS}"; then
            die "${EXIT_GIT_ERROR}" "git add/commit/push failed for ${TARGET_BASE_DIR}"
        fi
    else
        if ! git_push_with_retry "${TARGET_BASE_DIR}" "${GIT_REMOTE}" "${GIT_BRANCH}" \
                "${GIT_PUSH_RETRY_COUNT}" "${GIT_PUSH_RETRY_DELAY_SECONDS}"; then
            die "${EXIT_GIT_ERROR}" "git push failed for previously committed changes in ${TARGET_BASE_DIR}"
        fi
    fi

    log_info "${JOB_NAME} completed successfully."
    exit "${EXIT_SUCCESS}"
}

main "$@"
