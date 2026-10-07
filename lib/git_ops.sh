#!/usr/bin/env bash
# =============================================================================
# git_ops.sh
#
# Maintainers: see repository contributors.
#
# Git plumbing: repo validation, change detection, and add/commit/push with
# retry on push failures.
# =============================================================================

# Require explicit Git/SSH binary paths in the environment config.
# These paths must be set in sync.env and must be executable. No fallback
# is used because the JCL/BPXBATCH environment is not guaranteed to have
# either binary on PATH.
GIT_BIN="${GIT_BIN:-}"
SSH_BIN="${SSH_BIN:-}"

validate_git_ssh_paths() {
    local errors=0

    if [[ -z "${GIT_BIN}" ]]; then
        echo "FATAL: GIT_BIN is not set in sync.env" >&2
        errors=1
    elif [[ ! -x "${GIT_BIN}" ]]; then
        echo "FATAL: GIT_BIN is not executable: ${GIT_BIN}" >&2
        errors=1
    fi

    if [[ -z "${SSH_BIN}" ]]; then
        echo "FATAL: SSH_BIN is not set in sync.env" >&2
        errors=1
    elif [[ ! -x "${SSH_BIN}" ]]; then
        echo "FATAL: SSH_BIN is not executable: ${SSH_BIN}" >&2
        errors=1
    fi

    return $(( errors == 0 ? 0 : 1 ))
}

git_cmd() {
    "${GIT_BIN}" "$@"
}

# configure_git_push_trace_env
# Optional deep tracing for push diagnostics. Enable by setting
# GIT_PUSH_TRACE_ENABLED=true in sync.env. Trace output is written to
# GIT_PUSH_TRACE_LOG (default /tmp/git_push_trace.log).
configure_git_push_trace_env() {
    local enabled="${GIT_PUSH_TRACE_ENABLED:-false}"
    if [[ "${enabled}" != "true" ]]; then
        return 0
    fi

    local trace_log="${GIT_PUSH_TRACE_LOG:-/tmp/git_push_trace.log}"
    local trace_dir
    trace_dir="$(dirname "${trace_log}")"
    mkdir -p "${trace_dir}" 2>/dev/null || true

    export GIT_TRACE="${GIT_TRACE:-1}"
    export GIT_TRACE_SETUP="${GIT_TRACE_SETUP:-1}"
    export GIT_TRACE_PACKET="${GIT_TRACE_PACKET:-1}"
    export GIT_TRACE_PERFORMANCE="${GIT_TRACE_PERFORMANCE:-1}"

    log_info "Git push trace enabled; push stderr/stdout will be captured in ${trace_log}"
}

# configure_git_ssh_transport
# Some Git builds (including older/ported variants) do not reliably honor
# command-string based SSH launch settings and may try to exec the entire
# string as a path. To avoid that, create a small wrapper script and point
# GIT_SSH at it so Git executes a plain path.
configure_git_ssh_transport() {
    local wrapper_path="${GIT_SSH_WRAPPER_PATH:-/tmp/git_ssh_wrapper.sh}"
    local wrapper_dir
    wrapper_dir="$(dirname "${wrapper_path}")"
    mkdir -p "${wrapper_dir}" 2>/dev/null || true

    cat >"${wrapper_path}" <<EOF
#!/bin/sh
exec "${SSH_BIN}" \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=4 \
  -o TCPKeepAlive=yes \
    "\$@"
EOF
    chmod 700 "${wrapper_path}" 2>/dev/null || true

    unset GIT_SSH_COMMAND
    export GIT_SSH="${wrapper_path}"
}

# validate_git_repo <dir>
validate_git_repo() {
    local dir="$1"
    local git_output
    if git_output=$(git_cmd -C "${dir}" rev-parse --is-inside-work-tree 2>&1); then
        return 0
    fi
    log_error "git rev-parse --is-inside-work-tree failed for ${dir} using ${GIT_BIN}: ${git_output}"
    return 1
}

# has_git_changes <dir>
# Returns 0 (true) if there are staged/unstaged/untracked changes.
has_git_changes() {
    local dir="$1"
    [[ -n "$(git_cmd -C "${dir}" status --porcelain 2>/dev/null)" ]]
}

