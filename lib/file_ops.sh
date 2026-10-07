#!/usr/bin/env bash
# =============================================================================
# file_ops.sh
#
# Maintainers: see repository contributors.
#
# Configuration loading and file-copy / change-detection helpers.
# =============================================================================

# load_libraries_config <config_file>
# Prints one library name per line (comments and blank lines stripped).
load_libraries_config() {
    local config_file="$1"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Libraries configuration file not found: ${config_file}"
        return 1
    fi

    grep -v '^[[:space:]]*#' "${config_file}" | grep -v '^[[:space:]]*$' | sed 's/[[:space:]]*$//'
}

# copy_library <library_name> <source_base_dir> <target_base_dir>
# Copies all files for one library from source to target, preserving
# permissions/timestamps. Returns non-zero on failure.
copy_library() {
    local library="$1"
    local source_base="$2"
    local target_base="$3"
    local source_dir="${source_base}/${library}"
    local target_dir="${target_base}/${library}"

    if [[ ! -d "${source_dir}" ]]; then
        log_error "Source library directory not found, skipping: ${source_dir}"
        return 1
    fi

    if ! mkdir -p "${target_dir}"; then
        log_error "Unable to create target directory: ${target_dir}"
        return 1
    fi

    if ! cp -pR "${source_dir}/." "${target_dir}/"; then
        log_error "Copy failed: ${source_dir} -> ${target_dir}"
        return 1
    fi

    log_info "Copied library ${library} (${source_dir} -> ${target_dir})"
    return 0
}
