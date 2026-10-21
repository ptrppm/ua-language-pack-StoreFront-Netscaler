#!/bin/sh
# Ukrainian language pack for NetScaler Gateway (RfWebUI / WStheme), all portal themes.
# Petro Pikulin, petr.pikulin@gmail.com, https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler
#
# Keep this directory in /nsconfig/ua_langpack (survives reboot and firmware upgrade).
#   sh /nsconfig/ua_langpack/ua_langpack.sh install     - install now and re-apply at every boot
#   sh /nsconfig/ua_langpack/ua_langpack.sh uninstall   - remove everything
#   sh /nsconfig/ua_langpack/ua_langpack.sh status

PACK=$(cd "$(dirname "$0")" && pwd)
LP=/var/netscaler/logon/LogonPoint
CORE=$LP/receiver/js/ctxs.core.min.js
# Gateway serves pre-auth files only from stock directories (a new localization/uk/ gets 302),
# so the bundle lives next to the core.
UKDIR=$LP/receiver/js
BUNDLE=ctxs.strings.uk.js
RC=/nsconfig/rc.netscaler
MARK=UA_LANGPACK
# First line of rc.netscaler, in background: later lines there may block forever (e.g. ntpd_ctl full_start).
BOOTLINE="/bin/sh $PACK/ua_langpack.sh install >> /var/log/ua_langpack.log 2>&1 & # $MARK"

# Must stay on one line: uninstall removes it with sed by the marker.
PATCH=';/*'$MARK'*/(function(d){d.globalization.availableCulture("uk",{name:"uk",englishName:"Ukrainian",nativeName:"\u0423\u043a\u0440\u0430\u0457\u043d\u0441\u044c\u043a\u0430",stringBundle:"/logon/LogonPoint/receiver/js/ctxs.strings.uk.js",customStringBundle:""})})(jQuery);'

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') ua_langpack: $*"; }

is_patched() { grep -q "$MARK" "$CORE" 2>/dev/null; }

install() {
    [ -f "$PACK/$BUNDLE" ] || { log "ERROR: $PACK/$BUNDLE not found"; exit 1; }
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

    # 3. re-apply after reboot / firmware upgrade
    if [ "$(head -n 1 "$RC" 2>/dev/null)" != "$BOOTLINE" ]; then
        touch "$RC"
        # drop an old hook from anywhere in the file, put the current one on top; other lines untouched
        { echo "$BOOTLINE"; grep -v "$MARK" "$RC" || true; } > "$RC.ua_tmp" && cat "$RC.ua_tmp" > "$RC" && rm -f "$RC.ua_tmp"
        log "boot hook set as first line of $RC"
    fi

    # gateway serves logon files from integrated cache; empty after boot, stale after a live install
    log "done. In NetScaler CLI run: flush cache contentGroup loginstaticobjects"
}

uninstall() {
    # reverse order: unpatch core before removing the bundle
    if is_patched; then
        sed -i '' "/$MARK/d" "$CORE"
        log "core unpatched"
    fi
    rm -f "$UKDIR/$BUNDLE"
    [ -f "$RC" ] && grep -q "$MARK" "$RC" && sed -i '' "/$MARK/d" "$RC" && log "boot hook removed"
    log "uninstalled. In NetScaler CLI run: flush cache contentGroup loginstaticobjects"
}

status() {
    is_patched && echo "core:      patched" || echo "core:      NOT patched"
    [ -f "$UKDIR/$BUNDLE" ] && echo "bundle:    present" || echo "bundle:    MISSING"
    grep -q "$MARK" "$RC" 2>/dev/null && echo "boot hook: present" || echo "boot hook: MISSING"
}

case "$1" in
    install)   install ;;
    uninstall) uninstall ;;
    status)    status ;;
    *) echo "usage: $0 install|uninstall|status"; exit 2 ;;
esac
