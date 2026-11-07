#!/usr/bin/env python3
"""Static consistency checks for NetDoctor. Standard library only, no network.

Run from anywhere:  python3 scripts/check.py
Exit code 0 = everything consistent, 1 = at least one problem (each is printed).

What it checks (all of these were once broken by hand, which is why they are automated):
  1. VERSION in `netdoctor` has a matching section in both CHANGELOG files.
  2. The tool list is the same in the web UI (COMMANDS), the SwiftUI app (Tools.swift) and the CLI:
     same ids, same input names, same administrator setting.
  3. Every string the SwiftUI app shows exists in both Localizable.strings files, and the two files have
     the same keys.
  4. Every label / description / placeholder in the web UI has a Chinese translation.
  5. Relative links in the READMEs and CHANGELOGs point at files that exist.
  6. Every CLI command is listed in the usage text (both languages).
"""
import ast
import importlib.util
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []


def p(*parts):
    return os.path.join(ROOT, *parts)


def read(*parts):
    with open(p(*parts), encoding="utf-8") as f:
        return f.read()


def err(msg):
    errors.append(msg)


def section(title):
    print("•", title)


# Text that never needs translating: host names, IPs, numbers, URLs.
NEUTRAL = re.compile(r"^[\w.:/\-,@]*$")
NEUTRAL_EXTRA = {"URL", "DNS"}


def needs_translation(s):
    return s not in NEUTRAL_EXTRA and not NEUTRAL.match(s)


# ---------------------------------------------------------------------------------------------
cli = read("netdoctor")
m = re.search(r"^VERSION=(\S+)", cli, re.M)
VERSION = m.group(1) if m else None

section("1. version / changelog")
if not VERSION:
    err("netdoctor: VERSION= not found")
else:
    for f in ("CHANGELOG.md", "CHANGELOG.en.md"):
        if not re.search(r"^## \[%s\]" % re.escape(VERSION), read(f), re.M):
            err("%s has no '## [%s]' section (VERSION in netdoctor is %s)" % (f, VERSION, VERSION))

# A released version's changelog section is frozen: once the tag v<VERSION> exists, new entries belong
# under [Unreleased]. (This went wrong once: three new features were written into the released section.)
# Needs the tag in the local clone; skipped silently when it is not there (e.g. a shallow checkout).
if VERSION:
    import subprocess
    for f in ("CHANGELOG.md", "CHANGELOG.en.md"):
        pat = r"^## \[%s\][^\n]*\n(.*?)(?=^## \[|\Z)" % re.escape(VERSION)
        r = subprocess.run(["git", "show", "v%s:%s" % (VERSION, f)], cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            continue
        old, new = re.search(pat, r.stdout, re.M | re.S), re.search(pat, read(f), re.M | re.S)
        if old and new and old.group(1).strip() != new.group(1).strip():
            err("%s: the [%s] section changed after tag v%s was created; new entries belong under [Unreleased]"
                % (f, VERSION, VERSION))

# ---------------------------------------------------------------------------------------------
section("2. tool list: web UI / SwiftUI app / CLI")
spec = importlib.util.spec_from_file_location("netdoctor_gui", p("netdoctor-gui.py"))
gui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gui)
web = {c["id"]: c for c in gui.COMMANDS}

swift_src = read("NetDoctorApp", "Sources", "NetDoctor", "Tools.swift")
swift = {}
for chunk in swift_src.split('Tool(id: "')[1:]:
    tid = chunk.split('"', 1)[0]
    # up to the next Tool( is already cut by split; ToolInput(...) parentheses nest, so use plain regexes
    admin = re.search(r"admin:\s*\.(\w+)", chunk)
    swift[tid] = {
        "inputs": re.findall(r'ToolInput\(name:\s*"([^"]+)"', chunk),
        "admin": admin.group(1) if admin else "none",
    }

dispatch = cli[cli.rindex('case "$c" in'):]
cli_ids = {x for g in re.findall(r"([a-z0-9|]+)\)\s*cmd_", dispatch) for x in g.split("|")}

if set(web) != set(swift):
    err("tool ids differ: only in web %s; only in Swift %s" % (sorted(set(web) - set(swift)), sorted(set(swift) - set(web))))
