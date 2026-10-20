#!/usr/bin/env python3
"""Writes Tungsten/base/data/manifest.luau: every file Tungsten ships with
its size, so the start-up integrity check can tell missing or changed
files. Run it before packaging:

    python3 tools/make_manifest.py Tungsten
"""
import pathlib
import sys

# Files Tungsten writes while it runs, never shipped.
SKIP = {"base/settings.json", "base/plugins.json", "base/data/manifest.luau"}
SKIP_FOLDERS = ("logs/", "saved/")
# The prime plugins Tungsten ships (Plugins stage Q5).
PRIME_FOLDERS = {"ScriptViewer", "InstanceViewer", "Scanner"}


def skipped(rel):
    if rel in SKIP or rel.startswith(SKIP_FOLDERS):
        return True
    # A plugin's folder (plugins/<Folder>/...) belongs to its author, not to
    # Tungsten: only plugins/manager.luau, other files directly in plugins/
    # and the prime plugins Tungsten ships (PRIME_FOLDERS) are Tungsten's.
    # A plugin's settings.json is written while it runs: never listed.
    parts = rel.split("/")
    if parts[0] == "plugins" and len(parts) > 2:
        if parts[1] in PRIME_FOLDERS and parts[-1] != "settings.json":
            return False
        return True
    return False


def main(root):
    root = pathlib.Path(root)
    files = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if skipped(rel):
            continue
        if path.name.startswith(".") or rel.endswith(".bak"):
            continue
        files.append((rel, path.stat().st_size))
    lines = [
        "--[[",
        "\tTungsten · base/data/manifest",
        "\tEvery file Tungsten ships with and its size in bytes (made by",
        "\ttools/make_manifest.py). The start-up integrity check uses it.",
        "]]",
        "",
        "return {",
    ]
    for rel, size in files:
        lines.append('\t["%s"] = %d,' % (rel, size))
    lines.append("}")
    lines.append("")
    (root / "base/data/manifest.luau").write_text("\n".join(lines), newline="\n")
    print("%d files" % len(files))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Tungsten")
