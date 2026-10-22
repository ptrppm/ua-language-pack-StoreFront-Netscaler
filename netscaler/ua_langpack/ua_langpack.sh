#!/bin/sh
# Ukrainian language pack for NetScaler Gateway (RfWebUI / WStheme), all portal themes.
# Petro Pikulin, petr.pikulin@gmail.com, https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler
#
# Keep this directory in /nsconfig/ua_langpack (survives reboot and firmware upgrade).
#   sh /nsconfig/ua_langpack/ua_langpack.sh install     - install now and re-apply at every boot
#   sh /nsconfig/ua_langpack/ua_langpack.sh uninstall   - remove everything
#   sh /nsconfig/ua_langpack/ua_langpack.sh status
#   sh /nsconfig/ua_langpack/ua_langpack.sh check       - after a firmware upgrade: what needs translating

PACK=$(cd "$(dirname "$0")" && pwd)
LP=${UA_LOGONPOINT:-/var/netscaler/logon/LogonPoint}   # override only for testing
EN=$LP/receiver/js/localization/en/ctxs.strings.js
MANIFEST=$PACK/en.manifest                             # md5 of every English string the pack was made for
TAB=$(printf '\t')
CORE=$LP/receiver/js/ctxs.core.min.js
# Gateway serves pre-auth files only from stock directories (a new localization/uk/ gets 302),
# so the bundle lives next to the core.
UKDIR=$LP/receiver/js
BUNDLE=ctxs.strings.uk.js
# Legacy /vpn and /epa pages (logoff, EPA check, VPN errors) read themes/<bound theme>/resources/<lang>.xml
# for the languages listed in its config.xml
THEMES=${UA_THEMES:-/var/netscaler/logon/themes}       # override only for testing
XML=uk.xml
XMLEN=$THEMES/Default/resources/en.xml
RC=${UA_RC:-/nsconfig/rc.netscaler}                    # override only for testing
MARK=UA_LANGPACK
# First line of rc.netscaler, in background: later lines there may block forever (e.g. ntpd_ctl full_start).
BOOTLINE="/bin/sh $PACK/ua_langpack.sh boot >> /var/log/ua_langpack.log 2>&1 & # $MARK"
FLUSH='flush cache contentGroup loginstaticobjects (an error there only means integrated caching is off - nothing to flush)'

# Must stay on one line: uninstall removes it with sed by the marker.
PATCH=';/*'$MARK'*/(function(d){d.globalization.availableCulture("uk",{name:"uk",englishName:"Ukrainian",nativeName:"\u0423\u043a\u0440\u0430\u0457\u043d\u0441\u044c\u043a\u0430",stringBundle:"/logon/LogonPoint/receiver/js/ctxs.strings.uk.js",customStringBundle:""})})(jQuery);'

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') ua_langpack: $*"; }

is_patched() { grep -q "$MARK" "$CORE" 2>/dev/null; }

# FreeBSD md5 on NetScaler, md5sum elsewhere (tests)
md5str() { if command -v md5 >/dev/null 2>&1; then md5 -q -s "$1"; else printf '%s' "$1" | md5sum | cut -d' ' -f1; fi; }
md5file() { if command -v md5 >/dev/null 2>&1; then md5 -q "$1"; else md5sum < "$1" | cut -d' ' -f1; fi; }

# "key<TAB>raw value" for every 'key: "value",' line up to the end of the bundle.
# Same rule as tools/manifest.py; the last key character must not be a space.
entries() {
    sed -n -e '/^[[:space:]]*});/q' \
        -e 's/^[[:space:]]*"\{0,1\}\([A-Za-z0-9_]\([^":]*[^":[:space:]]\)\{0,1\}\)"\{0,1\}[[:space:]]*:[[:space:]]*"\(.*\)",\{0,1\}[[:space:]]*$/\1'"$TAB"'\3/p' "$1"
}

