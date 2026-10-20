import pathlib, sys
root = pathlib.Path(sys.argv[1])  # folder containing Tungsten/
test = pathlib.Path(sys.argv[2])
out = pathlib.Path(sys.argv[3])
parts = ["local FILES = {}\n"]
eq = "=" * 9
for f in sorted(root.glob("Tungsten/**/*")):
    if f.is_file():
        rel = f.relative_to(root).as_posix()
        if f.suffix in (".luau", ".json", ".md"):
            parts.append(f'FILES["{rel}"] = [{eq}[{f.read_text()}]{eq}]\n')
        else:
            parts.append(f'FILES["{rel}"] = "<binary>"\n')
# Test-only fixtures (never shipped) are available as FILES["fixtures/<name>"].
fixtures = pathlib.Path(__file__).with_name("fixtures")
for f in sorted(fixtures.glob("*.luau")):
    parts.append(f'FILES["fixtures/{f.name}"] = [{eq}[{f.read_text()}]{eq}]\n')
# Plugin folders for the plugin host tests: FILES["fixtures/plugins/<Folder>/<file>"].
for f in sorted(fixtures.glob("plugins/**/*")):
    if f.is_file():
        rel = f.relative_to(fixtures).as_posix()
        parts.append(f'FILES["fixtures/{rel}"] = [{eq}[{f.read_text()}]{eq}]\n')
harness = pathlib.Path(__file__).with_name("harness.luau").read_text()
parts.append("local H = (function()\n" + harness + "\nend)()\n")
parts.append(test.read_text())
out.write_text("".join(parts))
