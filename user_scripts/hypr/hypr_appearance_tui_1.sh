#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Hyprland Appearance TUI Configurator (v2.4 - Optimized & Hardened)
# -----------------------------------------------------------------------------
# Author: Dusk
# Target: Arch Linux / Hyprland / UWSM
# Description: Pure Bash TUI to modify hyprland appearance.conf in real-time.
#              Hardened against set -e failures, injection, and parsing errors.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Configuration ---
readonly CONFIG_FILE="${HOME}/.config/hypr/source/appearance.conf"

# ANSI Colors
readonly C_RESET=$'\033[0m'
readonly C_CYAN=$'\033[1;36m'      # Bright Cyan
readonly C_GREEN=$'\033[1;32m'     # Bright Green
readonly C_MAGENTA=$'\033[1;35m'   # Bright Magenta
readonly C_RED=$'\033[1;31m'       # Bright Red
readonly C_WHITE=$'\033[1;37m'     # Bright White
readonly C_GREY=$'\033[1;30m'      # Bold Dark Grey
readonly C_INVERSE=$'\033[7m'
readonly CLR_EOL=$'\033[K'
readonly CLR_EOS=$'\033[J'         # Clear to End of Screen

# Menu Definition
readonly MENU_ITEMS=(
    "Gaps In"
    "Gaps Out"
    "Border Size"
    "Rounding"
    "Rounding Power"
    "Active Opacity"
    "Inactive Opacity"
    "Fullscreen Opacity"
    "Dim Inactive"
    "Dim Strength"
    "Dim Special"
    "Shadow Enabled"
    "Shadow Range"
    "Shadow Power"
    "Shadow Color"
    "Blur Enabled"
    "Blur Size"
    "Blur Passes"
    "Blur Xray"
    "Blur Ignore Opacity"
    "Blur Vibrancy"
)
readonly MENU_LEN=${#MENU_ITEMS[@]}

# State
SELECTED=0

# --- Logging & Cleanup ---
log_info() { printf "%s[INFO]%s %s\n" "$C_CYAN" "$C_RESET" "$1"; }
log_err()  { printf "%s[ERROR]%s %s\n" "$C_RED" "$C_RESET" "$1" >&2; }

cleanup() {
    tput cnorm 2>/dev/null || true # Restore cursor safely
    printf "%s" "$C_RESET"
}
trap cleanup EXIT INT TERM

# --- Core Logic: Parsing ---

# Retrieve value from config; handles nested blocks safely
# Usage: get_value <key> [block]
get_value() {
    local key="$1"
    local block="${2:-}"

    [[ -f "$CONFIG_FILE" ]] || return 1

    awk -v key="$key" -v target_block="$block" '
        BEGIN { depth=0; in_target=0 }
        
        # Track braces to determine block depth
        /{/ {
            depth++
            if (target_block != "" && $0 ~ "^[[:space:]]*" target_block "[[:space:]]*\\{") {
                in_target=1
                target_depth=depth
            }
        }
        
        /}/ {
            if (in_target && depth == target_depth) {
                in_target=0
            }
            depth--
        }
        
        # Match Key
        {
            # Global or Block-Specific Match
            # If no block requested, we match global keys (usually depth 1 in hyprland syntax)
            # If block requested, we match only when in_target is true
            should_match = (target_block == "") || in_target

            if (should_match && $0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
                split($0, parts, "=")
                val = parts[2]
                sub(/[[:space:]]*#.*/, "", val)       # Remove comments
                sub(/^[[:space:]]+/, "", val)         # Trim leading whitespace
                sub(/[[:space:]]+$/, "", val)         # Trim trailing whitespace
                print val
                exit
            }
        }
    ' "$CONFIG_FILE"
}

# Update value in place
# Usage: set_value <key> <value> [block]
set_value() {
    local key="$1"
    local new_val="$2"
    local block="${3:-}"

    # Sanitize for SED
    local safe_val="${new_val//\\/\\\\}"
    safe_val="${safe_val//&/\\&}"

    if [[ -n "$block" ]]; then
        sed -i "/^[[:space:]]*$block[[:space:]]*{/,/}/ s|^\([[:space:]]*$key[[:space:]]*=[[:space:]]*\)[^#[:space:]]*|\1$safe_val|" "$CONFIG_FILE"
    else
        sed -i "s|^\([[:space:]]*$key[[:space:]]*=[[:space:]]*\)[^#[:space:]]*|\1$safe_val|" "$CONFIG_FILE"
    fi
}

# --- Action Handlers ---

# Usage: adjust_int key delta block [min] [max]
adjust_int() {
    local key="$1"
    local delta="$2"
    local block="${3:-}"
    local min="${4:-0}"
    local max="${5:-}"
    
    local current
    current=$(get_value "$key" "$block")
    [[ "$current" =~ ^-?[0-9]+$ ]] || current=0
    
    local new_val=$((current + delta))
    
    # Clamp (Using if statements to avoid set -e crashes)
    if (( new_val < min )); then new_val=$min; fi
    if [[ -n "$max" ]]; then
        if (( new_val > max )); then new_val=$max; fi
    fi
    
    set_value "$key" "$new_val" "$block"
}

# Usage: adjust_float key delta block [min] [max]
adjust_float() {
    local key="$1"
    local delta="$2"
    local block="${3:-}"
    local min="${4:-0}"
    local max="${5:-}"
    
    local current
    current=$(get_value "$key" "$block")
    [[ "$current" =~ ^-?[0-9]*\.?[0-9]+$ ]] || current="1.0"
    
    # Generic float calculation
    local new_val
    new_val=$(awk -v cur="$current" -v d="$delta" -v mn="$min" -v mx="$max" 'BEGIN {
        val = cur + d
        if (val < mn) val = mn
        if (mx != "" && val > mx) val = mx
        printf "%.2f", val
    }')
    
    set_value "$key" "$new_val" "$block"
}

toggle_bool() {
    local key="$1"
    local block="${2:-}"
    local current
    current=$(get_value "$key" "$block")
    
    if [[ "$current" == "true" ]]; then
        set_value "$key" "false" "$block"
    else
        set_value "$key" "true" "$block"
    fi
}

toggle_shadow_color() {
    local current
    current=$(get_value "color" "shadow")
    if [[ "$current" == *'$primary'* ]]; then
        set_value "color" "rgba(1a1a1aee)" "shadow"
    else
        set_value "color" '$primary' "shadow"
    fi
}

handle_action() {
    local direction="$1" # 1 or -1
    local item="${MENU_ITEMS[$SELECTED]}"
    
    # Optimization: Calculate float delta string without subshell
    local float_delta="0.05"
    if (( direction < 0 )); then
        float_delta="-0.05"
    fi

    case "$item" in
        "Gaps In")            adjust_int "gaps_in" "$direction" "" 0 ;;
        "Gaps Out")           adjust_int "gaps_out" "$direction" "" 0 ;;
        "Border Size")        adjust_int "border_size" "$direction" "" 0 ;;
        "Rounding")           adjust_int "rounding" "$direction" "" 0 ;;
        "Rounding Power")     adjust_float "rounding_power" "$float_delta" "" 0.0 ;;
        
        "Active Opacity")     adjust_float "active_opacity" "$float_delta" "" 0.0 1.0 ;;
        "Inactive Opacity")   adjust_float "inactive_opacity" "$float_delta" "" 0.0 1.0 ;;
        "Fullscreen Opacity") adjust_float "fullscreen_opacity" "$float_delta" "" 0.0 1.0 ;;
        
        "Dim Inactive")       toggle_bool "dim_inactive" ;;
        "Dim Strength")       adjust_float "dim_strength" "$float_delta" "" 0.0 1.0 ;;
        "Dim Special")        adjust_float "dim_special" "$float_delta" "" 0.0 1.0 ;;
        
        "Shadow Enabled")     toggle_bool "enabled" "shadow" ;;
        "Shadow Range")       adjust_int "range" "$direction" "shadow" 0 ;;
        "Shadow Power")       adjust_int "render_power" "$direction" "shadow" 1 4 ;; # Clamp 1-4
        "Shadow Color")       toggle_shadow_color ;;
        
        "Blur Enabled")       toggle_bool "enabled" "blur" ;;
        "Blur Size")          adjust_int "size" "$direction" "blur" 1 ;;
        "Blur Passes")        adjust_int "passes" "$direction" "blur" 1 ;;
        "Blur Xray")          toggle_bool "xray" "blur" ;;
        "Blur Ignore Opacity") toggle_bool "ignore_opacity" "blur" ;;
        "Blur Vibrancy")      adjust_float "vibrancy" "$float_delta" "blur" 0.0 ;;
    esac
}

