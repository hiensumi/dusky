#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: clean-uwsm-config.sh
# Description: Automates the cleanup of UWSM hardware/GPU configs.
#              Hardened for Arch Linux/Hyprland ecosystems.
# -----------------------------------------------------------------------------

# --- 1. Strict Mode ---
set -euo pipefail
IFS=$'\n\t'

# --- 2. TTY-Aware Color Definitions ---
if [[ -t 1 ]]; then
    readonly C_INFO=$'\033[1;34m'    # Bold Blue
    readonly C_SUCCESS=$'\033[1;32m' # Bold Green
    readonly C_RESET_OUT=$'\033[0m'
else
    readonly C_INFO='' C_SUCCESS='' C_RESET_OUT=''
fi

if [[ -t 2 ]]; then
    readonly C_ERR=$'\033[1;31m'     # Bold Red
    readonly C_RESET_ERR=$'\033[0m'
else
    readonly C_ERR='' C_RESET_ERR=''
fi

# --- 3. Logging Utilities ---
log_info()    { printf "%s[INFO]%s %s\n" "${C_INFO}" "${C_RESET_OUT}" "$*"; }
log_success() { printf "%s[OK]%s   %s\n" "${C_SUCCESS}" "${C_RESET_OUT}" "$*"; }
log_err()     { printf "%s[ERR]%s  %s\n" "${C_ERR}" "${C_RESET_ERR}" "$*" >&2; }

# --- 4. Signal Trapping ---
cleanup() {
    local sig=$?
    if (( sig > 128 )); then
        log_err "Script interrupted by signal (Code: $sig)"
    fi
}
trap cleanup EXIT

# --- 5. Root Privilege Check ---
if (( EUID == 0 )); then
    log_err "Refusing to run as root."
    log_err "This script modifies user files in ~/.config/uwsm."
    exit 1
fi

# --- 6. Configuration Paths ---
readonly UWSM_DIR="${HOME:?HOME not set}/.config/uwsm"
readonly ENV_FILE="${UWSM_DIR}/env"
readonly HYPR_FILE="${UWSM_DIR}/env-hyprland"

# --- 7. Core Function ---
comment_out_vars() {
    local file="$1"
    shift
    local -a vars=("$@")

    if [[ ! -f "$file" ]]; then
        log_err "File not found: $file"
        return 1
    fi
    
    if [[ ! -w "$file" ]]; then
        log_err "No write permission: $file"
        return 1
    fi

    if (( ${#vars[@]} == 0 )); then
        log_err "Dev Error: No variables provided for $file"
        return 1
    fi

    local IFS='|'
    local pattern="${vars[*]}"

    # sed modification
    if ! sed -i -E "s/^([[:space:]]*)export[[:space:]]+((${pattern})=)/\1# export \2/" "$file"; then
        log_err "sed command failed on $file"
        return 1
    fi

    return 0
}

# --- 8. Cleanup Logic (Refactored for Reuse) ---
run_cleanup_logic() {
    log_info "Initializing UWSM configuration cleanup..."
    local errors=0

    # ---------------------------------------------------------
    # TASK 1: Clean 'env-hyprland' (AQ_DRM_DEVICES)
    # ---------------------------------------------------------
    if [[ -f "$HYPR_FILE" ]]; then
        log_info "Scanning $HYPR_FILE..."
        if comment_out_vars "$HYPR_FILE" "AQ_DRM_DEVICES"; then
            log_success "Cleaned AQ_DRM_DEVICES"
        else
            errors=$((errors + 1))
        fi
    else
        log_err "File missing: $HYPR_FILE"
        errors=$((errors + 1))
    fi

    # ---------------------------------------------------------
    # TASK 2: Clean 'env' (Hardware Drivers)
    # ---------------------------------------------------------
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Scanning $ENV_FILE..."
        
        local -a hardware_vars=(
            "LIBVA_DRIVER_NAME"
            "__GLX_VENDOR_LIBRARY_NAME"
            "MOZ_DISABLE_RDD_SANDBOX"
            "NVD_BACKEND"
            "GBM_BACKEND"
            "__VK_LAYER_NV_optimus"
            "__GL_VRR_ALLOWED"
            "__GL_SHADER_DISK_CACHE"
            "__GL_SHADER_DISK_CACHE_PATH"
            "WLR_NO_HARDWARE_CURSORS"
        )

        if comment_out_vars "$ENV_FILE" "${hardware_vars[@]}"; then
            log_success "Cleaned hardware variables"
        else
            errors=$((errors + 1))
        fi
    else
        log_err "File missing: $ENV_FILE"
        errors=$((errors + 1))
    fi

    # ---------------------------------------------------------
    # Summary
    # ---------------------------------------------------------
    if (( errors > 0 )); then
        log_err "Cleanup completed with $errors error(s)."
        exit 1
    else
        log_success "Cleanup complete. Configurations reset to defaults."
        exit 0
    fi
}

# --- 9. Main Execution Flow ---
main() {
    # CASE 1: Auto Mode (Flag Present)
    if [[ "${1:-}" == "--auto" ]]; then
        run_cleanup_logic
    
    # CASE 2: Interactive Mode (Flag Missing)
    else
        # Print question in blue to match info style
        printf "%s[?]%s Do you want to comment out all GPU-related environment variables in UWSM files? [y/N] " "${C_INFO}" "${C_RESET_OUT}"
        read -r response
        
        # Check if response starts with y or Y
        if [[ "$response" =~ ^[yY] ]]; then
            run_cleanup_logic
        else
            log_info "Skipping cleanup per user request. Proceeding..."
            exit 0
        fi
    fi
}

main "$@"
