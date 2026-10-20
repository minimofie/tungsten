# Testing and delivery

## Offline tests

- **`tests/harness.luau`** is a mock Roblox and Volt runtime.
  - It models Instances, UIScale geometry and input.
  - Time is virtual: `H.advance(seconds)` runs `task` timers and `H.step()` runs one frame.
  - It bundles files: `H.FILES` stands in for the Volt workspace, and the real `Tungsten/` folder is loaded into it by `tests/build_test.py`.
  - It covers Volt's file, loader and hook functions.
- **Script Viewer stand-ins:**
  - Functions are described in `H.FN[fn] = { Constants, Upvalues, Protos, Info, Hash, C, Executor, Env, Source }`.
  - Other state: `H.SCRIPT_CLOSURES`, `H.RUNNING`, `H.SENV`, `H.LOADED`, `H.MODULE_VALUES`, `H.GC`, `H.READONLY`, `H.DECOMPILED`.
  - Switches that make a stand-in fail or behave differently: `H.SETCONSTANT_FAIL`, `H.FILTERGC_ENV_MISS`, `H.FILTERGC_SOURCE_MISS`, `H.FILTERGC_LOOSE`, `H.FILTERGC_WAIT`, `H.DECOMPILE_WAIT`, `H.GETGC_FAIL`.
  - Protos in the mock are plain tables (`{ Info, Constants, Protos }`), so `typeof` says "table" there. Keep that in mind for proto handling.
  - There is no `debug.getproto` stand-in yet. Add one when building the Functions revamp: activated closures can come from a `Closures` field on a proto entry.
- **`tests/README.md`** lists every suite and every mock behaviour. Keep it up to date.
- Shipped prime plugins are set aside unless the suite calls `H.keepPrimes()` before `H.run`. Turn one on with `H.FILES["Tungsten/base/plugins.json"] = '{"On":["scriptviewer"]}'`.
- Useful helpers:
  - `H.run(path)`, `H.find(root, name)`, `H.clickObject(gui)`, `H.hover(gui)`, `H.moveTo(point)`
  - `H.CLIPBOARD`
  - `T = H.genv.Tungsten.Context`
  - console: `T.Console.run("/cmd")` and `C.Lines[i].Plain`
  - menus: `T.Menus.build(id, ctx)`, where each item's `.Callback()` runs it
  - prompts: catch opened prompts with `T.UI.on("Prompt", "Opened", function(handle) … end)`. Forms have `handle.Fields.<key>.Get/Set` and `handle.Submit()`; confirms have `handle.Buttons.Confirm/Cancel.Instance`.
- **Mode `SHIFT = 58`:** `run_all.sh` prepends `SHIFT = 58` to each suite, which offsets the UI in absolute coordinates (`H.ABS_SHIFT = SHIFT or 0` at the top of each suite). Every suite must pass in both modes.
- **Writing a suite:** copy the header of an existing one (`check`, `E_ = H.env`, `H.ABS_SHIFT`). End with the line `print(("<name>: %d passed, %d failed, 0 runtime errors"):format(passed, failed))`. Stay under 200 locals per function; wrap sections in `do … end` when it grows.

```sh
tools/run_all.sh                       # everything, both modes; exit code 0 means all passed
tools/run_all.sh test_p1g.luau         # one suite, both modes
python3 tests/build_test.py . tests/test_p1g.luau /tmp/r.luau && luau /tmp/r.luau   # see a stack trace
```

Current count: 31 suites × 2 modes, 2,953 checks each.

## Delivery per round

1. `python3 tools/make_manifest.py Tungsten`. Always do this after changing anything under `Tungsten/`: the integrity check compares file sizes and the suites fail when it's stale.
2. `python3 tools/package.py out/Tungsten_<round>.zip`, plus a tests zip: `zip -qr out/Tungsten_tests_<round>.zip tests tools`.
3. Write the checklist. Use `checklists/` as the template: an install line, items with ids, expected results, and what to send on failure.
4. Send the changed files, both zips and the checklist. Summarize what changed, what wasn't tested in-game, and what's open. Then stop.
5. Images: draw an SVG and render a PNG (`tools/svg2png.py`, or ImageMagick `-flop` for mirrored icons, keeping RGBA with `PNG32:`).
