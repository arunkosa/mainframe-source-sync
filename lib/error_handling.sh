#!/usr/bin/env bash
# =============================================================================
# error_handling.sh
#
# Maintainers: see repository contributors.
#
# Shared exit-code constants, die() helper, and ERR/EXIT trap handlers.
#
# Exit codes mirror mainframe COND-code conventions (0/4/8/12/16) so
# downstream JCL steps can branch on the return code, e.g.:
#   //NEXTSTEP EXEC PGM=...,COND=(4,LT,SYNCSTEP)
# =============================================================================

readonly EXIT_SUCCESS=0
readonly EXIT_SUCCESS_NO_CHANGES=4
readonly EXIT_CONFIG_ERROR=8
readonly EXIT_PROCESSING_ERROR=12
readonly EXIT_GIT_ERROR=16
readonly EXIT_FATAL_ERROR=20

# Bash's built-in SECONDS variable auto-increments once per second since it
# was last assigned. Used instead of `date +%s` because z/OS USS's native
# date command does not support the GNU epoch-seconds format specifier.
SECONDS=0

# die <exit_code> <message>
# Logs an error and terminates the script immediately with the given code.
die() {
    local exit_code="$1"
    shift
    log_error "$*"
    exit "${exit_code}"
}

# on_error <line_no> <failed_command>
# Invoked via: trap 'on_error ${LINENO} "${BASH_COMMAND}"' ERR
# Catches any command failure NOT explicitly handled via die().
on_error() {
    local exit_status=$?
    local line_no="$1"
    local failed_command="$2"
    log_error "Unhandled error at line ${line_no}: '${failed_command}' exited with status ${exit_status}"
    exit "${EXIT_FATAL_ERROR}"
}

# on_exit
# Invoked via: trap on_exit EXIT
# Always runs on script termination; logs the final result and duration
# without altering the exit code already in effect.
on_exit() {
    local exit_code=$?
    local duration="${SECONDS}"
    case "${exit_code}" in
        "${EXIT_SUCCESS}")            log_info  "Job finished. RC=${exit_code} (SUCCESS). Duration=${duration}s" ;;
        "${EXIT_SUCCESS_NO_CHANGES}") log_info  "Job finished. RC=${exit_code} (SUCCESS - NO CHANGES). Duration=${duration}s" ;;
        *)                            log_error "Job finished. RC=${exit_code} (FAILURE). Duration=${duration}s" ;;
    esac
}
