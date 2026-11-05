PLUGIN_NAME=        autossh
PLUGIN_VERSION=     1.0.0
PLUGIN_COMMENT=     Create and automatically persist SSH based tunnels using autossh
PLUGIN_MAINTAINER=  jon@jonwedell.com
PLUGIN_WWW=         https://github.com/jonwedell/opnsense-plugin-autossh
PLUGIN_DEPENDS=     autossh

PLUGIN_PREFIX=      os-
PLUGIN_SUFFIX=
PLUGIN_DEVEL=       no

.include "../../Mk/plugins.mk"