# has_unpushed_commits <dir> <remote> <branch>
# Returns 0 (true) if the local branch has commits not yet on
# <remote>/<branch>. Catches the case where a previous run's `git commit`
# succeeded but the subsequent `git push` failed after exhausting retries
# - that commit sits locally, safely, but has_git_changes() alone can't
# see it (it only looks at working-tree/index status, not commit history
# vs the remote), so a later run with no NEW file changes would otherwise
# silently skip commit/push forever and strand that commit unpushed.
# Relies on the remote-tracking ref already being current from an earlier
# git_pull_latest call in this run - does not re-fetch.
has_unpushed_commits() {
    local dir="$1"
    local remote="$2"
    local branch="$3"

    local ahead
    ahead=$(git_cmd -C "${dir}" rev-list --count "${remote}/${branch}..HEAD" 2>/dev/null) || return 1
    [[ "${ahead}" -gt 0 ]]
}

# git_pull_latest <dir> <remote> <branch>
# Best practice: always sync the local branch with the remote before
# generating any new commits. Uses fetch + fast-forward-only merge rather
# than a plain `git pull` so that a real divergence (e.g. someone else
# pushed directly to the branch) fails loudly instead of silently creating
# a merge commit or masking a conflict. Run this BEFORE copying files from
# the mainframe export, so the working tree is clean/up to date first.
git_pull_latest() {
    local dir="$1"
    local remote="$2"
    local branch="$3"

    if ! git_cmd -C "${dir}" fetch "${remote}" "${branch}" >>"${LOG_FILE:-/dev/stderr}" 2>&1; then
        log_error "git fetch failed for ${remote}/${branch} in ${dir} using ${GIT_BIN}"
        return 1
    fi

    if ! git_cmd -C "${dir}" merge --ff-only "${remote}/${branch}" >>"${LOG_FILE:-/dev/stderr}" 2>&1; then
        log_error "git merge --ff-only failed for ${remote}/${branch} in ${dir} using ${GIT_BIN} - local and remote have diverged, manual resolution required"
        return 1
    fi

    log_info "Local branch is up to date with ${remote}/${branch}"
    return 0
}

# ensure_target_bootstrap_files <target_dir> <bootstrap_source_dir>
# Copies .gitattributes/.gitignore from <bootstrap_source_dir> into
# <target_dir> if either is missing there, then commits them as their own
# standalone commit (best practice: .gitattributes must be present before
# any tagged/EBCDIC source files are added, otherwise Rocket Git for z/OS
# rejects `git add` with "file is tagged, set corresponding
# zos-working-tree-encoding attribute"). Idempotent - a no-op once both
# files already exist in the target repo. Run this BEFORE copying any
# library files into the target repo.
ensure_target_bootstrap_files() {
    local target_dir="$1"
    local bootstrap_dir="$2"
    local -a added_files=()

    local f
    for f in .gitattributes .gitignore; do
        if [[ ! -f "${target_dir}/${f}" && -f "${bootstrap_dir}/${f}" ]]; then
            if ! cp "${bootstrap_dir}/${f}" "${target_dir}/${f}"; then
                log_error "Unable to copy bootstrap file ${f} into ${target_dir}"
                return 1
            fi
            added_files+=("${f}")
            log_info "Bootstrapped ${f} into ${target_dir}"
        fi
    done

    if [[ "${#added_files[@]}" -eq 0 ]]; then
        return 0
    fi

    if ! git_cmd -C "${target_dir}" add "${added_files[@]}"; then
        log_error "Unable to stage bootstrap files in ${target_dir}"
        return 1
    fi

    if ! git_cmd -C "${target_dir}" commit -m "Bootstrap: add ${added_files[*]}" >>"${LOG_FILE:-/dev/stderr}" 2>&1; then
        log_error "Unable to commit bootstrap files in ${target_dir}"
        return 1
    fi

    log_info "Committed bootstrap files: ${added_files[*]}"
    return 0
}

# ensure_git_identity <target_dir> <author_name> <author_email>
# Sets git user.name/user.email at the LOCAL (repo-level) git config for
# <target_dir> if either is not already set there. Without this, Rocket
# Git for z/OS auto-derives an identity from the OS username/hostname
# (for example a host-derived job-user identity) and
# prints a warning on every single commit. Idempotent - a no-op once both
# values are already configured locally. Run this BEFORE the first git
# commit in the target repo.
ensure_git_identity() {
    local target_dir="$1"
    local author_name="$2"
    local author_email="$3"

    local current_name current_email
    current_name=$(git_cmd -C "${target_dir}" config --local user.name 2>/dev/null || true)
    current_email=$(git_cmd -C "${target_dir}" config --local user.email 2>/dev/null || true)

    if [[ -z "${current_name}" ]]; then
        if ! git_cmd -C "${target_dir}" config --local user.name "${author_name}"; then
            log_error "Unable to set git user.name in ${target_dir}"
            return 1
        fi
        log_info "Set git user.name=${author_name} in ${target_dir}"
    fi

    if [[ -z "${current_email}" ]]; then
        if ! git_cmd -C "${target_dir}" config --local user.email "${author_email}"; then
            log_error "Unable to set git user.email in ${target_dir}"
            return 1
        fi
        log_info "Set git user.email=${author_email} in ${target_dir}"
    fi

    return 0
}

