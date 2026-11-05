#!/bin/sh
#
# Remove a staged (non-pkg) installation of this plugin.
#
# Tunnel and key definitions in /conf/config.xml are left alone, as is
# /var/db/autossh, so a later re-install picks up where this left off.
#
# Usage:  sh tools/uninstall.sh
#

set -e

PLUGIN_NAME="autossh"
PLUGIN_MODEL="ThreatPatrols/Autossh"
LOCALBASE="/usr/local"

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)/src

if [ "$(id -u)" != "0" ]; then
    echo "error: must run as root" >&2
    exit 1
fi

if [ ! -d "${SRC_DIR}" ]; then
    echo "error: cannot find ${SRC_DIR}, needed to know which files to remove" >&2
    exit 1
fi

echo ">>> Stopping tunnels"
if [ -x "${LOCALBASE}/etc/rc.d/opnsense-${PLUGIN_NAME}" ]; then
    "${LOCALBASE}/etc/rc.d/opnsense-${PLUGIN_NAME}" stop || true
fi

echo ">>> Removing staged files"
(cd "${SRC_DIR}" && find . -type f) | while read -r FILE; do
    rm -f "${LOCALBASE}/${FILE#./}"
done
(cd "${SRC_DIR}" && find . -type d -depth) | while read -r DIR; do
    rmdir "${LOCALBASE}/${DIR#./}" 2> /dev/null || true
done

rm -f "${LOCALBASE}/opnsense/version/${PLUGIN_NAME}"

echo ">>> Removing generated configuration"
rm -f /etc/rc.conf.d/${PLUGIN_NAME}
rm -f "${LOCALBASE}/etc/${PLUGIN_NAME}/${PLUGIN_NAME}.conf"

echo ">>> Reloading plugin configuration"
service configd restart
/usr/local/etc/rc.configure_plugins POST_DEINSTALL
"${LOCALBASE}/sbin/configctl" webgui restart

cat <<EOF

Removed. Left in place on purpose:
  /conf/config.xml  ->  the //ThreatPatrols/Autossh tunnel and key definitions
  /var/db/autossh   ->  private keys and known_hosts files
  /var/log/autossh  ->  logs

EOF
