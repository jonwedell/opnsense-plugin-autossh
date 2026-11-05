# os-autossh — OPNsense plugin

Create and automatically persist SSH tunnels on OPNsense using
[autossh](https://www.harding.motd.ca/autossh/): local, remote and dynamic port
forwards, plus layer 2/3 tun/tap tunnels, monitored and re-established when they
drop.

This is a modernized rewrite of the [Threat Patrols
os-autossh](https://github.com/threatpatrols/opnsense-plugin-autossh) plugin,
whose last release (v0.2.42, October 2022) was built for OPNsense 25.1 and
earlier. Upgrading past that removes the package, which takes the web UI with
it while leaving the generated files behind — tunnels keep running until the
next reboot, with nothing left to restart them.

> **Status: not yet tested on hardware.** Every integration point was checked
> against the OPNsense 26.7.8 sources and the generator is covered by a static
> validator, but no part of this has run on a live firewall. Treat the first
> install as a test, and keep a console session open.

## Compatibility with the original

The model is mounted at the same place as the original, `//ThreatPatrols/Autossh`,
and uses the same field names, option keys and model version (`0.3.0`). An
existing `/conf/config.xml` is read as-is: tunnels and keys appear immediately,
no migration or re-entry required.

Check what is there before installing:

```sh
grep -c ThreatPatrols /conf/config.xml
```

## Requirements

* OPNsense 26.7 or later (built and verified against 26.7.8)
* `pkg install autossh` — pulls in `openssh-portable`, providing
  `/usr/local/bin/ssh`

## Install

### From a built package

```sh
pkg add os-autossh-1.0.0.pkg
```

### Staged, without pkg

Useful for development, and on releases this has not been packaged for. Files
land exactly where the package would put them and the same post-install steps
run. A firmware upgrade will not remove them, but will not update them either.

```sh
git clone https://github.com/jonwedell/opnsense-plugin-autossh
cd opnsense-plugin-autossh
sh tools/install.sh     # sh tools/uninstall.sh to reverse
```

The plugin appears under **VPN → Autossh**.

## Build

`Mk/plugins.mk` from the OPNsense plugins tree is self-contained — it generates
`+MANIFEST`, `+DESC` and the plist itself and calls `pkg create` directly, with
no ports tree involved. The only FreeBSD-specific requirements are `make` and
`pkg`, so no FreeBSD machine of your own is needed:

* **GitHub Actions** — `.github/workflows/package.yml` lints on `ubuntu-latest`,
  then builds inside a FreeBSD 15.1 VM via `vmactions/freebsd-vm`. The `.pkg`
  is uploaded as an artifact, and attached to the release on a `v*` tag.
* **Locally on FreeBSD 15.x**, if you have one:

  ```sh
  git clone -b 26.7.8 https://github.com/opnsense/plugins /tmp/plugins
  mkdir -p /tmp/plugins/net/autossh
  cp -a . /tmp/plugins/net/autossh/
  cd /tmp/plugins/net/autossh && make package   # -> work/pkg/*.pkg
  ```

Run the static checks any time, on any platform:

```sh
python3 tools/validate.py
```

## What changed from the original

**Current OPNsense idioms.** The hand-rolled controllers and `UIModelGrid`
plumbing are replaced by `ApiMutableModelControllerBase` CRUD (`searchBase`,
`addBase`, `setBase`, `delBase`, `toggleBase`) with grids and dialogs generated
from the form XML via `getFormGrid`. Saving a tunnel no longer restarts it as a
side effect: edits are staged and applied with the standard Apply button.

**Selective restarts.** Apply renders each tunnel's `Host` block, compares it
against what is installed, and only restarts tunnels whose configuration
actually changed. Newly enabled tunnels are started, removed and disabled ones
stopped. Previously, new tunnels had to be started by hand.

**One config generator instead of a template plus a rewriting pass.** The
original rendered a Jinja template and then had Python reopen the result to
string-replace option keys with algorithm names, resolve the bind interface,
and inject the identity file. That is now a single Python generator that writes
the whole `ssh_config`, reading option-key mappings from the model XML so there
is still one source of truth. Writes go through a temporary file and `rename`,
so a running tunnel never reads a half-written identity or config.

**Current ssh directives.** `PubkeyAcceptedKeyTypes` → `PubkeyAcceptedAlgorithms`,
and `ChallengeResponseAuthentication yes` → `KbdInteractiveAuthentication no`.
(The original set both, and since ssh honours the *first* value it sees, the
deprecated alias won.) Post-quantum key exchange (`mlkem768x25519-sha256`,
`sntrup761x25519-sha512@openssh.com`) and the `rsa-sha2-*` algorithms are
offered and used by default; SHA-1 algorithms and `ssh-rsa` remain selectable
for old remotes but are no longer default. DSA key generation is gone, since
OpenSSH 10 removed DSA entirely.

**`Tunnel` / `TunnelDevice` implemented.** The original model had the fields but
its template left them as `[todo]`, so layer 2/3 tunnels silently did nothing.

**Validation.** The model rejects a tunnel that forwards nothing and has no
tunnel mode, a tunnel mode without a device, and a key record with no material.
A key still referenced by a tunnel cannot be deleted. Key type and material are
pinned after creation.

**A real rc script.** `# REQUIRE: NETWORKING DAEMON LOGIN SERVERS` and
`# KEYWORD: shutdown` were missing, so boot ordering was down to luck and
tunnels were not stopped cleanly on shutdown. `stop` now also reaps tunnels
that have been removed from the configuration.

## Layout

```
Makefile                                      plugin metadata for Mk/plugins.mk
src/etc/inc/plugins.inc.d/autossh.inc         service + syslog + HA registration
src/etc/rc.d/opnsense-autossh                 per-tunnel rc script
src/etc/syslog-ng.conf.d/autossh.conf         log target for /var/log/autossh
src/opnsense/mvc/app/models/…/Autossh.{xml,php}   data model and validation
src/opnsense/mvc/app/controllers/…/Api/        Tunnels, Keys, Connections, Service
src/opnsense/mvc/app/controllers/…/forms/      dialog + grid definitions
src/opnsense/mvc/app/views/…/*.volt            Tunnels/Keys page, Connection Status
src/opnsense/scripts/…/autossh.py              config generator, keygen, status
src/opnsense/service/conf/actions.d/           configd actions
src/opnsense/service/templates/…/              /etc/rc.conf.d/autossh
tools/{install,uninstall}.sh, tools/validate.py
```

## Notes

* Private keys live in `/conf/config.xml` (base64) and are materialized to
  `/var/db/autossh/<uuid>.identity` at 0600 on Apply. Config backups therefore
  contain your tunnel private keys — treat them accordingly.
* The public key is handed out with
  `command="",no-agent-forwarding,no-pty,no-user-rc,no-X11-forwarding`
  prepended; install it on the remote with those restrictions intact so the key
  can forward ports and nothing else.
* A `RemoteForward` bound to anything other than loopback also needs
  `GatewayPorts` on the remote sshd.
* Each enabled tunnel registers as its own service, so it appears individually
  under **System → Diagnostics → Services**.

## Licence

BSD-2-Clause. Copyright (c) 2018 Verb Networks, (c) 2022 Threat Patrols Pty Ltd,
(c) 2026 Jon Wedell.
