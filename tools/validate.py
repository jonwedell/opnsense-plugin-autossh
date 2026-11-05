#!/usr/bin/env python3

"""
Static consistency checks for the plugin sources.

Runs anywhere Python 3 does -- no FreeBSD, no OPNsense -- so it can gate a pull
request before the packaging job spins up a VM. Catches the class of mistake
that otherwise only shows up as an empty dropdown or a silently dropped ssh
option on a live firewall:

  * an OptionField default that names an option key which does not exist
  * a single-value field carrying a comma separated default
  * a form field id with no matching model field
  * a generator/model mismatch in the option-key mapping tables
  * a generator reading a tunnel field the model does not define
  * an installed configuration that reads back as changed when it is not,
    which would restart tunnels needlessly on every Apply

Usage:  python3 tools/validate.py
"""

import importlib.util
import os
import re
import sys
import tempfile
from xml.etree import ElementTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MODEL = os.path.join(ROOT, "src/opnsense/mvc/app/models/ThreatPatrols/Autossh/Autossh.xml")
GENERATOR = os.path.join(ROOT, "src/opnsense/scripts/ThreatPatrols/Autossh/autossh.py")
FORMS = (
    ("src/opnsense/mvc/app/controllers/ThreatPatrols/Autossh/forms/dialogTunnel.xml", "tunnel"),
    ("src/opnsense/mvc/app/controllers/ThreatPatrols/Autossh/forms/dialogKey.xml", "key"),
)


def option_keys(field):
    """Return the option keys the model will actually accept for a field.

    BaseModel::parseOptionData keys the option list by the `value` attribute
    when one is present, falling back to the element name otherwise. So for
    `<ciphers_01 value="aes128-ctr">` the accepted value is `aes128-ctr`; the
    element name is only an XML-legal placeholder (option keys like
    `chacha20-poly1305@openssh.com` are not valid element names) and never
    reaches the model.
    """
    options = field.find("optionvalues")
    if options is None:
        return []

    return [
        option.get("value") if option.get("value") is not None else option.tag
        for option in options
    ]


def check_option_defaults(groups, problems):
    for group, node in groups.items():
        for field in node:
            if field.get("type") != "OptionField":
                continue

            keys = option_keys(field)

            # a duplicate value attribute silently collapses two options into one
            for key in {k for k in keys if keys.count(k) > 1}:
                problems.append(f"{group}.{field.tag}: option key '{key}' is declared more than once")

            default = field.find("default")
            if default is None or not (default.text or "").strip():
                continue

            for value in [v.strip() for v in default.text.split(",") if v.strip()]:
                if value not in keys:
                    problems.append(f"{group}.{field.tag}: default '{value}' is not an accepted option")

            multiple = field.find("multiple")
            if (multiple is None or multiple.text != "Y") and "," in default.text:
                problems.append(f"{group}.{field.tag}: single-value field has a multi-value default")


def check_forms(fields, problems):
    for form_file, prefix in FORMS:
        root = ElementTree.parse(os.path.join(ROOT, form_file)).getroot()
        for field in root.findall("field"):
            identifier = field.find("id")
            if identifier is None:
                continue  # headers and separators carry no id

            group, _, name = (identifier.text or "").partition(".")
            if group != prefix:
                problems.append(f"{form_file}: id '{identifier.text}' should start with '{prefix}.'")
            elif name not in fields[prefix]:
                problems.append(f"{form_file}: id '{identifier.text}' has no matching model field")


