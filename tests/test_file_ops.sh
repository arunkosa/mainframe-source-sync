#!/usr/bin/env bash
# Smoke tests for lib/file_ops.sh
#
# Maintainers: see repository contributors.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/logging.sh"
source "${REPO_ROOT}/lib/file_ops.sh"

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

# --- load_libraries_config ---
CONF_FILE="${TMP_DIR}/libraries.conf"
cat > "${CONF_FILE}" <<EOF
# comment line
LIB_ONE

LIB_TWO
   # indented comment
LIB_THREE
EOF

mapfile -t libs < <(load_libraries_config "${CONF_FILE}")
assert "parsed 3 libraries" '[[ "${#libs[@]}" -eq 3 ]]'
assert "first library is LIB_ONE" '[[ "${libs[0]}" == "LIB_ONE" ]]'
assert "third library is LIB_THREE" '[[ "${libs[2]}" == "LIB_THREE" ]]'

# --- copy_library ---
SRC_BASE="${TMP_DIR}/src"
TGT_BASE="${TMP_DIR}/tgt"
mkdir -p "${SRC_BASE}/MYLIB"
echo "member data" > "${SRC_BASE}/MYLIB/MEMBER1"

copy_library "MYLIB" "${SRC_BASE}" "${TGT_BASE}"
copy_rc=$?
assert "copy_library returns success" '[[ ${copy_rc} -eq 0 ]]'
assert "copy_library copied file" '[[ -f "${TGT_BASE}/MYLIB/MEMBER1" ]]'

copy_library "MISSING_LIB" "${SRC_BASE}" "${TGT_BASE}"
missing_lib_rc=$?
assert "copy_library returns failure for missing source" '[[ ${missing_lib_rc} -ne 0 ]]'

echo "----"
echo "Results: ${pass} passed, ${fail} failed"
exit $(( fail > 0 ? 1 : 0 ))
