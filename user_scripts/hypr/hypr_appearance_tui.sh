#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Hyprland Appearance TUI Configurator (v2.7 - Navigation Fix)
# -----------------------------------------------------------------------------
# Author: Dusk
# Target: Arch Linux / Hyprland / UWSM
# Description: Pure Bash TUI to modify hyprland appearance.conf in real-time.
#              Hardened against set -e failures, injection, and parsing errors.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Configuration ---
readonly CONFIG_FILE="${HOME}/.config/hypr/source/appearance.conf"

# --- DEFAULTS (Immutable) ---
declare -Ar DEFAULTS=(
    # General
    [gaps_in]=6
    [gaps_out]=12
    [border_size]=2
    
    # Decoration
    [rounding]=6
    [rounding_power]=6.0
    [active_opacity]=1.0
    [inactive_opacity]=1.0
    [fullscreen_opacity]=1.0
    [dim_inactive]=true
    [dim_strength]=0.2
    [dim_special]=0.8
    
    # Shadow (Block: shadow)
    [shadow_enabled]=false
    [shadow_range]=35
    [shadow_power]=2
    [shadow_color]='rgba(1a1a1aee)'
    
    # Blur (Block: blur)
    [blur_enabled]=false
    [blur_size]=4
    [blur_passes]=2
    [blur_xray]=false
    [blur_ignore_opacity]=true
    [blur_vibrancy]=0.1696
)

# ANSI Colors & Control Sequences
readonly C_RESET=$'\033[0m'
readonly C_CYAN=$'\033[1;36m'
readonly C_GREEN=$'\033[1;32m'
readonly C_MAGENTA=$'\033[1;35m'
readonly C_RED=$'\033[1;31m'
readonly C_WHITE=$'\033[1;37m'
readonly C_GREY=$'\033[1;30m'
readonly C_INVERSE=$'\033[7m'
readonly CLR_EOL=$'\033[K'
readonly CLR_EOS=$'\033[J'
readonly CURSOR_HOME=$'\033[H'
readonly CURSOR_HIDE=$'\033[?25l'
readonly CURSOR_SHOW=$'\033[?25h'

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
declare -i SELECTED=0

