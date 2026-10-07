#!/usr/bin/env bash
# Smoke tests for lib/logging.sh
#
# Maintainers: see repository contributors.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/logging.sh"

TMP_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_LOG_DIR}"' EXIT

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

init_logging "${TMP_LOG_DIR}" "test_job"
assert "log file was created" '[[ -f "${LOG_FILE}" ]]'

log_info "hello world"
assert "log_info wrote to log file" 'grep -q "hello world" "${LOG_FILE}"'
assert "log_info line has INFO level tag" 'grep -q "\[INFO\]" "${LOG_FILE}"'

log_error "boom"
assert "log_error wrote to log file" 'grep -q "boom" "${LOG_FILE}"'
assert "log_error line has ERROR level tag" 'grep -q "\[ERROR\]" "${LOG_FILE}"'

echo "----"
echo "Results: ${pass} passed, ${fail} failed"
exit $(( fail > 0 ? 1 : 0 ))