# --- UI Renderer ---

draw_ui() {
    printf '\033[H' # Cursor Home
    
    # Header
    printf "%s┌────────────────────────────────────────────────────────┐%s\n" "$C_MAGENTA" "$C_RESET"
    printf "%s│ %sHyprland Configuration %s:: %sReal-time Preview %s          │%s\n" "$C_MAGENTA" "$C_WHITE" "$C_MAGENTA" "$C_CYAN" "$C_MAGENTA" "$C_RESET"
    printf "%s└────────────────────────────────────────────────────────┘%s\n" "$C_MAGENTA" "$C_RESET"
    
    local i
    for ((i=0; i<MENU_LEN; i++)); do
        local item="${MENU_ITEMS[$i]}"
        local key block val display
        
        # Mapping for UI Reading
        case "$item" in
            "Gaps In")            key="gaps_in";        block="";;
            "Gaps Out")           key="gaps_out";       block="";;
            "Border Size")        key="border_size";    block="";;
            "Rounding")           key="rounding";       block="";;
            "Rounding Power")     key="rounding_power"; block="";;
            "Active Opacity")     key="active_opacity"; block="";;
            "Inactive Opacity")   key="inactive_opacity"; block="";;
            "Fullscreen Opacity") key="fullscreen_opacity"; block="";;
            "Dim Inactive")       key="dim_inactive";   block="";;
            "Dim Strength")       key="dim_strength";   block="";;
            "Dim Special")        key="dim_special";    block="";;
            "Shadow Enabled")     key="enabled";        block="shadow";;
            "Shadow Range")       key="range";          block="shadow";;
            "Shadow Power")       key="render_power";   block="shadow";;
            "Shadow Color")       key="color";          block="shadow";;
            "Blur Enabled")       key="enabled";        block="blur";;
            "Blur Size")          key="size";           block="blur";;
            "Blur Passes")        key="passes";         block="blur";;
            "Blur Xray")          key="xray";           block="blur";;
            "Blur Ignore Opacity") key="ignore_opacity"; block="blur";;
            "Blur Vibrancy")      key="vibrancy";       block="blur";;
        esac

        val=$(get_value "$key" "$block")

        # Display Formatting
        if [[ "$val" == "true" ]]; then
            display="${C_GREEN}ON${C_RESET}"
        elif [[ "$val" == "false" ]]; then
            display="${C_RED}OFF${C_RESET}"
        elif [[ "$item" == "Shadow Color" ]]; then
            if [[ "$val" == *'$primary'* ]]; then
                display="${C_MAGENTA}Dynamic (\$primary)${C_RESET}"
            else
                display="${C_GREY}Static ($val)${C_RESET}"
            fi
        elif [[ -z "$val" ]]; then
            display="${C_RED}unset${C_RESET}"
        else
            display="${C_WHITE}$val${C_RESET}"
        fi

        # Selection Highlight
        if (( i == SELECTED )); then
            printf "%s ➤ %s %-20s %s : %b%s\n" "$C_CYAN" "$C_INVERSE" "$item" "$C_RESET" "$display" "$CLR_EOL"
        else
            printf "    %-20s   : %b%s\n" "$item" "$display" "$CLR_EOL"
        fi
    done
    
    # Footer
    printf "\n%s [↑/↓/j/k] Navigate  [←/→/h/l/Space] Adjust  [q] Save & Quit%s\n" "$C_CYAN" "$C_RESET"
    printf "%s File: %s%s%s%s" "$C_CYAN" "$CONFIG_FILE" "$C_RESET" "$CLR_EOL" "$CLR_EOS"
}

