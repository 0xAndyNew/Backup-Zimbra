#!/usr/bin/env bash
# Version check and package self-update from GitHub Releases.
# Compatible with Bash 4.2+, mawk/gawk, and curl 7.29 (CentOS/RHEL 7/8/9, Ubuntu 18/20/22).
# Installs ONLY the single verified zimbra-backup package via rpm -Uvh or dpkg -i;
# never runs OS repository syncs or system-wide package updates.

ZB_UPDATE_REPO="${ZB_UPDATE_REPO:-0xAndyNew/Backup-Zimbra}"
ZB_UPDATE_API_URL="${ZB_UPDATE_API_URL:-https://api.github.com/repos/${ZB_UPDATE_REPO}/releases/latest}"
ZB_UPDATE_WEB_URL="${ZB_UPDATE_WEB_URL:-https://github.com/${ZB_UPDATE_REPO}/releases}"
ZB_UPDATE_SKIP_ROOT_CHECK="${ZB_UPDATE_SKIP_ROOT_CHECK:-0}"
ZB_UPDATE_TMP_BASE="${ZB_UPDATE_TMP_BASE:-/var/tmp}"
ZB_UPDATE_FORMAT="${ZB_UPDATE_FORMAT:-}"

ZB_EXIT_UPDATE_REQUESTED=42
ZB_EXIT_UPDATE_AVAILABLE=10

ZB_UPD_CURRENT=""
ZB_UPD_LATEST=""
ZB_UPD_TAG=""
ZB_UPD_FORMAT=""
ZB_UPD_ASSET=""
ZB_UPD_ASSET_URL=""
ZB_UPD_SHA_URL=""
ZB_UPD_SHA256=""
ZB_UPD_RELEASE_URL=""
ZB_UPD_PUBLISHED=""
ZB_UPD_JSON_FILE=""

