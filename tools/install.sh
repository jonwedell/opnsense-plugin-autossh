#!/bin/sh
#
# Stage the plugin directly onto a running OPNsense system, without pkg.
#
# Useful for iterating during development, and as a way to run the plugin on a
# release it has not been packaged for. The files land in exactly the same
# places the package would put them, and the same post-install steps are run.
#
# Because pkg does not know about these files, a firmware upgrade will not
# remove them -- which is the whole point here -- but it also will not update
# or verify them. Re-run this script after changing anything.
#
# Usage:  sh tools/install.sh
#

set -e

PLUGIN_NAME="autossh"
PLUGIN_VERSION="1.0.2"
PLUGIN_MODEL="ThreatPatrols/Autossh"
LOCALBASE="/usr/local"

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)/src

if [ "$(id -u)" != "0" ]; then
    echo "error: must run as root" >&2
    exit 1
fi

if [ ! -f "${LOCALBASE}/sbin/opnsense-version" ]; then
    echo "error: this does not look like an OPNsense system" >&2
    exit 1
fi

if [ ! -d "${SRC_DIR}" ]; then
    echo "error: cannot find ${SRC_DIR}" >&2
    exit 1
fi

PRODUCT_ABI=$("${LOCALBASE}/sbin/opnsense-version" -a)
PRODUCT_ARCH=$("${LOCALBASE}/sbin/opnsense-version" -A)

echo ">>> Installing os-${PLUGIN_NAME} ${PLUGIN_VERSION} for OPNsense ${PRODUCT_ABI}"

if [ ! -x "${LOCALBASE}/bin/autossh" ]; then
    echo "!!! ${LOCALBASE}/bin/autossh is missing. Install it first:"
    echo "        pkg install autossh"
    echo "    Continuing, but no tunnel will start until it is present."
fi

# A hand-rolled rc script managing the same tunnels would fight this plugin
# over the same pidfiles and forwarded ports.
if [ -f "${LOCALBASE}/etc/rc.d/autossh_tunnels" ]; then
    echo "!!! ${LOCALBASE}/etc/rc.d/autossh_tunnels exists."
    echo "    Retire it before using this plugin, otherwise both will manage the"
    echo "    same tunnels:"
    echo "        service autossh_tunnels stop"
    echo "        rm -f ${LOCALBASE}/etc/rc.d/autossh_tunnels /etc/rc.conf.d/autossh_tunnels"
fi

echo ">>> Staging files into ${LOCALBASE}"
tar -C "${SRC_DIR}" -cf - . | tar -C "${LOCALBASE}" -xf -

# Up to 1.0.1 a static syslog-ng snippet was shipped as well. Core already
# generates syslog-ng-autossh.conf from autossh_syslog(), so the two clashed
# and syslog-ng refused to load its configuration. pkg removes the file on
# upgrade; a staged install has to do it here.
STALE_SYSLOG_CONF="${LOCALBASE}/etc/syslog-ng.conf.d/autossh.conf"
if [ -f "${STALE_SYSLOG_CONF}" ]; then
    echo ">>> Removing stale ${STALE_SYSLOG_CONF}"
    rm -f "${STALE_SYSLOG_CONF}"
    RESTART_SYSLOG=1
fi

chmod 0755 "${LOCALBASE}/etc/rc.d/opnsense-${PLUGIN_NAME}"
chmod 0755 "${LOCALBASE}/opnsense/scripts/${PLUGIN_MODEL}/autossh.py"
chmod 0644 "${LOCALBASE}/etc/inc/plugins.inc.d/${PLUGIN_NAME}.inc"

echo ">>> Writing version metadata"
mkdir -p "${LOCALBASE}/opnsense/version"
cat > "${LOCALBASE}/opnsense/version/${PLUGIN_NAME}" <<EOF
{
    "product_abi": "${PRODUCT_ABI}",
    "product_arch": "${PRODUCT_ARCH}",
    "product_id": "os-${PLUGIN_NAME}",
    "product_name": "${PLUGIN_NAME}",
    "product_tier": "3",
    "product_version": "${PLUGIN_VERSION}",
    "product_website": "https://github.com/jonwedell/opnsense-plugin-autossh"
}
EOF

# Volt compiles views into the PHP cache and only recompiles when the source
# mtime is newer. Staged files can arrive with mtimes that defeat that (clock
# skew, archives preserving timestamps), so drop ours explicitly.
echo ">>> Clearing compiled view cache"
rm -f /var/lib/php/cache/*Autossh* 2> /dev/null || true

# Mirror what the package's generated +POST_INSTALL would do, in the same order.
echo ">>> Restarting configd to pick up the new actions"
service configd restart

if [ -f "${LOCALBASE}/opnsense/mvc/script/run_migrations.php" ]; then
    echo ">>> Running model migrations"
    "${LOCALBASE}/opnsense/mvc/script/run_migrations.php" "${PLUGIN_MODEL}"
fi

echo ">>> Reloading plugin configuration (menu, ACL, services)"
/usr/local/etc/rc.configure_plugins POST_INSTALL

echo ">>> Reloading templates"
"${LOCALBASE}/sbin/configctl" template reload "${PLUGIN_MODEL}"

if [ -n "${RESTART_SYSLOG}" ]; then
    echo ">>> Restarting syslog-ng"
    "${LOCALBASE}/sbin/configctl" syslog restart
fi

echo ">>> Restarting the web interface"
"${LOCALBASE}/sbin/configctl" webgui restart

cat <<EOF

Done. The plugin is at VPN: Autossh in the menu.

Next steps:
  1. Check that your existing tunnels and keys are listed (they are read from
     the //ThreatPatrols/Autossh section already in /conf/config.xml).
  2. Press Apply on the Tunnels page to regenerate
     ${LOCALBASE}/etc/autossh/autossh.conf and start what should be running.
  3. Validate the generated configuration before trusting it:
       ${LOCALBASE}/bin/ssh -G -F ${LOCALBASE}/etc/autossh/autossh.conf <tunnel-uuid> > /dev/null && echo CONFIG_OK

EOF