for tid in sorted(set(web) & set(swift)):
    wi = [i["name"] for i in web[tid].get("inputs", [])]
    if wi != swift[tid]["inputs"]:
        err("tool '%s': inputs differ, web=%s swift=%s" % (tid, wi, swift[tid]["inputs"]))
    wa = web[tid].get("admin")
    wa = "required" if wa is True else (wa if wa else "none")
    if wa != swift[tid]["admin"]:
        err("tool '%s': admin setting differs, web=%s swift=%s" % (tid, wa, swift[tid]["admin"]))
for tid in sorted(web):
    if tid not in cli_ids:
        err("tool '%s' has no CLI command in the dispatcher" % tid)

# ---------------------------------------------------------------------------------------------
section("3. SwiftUI localization")


def strings_keys(lang):
    text = read("NetDoctorApp", "Resources", lang + ".lproj", "Localizable.strings")
    return {k.replace('\\"', '"') for k in re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', text, re.M)}


en_keys, zh_keys = strings_keys("en"), strings_keys("zh-Hans")
if en_keys != zh_keys:
    err("Localizable.strings keys differ: only in en %s; only in zh-Hans %s"
        % (sorted(en_keys - zh_keys)[:5], sorted(zh_keys - en_keys)[:5]))

swift_all = "".join(
    read("NetDoctorApp", "Sources", "NetDoctor", f)
    for f in sorted(os.listdir(p("NetDoctorApp", "Sources", "NetDoctor"))) if f.endswith(".swift")
)
used = set()
for pat in (
    r'loc\("((?:[^"\\]|\\.)*)"\)',
    r'\b(?:Text|Button|Label|Toggle|Section|TextField|Menu|Picker)\(\s*"((?:[^"\\]|\\.)*)"',
    r'(?:title|summary|label|placeholder): "((?:[^"\\]|\\.)*)"',
):
    used |= set(re.findall(pat, swift_all))
used = {u.replace('\\"', '"') for u in used}
used = {u for u in used if u and needs_translation(u) and not re.fullmatch(r"[\d\W]*", u) and "\\(" not in u}
missing = sorted(u for u in used if u not in en_keys)
if missing:
    err("strings used by the SwiftUI app but missing from Localizable.strings: %s" % missing)

# ---------------------------------------------------------------------------------------------
section("4. web UI Chinese translations")
zh = gui.ZH
need = []
for c in gui.COMMANDS:
    need += [c["label"], c["desc"]]
    for i in c.get("inputs", []):
        need += [i["label"], i.get("ph", "")]
missing = sorted({s for s in need if s and needs_translation(s) and s not in zh})
if missing:
    err("web UI strings without a Chinese translation in ZH: %s" % missing)

# ---------------------------------------------------------------------------------------------
section("5. documentation links")
for f in ("README.md", "README.en.md", "CHANGELOG.md", "CHANGELOG.en.md"):
    for url in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", read(f)):
        if url.startswith(("http://", "https://", "mailto:")):
            continue
        if not os.path.exists(p(url)):
            err("%s links to %s, which does not exist" % (f, url))

# ---------------------------------------------------------------------------------------------
section("6. usage text lists every command")
usage_m = re.search(r"^usage\(\)\s*\{(.*?)^\}", cli, re.M | re.S)
usage = usage_m.group(1) if usage_m else ""
aliases = {"q", "diagnose", "version", "help", "-v", "--version", "-h", "--help"}
for cid in sorted(cli_ids - aliases):
    if not re.search(r"^\s{2}%s\b" % re.escape(cid), usage, re.M):
        err("command '%s' is not listed in usage()" % cid)
    # both language blocks must list it
    if len(re.findall(r"^\s{2}%s\b" % re.escape(cid), usage, re.M)) < 2:
        err("command '%s' appears only once in usage() (needs the Chinese and the English line)" % cid)

# ---------------------------------------------------------------------------------------------
print()
if errors:
    print("%d problem(s):" % len(errors))
    for e in errors:
        print("  ✗", e)
    sys.exit(1)
print("all consistent (VERSION %s, %d tools)" % (VERSION, len(web)))