# --- Main Loop ---

main() {
    # 1. Pre-flight Checks
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_err "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    if ! command -v awk &>/dev/null || ! command -v sed &>/dev/null; then
        log_err "Missing dependencies: awk or sed"
        exit 1
    fi

    # 2. Setup
    tput civis 2>/dev/null || true
    clear

    # 3. Input Loop
    local key seq
    while true; do
        draw_ui
        
        IFS= read -rsn1 key || true
        
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 seq || seq=""
            case "$seq" in
                '[A') SELECTED=$(( (SELECTED - 1 + MENU_LEN) % MENU_LEN )) ;;
                '[B') SELECTED=$(( (SELECTED + 1) % MENU_LEN )) ;;
                '[C') handle_action 1 ;;
                '[D') handle_action -1 ;;
            esac
        else
            # Single key inputs (Vim + Standard)
            case "$key" in
                k|K) # Up
                    SELECTED=$(( (SELECTED - 1 + MENU_LEN) % MENU_LEN )) 
                    ;;
                j|J) # Down
                    SELECTED=$(( (SELECTED + 1) % MENU_LEN )) 
                    ;;
                l|L|" ") # Right/Action
                    handle_action 1 
                    ;;
                h|H) # Left/Action
                    handle_action -1 
                    ;;
                q|Q) # Quit
                    clear
                    log_info "Configuration saved."
                    break 
                    ;;
            esac
        fi
    done
}

main
