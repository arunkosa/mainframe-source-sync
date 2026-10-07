#!/usr/bin/env bash
# =============================================================================
# logging.sh
#
# Maintainers: see repository contributors.
#
# Enterprise-style leveled, timestamped logging with per-run log files and
# retention-based cleanup.
#
# Exposes:
#   init_logging <log_dir> <job_name>
#   log_info / log_warn / log_error / log_debug <message>
#   rotate_logs <log_dir> <retention_days>
# =============================================================================

LOG_FILE=""
DEBUG="${DEBUG:-false}"

# init_logging <log_dir> <job_name>
# Creates <log_dir> if needed and opens a timestamped log file for this run.
init_logging() {
    local log_dir="$1"
    local job_name="$2"

    if ! mkdir -p "${log_dir}" 2>/dev/null; then
        echo "FATAL: unable to create log directory: ${log_dir}" >&2
        exit "${EXIT_CONFIG_ERROR:-8}"
    fi

    LOG_FILE="${log_dir}/${job_name}_$(date '+%Y%m%d_%H%M%S').log"
    if ! : > "${LOG_FILE}"; then
        echo "FATAL: unable to write to log file: ${LOG_FILE}" >&2
        exit "${EXIT_CONFIG_ERROR:-8}"
    fi
}

# _log <level> <message...>
_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="${timestamp} [${level}] [PID:$$] ${message}"

    if [[ -n "${LOG_FILE}" ]]; then
        echo "${line}" >> "${LOG_FILE}"
    fi

    if [[ "${level}" == "ERROR" || "${level}" == "WARN" ]]; then
        echo "${line}" >&2
    else
        echo "${line}"
    fi
}

log_info()  { _log "INFO"  "$*"; }
log_warn()  { _log "WARN"  "$*"; }
log_error() { _log "ERROR" "$*"; }
log_debug() { [[ "${DEBUG}" == "true" ]] && _log "DEBUG" "$*"; return 0; }

# rotate_logs <log_dir> <retention_days>
# Deletes *.log files in <log_dir> older than <retention_days> days.
# Uses only POSIX find options (no -maxdepth) for portability to z/OS USS's
# native find, which does not support GNU find extensions.
rotate_logs() {
    local log_dir="$1"
    local retention_days="$2"
    find "${log_dir}" -name '*.log' -type f -mtime "+${retention_days}" -exec rm -f {} \; 2>/dev/null
    log_debug "Log rotation complete (retention: ${retention_days} days)"
}