# --- Logging & Cleanup ---
log_info() { printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$1"; }
log_err()  { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }

cleanup() {
    tput cnorm 2>/dev/null || printf '%s' "$CURSOR_SHOW"
    printf '%s' "$C_RESET"
    clear
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Core Logic: Parsing ---

get_value() {
    local key="$1"
    local block="${2:-}"

    [[ -f "$CONFIG_FILE" ]] || return 1

    awk -v key="$key" -v target_block="$block" '
        BEGIN { depth = 0; in_target = 0; found = 0 }
        /{/ {
            depth++
            if (target_block != "" && match($0, "^[[:space:]]*" target_block "[[:space:]]*\\{")) {
                in_target = 1
                target_depth = depth
            }
        }
        /}/ {
            if (in_target && depth == target_depth) { in_target = 0 }
            depth--
        }
        /=/ && !found {
            should_match = (target_block == "") || in_target
            if (should_match && match($0, "^[[:space:]]*" key "[[:space:]]*=")) {
                pos = index($0, "=")
                val = substr($0, pos + 1)
                gsub(/[[:space:]]*#.*/, "", val)
                gsub(/^[[:space:]]+/, "", val)
                gsub(/[[:space:]]+$/, "", val)
                print val
                found = 1
                exit
            }
        }
    ' "$CONFIG_FILE"
}

set_value() {
    local key="$1"
    local new_val="$2"
    local block="${3:-}"

    local safe_val="$new_val"
    safe_val="${safe_val//\\/\\\\}"
    safe_val="${safe_val//&/\\&}"
    safe_val="${safe_val//|/\\|}"

    if [[ -n "$block" ]]; then
        sed -i "/^[[:space:]]*${block}[[:space:]]*{/,/}/ s|^\([[:space:]]*${key}[[:space:]]*=[[:space:]]*\)[^#[:space:]]*|\1${safe_val}|" "$CONFIG_FILE"
    else
        sed -i "s|^\([[:space:]]*${key}[[:space:]]*=[[:space:]]*\)[^#[:space:]]*|\1${safe_val}|" "$CONFIG_FILE"
    fi
}

# --- Action Handlers ---

reset_defaults() {
    set_value "gaps_in" "${DEFAULTS[gaps_in]}"
    set_value "gaps_out" "${DEFAULTS[gaps_out]}"
    set_value "border_size" "${DEFAULTS[border_size]}"
    set_value "rounding" "${DEFAULTS[rounding]}"
    set_value "rounding_power" "${DEFAULTS[rounding_power]}"
    set_value "active_opacity" "${DEFAULTS[active_opacity]}"
    set_value "inactive_opacity" "${DEFAULTS[inactive_opacity]}"
    set_value "fullscreen_opacity" "${DEFAULTS[fullscreen_opacity]}"
    set_value "dim_inactive" "${DEFAULTS[dim_inactive]}"
    set_value "dim_strength" "${DEFAULTS[dim_strength]}"
    set_value "dim_special" "${DEFAULTS[dim_special]}"
    set_value "enabled" "${DEFAULTS[shadow_enabled]}" "shadow"
    set_value "range" "${DEFAULTS[shadow_range]}" "shadow"
    set_value "render_power" "${DEFAULTS[shadow_power]}" "shadow"
    set_value "color" "${DEFAULTS[shadow_color]}" "shadow"
    set_value "enabled" "${DEFAULTS[blur_enabled]}" "blur"
    set_value "size" "${DEFAULTS[blur_size]}" "blur"
    set_value "passes" "${DEFAULTS[blur_passes]}" "blur"
    set_value "xray" "${DEFAULTS[blur_xray]}" "blur"
    set_value "ignore_opacity" "${DEFAULTS[blur_ignore_opacity]}" "blur"
    set_value "vibrancy" "${DEFAULTS[blur_vibrancy]}" "blur"
}

adjust_int() {
    local key="$1"
    local delta="$2"
    local block="${3:-}"
    local -i min="${4:-0}"
    local max="${5:-}"
    
    local current
    current=$(get_value "$key" "$block") || current=0
    [[ "$current" =~ ^-?[0-9]+$ ]] || current=0
    
    local -i new_val=$((current + delta))
    
    ((new_val < min)) && new_val=$min
    [[ -n "$max" ]] && ((new_val > max)) && new_val=$max
    
    set_value "$key" "$new_val" "$block"
}

adjust_float() {
    local key="$1"
    local delta="$2"
    local block="${3:-}"
    local min="${4:-0}"
    local max="${5:-}"
    
    local current
    current=$(get_value "$key" "$block") || current="1.0"
    [[ "$current" =~ ^-?[0-9]*\.?[0-9]+$ ]] || current="1.0"
    
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
    current=$(get_value "$key" "$block") || current="false"
    
    if [[ "$current" == "true" ]]; then
        set_value "$key" "false" "$block"
    else
        set_value "$key" "true" "$block"
    fi
}

toggle_shadow_color() {
    local current
    current=$(get_value "color" "shadow") || current=""
    if [[ "$current" == *'$primary'* ]]; then
        set_value "color" "rgba(1a1a1aee)" "shadow"
    else
        set_value "color" '$primary' "shadow"
    fi
}

handle_action() {
    local -i direction="$1"
    local item="${MENU_ITEMS[SELECTED]}"
    
    local float_delta="0.05"
    ((direction < 0)) && float_delta="-0.05"

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
        "Shadow Power")       adjust_int "render_power" "$direction" "shadow" 1 4 ;;
        "Shadow Color")       toggle_shadow_color ;;
        "Blur Enabled")       toggle_bool "enabled" "blur" ;;
        "Blur Size")          adjust_int "size" "$direction" "blur" 1 ;;
        "Blur Passes")        adjust_int "passes" "$direction" "blur" 1 ;;
        "Blur Xray")          toggle_bool "xray" "blur" ;;
        "Blur Ignore Opacity") toggle_bool "ignore_opacity" "blur" ;;
        "Blur Vibrancy")      adjust_float "vibrancy" "$float_delta" "blur" 0.0 ;;
    esac
}

