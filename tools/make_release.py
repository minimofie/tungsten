#!/usr/bin/env python3
"""Writes release.txt at the repo root: every file the loader (loader.luau)
downloads into Volt's workspace/Tungsten/, with a content hash and its size.
Run it after make_manifest.py, before committing:

    python3 tools/make_release.py

Lines: "version <x>", then "<sha1, 12 hex> <size> <path under Tungsten/>".
The same files ship as package.py zips: what Tungsten writes while it runs
(logs/, saved/, settings, the loader's own record) and plugin folders other
than the primes are left out, so an update never touches them."""
import hashlib, pathlib, re, sys

PRIME_FOLDERS = {"ScriptViewer", "InstanceViewer", "Scanner"}
SKIP = {"base/settings.json", "base/plugins.json", "base/installed.txt"}


def shipped(rel):
    if rel in SKIP or rel.startswith(("logs/", "saved/")):
        return False
    parts = rel.split("/")
    if parts[-1].startswith(".") or rel.endswith(".bak"):
        return False
    if parts[0] == "plugins" and len(parts) > 2:
        return parts[1] in PRIME_FOLDERS and parts[-1] != "settings.json"
    return True


def main(repo):
    repo = pathlib.Path(repo)
    root = repo / "Tungsten"
    version = re.search(r'local VERSION = "([^"]+)"', (root / "Tungsten.luau").read_text()).group(1)
    lines = ["version " + version]
    for f in sorted(root.rglob("*")):
        rel = f.relative_to(root).as_posix()
        if f.is_file() and shipped(rel):
            data = f.read_bytes()
            if " " in rel:
                sys.exit("release: no spaces allowed in shipped paths: " + rel)
            lines.append("%s %d %s" % (hashlib.sha1(data).hexdigest()[:12], len(data), rel))
    (repo / "release.txt").write_text("\n".join(lines) + "\n", newline="\n")
    print(len(lines) - 1, "files, version", version)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