# "partition|tag|attributes<TAB>raw text" for every String/Property/Title line of a theme resources file.
# Same rule as xml_entries() in tools/manifest.py; Citrix files have one element per line.
xml_entries() {
    awk '{
        s = $0; sub(/\r$/, "", s); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
        if (match(s, /^<Partition id="[^"]*"/)) { part = substr(s, 16, RLENGTH - 16); next }
        if (s !~ /^<(String|Property|Title)[ \t>\/]/) next
        gt = index(s, ">"); head = substr(s, 2, gt - 2); rest = substr(s, gt + 1)
        tag = head; sub(/[ \t\/].*$/, "", tag)
        value = ""
        if (head ~ /\/$/) {
            head = substr(head, 1, length(head) - 1)
        } else {
            # text up to the last closing tag
            close_tag = "</" tag ">"; end = 0; r = rest; off = 0
            while ((i = index(r, close_tag)) > 0) { end = off + i; off += i; r = substr(r, i + 1) }
            value = end ? substr(rest, 1, end - 1) : rest
        }
        attrs = substr(head, length(tag) + 1); sub(/^[ \t]+/, "", attrs); sub(/[ \t]+$/, "", attrs)
        print part "|" tag "|" attrs "\t" value
    }' "$1"
}

# Firmware upgrades may add strings or change English texts; compare with the build the pack was made for
check() {
    [ -f "$EN" ] || { echo "English bundle not found: $EN"; exit 1; }
    [ -f "$MANIFEST" ] || { echo "Not found: $MANIFEST"; exit 1; }
    # NetScaler's FreeBSD has no comm/join: only these tools are used; fail loudly rather than report "complete"
    for c in awk sed sort cut mktemp wc tr grep; do
        command -v "$c" >/dev/null 2>&1 || { echo "ERROR: required command not found: $c"; exit 1; }
    done
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/ua_check.XXXXXX") || exit 1
    export LC_ALL=C
    # "source:key<TAB>English text"; first occurrence of a key wins, as in tools/manifest.py
    # (Citrix's own file has TryAgain twice)
    {
        entries "$EN" | awk -F "$TAB" '!seen[$1]++' | sed 's/^/js:/'
        [ -f "$XMLEN" ] && xml_entries "$XMLEN" | awk -F "$TAB" '!seen[$1]++' | sed 's/^/xml:/'
    } > "$tmp/en"
    cut -f1 "$tmp/en" | sort -u > "$tmp/en.keys"
    {
        entries "$PACK/$BUNDLE" | cut -f1 | sed 's/^/js:/'
        xml_entries "$PACK/$XML" | cut -f1 | sed 's/^/xml:/'
    } | sort -u > "$tmp/uk.keys"
    if [ ! -s "$tmp/en.keys" ] || [ ! -s "$tmp/uk.keys" ]; then
        echo "ERROR: could not read strings from $EN or $PACK/$BUNDLE"; rm -rf "$tmp"; exit 1
    fi
    while IFS="$TAB" read -r k v; do
        printf '%s\t%s\n' "$k" "$(md5str "$v")"
    done < "$tmp/en" > "$tmp/now"
    grep -v '^#' "$MANIFEST" > "$tmp/was"

    # set operations with awk: file 1 is loaded into an array, file 2 is filtered against it
    awk 'NR == FNR { t[$0]; next } !($0 in t)' "$tmp/uk.keys" "$tmp/en.keys" > "$tmp/new"
    awk -F "$TAB" 'NR == FNR { w[$1] = $2; next } ($1 in w) && w[$1] != $2 { print $1 }' \
        "$tmp/was" "$tmp/now" | sort > "$tmp/changed"
    awk 'NR == FNR { t[$0]; next } !($0 in t)' "$tmp/en.keys" "$tmp/uk.keys" > "$tmp/obsolete"

    echo "Pack made for: $(sed -n '1s/^# netscaler \([^ ]*\).*/\1/p' "$MANIFEST")"
    echo "English strings now: $(wc -l < "$tmp/en.keys" | tr -d ' ')"
    for kind in new changed obsolete; do
        case $kind in
            new)      title='NEW - not translated, shown in English' ;;
            changed)  title='CHANGED - English text differs, review the translation' ;;
            obsolete) title='OBSOLETE - no longer used by this firmware (harmless)' ;;
        esac
        echo "== $title: $(wc -l < "$tmp/$kind" | tr -d ' ')"
        [ "$kind" = obsolete ] && continue
        while read -r k; do
            printf '  %s: "%s"\n' "$k" "$(awk -F "$TAB" -v k="$k" '$1 == k { print $2; exit }' "$tmp/en")"
        done < "$tmp/$kind"
    done
    todo=$(cat "$tmp/new" "$tmp/changed" | wc -l | tr -d ' ')
    rm -rf "$tmp"
    [ "$todo" -eq 0 ] && echo "The translation is complete for this firmware." && return 0
    echo "Report these on https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler/issues"
    return 3
}

