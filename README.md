# Tungsten

A client-side Luau script for the Volt executor (Roblox): an explorer + console base with plugins in tabs.

## Run it

Paste this into Volt and execute:

```lua
loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/loader.luau" }).Body)()
```

`HEAD` is the repository's default branch. If nothing happens or you get "attempt to call a nil value", the download failed; this longer line says why:

```lua
local r = request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/loader.luau" }); assert(r.StatusCode == 200, "Tungsten loader: HTTP " .. tostring(r.StatusCode)); loadstring(r.Body)()
```

The loader downloads Tungsten into Volt's `workspace/Tungsten/` folder and starts it. On later runs it downloads only the files that changed, so the same line also updates Tungsten. Your settings, logs, saved files and added plugins are never touched. If GitHub can't be reached, the copy already in the workspace runs.

Options go in a table after the chunk:

```lua
-- run from another branch, or update without starting Tungsten
loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/dev/loader.luau" }).Body)({ Branch = "dev" })
loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/loader.luau" }).Body)({ Run = false })
```

| Option | Default | Meaning |
| --- | --- | --- |
| `Branch` | `"HEAD"` (the repository's default branch) | branch to download from |
| `Owner` / `Repo` | `"minimofie"` / `"tungsten"` | for a fork |
| `Run` | `true` | `false` updates the folder without starting Tungsten |

Without the loader: copy `Tungsten/` into Volt's `workspace/Tungsten/` and run `Tungsten.luau`.

## The repository

- `Tungsten/`: the script (what ships)
- `loader.luau`, `release.txt`: the web loader and the file list it downloads by (`tools/make_release.py`)
- `tests/`, `tools/`: offline mock runtime, suites, packaging (`tools/run_all.sh`)
- `docs/`: handoff, plan, decisions, Volt notes, status, the next task
- `checklists/`: in-game checklists per round
- `CLAUDE.md`: start here when working on it with Claude Code
