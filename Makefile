PLUGIN_NAME=        autossh
PLUGIN_VERSION=     1.0.1
PLUGIN_COMMENT=     Create and automatically persist SSH based tunnels using autossh
PLUGIN_MAINTAINER=  jon@jonwedell.com
PLUGIN_WWW=         https://github.com/jonwedell/opnsense-plugin-autossh
PLUGIN_DEPENDS=     autossh

#
# Do not set PLUGIN_DEVEL or PLUGIN_SUFFIX here. Mk/plugins.mk selects the
# devel branch on `.if "${PLUGIN_DEVEL}" != ""`, so even PLUGIN_DEVEL=no
# counts as yes: the package would declare ${PLUGIN_NAME} as its own conflict
# and firmware/register.php would scrub it straight back out of the plugin
# inventory, leaving it permanently "(misconfigured)". PLUGIN_PREFIX defaults
# to os- and PLUGIN_SUFFIX to -devel, which is what we want.
#

.include "../../Mk/plugins.mk"