def check_generator(groups, fields, problems):
    source = open(GENERATOR, encoding="utf-8").read()

    declared = set(re.findall(
        r'^\s+"([a-z_]+)",$',
        source.split("MAPPED_FIELDS = (")[1].split(")")[0],
        re.M,
    ))

    for name in declared:
        field = groups["tunnel"].find(name)
        if field is None:
            problems.append(f"MAPPED_FIELDS references unknown model field '{name}'")
        elif field.find("optionvalues") is None:
            problems.append(f"MAPPED_FIELDS field '{name}' declares no optionvalues")

    for name in set(re.findall(r'resolve_mapped\("([a-z_]+)"', source)) - declared:
        problems.append(f"resolve_mapped('{name}') is not listed in MAPPED_FIELDS")

    for name in set(re.findall(r'tunnel\.get\("([a-z_]+)"', source)) - fields["tunnel"]:
        problems.append(f"generator reads tunnel field '{name}' which the model does not define")


def load_generator():
    # importing would otherwise drop a __pycache__ into src/, which
    # tools/install.sh would then stage onto the firewall
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("autossh_generator", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_change_detection(problems):
    """Render a configuration the way generate() does, read it back, and
    require that no unchanged tunnel is reported as changed."""
    generator = load_generator()
    tunnel = {"hostname": "remote.example", "user": "tunnel", "local_forward": "8080 127.0.0.1:80"}
    uuids = ("00000000-0000-0000-0000-00000000000a", "00000000-0000-0000-0000-00000000000b",
             "00000000-0000-0000-0000-00000000000c")
    blocks = {uuid: generator.render_tunnel(uuid, tunnel, {}, {}) for uuid in uuids}

    with tempfile.TemporaryDirectory() as workdir:
        filename = os.path.join(workdir, "autossh.conf")
        with open(filename, "w", encoding="utf-8") as handle:
            handle.write(generator.CONFIG_HEADER + "".join("\n" + blocks[uuid] for uuid in sorted(blocks)))
        installed = generator.read_existing_blocks(filename)

    for uuid, block in blocks.items():
        if uuid not in installed:
            problems.append(f"change detection: block {uuid} not found when read back")
        elif generator.block_changed(installed[uuid], block):
            problems.append(f"change detection: unchanged block {uuid} reads back as changed")

    altered = generator.render_tunnel(uuids[0], dict(tunnel, port="2222"), {}, {})
    if uuids[0] in installed and not generator.block_changed(installed[uuids[0]], altered):
        problems.append("change detection: a changed block reads back as unchanged")


def check_makefile(problems):
    """Guard the Makefile knobs that are easy to get backwards.

    Mk/plugins.mk takes the devel branch on `.if "${PLUGIN_DEVEL}" != ""`, so
    any non-empty value -- `no` included -- makes the package declare
    ${PLUGIN_NAME} as its own conflict. firmware/register.php then scrubs the
    plugin out of the inventory as obsolete immediately after registering it,
    and the Plugins page reports it as "(misconfigured)" forever.
    """
    source = open(os.path.join(ROOT, "Makefile"), encoding="utf-8").read()

    for knob in ("PLUGIN_DEVEL", "PLUGIN_SUFFIX"):
        for line in source.splitlines():
            if line.startswith("#"):
                continue
            if re.match(rf"^\s*{knob}\s*[?:]?=", line):
                problems.append(
                    f"Makefile sets {knob} ({line.strip()!r}); leave it unset so the "
                    f"package does not conflict with itself"
                )


def main():
    model = ElementTree.parse(MODEL).getroot()
    groups = {
        "tunnel": model.find("./items/tunnels/tunnel"),
        "key": model.find("./items/keys/key"),
    }

    for name, node in groups.items():
        if node is None:
            print(f"error: cannot find the {name} definition in {MODEL}", file=sys.stderr)
            return 2

    fields = {name: {child.tag for child in node} for name, node in groups.items()}

    problems = []
    check_option_defaults(groups, problems)
    check_forms(fields, problems)
    check_generator(groups, fields, problems)
    check_change_detection(problems)
    check_makefile(problems)

    print(f"model: {len(fields['tunnel'])} tunnel fields, {len(fields['key'])} key fields")

    if problems:
        print(f"\n{len(problems)} problem(s) found:")
        for problem in problems:
            print(" -", problem)
        return 1

    print("no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
