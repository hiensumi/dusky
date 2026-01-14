#!/usr/bin/env bash
# Interactive Optional package installer
#
# ------------------------------------------------------------------------------
# 1. SETUP & SAFETY
# ------------------------------------------------------------------------------
set -uo pipefail

# Visual Constants (ANSI)
readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_DIM=$'\033[2m'
readonly C_GREEN=$'\033[1;32m'
readonly C_BLUE=$'\033[1;34m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_RED=$'\033[1;31m'
readonly C_CYAN=$'\033[1;36m'
readonly C_MAGENTA=$'\033[1;35m'

# Terminal Control
readonly TERM_CLEAR=$'\033[2J\033[H'
readonly CURSOR_SHOW=$'\033[?25h'

# Global for cleanup trap
_TMPFILE=""

# ------------------------------------------------------------------------------
# 2. LOGGING & TRAPS
# ------------------------------------------------------------------------------
log_info()    { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
log_success() { printf '%s[SUCCESS]%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
log_warn()    { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()     { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_task()    { printf '\n%s:: %s%s\n' "${C_BOLD}${C_CYAN}" "$*" "$C_RESET" >&2; }

cleanup() {
    # Clean temp file if exists
    [[ -n "$_TMPFILE" && -f "$_TMPFILE" ]] && rm -f "$_TMPFILE"
    # Restore terminal state
    printf '%s%s' "$CURSOR_SHOW" "$C_RESET" >&2
}

trap cleanup EXIT
trap 'printf "\n"; log_warn "Interrupted by user."; exit 130' INT TERM HUP

# ------------------------------------------------------------------------------
# 3. DATA & UTILS
# ------------------------------------------------------------------------------
readonly RAW_PKG_DATA="
Tools   | pacseek-bin           | TUI for browsing Pacman/AUR databases
# Tools   | yayfzf                | TUI for browsing AUR databases
# Tools   | gnome-software        | Gnome Package installer and manager
Tools   | pamac-aur             | GUI Package installer and manager
Tools   | keypunch-git          | Gamified typing proficiency trainer
Tools   | kew-git               | Minimalist, efficient CLI music player
Tools   | youtube-dl-gui-bin    | GUI wrapper for yt-dlp
Tools   | sysmontask            | Windows-style Task Manager for Linux
# Tools   | lazydocker            | TUI for managing Docker containers
Productivity   | pinta                 | Simple drawing/editing tool (Paint.NET clone)
Productivity   | gimp                  | Photoshop alternative for linux
Productivity   | libreoffice-still     | Microsoft office alternative (Stable)
# Productivity   | libreoffice-fresh     | Microsoft office alternative (latest)
Games   | pipes-rs-bin          | Rust port of the classic pipes screensaver
Games   | 2048.c                | The 2048 sliding tile game in C
Games   | edex-ui-bin           | Sci-Fi/Tron-inspired terminal emulator
Games   | clidle-bin            | Wordle clone for the command line
Games   | maze-tui              | Visual maze generator and solver
Games   | vitetris              | Classic Tetris clone for the terminal
Security| wdpass                | Unlock Western Digital MyPassport drives
Security| dislocker             | FUSE driver to read BitLocker partitions
Drivers | b43-firmware          | Legacy Broadcom B43 wireless firmware
Hardware| asusctl               | ASUS ROG/TUF control (WARNING: Long Compile Time)
"

# Bash 5+ In-Place Trimming (No Subshells)
# Usage: trim_var variable_name
trim_var() {
    local -n var=$1
    # Remove leading whitespace
    var="${var#"${var%%[![:space:]]*}"}"
    # Remove trailing whitespace
    var="${var%"${var##*[![:space:]]}"}"
}

check_environment() {
    if [[ ! -t 0 || ! -t 2 ]]; then
        log_err "This script requires an interactive terminal (TTY)."
        exit 1
    fi

    if [[ $EUID -eq 0 ]]; then
        log_err "Do not run as root. AUR helpers handle sudo internally."
        exit 1
    fi
}

detect_aur_helper() {
    if command -v paru &>/dev/null; then
        printf '%s' "paru"
    elif command -v yay &>/dev/null; then
        printf '%s' "yay"
    else
        log_err "Critical: No AUR helper found. Install 'paru' or 'yay'."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 4. INTERACTIVE MENU (TUI)
# ------------------------------------------------------------------------------
# Writes selected packages to stdout (one per line).
# Returns: 0 = confirmed, 1 = cancelled
select_packages() {
    local -a pkg_names=() pkg_descs=() pkg_groups=() pkg_status=()
    local group pkg desc

    # Parse data efficienty
    while IFS='|' read -r group pkg desc; do
        # Trim using references (no subshells)
        trim_var group
        [[ -z "$group" || "$group" == \#* ]] && continue

        trim_var pkg
        trim_var desc

        pkg_groups+=("$group")
        pkg_names+=("$pkg")
        pkg_descs+=("$desc")
        pkg_status+=(0)
    done <<< "$RAW_PKG_DATA"

    local total=${#pkg_names[@]}
    local selected_count=0 last_group="" mark color input idx
    local i # Loop variable declared once

    while true; do
        # Clear screen via stderr
        printf '%s' "$TERM_CLEAR" >&2
        
        printf '%s:: Optional Package Selector%s\n' "${C_BOLD}${C_MAGENTA}" "$C_RESET" >&2
        printf '%s   [1-%d] Toggle | [a] All | [n] None | [q] Quit | [ENTER] Install%s\n' \
            "$C_DIM" "$total" "$C_RESET" >&2

        last_group=""
        for ((i = 0; i < total; i++)); do
            # Group header
            if [[ "${pkg_groups[i]}" != "$last_group" ]]; then
                printf '\n %s[ %s ]%s\n' "${C_BOLD}${C_CYAN}" "${pkg_groups[i]}" "$C_RESET" >&2
                last_group="${pkg_groups[i]}"
            fi

            # Checkbox state
            if ((pkg_status[i])); then
                mark="X"
                color="$C_GREEN"
            else
                mark=" "
                color="$C_RESET"
            fi

            printf ' [%s] %s%2d.%s %s%-20s%s : %s%s%s\n' \
                "$mark" "$C_DIM" "$((i + 1))" "$C_RESET" \
                "$color" "${pkg_names[i]}" "$C_RESET" \
                "$C_DIM" "${pkg_descs[i]}" "$C_RESET" >&2
        done

        # Count selected
        selected_count=0
        for ((i = 0; i < total; i++)); do
            ((pkg_status[i])) && ((selected_count++))
        done

        printf '\n%s[%d selected]%s %sChoice:%s ' \
            "$C_CYAN" "$selected_count" "$C_RESET" "$C_YELLOW" "$C_RESET" >&2

        read -r input

        case "${input,,}" in
            "")
                break
                ;;
            q|quit)
                log_warn "Selection cancelled."
                return 1
                ;;
            a|all)
                for ((i = 0; i < total; i++)); do pkg_status[i]=1; done
                ;;
            n|none)
                for ((i = 0; i < total; i++)); do pkg_status[i]=0; done
                ;;
            *)
                if [[ "$input" =~ ^[0-9]+$ ]] && ((input >= 1 && input <= total)); then
                    idx=$((input - 1))
                    # Toggle 0/1 using bitwise XOR or math
                    ((pkg_status[idx] = 1 - pkg_status[idx]))
                fi
                ;;
        esac
    done

    # Output selected packages to stdout
    for ((i = 0; i < total; i++)); do
        ((pkg_status[i])) && printf '%s\n' "${pkg_names[i]}"
    done
    return 0
}

# ------------------------------------------------------------------------------
# 5. INSTALLATION LOGIC
# ------------------------------------------------------------------------------
install_process() {
    local helper="$1"
    shift
    local -a targets=("$@")

    if ((${#targets[@]} == 0)); then
        log_warn "No packages selected. Exiting."
        return 0
    fi

    log_task "Checking installation status..."

    local -a to_install
    # || true is crucial to prevent pipefail if no packages are missing
    mapfile -t to_install < <(pacman -T "${targets[@]}" 2>/dev/null || true)

    if ((${#to_install[@]} == 0)); then
        log_success "All selected packages are already installed."
        return 0
    fi

    log_info "Packages to install: ${#to_install[@]}"

    # --- Step 1: Batch Install (Fast Path) ---
    log_task "Attempting Batch Installation..."
    if "$helper" -S --needed --noconfirm "${to_install[@]}"; then
        log_success "Batch installation successful."
        return 0
    fi

    log_warn "Batch install failed. Switching to Interactive Granular Mode."

    # --- Step 2: Granular Install (Safe Path) ---
    local -a remaining
    mapfile -t remaining < <(pacman -T "${to_install[@]}" 2>/dev/null || true)

    ((${#remaining[@]} == 0)) && return 0

    local fail_count=0 pkg choice

    for pkg in "${remaining[@]}"; do
        log_task "Processing: $pkg"

        # Auto-retry once
        if "$helper" -S --needed --noconfirm "$pkg"; then
            log_success "$pkg installed."
            continue
        fi

        log_err "Auto-install failed for $pkg."

        printf '%sRetry manually to see errors? [y/N]: %s' "$C_YELLOW" "$C_RESET" >&2
        read -r -n 1 choice
        printf '\n' >&2

        if [[ "${choice,,}" == "y" ]]; then
            if "$helper" -S "$pkg"; then
                log_success "$pkg installed manually."
            else
                log_err "$pkg failed manual install."
                ((fail_count++))
            fi
        else
            log_warn "Skipping $pkg."
            ((fail_count++))
        fi
    done

    # Cap exit code to 125 to avoid shell reserved codes
    ((fail_count > 125)) && fail_count=125
    return "$fail_count"
}

# ------------------------------------------------------------------------------
# 6. MAIN EXECUTION
# ------------------------------------------------------------------------------
main() {
    check_environment
    local aur_helper
    aur_helper=$(detect_aur_helper)

    log_info "Starting Optional Packages Installer..."

    # Create secure temp file to capture exit code from select_packages
    _TMPFILE=$(mktemp) || { log_err "Failed to create temp file"; exit 1; }

    # Redirect stdout to file, allowing us to capture exit code of function
    if ! select_packages > "$_TMPFILE"; then
        rm -f "$_TMPFILE"
        exit 0
    fi

    local -a selected_packages
    mapfile -t selected_packages < "$_TMPFILE"
    rm -f "$_TMPFILE"
    _TMPFILE=""

    # Filter empty lines
    local -a final_list=()
    local item
    for item in "${selected_packages[@]}"; do
        [[ -n "$item" ]] && final_list+=("$item")
    done

    # Bash safe array expansion
    install_process "$aur_helper" "${final_list[@]}"
}

main "$@"
