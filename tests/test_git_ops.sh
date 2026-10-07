#!/usr/bin/env bash
# Smoke tests for lib/git_ops.sh
#
# Maintainers: see repository contributors.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/logging.sh"
source "${REPO_ROOT}/lib/git_ops.sh"

GIT_BIN="${GIT_BIN:-}"
git_cmd() {
    "${GIT_BIN}" "$@"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
init_logging "${TMP_DIR}/logs" "test_job"

pass=0
fail=0
assert() {
    local description="$1"
    local condition="$2"
    if eval "${condition}"; then
        echo "PASS: ${description}"
        pass=$((pass + 1))
    else
        echo "FAIL: ${description}"
        fail=$((fail + 1))
    fi
}

# --- explicit path validation ---
GIT_BIN=""
SSH_BIN=""
validate_git_ssh_paths
missing_path_rc=$?
assert "validate_git_ssh_paths fails when paths are empty" '[[ ${missing_path_rc} -ne 0 ]]'

GIT_BIN="$(command -v git)"
SSH_BIN="$(command -v ssh)"

REPO_DIR="${TMP_DIR}/repo"
mkdir -p "${REPO_DIR}"
git_cmd -C "${REPO_DIR}" init -q -b main
git_cmd -C "${REPO_DIR}" config user.email "test@example.com"
git_cmd -C "${REPO_DIR}" config user.name "Test User"

validate_git_repo "${REPO_DIR}"
validate_rc=$?
assert "validate_git_repo succeeds for a real repo" '[[ ${validate_rc} -eq 0 ]]'

validate_git_repo "${TMP_DIR}"
validate_nonrepo_rc=$?
assert "validate_git_repo fails for a non-repo dir" '[[ ${validate_nonrepo_rc} -ne 0 ]]'

echo "one" > "${REPO_DIR}/file.txt"
has_git_changes "${REPO_DIR}"
changes_rc=$?
assert "has_git_changes detects untracked file" '[[ ${changes_rc} -eq 0 ]]'

git_cmd -C "${REPO_DIR}" add -A
git_cmd -C "${REPO_DIR}" commit -q -m "initial commit"
has_git_changes "${REPO_DIR}"
no_changes_rc=$?
assert "has_git_changes is false after commit" '[[ ${no_changes_rc} -ne 0 ]]'

# --- git_add_commit_push end-to-end against a local bare "remote" ---
BARE_REMOTE="${TMP_DIR}/remote.git"
git_cmd init -q --bare "${BARE_REMOTE}"
git_cmd -C "${REPO_DIR}" remote add origin "${BARE_REMOTE}"
git_cmd -C "${REPO_DIR}" push -q -u origin main >/dev/null 2>&1
# Point the bare remote's HEAD at main so `git clone` checks it out by
# default (a fresh --bare repo's HEAD may default to master/whatever
# init.defaultBranch is, which never received a push).
git_cmd -C "${BARE_REMOTE}" symbolic-ref HEAD refs/heads/main

echo "two" > "${REPO_DIR}/file2.txt"
git_add_commit_push "${REPO_DIR}" "test commit" "origin" "main" 1 1
commit_push_rc=$?
assert "git_add_commit_push succeeds end-to-end" '[[ ${commit_push_rc} -eq 0 ]]'

# --- git_pull_latest: fast-forward success case ---
# A second clone of the same remote pushes a commit; the first clone should
# be able to fast-forward onto it.
CLONE_DIR="${TMP_DIR}/clone"
git_cmd clone -q "${BARE_REMOTE}" "${CLONE_DIR}"
git_cmd -C "${CLONE_DIR}" config user.email "test@example.com"
git_cmd -C "${CLONE_DIR}" config user.name "Test User"
echo "from clone" > "${CLONE_DIR}/file3.txt"
git_cmd -C "${CLONE_DIR}" add -A
git_cmd -C "${CLONE_DIR}" commit -q -m "commit from second clone"
git_cmd -C "${CLONE_DIR}" push -q origin main

git_pull_latest "${REPO_DIR}" "origin" "main"
pull_ff_rc=$?
assert "git_pull_latest fast-forwards cleanly" '[[ ${pull_ff_rc} -eq 0 ]]'
assert "git_pull_latest brought in the remote file" '[[ -f "${REPO_DIR}/file3.txt" ]]'

# --- git_pull_latest: diverged history failure case ---
# Both REPO_DIR and CLONE_DIR now commit different changes to the same
# already-pushed file without pulling first - REPO_DIR's fetch+ff-only
# merge should fail loudly rather than silently merging/rebasing.
echo "local change" > "${REPO_DIR}/file3.txt"
git_cmd -C "${REPO_DIR}" add -A
git_cmd -C "${REPO_DIR}" commit -q -m "diverging local commit"

echo "remote change" > "${CLONE_DIR}/file3.txt"
git_cmd -C "${CLONE_DIR}" add -A
git_cmd -C "${CLONE_DIR}" commit -q -m "diverging remote commit"
git_cmd -C "${CLONE_DIR}" push -q origin main

git_pull_latest "${REPO_DIR}" "origin" "main"
pull_diverged_rc=$?
assert "git_pull_latest fails on diverged history instead of auto-merging" '[[ ${pull_diverged_rc} -ne 0 ]]'

# --- ensure_target_bootstrap_files ---
BOOTSTRAP_SRC="${TMP_DIR}/bootstrap_src"
mkdir -p "${BOOTSTRAP_SRC}"
echo "*.ddl zos-working-tree-encoding=IBM-1047" > "${BOOTSTRAP_SRC}/.gitattributes"
echo ".DS_Store" > "${BOOTSTRAP_SRC}/.gitignore"

BOOTSTRAP_REPO_DIR="${TMP_DIR}/bootstrap_repo"
mkdir -p "${BOOTSTRAP_REPO_DIR}"
git_cmd -C "${BOOTSTRAP_REPO_DIR}" init -q -b main
git_cmd -C "${BOOTSTRAP_REPO_DIR}" config user.email "test@example.com"
git_cmd -C "${BOOTSTRAP_REPO_DIR}" config user.name "Test User"
echo "seed" > "${BOOTSTRAP_REPO_DIR}/seed.txt"
git_cmd -C "${BOOTSTRAP_REPO_DIR}" add -A
git_cmd -C "${BOOTSTRAP_REPO_DIR}" commit -q -m "seed commit"

ensure_target_bootstrap_files "${BOOTSTRAP_REPO_DIR}" "${BOOTSTRAP_SRC}"
bootstrap_rc=$?
assert "ensure_target_bootstrap_files succeeds" '[[ ${bootstrap_rc} -eq 0 ]]'
assert "ensure_target_bootstrap_files copies .gitattributes" '[[ -f "${BOOTSTRAP_REPO_DIR}/.gitattributes" ]]'
assert "ensure_target_bootstrap_files copies .gitignore" '[[ -f "${BOOTSTRAP_REPO_DIR}/.gitignore" ]]'
has_git_changes "${BOOTSTRAP_REPO_DIR}"
bootstrap_committed_rc=$?
assert "ensure_target_bootstrap_files commits the bootstrap files" '[[ ${bootstrap_committed_rc} -ne 0 ]]'

bootstrap_commit_count_before="$(git_cmd -C "${BOOTSTRAP_REPO_DIR}" rev-list --count HEAD)"
ensure_target_bootstrap_files "${BOOTSTRAP_REPO_DIR}" "${BOOTSTRAP_SRC}"
bootstrap_rerun_rc=$?
bootstrap_commit_count_after="$(git_cmd -C "${BOOTSTRAP_REPO_DIR}" rev-list --count HEAD)"
assert "ensure_target_bootstrap_files is idempotent (no new commit)" \
    '[[ ${bootstrap_rerun_rc} -eq 0 && "${bootstrap_commit_count_before}" -eq "${bootstrap_commit_count_after}" ]]'

# --- ensure_git_identity ---
IDENTITY_REPO_DIR="${TMP_DIR}/identity_repo"
mkdir -p "${IDENTITY_REPO_DIR}"
git_cmd -C "${IDENTITY_REPO_DIR}" init -q -b main

ensure_git_identity "${IDENTITY_REPO_DIR}" "Mainframe Source Sync" "maintainer@example.com"
identity_rc=$?
assert "ensure_git_identity succeeds" '[[ ${identity_rc} -eq 0 ]]'
identity_name="$(git_cmd -C "${IDENTITY_REPO_DIR}" config --local user.name)"
identity_email="$(git_cmd -C "${IDENTITY_REPO_DIR}" config --local user.email)"
assert "ensure_git_identity sets user.name" '[[ "${identity_name}" == "Mainframe Source Sync" ]]'
assert "ensure_git_identity sets user.email" '[[ "${identity_email}" == "maintainer@example.com" ]]'

# Rerun with different values - should NOT overwrite an already-set identity
ensure_git_identity "${IDENTITY_REPO_DIR}" "Someone Else" "someone.else@example.com"
identity_rerun_rc=$?
identity_name_after="$(git_cmd -C "${IDENTITY_REPO_DIR}" config --local user.name)"
assert "ensure_git_identity does not overwrite an existing identity" \
    '[[ ${identity_rerun_rc} -eq 0 && "${identity_name_after}" == "Mainframe Source Sync" ]]'

# --- has_unpushed_commits ---
UNPUSHED_REMOTE="${TMP_DIR}/unpushed_remote.git"
git_cmd init -q --bare "${UNPUSHED_REMOTE}"

UNPUSHED_REPO_DIR="${TMP_DIR}/unpushed_repo"
mkdir -p "${UNPUSHED_REPO_DIR}"
git_cmd -C "${UNPUSHED_REPO_DIR}" init -q -b main
git_cmd -C "${UNPUSHED_REPO_DIR}" config user.email "test@example.com"
git_cmd -C "${UNPUSHED_REPO_DIR}" config user.name "Test User"
git_cmd -C "${UNPUSHED_REPO_DIR}" remote add origin "${UNPUSHED_REMOTE}"
echo "seed" > "${UNPUSHED_REPO_DIR}/seed.txt"
git_cmd -C "${UNPUSHED_REPO_DIR}" add -A
git_cmd -C "${UNPUSHED_REPO_DIR}" commit -q -m "seed commit"
git_cmd -C "${UNPUSHED_REPO_DIR}" push -q -u origin main
git_cmd -C "${UNPUSHED_REMOTE}" symbolic-ref HEAD refs/heads/main

has_unpushed_commits "${UNPUSHED_REPO_DIR}" "origin" "main"
unpushed_none_rc=$?
assert "has_unpushed_commits is false right after a push" '[[ ${unpushed_none_rc} -ne 0 ]]'

echo "committed but not pushed" > "${UNPUSHED_REPO_DIR}/file4.txt"
git_cmd -C "${UNPUSHED_REPO_DIR}" add -A
git_cmd -C "${UNPUSHED_REPO_DIR}" commit -q -m "commit without pushing"
has_unpushed_commits "${UNPUSHED_REPO_DIR}" "origin" "main"
unpushed_some_rc=$?
assert "has_unpushed_commits detects a commit not yet pushed" '[[ ${unpushed_some_rc} -eq 0 ]]'

git_cmd -C "${UNPUSHED_REPO_DIR}" push -q origin main
has_unpushed_commits "${UNPUSHED_REPO_DIR}" "origin" "main"
unpushed_after_push_rc=$?
assert "has_unpushed_commits is false again after pushing" '[[ ${unpushed_after_push_rc} -ne 0 ]]'

echo "----"
echo "Results: ${pass} passed, ${fail} failed"
exit $(( fail > 0 ? 1 : 0 ))