# git_push_with_retry <dir> <remote> <branch> [retry_count] [retry_delay]
# Retries `git push` on failure (handles transient network issues, e.g.
# an SSH connection dropped by an idle-timing-out firewall/NAT). Also sets
# SSH keepalives so those drops happen less often in the first place.
git_push_with_retry() {
    local dir="$1"
    local remote="$2"
    local branch="$3"
    local retry_count="${4:-3}"
    local retry_delay="${5:-10}"

    # SSH keepalives: without these, a long-lived push over SSH can be
    # silently dropped mid-transfer by an intervening firewall/NAT/proxy
    # that considers the connection idle (observed on z/OS as "Connection
    # to github.com closed by remote host" / "unexpected disconnect while
    # reading sideband packet" / CEE5213S SIGPIPE). Sending periodic
    # keepalive packets prevents middleboxes from killing the connection
    # and lets the client detect a truly dead connection faster. Use a
    # wrapper script via GIT_SSH so Git always executes a plain file path.
    configure_git_ssh_transport

    configure_git_push_trace_env
    local trace_enabled="${GIT_PUSH_TRACE_ENABLED:-false}"
    local trace_log="${GIT_PUSH_TRACE_LOG:-/tmp/git_push_trace.log}"

    local attempt=1
    while (( attempt <= retry_count )); do
        log_info "Using GIT_SSH wrapper path: ${GIT_SSH:-<unset>}"
        if [[ -n "${GIT_SSH:-}" && -e "${GIT_SSH}" ]]; then
            local wrapper_ls
            if wrapper_ls=$(ls -ld "${GIT_SSH}" 2>&1); then
                log_info "GIT_SSH wrapper details: ${wrapper_ls}"
            else
                log_warn "Unable to stat GIT_SSH wrapper ${GIT_SSH}: ${wrapper_ls}"
            fi

            if [[ -x "${GIT_SSH}" ]]; then
                log_info "GIT_SSH wrapper is executable"
            else
                log_warn "GIT_SSH wrapper is NOT executable: ${GIT_SSH}"
            fi
        else
            log_warn "GIT_SSH wrapper path does not exist: ${GIT_SSH:-<unset>}"
        fi

        local push_log_target="${LOG_FILE:-/dev/stderr}"
        if [[ "${trace_enabled}" == "true" ]]; then
            push_log_target="${trace_log}"
            {
                echo "==== git push attempt ${attempt} at $(date '+%Y-%m-%d %H:%M:%S') ===="
                echo "GIT_BIN=${GIT_BIN}"
                echo "SSH_BIN=${SSH_BIN}"
                echo "GIT_SSH=${GIT_SSH:-<unset>}"
            } >>"${trace_log}"
        fi

        if git_cmd -C "${dir}" push "${remote}" "${branch}" >>"${push_log_target}" 2>&1; then
            log_info "git push succeeded (attempt ${attempt}) to ${remote}/${branch} using ${GIT_BIN}"
            return 0
        fi

        if [[ "${trace_enabled}" == "true" ]]; then
            log_warn "git push trace attempt ${attempt} failed; see ${trace_log}"
        fi
        log_warn "git push failed (attempt ${attempt}/${retry_count}) using ${GIT_BIN}; retrying in ${retry_delay}s"
        sleep "${retry_delay}"
        attempt=$(( attempt + 1 ))
    done

    log_error "git push failed after ${retry_count} attempts to ${remote}/${branch} using ${GIT_BIN}"
    return 1
}

# git_add_commit_push <dir> <commit_message> <remote> <branch> [retry_count] [retry_delay]
git_add_commit_push() {
    local dir="$1"
    local commit_message="$2"
    local remote="$3"
    local branch="$4"
    local retry_count="${5:-3}"
    local retry_delay="${6:-10}"

    if ! git_cmd -C "${dir}" add -A; then
        log_error "git add failed in ${dir}"
        return 1
    fi
    log_info "git add completed in ${dir}"

    if ! git_cmd -C "${dir}" commit -m "${commit_message}" >>"${LOG_FILE:-/dev/stderr}" 2>&1; then
        log_error "git commit failed in ${dir}"
        return 1
    fi
    log_info "git commit completed: ${commit_message}"

    git_push_with_retry "${dir}" "${remote}" "${branch}" "${retry_count}" "${retry_delay}"
}