# true when the firmware's English bundle is not the one the pack was made for
firmware_strings_changed() {
    [ -f "$MANIFEST" ] && [ -f "$EN" ] || return 1
    [ "$(md5file "$EN")" != "$(sed -n '1s/.*en-file-md5 //p' "$MANIFEST")" ]
}

# at every boot: one log line when the firmware's English strings differ from the pack's build
note_new_firmware() {
    firmware_strings_changed || return 0
    log "NOTE: this firmware's English strings differ from the pack's build - run: sh $PACK/ua_langpack.sh check"
}

# resources folders of the themes (EULA holds only the EULA texts); names may contain spaces
theme_dirs() {
    for d in "$THEMES"/*/resources; do
        [ -f "$d/en.xml" ] && [ -f "$d/config.xml" ] && [ "$d" != "$THEMES/EULA/resources" ] && echo "$d"
    done
}

# config.xml of a custom theme is often a symlink to X1's: edit the file it points to
theme_config() { realpath "$1/config.xml"; }

has_uk() { grep -q '<Language>uk</Language>' "$1"; }

# every theme has uk.xml and lists uk in its config.xml
xml_installed() {
    theme_dirs | while IFS= read -r d; do
        [ -f "$d/$XML" ] && has_uk "$(theme_config "$d")" || echo "$d"
    done | grep -q . && return 1
    return 0
}

xml_install() {
    theme_dirs | while IFS= read -r d; do
        t=$(basename "$(dirname "$d")")
        if [ -f "$d/$XML" ] && ! grep -q "$MARK" "$d/$XML"; then
            log "theme $t: own $XML found, left as is"
        elif ! cmp -s "$PACK/$XML" "$d/$XML"; then
            cp "$PACK/$XML" "$d/$XML" && chmod 644 "$d/$XML" && log "theme $t: $XML copied"
        fi
        cfg=$(theme_config "$d")
        has_uk "$cfg" && continue
        # own line before </SupportedLanguageList>, so uninstall restores the file byte for byte
        awk '/<\/SupportedLanguageList>/ && !done { print "    <Language>uk</Language>"; done = 1 } { print }' \
            "$cfg" > "$cfg.ua_tmp" && cat "$cfg.ua_tmp" > "$cfg" && rm -f "$cfg.ua_tmp"
        log "theme $t: uk added to $cfg"
    done
}

xml_uninstall() {
    theme_dirs | while IFS= read -r d; do
        grep -q "$MARK" "$d/$XML" 2>/dev/null && rm -f "$d/$XML" && log "theme $(basename "$(dirname "$d")"): $XML removed"
    done
    # a config.xml may be shared by several themes: drop uk only when none of them has uk.xml left
    theme_dirs | while IFS= read -r d; do
        cfg=$(theme_config "$d")
        has_uk "$cfg" || continue
        theme_dirs | while IFS= read -r o; do
            [ "$(theme_config "$o")" = "$cfg" ] && [ -f "$o/$XML" ] && echo "$o"
        done | grep -q . && continue
        sed -i '' '/<Language>uk<\/Language>/d' "$cfg" && log "uk removed from $cfg"
    done
}

install() {
    [ -f "$PACK/$BUNDLE" ] || { log "ERROR: $PACK/$BUNDLE not found"; exit 1; }
    [ -f "$PACK/$XML" ] || { log "ERROR: $PACK/$XML not found"; exit 1; }
    [ -f "$CORE" ] || { log "ERROR: $CORE not found"; exit 1; }

    # 1. bundle first: a patched core without the bundle would hang the portal on loading
    if ! cmp -s "$PACK/$BUNDLE" "$UKDIR/$BUNDLE"; then
        cp "$PACK/$BUNDLE" "$UKDIR/$BUNDLE" && chmod 644 "$UKDIR/$BUNDLE" || { log "ERROR: cannot copy bundle"; exit 1; }
        log "bundle copied to $UKDIR"
    fi

    # 2. register the culture in the shared core (used by every RfWebUI/WStheme theme)
    if is_patched; then
        log "core already patched"
    else
        mkdir -p "$PACK/backup"
        cp -p "$CORE" "$PACK/backup/ctxs.core.min.js.$(md5 -q "$CORE")"
        # patch goes on its own line so uninstall restores the file byte for byte
        [ "$(tail -c 1 "$CORE" | od -An -c | tr -d ' ')" = '\n' ] || { log "ERROR: $CORE does not end with a newline"; exit 1; }
        printf '%s\n' "$PATCH" >> "$CORE"
        log "core patched"
    fi

    # 3. legacy /vpn and /epa pages: uk.xml in every theme
    xml_install

    # 4. re-apply after reboot / firmware upgrade
    if [ "$(head -n 1 "$RC" 2>/dev/null)" != "$BOOTLINE" ]; then
        touch "$RC"
        # drop an old hook from anywhere in the file, put the current one on top; other lines untouched
        { echo "$BOOTLINE"; grep -v "$MARK" "$RC" || true; } > "$RC.ua_tmp" && cat "$RC.ua_tmp" > "$RC" && rm -f "$RC.ua_tmp"
        log "boot hook set as first line of $RC"
    fi

    note_new_firmware

    # gateway serves logon files from integrated cache; empty after boot, stale after a live install
    log "done. In NetScaler CLI run: $FLUSH"
}

# at every boot, from rc.netscaler in background: apply, then re-check for a few minutes
# in case the portal files appear or get replaced later in the boot
boot() {
    i=0
    while [ ! -f "$CORE" ] && [ $i -lt 30 ]; do sleep 10; i=$((i + 1)); done
    log "boot"
    ( install )
    for i in 1 2 3 4 5; do
        sleep 60
        grep -q "$MARK" "$RC" 2>/dev/null || break      # uninstalled meanwhile
        is_patched && cmp -s "$PACK/$BUNDLE" "$UKDIR/$BUNDLE" && xml_installed && continue
        log "boot: portal files were replaced, applying again"
        ( install )
    done
}

uninstall() {
    # reverse order: unpatch core before removing the bundle
    if is_patched; then
        sed -i '' "/$MARK/d" "$CORE"
        log "core unpatched"
    fi
    rm -f "$UKDIR/$BUNDLE"
    xml_uninstall
    [ -f "$RC" ] && grep -q "$MARK" "$RC" && sed -i '' "/$MARK/d" "$RC" && log "boot hook removed"
    log "uninstalled. In NetScaler CLI run: $FLUSH"
}

status() {
    is_patched && echo "core:      patched" || echo "core:      NOT patched"
    [ -f "$UKDIR/$BUNDLE" ] && echo "bundle:    present" || echo "bundle:    MISSING"
    theme_dirs | while IFS= read -r d; do
        t=$(basename "$(dirname "$d")")
        [ -f "$d/$XML" ] && has_uk "$(theme_config "$d")" && echo "theme:     $t - uk" || echo "theme:     $t - NOT installed"
    done
    grep -q "$MARK" "$RC" 2>/dev/null && echo "boot hook: present" || echo "boot hook: MISSING"
    if firmware_strings_changed; then
        echo "strings:   firmware differs from the pack's build - run: sh $PACK/ua_langpack.sh check"
    else
        echo "strings:   same as the pack's build ($(sed -n '1s/^# netscaler \([^ ]*\).*/\1/p' "$MANIFEST" 2>/dev/null))"
    fi
}

case "$1" in
    install)   install ;;
    boot)      boot ;;
    uninstall) uninstall ;;
    status)    status ;;
    check)     check; exit $? ;;
    *) echo "usage: $0 install|uninstall|status|check"; exit 2 ;;
esac