# Compare two version-release strings (e.g. 0.3.17-2 vs 0.3.18-1).
# Prints: lt | eq | gt
zb_version_compare() {
    local a="${1#v}" b="${2#v}" i x y
    a="${a#V}"; b="${b#V}"
    local -a pa pb
    IFS='.-' read -r -a pa <<< "$a"
    IFS='.-' read -r -a pb <<< "$b"
    local n=${#pa[@]}
    (( ${#pb[@]} > n )) && n=${#pb[@]}
    for (( i = 0; i < n; i++ )); do
        x="${pa[i]:-0}"
        y="${pb[i]:-0}"
        [[ "$x" =~ ^[0-9]+$ ]] || x=0
        [[ "$y" =~ ^[0-9]+$ ]] || y=0
        if (( 10#$x < 10#$y )); then
            printf 'lt'
            return 0
        fi
        if (( 10#$x > 10#$y )); then
            printf 'gt'
            return 0
        fi
    done
    printf 'eq'
}

zb_update_detect_format() {
    if [[ -n "${ZB_UPDATE_FORMAT:-}" ]]; then
        case "$ZB_UPDATE_FORMAT" in
            rpm|deb|source)
                printf '%s' "$ZB_UPDATE_FORMAT"
                return 0
                ;;
            *)
                zb_err "Invalid ZB_UPDATE_FORMAT: $ZB_UPDATE_FORMAT"
                return 1
                ;;
        esac
    fi

    # Running from a git checkout or custom ZB_LIB_DIR must not overwrite system packages.
    if [[ "${ZB_LIB_DIR:-}" != "/usr/libexec/zimbra-backup" ]]; then
        printf 'source'
        return 0
    fi

    if command -v rpm >/dev/null 2>&1 && rpm -q zimbra-backup >/dev/null 2>&1; then
        printf 'rpm'
        return 0
    fi

    if command -v dpkg-query >/dev/null 2>&1; then
        local dpkg_st=""
        dpkg_st="$(dpkg-query -W -f='${Status}' zimbra-backup 2>/dev/null || true)"
        if [[ "$dpkg_st" == "install ok installed" ]]; then
            printf 'deb'
            return 0
        fi
    fi

    printf 'source'
}

zb_update_installed_version() {
    local fmt="${1:-$(zb_update_detect_format)}"
    local ver=""
    case "$fmt" in
        rpm)
            ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' zimbra-backup 2>/dev/null | head -n 1 || true)"
            ;;
        deb)
            ver="$(dpkg-query -W -f='${Version}\n' zimbra-backup 2>/dev/null | head -n 1 || true)"
            ;;
    esac
    ver="$(zb_trim "$ver")"
    if [[ -z "$ver" ]]; then
        ver="${ZB_VERSION}-${ZB_PKG_RELEASE:-1}"
    fi
    printf '%s' "$ver"
}

zb_update_sha256_file() {
    local fpath="$1"
    local out=""
    if command -v sha256sum >/dev/null 2>&1; then
        out="$(sha256sum -- "$fpath" 2>/dev/null | awk '{print tolower($1)}')" || true
    elif command -v shasum >/dev/null 2>&1; then
        out="$(shasum -a 256 -- "$fpath" 2>/dev/null | awk '{print tolower($1)}')" || true
    elif command -v openssl >/dev/null 2>&1; then
        out="$(openssl dgst -sha256 "$fpath" 2>/dev/null | awk '{print tolower($NF)}')" || true
    fi
    [[ "$out" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$out"
}

zb_update_parse_sha256sums() {
    local sums_file="$1" target_asset="$2"
    [[ -f "$sums_file" ]] || return 1
    local sha=""
    sha="$(tr -d '\r' < "$sums_file" | awk -v target="$target_asset" '
        NF >= 2 {
            fname = $2
            sub(/^\*/, "", fname)
            if (fname == target && $1 ~ /^[0-9A-Fa-f]+$/ && length($1) == 64) {
                print tolower($1)
                exit
            }
        }
    ' || true)"
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$sha"
}

zb_update_parse_body_sha256() {
    local json_file="$1" target_asset="$2"
    [[ -f "$json_file" ]] || return 1
    local escaped_asset="${target_asset//./\\.}"
    local hit="" sha=""
    hit="$(grep -oE "\`${escaped_asset}\`: \`[0-9A-Fa-f]{64}\`" "$json_file" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$hit" ]]; then
        sha="$(printf '%s' "$hit" | sed 's/.*`\([0-9A-Fa-f]*\)`$/\1/')"
        sha="${sha,,}"
        if [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
            printf '%s' "$sha"
            return 0
        fi
    fi
    return 1
}

zb_update_asset_version_from_name() {
    local name="$1"
    if [[ "$name" =~ ^zimbra-backup-([0-9]+(\.[0-9]+)+-[0-9]+)\.noarch\.rpm$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$name" =~ ^zimbra-backup_([0-9]+(\.[0-9]+)+-[0-9]+)_all\.deb$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

zb_update_find_asset_in_list() {
    local urls_file="$1" fmt="$2" tag="$3"
    local dl_prefix="${ZB_UPDATE_WEB_URL}/download/${tag}/"
    local line="" base=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(zb_trim "$line")"
        [[ "$line" == "${dl_prefix}"* ]] || continue
        base="${line#"$dl_prefix"}"
        case "$fmt" in
            rpm)
                if [[ "$base" =~ ^zimbra-backup-[0-9]+(\.[0-9]+)+-[0-9]+\.noarch\.rpm$ ]]; then
                    printf '%s' "$line"
                    return 0
                fi
                ;;
            deb)
                if [[ "$base" =~ ^zimbra-backup_[0-9]+(\.[0-9]+)+-[0-9]+_all\.deb$ ]]; then
                    printf '%s' "$line"
                    return 0
                fi
                ;;
            source)
                if [[ "$base" =~ ^zimbra-backup-[0-9]+(\.[0-9]+)+-[0-9]+\.noarch\.rpm$ ]] \
                    || [[ "$base" =~ ^zimbra-backup_[0-9]+(\.[0-9]+)+-[0-9]+_all\.deb$ ]]; then
                    printf '%s' "$line"
                    return 0
                fi
                ;;
        esac
    done < "$urls_file"
    return 1
}

zb_update_fetch_latest() {
    local work_dir="$1" fmt="$2"
    ZB_UPD_LATEST=""
    ZB_UPD_TAG=""
    ZB_UPD_ASSET=""
    ZB_UPD_ASSET_URL=""
    ZB_UPD_SHA_URL=""
    ZB_UPD_SHA256=""
    ZB_UPD_RELEASE_URL=""
    ZB_UPD_PUBLISHED=""
    ZB_UPD_JSON_FILE=""

    local json_file="${work_dir}/latest.json"
    local urls_file="${work_dir}/urls.txt"
    local sums_file="${work_dir}/SHA256SUMS"
    local tag="" pub_at="" rel_url="" asset_url="" sha_url=""

    if curl -fsSL --proto =https --proto-redir =https \
        --connect-timeout 15 --max-time 30 \
        -A "zimbra-backup/${ZB_VERSION}" \
        -H "Accept: application/vnd.github+json" \
        -o "$json_file" \
        "$ZB_UPDATE_API_URL" 2>/dev/null; then

        tag="$(grep -o '"tag_name": *"[^"]*"' "$json_file" 2>/dev/null | head -n 1 \
            | sed 's/.*"tag_name": *"\([^"]*\)"/\1/' || true)"
        if [[ "$tag" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]]; then
            ZB_UPD_JSON_FILE="$json_file"
            pub_at="$(grep -o '"published_at": *"[^"]*"' "$json_file" 2>/dev/null | head -n 1 \
                | sed 's/.*"published_at": *"\([^"]*\)"/\1/' || true)"
            rel_url="$(grep -o '"html_url": *"https://[^"]*releases/tag/[^"]*"' "$json_file" 2>/dev/null | head -n 1 \
                | sed 's/.*"html_url": *"\([^"]*\)"/\1/' || true)"
            grep -o '"browser_download_url": *"[^"]*"' "$json_file" 2>/dev/null \
                | sed 's/.*"browser_download_url": *"\([^"]*\)"/\1/' > "$urls_file" || true

            asset_url="$(zb_update_find_asset_in_list "$urls_file" "$fmt" "$tag" || true)"
            local expected_sha_url="${ZB_UPDATE_WEB_URL}/download/${tag}/SHA256SUMS"
            if grep -Fxq "$expected_sha_url" "$urls_file" 2>/dev/null; then
                sha_url="$expected_sha_url"
            fi
        else
            tag=""
        fi
    fi

    # Fallback: GitHub web /releases/latest redirect + SHA256SUMS (immune to 60/hr API rate limit)
    if [[ -z "$tag" ]]; then
        local eff_url=""
        eff_url="$(curl -fsSL --proto =https --proto-redir =https \
            --connect-timeout 15 --max-time 30 \
            -A "zimbra-backup/${ZB_VERSION}" \
            -o /dev/null -w '%{url_effective}' \
            "${ZB_UPDATE_WEB_URL}/latest" 2>/dev/null || true)"
        if [[ "$eff_url" =~ /releases/tag/(v[0-9]+(\.[0-9]+){1,3})$ ]]; then
            tag="${BASH_REMATCH[1]}"
        else
            zb_err "Could not check latest release on GitHub (${ZB_UPDATE_WEB_URL})."
            return 1
        fi
        rel_url="${ZB_UPDATE_WEB_URL}/tag/${tag}"
        sha_url="${ZB_UPDATE_WEB_URL}/download/${tag}/SHA256SUMS"
        if curl -fsSL --proto =https --proto-redir =https \
            --connect-timeout 15 --max-time 30 \
            -A "zimbra-backup/${ZB_VERSION}" \
            -o "$sums_file" \
            "$sha_url" 2>/dev/null; then
            local matched_line="" matched_sha="" matched_name=""
            if [[ "$fmt" == "rpm" ]]; then
                matched_line="$(tr -d '\r' < "$sums_file" | awk '$2 ~ /^(\*)?zimbra-backup-[0-9]+\.[0-9]+(\.[0-9]+)*-[0-9]+\.noarch\.rpm$/ {print; exit}' || true)"
            elif [[ "$fmt" == "deb" ]]; then
                matched_line="$(tr -d '\r' < "$sums_file" | awk '$2 ~ /^(\*)?zimbra-backup_[0-9]+\.[0-9]+(\.[0-9]+)*-[0-9]+_all\.deb$/ {print; exit}' || true)"
            else
                matched_line="$(tr -d '\r' < "$sums_file" | awk '$2 ~ /^(\*)?zimbra-backup[-_][0-9]+/ {print; exit}' || true)"
            fi
            if [[ -n "$matched_line" ]]; then
                matched_sha="$(printf '%s\n' "$matched_line" | awk '{print tolower($1)}')"
                matched_name="$(printf '%s\n' "$matched_line" | awk '{sub(/^\*/, "", $2); print $2}')"
                if [[ "$matched_sha" =~ ^[0-9a-f]{64}$ ]] && zb_update_asset_version_from_name "$matched_name" >/dev/null; then
                    asset_url="${ZB_UPDATE_WEB_URL}/download/${tag}/${matched_name}"
                    ZB_UPD_SHA256="$matched_sha"
                fi
            fi
        fi
    fi

    ZB_UPD_TAG="$tag"
    ZB_UPD_RELEASE_URL="${rel_url:-${ZB_UPDATE_WEB_URL}/tag/${tag}}"
    ZB_UPD_PUBLISHED="${pub_at%%T*}"
    ZB_UPD_SHA_URL="$sha_url"

    if [[ -n "$asset_url" ]]; then
        ZB_UPD_ASSET_URL="$asset_url"
        ZB_UPD_ASSET="${asset_url##*/}"
        ZB_UPD_LATEST="$(zb_update_asset_version_from_name "$ZB_UPD_ASSET" || true)"
    fi

    if [[ "$fmt" == "source" && -z "$ZB_UPD_LATEST" ]]; then
        ZB_UPD_LATEST="${tag#v}-1"
    fi

    if [[ -z "$ZB_UPD_LATEST" ]]; then
        zb_err "Release ${tag} does not contain a matching '${fmt}' package asset."
        return 1
    fi
    return 0
}

zb_update_check() {
    local work_dir="$1"
    ZB_UPD_FORMAT="$(zb_update_detect_format)" || return 1
    ZB_UPD_CURRENT="$(zb_update_installed_version "$ZB_UPD_FORMAT")"
    zb_update_fetch_latest "$work_dir" "$ZB_UPD_FORMAT" || return 1

    local cmp
    cmp="$(zb_version_compare "$ZB_UPD_CURRENT" "$ZB_UPD_LATEST")"
    if [[ "$cmp" == "lt" ]]; then
        return "$ZB_EXIT_UPDATE_AVAILABLE"
    fi
    return 0
}

zb_update_print_summary() {
    zb_msg "  Package format    : ${ZB_UPD_FORMAT}"
    zb_msg "  Installed version : ${ZB_UPD_CURRENT}"
    if [[ -n "${ZB_UPD_PUBLISHED:-}" ]]; then
        zb_msg "  Latest version    : ${ZB_UPD_LATEST} (published ${ZB_UPD_PUBLISHED})"
    else
        zb_msg "  Latest version    : ${ZB_UPD_LATEST}"
    fi
    if [[ -n "${ZB_UPD_ASSET:-}" && "$ZB_UPD_FORMAT" != "source" ]]; then
        zb_msg "  Package asset     : ${ZB_UPD_ASSET}"
    fi
    zb_msg "  Release notes     : ${ZB_UPD_RELEASE_URL}"
}

# Check whether operation.lock is held without modifying state or ownership.
zb_update_lock_busy() {
    [[ -f "$ZB_LOCK_FILE" && ! -L "$ZB_LOCK_FILE" ]] || return 1
    command -v flock >/dev/null 2>&1 || return 1
    ! ( exec 9<"$ZB_LOCK_FILE" && flock -n 9 ) 2>/dev/null
}

# Acquire operation.lock on FD 9 in the caller's shell (must run in a subshell).
# Ensures root never creates operation.lock owned by root:root (which would break zimbra cron jobs).
zb_update_acquire_op_lock() {
    command -v flock >/dev/null 2>&1 || { zb_err "Command 'flock' not found (install util-linux)."; return 1; }
    [[ -d "$ZB_STATE_DIR" ]] || return 0
    [[ ! -L "$ZB_STATE_DIR" ]] || { zb_err "Refusing symlink state directory: $ZB_STATE_DIR"; return 1; }
    [[ ! -L "$ZB_LOCK_FILE" ]] || { zb_err "Refusing symlink lock file: $ZB_LOCK_FILE"; return 1; }

    if [[ ! -e "$ZB_LOCK_FILE" ]]; then
        if (( EUID == 0 )) && [[ "${ZB_UPDATE_SKIP_ROOT_CHECK:-0}" != "1" ]]; then
            if command -v runuser >/dev/null 2>&1; then
                runuser -u "$ZB_ZIMBRA_USER" -- sh -c 'umask 077 && : > "$1"' _ "$ZB_LOCK_FILE" 2>/dev/null || return 1
            else
                su -s /bin/sh "$ZB_ZIMBRA_USER" -c "umask 077 && : > $(printf '%q' "$ZB_LOCK_FILE")" 2>/dev/null || return 1
            fi
        else
            ( umask 077 && : > "$ZB_LOCK_FILE" ) || return 1
        fi
    fi

    [[ -f "$ZB_LOCK_FILE" && ! -L "$ZB_LOCK_FILE" ]] || { zb_err "Invalid lock file: $ZB_LOCK_FILE"; return 1; }
    exec 9<"$ZB_LOCK_FILE" || { zb_err "Cannot open lock file: $ZB_LOCK_FILE"; return 1; }
    if ! flock -n 9; then
        zb_err "Another backup or restore operation is currently running (${ZB_LOCK_FILE} is locked). Wait for it to finish before updating."
        return 1
    fi
    return 0
}

# Download, verify SHA-256 + package identity, and install single package under operation.lock.
# Executed in a subshell so FD 9 (flock) and cleanup trap never leak to the parent shell.
zb_update_install() (
    if (( EUID != 0 )) && [[ "${ZB_UPDATE_SKIP_ROOT_CHECK:-0}" != "1" ]]; then
        zb_err "Installing updates requires root privileges."
        return 1
    fi

    case "$ZB_UPD_FORMAT" in
        rpm|deb) ;;
        source)
            zb_err "Running from a source checkout; update manually with 'git pull'."
            return 1
            ;;
        *)
            zb_err "Unsupported package format: ${ZB_UPD_FORMAT}"
            return 1
            ;;
    esac

    [[ -n "$ZB_UPD_ASSET" && -n "$ZB_UPD_ASSET_URL" && -n "$ZB_UPD_LATEST" ]] || {
        zb_err "Incomplete update metadata; run check before install."
        return 1
    }

    local expected_prefix="${ZB_UPDATE_WEB_URL}/download/${ZB_UPD_TAG}/"
    if [[ "$ZB_UPD_ASSET_URL" != "${expected_prefix}"* ]]; then
        zb_err "Refusing unexpected download URL: $ZB_UPD_ASSET_URL"
        return 1
    fi

    zb_update_acquire_op_lock || return 1

    local dl_dir=""
    cleanup_update_install() {
        local rc=$?
        trap - EXIT INT TERM HUP
        if [[ -n "$dl_dir" && -d "$dl_dir" ]]; then
            rm -rf -- "$dl_dir" 2>/dev/null || true
        fi
        return "$rc"
    }
    trap cleanup_update_install EXIT INT TERM HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    umask 077
    [[ -d "$ZB_UPDATE_TMP_BASE" && ! -L "$ZB_UPDATE_TMP_BASE" ]] || {
        zb_err "Unsafe temporary base directory: $ZB_UPDATE_TMP_BASE"
        return 1
    }
    dl_dir="$(mktemp -d "${ZB_UPDATE_TMP_BASE}/zimbra-backup-update.XXXXXX")" || {
        zb_err "Failed to create secure temporary directory under $ZB_UPDATE_TMP_BASE"
        return 1
    }
    chmod 700 "$dl_dir"

    # Resolve expected SHA-256 before downloading package archive
    local expected_sha="${ZB_UPD_SHA256:-}"
    if [[ -z "$expected_sha" && -n "${ZB_UPD_SHA_URL:-}" ]]; then
        if [[ "$ZB_UPD_SHA_URL" != "${expected_prefix}SHA256SUMS" ]]; then
            zb_err "Refusing unexpected SHA256SUMS URL: $ZB_UPD_SHA_URL"
            return 1
        fi
        local sums_dl="${dl_dir}/SHA256SUMS"
        if curl -fsSL --proto =https --proto-redir =https \
            --connect-timeout 15 --max-time 30 \
            -A "zimbra-backup/${ZB_VERSION}" \
            -o "$sums_dl" \
            "$ZB_UPD_SHA_URL" 2>/dev/null; then
            expected_sha="$(zb_update_parse_sha256sums "$sums_dl" "$ZB_UPD_ASSET" || true)"
        fi
    fi
    if [[ -z "$expected_sha" && -n "${ZB_UPD_JSON_FILE:-}" && -f "${ZB_UPD_JSON_FILE:-}" ]]; then
        expected_sha="$(zb_update_parse_body_sha256 "$ZB_UPD_JSON_FILE" "$ZB_UPD_ASSET" || true)"
    fi
    if [[ ! "$expected_sha" =~ ^[0-9a-f]{64}$ ]]; then
        zb_err "Could not verify expected SHA-256 checksum for ${ZB_UPD_ASSET}. Aborting install."
        return 1
    fi

    local pkg_file="${dl_dir}/${ZB_UPD_ASSET}"
    zb_info "Downloading ${ZB_UPD_ASSET}..."
    if ! curl -fSL --proto =https --proto-redir =https \
        --connect-timeout 15 --max-time 600 \
        -A "zimbra-backup/${ZB_VERSION}" \
        -o "$pkg_file" \
        "$ZB_UPD_ASSET_URL"; then
        zb_err "Failed to download ${ZB_UPD_ASSET_URL}."
        return 1
    fi

    local actual_sha=""
    actual_sha="$(zb_update_sha256_file "$pkg_file" || true)"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        zb_err "SHA-256 checksum mismatch for ${ZB_UPD_ASSET} (expected ${expected_sha}, got ${actual_sha:-unknown}). Aborting."
        return 1
    fi
    zb_info "Verified SHA-256 checksum (${actual_sha})."

    # Verify package name metadata and install ONLY this single package (no OS repo updates).
    local pkg_name=""
    if [[ "$ZB_UPD_FORMAT" == "rpm" ]]; then
        pkg_name="$(rpm -qp --qf '%{NAME}\n' "$pkg_file" 2>/dev/null | head -n 1 || true)"
        [[ "$pkg_name" == "zimbra-backup" ]] || { zb_err "Unexpected RPM package name: '${pkg_name}'. Aborting."; return 1; }
        zb_info "Installing RPM package with rpm -Uvh (Zimbra services and OS packages untouched)..."
        rpm -Uvh "$pkg_file" || { zb_err "rpm -Uvh failed."; return 1; }
    else
        pkg_name="$(dpkg-deb -f "$pkg_file" Package 2>/dev/null | head -n 1 || true)"
        [[ "$pkg_name" == "zimbra-backup" ]] || { zb_err "Unexpected DEB package name: '${pkg_name}'. Aborting."; return 1; }
        zb_info "Installing DEB package with dpkg -i (Zimbra services and OS packages untouched)..."
        dpkg -i "$pkg_file" || { zb_err "dpkg -i failed."; return 1; }
    fi

    local after_ver=""
    after_ver="$(zb_update_installed_version "$ZB_UPD_FORMAT")"
    if [[ "$(zb_version_compare "$after_ver" "$ZB_UPD_LATEST")" == "lt" ]]; then
        zb_err "Post-install version check failed (installed: ${after_ver}, expected: ${ZB_UPD_LATEST})."
        return 1
    fi
    zb_info "Successfully updated zimbra-backup: ${ZB_UPD_CURRENT} -> ${after_ver}"
    return 0
)

zb_cli_update() (
    local check_only=0
    local assume_yes=0

    while (( $# > 0 )); do
        case "$1" in
            --check|-c) check_only=1; shift ;;
            --yes|-y) assume_yes=1; shift ;;
            -h|--help)
                cat <<EOF
Usage: zimbra-backup update [--check] [--yes]
  --check, -c   Check GitHub Releases for a newer version without installing (exit 0=latest, 10=update available, 1=error).
  --yes,   -y   Install the latest version without interactive confirmation (requires root).
EOF
                return 0
                ;;
            *)
                zb_err "Unknown 'update' option: $1"
                return 1
                ;;
        esac
    done

    if (( check_only == 0 )) && (( EUID != 0 )) && [[ "${ZB_UPDATE_SKIP_ROOT_CHECK:-0}" != "1" ]]; then
        zb_err "Updating zimbra-backup requires root privileges. Run as root: zimbra-backup update (or use '--check')."
        return 1
    fi

    local chk_dir=""
    cleanup_cli_update() {
        local rc=$?
        trap - EXIT INT TERM HUP
        if [[ -n "$chk_dir" && -d "$chk_dir" ]]; then
            rm -rf -- "$chk_dir" 2>/dev/null || true
        fi
        return "$rc"
    }
    trap cleanup_cli_update EXIT INT TERM HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    chk_dir="$(mktemp -d "${ZB_UPDATE_TMP_BASE}/zimbra-backup-check.XXXXXX" 2>/dev/null || mktemp -d "/tmp/zb-check.XXXXXX")" || {
        zb_err "Failed to create temporary directory for update check."
        return 1
    }

    local chk_rc=0
    zb_info "Checking GitHub Releases for the latest version..."
    zb_update_check "$chk_dir" || chk_rc=$?

    if (( chk_rc == 1 )); then
        return 1
    fi

    zb_update_print_summary

    if (( chk_rc == 0 )); then
        zb_info "You are running the latest version (${ZB_UPD_CURRENT})."
        return 0
    fi

    if (( check_only == 1 )); then
        zb_info "Update available: ${ZB_UPD_CURRENT} -> ${ZB_UPD_LATEST}"
        if [[ "$ZB_UPD_FORMAT" == "source" ]]; then
            zb_msg "Running from a source checkout; update manually with 'git pull'."
        elif (( EUID != 0 )); then
            zb_msg "Run as root to install: zimbra-backup update"
        else
            zb_msg "Run 'zimbra-backup update' to install."
        fi
        return "$ZB_EXIT_UPDATE_AVAILABLE"
    fi

    if [[ "$ZB_UPD_FORMAT" == "source" ]]; then
        zb_warn "Running from a source checkout; package auto-update is disabled. Update manually via 'git pull'."
        return 1
    fi

    if zb_update_lock_busy; then
        zb_err "Another backup or restore operation is currently running (${ZB_LOCK_FILE} is locked). Wait for it to finish before updating."
        return 1
    fi

    if (( assume_yes == 0 )); then
        if [[ ! -t 0 && "${ZB_TEST_INTERACTIVE_PIPE:-0}" != "1" ]]; then
            zb_info "Update available (${ZB_UPD_CURRENT} -> ${ZB_UPD_LATEST}). Re-run with '--yes' in non-interactive shells."
            return "$ZB_EXIT_UPDATE_AVAILABLE"
        fi
        zb_msg "------------------------------------------------------------"
        zb_msg "  Jobs, settings, and crontab schedules are preserved during upgrade."
        local ans="no"
        ans="$(zb_prompt_yesno "Update to ${ZB_UPD_LATEST} now?" "no")" || ans="no"
        if [[ "$ans" != "yes" ]]; then
            zb_info "Update cancelled."
            return 0
        fi
    fi

    zb_update_install
)

zb_tui_update_menu() {
    zb_tui_header "CHECK FOR UPDATES"
    zb_info "Checking GitHub Releases for the latest version..."

    local chk_dir=""
    chk_dir="$(mktemp -d "${ZB_RUN_DIR:-/tmp}/.zb_upd_check.XXXXXX" 2>/dev/null || mktemp -d "/tmp/zb-upd-check.XXXXXX")" || {
        zb_warn "Could not create temporary directory for update check."
        zb_pause
        return 0
    }

    local chk_rc=0
    zb_update_check "$chk_dir" || chk_rc=$?
    rm -rf -- "$chk_dir" 2>/dev/null || true

    if (( chk_rc == 1 )); then
        zb_warn "Could not reach GitHub (offline or proxy?). Manual upgrade URL: ${ZB_UPDATE_WEB_URL}"
        zb_pause
        return 0
    fi

    zb_update_print_summary
    zb_msg "------------------------------------------------------------"

    if (( chk_rc == 0 )); then
        zb_info "You are running the latest version (${ZB_UPD_CURRENT})."
        zb_pause
        return 0
    fi

    if [[ "$ZB_UPD_FORMAT" == "source" ]]; then
        zb_info "Running from a source checkout; update manually with 'git pull'."
        zb_pause
        return 0
    fi

    zb_msg "  Your jobs, settings, and crontab schedule are preserved during upgrade."
    local ans="no"
    ans="$(zb_prompt_yesno "Update to ${ZB_UPD_LATEST} now?" "no")" || ans="no"
    if [[ "$ans" != "yes" ]]; then
        zb_info "Update cancelled."
        zb_pause
        return 0
    fi

    if zb_update_lock_busy; then
        zb_warn "Cannot update while a backup or restore operation is running (${ZB_LOCK_FILE}). Try again later."
        zb_pause
        return 0
    fi

    if [[ "${ZB_ROOT_SUPERVISOR:-0}" == "1" ]]; then
        zb_info "Handing over to root supervisor to install update..."
        exit "$ZB_EXIT_UPDATE_REQUESTED"
    fi

    zb_warn "Installing packages requires root privileges."
    zb_msg "  Exit the menu and run as root: zimbra-backup update"
    zb_pause
}