draw_ui() {
    printf '%s' "$CURSOR_HOME"
    
    printf '%s┌────────────────────────────────────────────────────────┐%s\n' "$C_MAGENTA" "$C_RESET"
    printf '%s│ %sHyprland Configuration %s:: %sReal-time Preview %s          │%s\n' "$C_MAGENTA" "$C_WHITE" "$C_MAGENTA" "$C_CYAN" "$C_MAGENTA" "$C_RESET"
    printf '%s└────────────────────────────────────────────────────────┘%s\n' "$C_MAGENTA" "$C_RESET"
    
    local -i i
    local item key block val display
    
    for ((i = 0; i < MENU_LEN; i++)); do
        item="${MENU_ITEMS[i]}"
        case "$item" in
            "Gaps In")            key="gaps_in"; block="" ;;
            "Gaps Out")           key="gaps_out"; block="" ;;
            "Border Size")        key="border_size"; block="" ;;
            "Rounding")           key="rounding"; block="" ;;
            "Rounding Power")     key="rounding_power"; block="" ;;
            "Active Opacity")     key="active_opacity"; block="" ;;
            "Inactive Opacity")   key="inactive_opacity"; block="" ;;
            "Fullscreen Opacity") key="fullscreen_opacity"; block="" ;;
            "Dim Inactive")       key="dim_inactive"; block="" ;;
            "Dim Strength")       key="dim_strength"; block="" ;;
            "Dim Special")        key="dim_special"; block="" ;;
            "Shadow Enabled")     key="enabled"; block="shadow" ;;
            "Shadow Range")       key="range"; block="shadow" ;;
            "Shadow Power")       key="render_power"; block="shadow" ;;
            "Shadow Color")       key="color"; block="shadow" ;;
            "Blur Enabled")       key="enabled"; block="blur" ;;
            "Blur Size")          key="size"; block="blur" ;;
            "Blur Passes")        key="passes"; block="blur" ;;
            "Blur Xray")          key="xray"; block="blur" ;;
            "Blur Ignore Opacity") key="ignore_opacity"; block="blur" ;;
            "Blur Vibrancy")      key="vibrancy"; block="blur" ;;
        esac

        val=$(get_value "$key" "$block") || val=""

        case "$val" in
            true)  display="${C_GREEN}ON${C_RESET}" ;;
            false) display="${C_RED}OFF${C_RESET}" ;;
            "")    display="${C_RED}unset${C_RESET}" ;;
            *'$primary'*) display="${C_MAGENTA}Dynamic (\$primary)${C_RESET}" ;;
            *)
                if [[ "$item" == "Shadow Color" ]]; then
                    display="${C_GREY}Static (${val})${C_RESET}"
                else
                    display="${C_WHITE}${val}${C_RESET}"
                fi ;;
        esac

        if ((i == SELECTED)); then
            printf '%s ➤ %s%-20s%s : %s%s\n' "$C_CYAN" "$C_INVERSE" "$item" "$C_RESET" "$display" "$CLR_EOL"
        else
            printf '    %-20s   : %s%s\n' "$item" "$display" "$CLR_EOL"
        fi
    done
    
    printf '\n%s [↑/↓/j/k] Nav  [←/→/h/l/Space] Adj  [r] Reset  [q] Quit%s\n' "$C_CYAN" "$C_RESET"
    printf '%s File: %s%s%s%s' "$C_CYAN" "$CONFIG_FILE" "$C_RESET" "$CLR_EOL" "$CLR_EOS"
}

main() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_err "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    if ! command -v awk &>/dev/null || ! command -v sed &>/dev/null; then
        log_err "Missing dependencies: awk or sed"
        exit 1
    fi

    tput civis 2>/dev/null || printf '%s' "$CURSOR_HIDE"
    clear

    local key seq
    while true; do
        draw_ui
        IFS= read -rsn1 key || true
        
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 seq || seq=""
            case "$seq" in
                # Added '|| true' to prevent crash when calculation equals 0
                '[A') ((SELECTED = (SELECTED - 1 + MENU_LEN) % MENU_LEN)) || true ;;
                '[B') ((SELECTED = (SELECTED + 1) % MENU_LEN)) || true ;;
                '[C') handle_action 1 ;;
                '[D') handle_action -1 ;;
            esac
        else
            case "$key" in
                # Added '|| true' here as well
                k|K) ((SELECTED = (SELECTED - 1 + MENU_LEN) % MENU_LEN)) || true ;;
                j|J) ((SELECTED = (SELECTED + 1) % MENU_LEN)) || true ;;
                l|L|' ') handle_action 1 ;;
                h|H) handle_action -1 ;;
                r|R) reset_defaults ;;
                q|Q|$'\x03')
                    log_info "Configuration saved."
                    break
                    ;;
            esac
        fi
    done
}

main
