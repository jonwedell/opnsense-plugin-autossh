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

Usage:  python3 tools/validate.py
"""

import os
import re
import sys
from xml.etree import ElementTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MODEL = os.path.join(ROOT, "src/opnsense/mvc/app/models/ThreatPatrols/Autossh/Autossh.xml")
GENERATOR = os.path.join(ROOT, "src/opnsense/scripts/ThreatPatrols/Autossh/autossh.py")
FORMS = (
    ("src/opnsense/mvc/app/controllers/ThreatPatrols/Autossh/forms/dialogTunnel.xml", "tunnel"),
    ("src/opnsense/mvc/app/controllers/ThreatPatrols/Autossh/forms/dialogKey.xml", "key"),
)


def check_option_defaults(groups, problems):
    for group, node in groups.items():
        for field in node:
            if field.get("type") != "OptionField":
                continue

            options = field.find("optionvalues")
            keys = {option.tag for option in options} if options is not None else set()

            default = field.find("default")
            if default is None or not (default.text or "").strip():
                continue

            for value in [v.strip() for v in default.text.split(",") if v.strip()]:
                if value not in keys:
                    problems.append(f"{group}.{field.tag}: default '{value}' is not a declared option")

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
