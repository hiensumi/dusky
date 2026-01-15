#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Hyprland Animation Switcher for Rofi
# -----------------------------------------------------------------------------
# Strict Mode:
# -u: Error on unset variables (catches typos)
# -o pipefail: Pipeline fails if any command fails
set -u
set -o pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
# Use readonly for constants to prevent accidental overwrites
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly ANIM_DIR="$CONFIG_DIR/hypr/source/animations"
readonly LINK_DIR="$ANIM_DIR/active"
readonly DEST_FILE="$LINK_DIR/active.conf"

# Visual Assets (Nerd Fonts)
readonly ICON_ACTIVE=""   # Checkmark
readonly ICON_FILE=""     # File
readonly ICON_ERROR=""    # Warning

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

notify_user() {
    local title="$1"
    local message="$2"
    local urgency="${3:-low}"
    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -a "Hyprland Animations" "$title" "$message"
    fi
}

reload_hyprland() {
    # Silence output to prevent polluting Rofi's stream
    if command -v hyprctl &>/dev/null; then
        hyprctl reload &>/dev/null
    fi
}

# Sanitize filenames for Rofi's Pango markup
# Converts '&' -> '&amp;', '<' -> '&lt;', etc.
escape_markup() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&apos;}"
    printf '%s' "$s"
}

# -----------------------------------------------------------------------------
# EXECUTION LOGIC (Selection Made)
# -----------------------------------------------------------------------------

selection="${ROFI_INFO:-}"

# Fallback: Handle manual CLI usage or older Rofi versions
if [[ -z "$selection" && -n "${1:-}" ]]; then
    # Use printf to safely handle inputs starting with dashes
    # xargs -r prevents execution on empty input
    clean_name=$(printf '%s' "$1" | sed 's/<[^>]*>//g' | xargs -r)
    selection="$ANIM_DIR/$clean_name"
fi

if [[ -n "$selection" ]]; then
    if [[ ! -f "$selection" ]]; then
        notify_user "Error" "File not found: $selection" "critical"
        exit 1
    fi

    # Ensure target directory exists
    if ! mkdir -p -- "$LINK_DIR" 2>/dev/null; then
        notify_user "Error" "Cannot create directory: $LINK_DIR" "critical"
        exit 1
    fi

    # ATOMIC-ISH UPDATE
    # 1. Remove existing file (rm -f ignores non-existent files)
    rm -f -- "$DEST_FILE"

    # 2. Copy the new file
    if cp -- "$selection" "$DEST_FILE"; then
        # Use parameter expansion for basename (faster than subshell)
        filename="${selection##*/}"
        reload_hyprland
        notify_user "Success" "Switched to: $filename"
        exit 0
    else
        notify_user "Failure" "Could not copy configuration." "critical"
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# MENU GENERATION (No Selection)
# -----------------------------------------------------------------------------

# Rofi Protocol Headers
# FIX: Use escape sequences directly in the format string.
# Passing them as arguments (via %s and $'\0...') fails because Bash 
# truncates strings at the first null byte.
printf '\0prompt\x1fAnimations\n'
printf '\0markup-rows\x1ftrue\n'
printf '\0no-custom\x1ftrue\n'
printf '\0message\x1fSelect a configuration to apply instantly\n'

# Validate Source Directory
if [[ ! -d "$ANIM_DIR" ]]; then
    printf '%s\0icon\x1f%s\x1finfo\x1fignore\n' "Directory Missing" "$ICON_ERROR"
    exit 0
fi

# Gather .conf files safely
shopt -s nullglob
files=("$ANIM_DIR"/*.conf)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
    printf '%s\0icon\x1f%s\x1finfo\x1fignore\n' "No .conf files found" "$ICON_ERROR"
    exit 0
fi

# Determine Active File via Content Comparison
# Initialize as integer
active_index=-1

# Only run cmp if destination exists
if [[ -f "$DEST_FILE" ]]; then
    for i in "${!files[@]}"; do
        if cmp -s "${files[$i]}" "$DEST_FILE"; then
            active_index=$i
            break
        fi
    done
fi

# Tell Rofi which row to highlight
if (( active_index >= 0 )); then
    printf '\0active\x1f%d\n' "$active_index"
fi

# Generate Rows
for i in "${!files[@]}"; do
    file="${files[$i]}"
    filename="${file##*/}"
    
    # Escape filename for display to prevent Pango errors
    escaped_name=$(escape_markup "$filename")

    if (( i == active_index )); then
        # Active State
        printf "<span weight='bold'>%s</span> <span size='small' style='italic'>(Active)</span>\0icon\x1f%s\x1finfo\x1f%s\n" \
            "$escaped_name" "$ICON_ACTIVE" "$file"
    else
        # Inactive State
        printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' \
            "$escaped_name" "$ICON_FILE" "$file"
    fi
done

exit 0
