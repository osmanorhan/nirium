#!/usr/bin/env bash
#
# Nirium System Manager
# Declarative, rolling-update system for Nirium
#

set -Eeuo pipefail

CONFIG_FILE="/etc/nirium/configuration.toml"
GENERATIONS_DIR="/opt/nirium/generations"
XDG_ETC="/etc/xdg"
UPSTREAM_URL="https://github.com/osmanorhan/nirium"
TMP_CLONE_DIR="/tmp/nirium-update"
STAGING_DIR="/tmp/nirium-staging"

die() {
    echo -e "\e[1;31m[ERROR]\e[0m $*" >&2
    exit 1
}

info() {
    echo -e "\e[1;34m[INFO]\e[0m $*"
}

success() {
    echo -e "\e[1;32m[SUCCESS]\e[0m $*"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This command must be run as root (e.g. sudo nirium update)"
    fi
}

apply_keyd_copy_paste_remap() {
    if ! command -v keyd >/dev/null 2>&1; then
        info "keyd not installed; skipping Mod+C/Mod+V remap"
        return 0
    fi

    install -d /etc/keyd
    cat > /etc/keyd/default.conf <<'KEYDCONF'
[ids]
*

[main]
leftmeta+c = C-c
leftmeta+v = C-v
leftmeta+x = C-x
leftmeta+a = C-a
rightmeta+c = C-c
rightmeta+v = C-v
rightmeta+x = C-x
rightmeta+a = C-a
meta+c = C-c
meta+v = C-v
meta+x = C-x
meta+a = C-a
KEYDCONF

    systemctl enable keyd.service >/dev/null 2>&1 || true
    systemctl restart keyd.service >/dev/null 2>&1 || true
    info "Applied keyd Mod+C/Mod+V remap"
}

# Very basic bash-native TOML parser for our strict format
parse_config_is_enabled() {
    local component="$1"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1 # missing file means disabled
    fi

    # Look for a line like `component = true` after `[components]` section
    local in_components=0
    while IFS= read -r line; do
        # Strip whitespace and comments
        line="${line%%#*}"
        line="$(echo "$line" | xargs)"
        [[ -z "$line" ]] && continue

        if [[ "$line" == "[components]" ]]; then
            in_components=1
            continue
        elif [[ "$line" == [*] ]]; then
            in_components=0
            continue
        fi

        if [[ $in_components -eq 1 ]]; then
            # Parse `key = value`
            local key="${line%%=*}"
            local val="${line#*=}"
            key="$(echo "$key" | xargs)"
            val="$(echo "$val" | xargs)"

            if [[ "$key" == "$component" ]]; then
                if [[ "$val" == "true" ]]; then
                    return 0
                else
                    return 1
                fi
            fi
        fi
    done < "$CONFIG_FILE"
    
    return 1 # Not found, disabled by default
}

list_managed_users() {
    local username=""
    local uid=""
    local gid=""
    local home=""
    local shell=""

    while IFS=: read -r username _ uid gid _ home shell; do
        (( uid >= 1000 )) || continue
        [[ "$username" == "nobody" ]] && continue
        [[ -d "$home" ]] || continue
        if [[ "$shell" == */nologin || "$shell" == */false ]]; then
            continue
        fi
        printf '%s:%s\n' "$username" "$home"
    done < <(getent passwd)
}

