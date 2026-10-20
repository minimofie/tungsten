#!/usr/bin/env python3
"""Zips the Tungsten folder for shipping: python3 tools/package.py <out.zip>

Leaves out what Tungsten writes while it runs (logs/, saved/,
base/settings.json, base/plugins.json, the loader's base/installed.txt, any plugin's settings.json) and
plugin folders that aren't the prime plugins Tungsten ships."""
import pathlib, sys, zipfile
PRIME_FOLDERS = {"ScriptViewer", "InstanceViewer", "Scanner"}
SKIP = {"base/settings.json", "base/plugins.json", "base/installed.txt"}

def shipped(rel):
    if rel in SKIP or rel.startswith(("logs/", "saved/")):
        return False
    parts = rel.split("/")
    if parts[0] == "plugins" and len(parts) > 2:
        return parts[1] in PRIME_FOLDERS and parts[-1] != "settings.json"
    return True

root = pathlib.Path("Tungsten")
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    n = 0
    for f in sorted(root.rglob("*")):
        rel = f.relative_to(root).as_posix()
        if f.is_file() and shipped(rel):
            z.write(f, "Tungsten/" + rel)
            n += 1
print(n, "files")