ensure_home_component_links() {
    local components=("$@")
    if (( ${#components[@]} == 0 )); then
        return 0
    fi

    local user_entry=""
    local username=""
    local home=""
    local user_config_dir=""
    local comp=""
    local system_source=""
    local destination=""
    local source_real=""
    local dest_real=""
    local theme_source=""

    while IFS= read -r user_entry; do
        username="${user_entry%%:*}"
        home="${user_entry#*:}"
        user_config_dir="$home/.config"

        install -d "$user_config_dir"
        chown "$username:$username" "$user_config_dir" 2>/dev/null || true

        for comp in "${components[@]}"; do
            system_source="$XDG_ETC/$comp"
            if [[ "$comp" == "niri" ]]; then
                system_source="/etc/niri"
            fi

            if [[ ! -e "$system_source" && ! -L "$system_source" ]]; then
                continue
            fi

            destination="$user_config_dir/$comp"
            if [[ -L "$destination" && ! -e "$destination" ]]; then
                rm -f "$destination"
            fi

            if [[ "$comp" == "theme" ]]; then
                source_real="$(readlink -f "$system_source" || true)"
                if [[ -L "$destination" ]]; then
                    dest_real="$(readlink -f "$destination" || true)"
                    if [[ -n "$dest_real" && ( "$dest_real" == "$source_real" || "$dest_real" == /opt/nirium/generations/*/theme ) ]]; then
                        rm -f "$destination"
                    fi
                fi

                if [[ ! -e "$destination" && ! -L "$destination" ]]; then
                    if [[ -L "$system_source" ]]; then
                        theme_source="$(readlink -f "$system_source")"
                        cp -r "$theme_source" "$destination"
                    else
                        cp -r "$system_source" "$destination"
                    fi

                    if [[ ! -e "$destination/bg/current" && -f "$destination/bg/bg-1.jpg" ]]; then
                        ln -s "bg-1.jpg" "$destination/bg/current"
                    fi

                    chown -R "$username:$username" "$destination" 2>/dev/null || true
                    info "  - Seeded writable $destination"
                elif [[ ! -L "$destination" && -d "$destination" ]]; then
                    if [[ ! -e "$destination/bg/current" && -f "$destination/bg/bg-1.jpg" ]]; then
                        ln -s "bg-1.jpg" "$destination/bg/current"
                        chown -h "$username:$username" "$destination/bg/current" 2>/dev/null || true
                    fi
                fi

                continue
            fi

            if [[ "$comp" == "niri" && -d "$destination" && ! -L "$destination" && ! -e "$destination/config.kdl" ]]; then
                # Migrate legacy first-boot-only dirs created by older installers.
                local has_extra_entries=""
                has_extra_entries="$(find "$destination" -mindepth 1 ! -name "first-boot.sh" -print -quit 2>/dev/null || true)"
                if [[ -z "$has_extra_entries" ]]; then
                    rm -rf "$destination"
                    ln -s "$system_source" "$destination"
                    chown -h "$username:$username" "$destination" 2>/dev/null || true
                    info "  - Migrated legacy $destination to managed symlink"
                    continue
                fi
            fi

            if [[ ! -e "$destination" && ! -L "$destination" ]]; then
                ln -s "$system_source" "$destination"
                chown -h "$username:$username" "$destination" 2>/dev/null || true
                info "  - Linked $destination -> $system_source"
            elif [[ ! -L "$destination" ]]; then
                info "  - Keeping existing user override at $destination"
            fi
        done
    done < <(list_managed_users)
}

# The main update routine
cmd_update() {
    require_root

    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Configuration file not found at $CONFIG_FILE"
    fi

    info "Fetching latest Nirium configurations..."
    
    # Clean up old temp dirs
    rm -rf "$TMP_CLONE_DIR" "$STAGING_DIR"

    # Clone the latest main
    git clone --depth 1 "$UPSTREAM_URL" "$TMP_CLONE_DIR" >/dev/null 2>&1 || die "Failed to clone $UPSTREAM_URL"

    local repo_dir="$TMP_CLONE_DIR"

    if [[ -d "${GENERATIONS_DIR}/latest" ]]; then
        info "Rotating current 'latest' to 'previous'..."
        rm -rf "${GENERATIONS_DIR}/previous"
        mv "${GENERATIONS_DIR}/latest" "${GENERATIONS_DIR}/previous"
    fi

    local gen_name="latest"
    local gen_dir="${GENERATIONS_DIR}/${gen_name}"
    
    info "Generating new profile: $gen_name"
    mkdir -p "$gen_dir"

    # Define the components we support managing in /etc/xdg
    # If the user turns them on in /etc/nirium/configuration.toml, we install them
    local components=(niri waybar swaync fuzzel hypr kitty theme wlogout starship)
    
    local any_installed=0

    for comp in "${components[@]}"; do
        local is_enabled=0
        if [[ "$comp" == "hypr" ]]; then
            # hypr dir contains hyprlock and hypridle
            if parse_config_is_enabled "hyprlock" || parse_config_is_enabled "hypridle"; then
                is_enabled=1
            fi
        else
            if parse_config_is_enabled "$comp"; then
                is_enabled=1
            fi
        fi

        if [[ $is_enabled -eq 1 ]]; then
            info "  - Including component: $comp"
            local tmpl_dir="${repo_dir}/templates/${comp}"
            
            if [[ -d "$tmpl_dir" ]]; then
                # Copy into the immutable generation folder
                mkdir -p "$gen_dir/$comp"
                cp -r "$tmpl_dir/"* "$gen_dir/$comp/"
                any_installed=1
            else
                info "    (Warning: Template for $comp not found upstream, skipping)"
            fi
        fi
    done

    if [[ $any_installed -eq 0 ]]; then
        info "No components enabled in configuration. Nothing to update."
        rm -rf "$TMP_CLONE_DIR" "$gen_dir"
        exit 0
    fi

    # Sync system dependencies (e.g. pacman packages defined by Nirium)
    local pkg_file="${repo_dir}/packages/desktop.pacman"
    if [[ -f "$pkg_file" ]]; then
        info "Synchronizing required system packages..."
        local PKG_LIST=()
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            line="$(echo "$line" | xargs)"
            if [[ -n "$line" ]]; then
                PKG_LIST+=("$line")
            fi
        done < "$pkg_file"

        if [[ ${#PKG_LIST[@]} -gt 0 ]]; then
            pacman -S --noconfirm --needed "${PKG_LIST[@]}" || info "    (Warning: Some packages failed to install or update)"
        fi
    fi

    info "Applying generation $gen_name to $XDG_ETC..."
    
    local linked_components=()

    # Create symlinks in /etc/xdg
    for comp in "${components[@]}"; do
        if [[ -d "$gen_dir/$comp" ]]; then
            # We enforce linking from the generation dir to XDG
            # E.g. /etc/xdg/niri -> /opt/nirium/generations/gen-X/niri
            local target_xdg="$XDG_ETC/$comp"
            if [[ "$comp" == "niri" ]]; then
                target_xdg="/etc/niri"
            fi
            
            if [[ -e "$target_xdg" && ! -L "$target_xdg" ]]; then
                info "  - Backing up existing non-symlink $target_xdg to ${target_xdg}.bak"
                mv "$target_xdg" "${target_xdg}.bak"
            fi
            
            # Create or update the symlink
            ln -sfn "$gen_dir/$comp" "$target_xdg"
            info "  - Symlinked $target_xdg -> $gen_name/$comp"
            linked_components+=("$comp")
        fi
    done

    info "Linking enabled components into user ~/.config directories..."
    ensure_home_component_links "${linked_components[@]}"
    apply_keyd_copy_paste_remap
    
    # Self-update the nirium CLI tool if it changed upstream
    local upstream_script="${repo_dir}/nirium.sh"
    if [[ -f "$upstream_script" ]]; then
        info "Checking for nirium CLI updates..."
        # If running as /usr/bin/nirium or similar, we update ourselves
        local current_bin="$(command -v nirium || echo "")"
        if [[ -n "$current_bin" ]]; then
            local current_real=""
            local upstream_real=""
            current_real="$(readlink -f "$current_bin" 2>/dev/null || printf '%s\n' "$current_bin")"
            upstream_real="$(readlink -f "$upstream_script" 2>/dev/null || printf '%s\n' "$upstream_script")"

            if [[ "$current_real" != "$upstream_real" ]]; then
                local tmp_bin="${current_bin}.tmp.$$"
                install -m 755 "$upstream_script" "$tmp_bin"
                mv -f "$tmp_bin" "$current_bin"
                info "  - Successfully updated $current_bin"
            fi
        fi
    fi

    # Cleanup
    rm -rf "$TMP_CLONE_DIR"

    success "Update complete! You are now on $gen_name."
    success "Any custom files in ~/.config remain untouched and will override these defaults."
}

# List all generations
cmd_list() {
    echo "Available Nirium Generations:"
    if [[ -d "$GENERATIONS_DIR/latest" ]]; then
        echo "  * latest (current active generation)"
    fi
    if [[ -d "$GENERATIONS_DIR/previous" ]]; then
        echo "    previous (available for rollback)"
    fi
    if [[ ! -d "$GENERATIONS_DIR/latest" && ! -d "$GENERATIONS_DIR/previous" ]]; then
        echo "  (None)"
    fi
}

# The rollback routine
cmd_rollback() {
    require_root
    
    if [[ ! -d "$GENERATIONS_DIR/previous" ]]; then
        die "No previous generation found! Ensure you have updated at least once."
    fi

    info "Rolling back to previous generation..."
    
    # We swap latest and previous so rollback can be undone
    if [[ -d "$GENERATIONS_DIR/latest" ]]; then
        mv "$GENERATIONS_DIR/latest" "$GENERATIONS_DIR/temp"
    fi
    mv "$GENERATIONS_DIR/previous" "$GENERATIONS_DIR/latest"
    if [[ -d "$GENERATIONS_DIR/temp" ]]; then
        mv "$GENERATIONS_DIR/temp" "$GENERATIONS_DIR/previous"
    fi
    
    local gen_dir="$GENERATIONS_DIR/latest"
    local components=(niri waybar swaync fuzzel hypr kitty theme wlogout starship)
    local linked_components=()
    for comp in "${components[@]}"; do
        local target_xdg="$XDG_ETC/$comp"
        if [[ "$comp" == "niri" ]]; then
            target_xdg="/etc/niri"
        fi
        
        if [[ -d "$gen_dir/$comp" ]]; then
            if [[ -e "$target_xdg" && ! -L "$target_xdg" ]]; then
                mv "$target_xdg" "${target_xdg}.bak"
            fi
            ln -sfn "$gen_dir/$comp" "$target_xdg"
            linked_components+=("$comp")
        else
            # Remove stale symlinks for components that no longer exist
            if [[ -L "$target_xdg" && ! -e "$target_xdg" ]]; then
                rm -f "$target_xdg"
            fi
        fi
    done

    info "Ensuring user ~/.config links point to active generation..."
    ensure_home_component_links "${linked_components[@]}"

    success "Rollback complete! You are now using the previous configuration."
}

# The bootstrap routine (used by installer, avoids git clone)
cmd_bootstrap() {
    require_root
    
    local local_dir="${1:-}"
    if [[ -z "$local_dir" || ! -d "$local_dir" ]]; then
        die "Usage: nirium bootstrap <path_to_repository>"
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Configuration file not found at $CONFIG_FILE"
    fi

    info "Bootstrapping Nirium configurations from local dir: $local_dir"
    
    local gen_name="latest"
    local gen_dir="${GENERATIONS_DIR}/${gen_name}"
    
    info "Generating initial profile: $gen_name"
    mkdir -p "$gen_dir"

    local components=(niri waybar swaync fuzzel hypr kitty theme wlogout starship)
    local linked_components=()
    local any_installed=0

    for comp in "${components[@]}"; do
        local is_enabled=0
        if [[ "$comp" == "hypr" ]]; then
            if parse_config_is_enabled "hyprlock" || parse_config_is_enabled "hypridle"; then
                is_enabled=1
            fi
        else
            if parse_config_is_enabled "$comp"; then
                is_enabled=1
            fi
        fi

        if [[ $is_enabled -eq 1 ]]; then
            info "  - Including component: $comp"
            local tmpl_dir="${local_dir}/templates/${comp}"
            
            if [[ -d "$tmpl_dir" ]]; then
                mkdir -p "$gen_dir/$comp"
                cp -r "$tmpl_dir/"* "$gen_dir/$comp/"
                any_installed=1
            else
                info "    (Warning: Template for $comp not found in bootstrap dir, skipping)"
            fi
        fi
    done

    if [[ $any_installed -eq 0 ]]; then
        info "No components enabled in configuration. Nothing to bootstrap."
        rm -rf "$gen_dir"
        exit 0
    fi

    info "Applying generation $gen_name to $XDG_ETC..."
    
    for comp in "${components[@]}"; do
        if [[ -d "$gen_dir/$comp" ]]; then
            local target_xdg="$XDG_ETC/$comp"
            if [[ "$comp" == "niri" ]]; then
                target_xdg="/etc/niri"
            fi
            
            if [[ -e "$target_xdg" && ! -L "$target_xdg" ]]; then
                info "  - Backing up existing non-symlink $target_xdg to ${target_xdg}.bak"
                mv "$target_xdg" "${target_xdg}.bak"
            fi
            
            ln -sfn "$gen_dir/$comp" "$target_xdg"
            linked_components+=("$comp")
        fi
    done

    info "Linking enabled components into user ~/.config directories..."
    ensure_home_component_links "${linked_components[@]}"
    apply_keyd_copy_paste_remap

    success "Bootstrap complete! You are now on $gen_name."
}

# The detach routine (copies XDG defaults to user's home dir)
cmd_detach() {
    local comp="${1:-}"
    
    if [[ -z "$comp" ]]; then
        die "Usage: nirium detach <component>\nExample: nirium detach niri"
    fi

    # Determine user context (we might be run by a normal user or root via sudo)
    local target_user="${SUDO_USER:-$USER}"
    if [[ "$target_user" == "root" ]]; then
        die "Cannot detach configurations directly to the root user's home. Run as a normal user, or via sudo."
    fi

    local target_home=""
    target_home="$(getent passwd "$target_user" | cut -d: -f6)"
    if [[ -z "$target_home" ]]; then
        die "Unable to resolve home directory for $target_user"
    fi

    local target_uid=""
    local target_gid=""
    target_uid="$(id -u "$target_user")"
    target_gid="$(id -g "$target_user")"

    local xdg_source="$XDG_ETC/$comp"
    if [[ "$comp" == "niri" ]]; then
        xdg_source="/etc/niri"
    fi
    
    if [[ ! -e "$xdg_source" ]]; then
        die "No system configuration found for component '$comp' at $xdg_source."
    fi

    local dest_dir="${target_home}/.config/${comp}"
    
    if [[ -L "$dest_dir" ]]; then
        local source_real=""
        local dest_real=""

        if [[ -L "$xdg_source" ]]; then
            source_real="$(readlink -f "$xdg_source" || true)"
        else
            source_real="$xdg_source"
        fi
        dest_real="$(readlink -f "$dest_dir" || true)"

        if [[ -n "$source_real" && -n "$dest_real" && "$source_real" == "$dest_real" ]]; then
            rm -f "$dest_dir"
        else
            die "A configuration symlink already exists at $dest_dir. Remove or rename it first before detaching."
        fi
    elif [[ -e "$dest_dir" ]]; then
        die "A configuration already exists at $dest_dir. Remove or rename it first before detaching."
    fi

    info "Detaching '$comp' configuration to $dest_dir..."
    
    # We copy the resolved symlink destination so they get real files, not a symlink to immutable storage
    if [[ -L "$xdg_source" ]]; then
        local real_source="$(readlink -f "$xdg_source")"
        cp -r "$real_source" "$dest_dir"
    else
        cp -r "$xdg_source" "$dest_dir"
    fi

    # Ensure ownership is correct
    if [[ $EUID -eq 0 ]]; then
        chown -R "$target_uid:$target_gid" "$dest_dir"
    fi

    success "Successfully detached!"
    echo "  You can now edit your custom files at: $dest_dir"
    echo "  Nirium updates will no longer override your changes for $comp."
}

# The doctor routine (checks and fixes missing symlinks)
cmd_doctor() {
    require_root

    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "Configuration file not found at $CONFIG_FILE. Cannot run doctor."
    fi

    local current_gen="$GENERATIONS_DIR/latest"
    if [[ ! -d "$current_gen" ]]; then
        die "No active generation found at $current_gen. Has nirium update been run?"
    fi

    info "Nirium Doctor: Verifying system state against configuration..."

    local components=(niri waybar swaync fuzzel hypr kitty theme wlogout starship)
    local linked_components=()
    local issues_found=0

    for comp in "${components[@]}"; do
        local is_enabled=0
        if [[ "$comp" == "hypr" ]]; then
            if parse_config_is_enabled "hyprlock" || parse_config_is_enabled "hypridle"; then
                is_enabled=1
            fi
        else
            if parse_config_is_enabled "$comp"; then
                is_enabled=1
            fi
        fi

        if [[ $is_enabled -eq 1 ]]; then
            # Verify the generation actually has this component
            if [[ ! -d "$current_gen/$comp" ]]; then
                info "  [WARN] Component '$comp' is enabled in config, but missing from $current_gen/$comp."
                ((issues_found++))
                continue
            fi

            local target_xdg="$XDG_ETC/$comp"
            if [[ "$comp" == "niri" ]]; then
                target_xdg="/etc/niri"
            fi

            # Check if system symlink is missing or broken
            local needs_fix=0
            if [[ ! -e "$target_xdg" ]]; then
                 info "  [FIX] System symlink for '$comp' is missing at $target_xdg."
                 needs_fix=1
            elif [[ ! -L "$target_xdg" ]]; then
                 info "  [WARN] $target_xdg exists but is not a symlink. Backing up and fixing."
                 mv "$target_xdg" "${target_xdg}.bak.doctor"
                 needs_fix=1
            else
                 # It's a symlink, check where it points
                 local current_target="$(readlink -f "$target_xdg" || true)"
                 local expected_target="$(readlink -f "$current_gen/$comp" || true)"
                 if [[ "$current_target" != "$expected_target" ]]; then
                     info "  [FIX] System symlink for '$comp' points to wrong location: $current_target (expected $expected_target)."
                     needs_fix=1
                 fi
            fi

            if [[ $needs_fix -eq 1 ]]; then
                ln -sfn "$current_gen/$comp" "$target_xdg"
                info "    -> Fixed system symlink: $target_xdg -> $current_gen/$comp"
                ((issues_found++))
            fi

            linked_components+=("$comp")
        fi
    done

    if [[ ${#linked_components[@]} -gt 0 ]]; then
        info "Verifying user ~/.config directories..."
        # ensure_home_component_links handles fixing missing links/seeds automatically
        # To make it report as "issues found", we'd need to inspect before/after or grep its output
        # For now, we trust it to fix things silently, but we'll print its standard verbose output.
        ensure_home_component_links "${linked_components[@]}"
    fi

    apply_keyd_copy_paste_remap

    if [[ $issues_found -eq 0 ]]; then
        success "System state aligns with configuration. No issues found."
    else
        success "Doctor completed. Found and resolved $issues_found issue(s)."
    fi
}

usage() {
    cat <<EOF
Nirium Manager

Usage:
  nirium update    Fetch latest changes and apply a new system generation
  nirium rollback  Revert /etc/xdg symlinks to the previous generation
  nirium detach    Copy a component's defaults to ~/.config to override them (e.g., nirium detach niri)
  nirium list      View all installed generations
  nirium bootstrap <dir>  Bootstrap initial generation from a local directory
  nirium doctor    Verify and repair system state according to configuration

Options:
  -h, --help       Show this help
EOF
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    case "$1" in
        update) cmd_update ;;
        rollback) cmd_rollback "$@" ;;
        list) cmd_list ;;
        detach) cmd_detach "${2:-}" ;;
        bootstrap) cmd_bootstrap "${2:-}" ;;
        doctor) cmd_doctor ;;
        -h|--help) usage ;;
        *) die "Unknown command: $1" ;;
    esac
}

main "$@"
