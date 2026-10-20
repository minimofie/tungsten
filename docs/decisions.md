# Decisions

Newest first within each section. Where this file and the original handoff disagree, this file wins.

## Plugins-stage open questions (from the handoff and the plan)

| # | Question | Decision |
| --- | --- | --- |
| Q1 | Several objects selected: load the list or the first? | **Accepted:** the list is loaded; the path bar shows the first plus "+N"; tabs get the whole list. |
| Q2 | Does selecting in the explorer also load? | **Accepted:** no, only explicit loads (Load, the path bar arrow or crumb, a typed path, `/load`, plugins). The selection stays `$sel`. |
| Q3 | Keep per-tab path bar objects? | **Accepted:** no, there is one loaded target; `api.pathbar.show` means "load this". |
| Q4 | Sub-tab style | **Approved** ("all approved, continue"): rounded pills on a Chrome band, the open one AccentSoft, SurfaceHover on hover, icon plus text, badges. Mock-up in `assets/Tungsten_P0b_SubTabs.svg/.png`. |
| Q5 | Do primes ship, and start on? | **Accepted:** they ship in `Tungsten/plugins/<ScriptViewer\|InstanceViewer\|Scanner>/` and start off; the user turns them on in the Plugins tab. This overrides Stage 5's P2 for primes. |
| Q6 | Prime-only explorer rights (`api.explorer.select` / `setProperty`) | **Open**, for round 2. |
| Q7 | Prime load order | **Accepted:** `scriptviewer`, `instanceviewer`, `scanner`. |
| Q8 | Non-Instance loaded targets (function, table, connection, call)? | **Yes** (P0a, `Loaded.target`). |
| Q9 | What does "scans watched things" mean? | **Open**, for round 3. The proposal is a watch list re-checked on an interval, with a change log. |
| Q10 | May the script viewer make a read-only table writable? | **Yes:** only after a confirm, then read-only again straight after (built in 1.6). Frozen tables are never written. |
| Q11 | Edit hidden or non-scriptable properties? | **Open**, for round 2b. The proposal is to always read them and write behind a per-edit confirm. |
| Q12 | Soft links (`Uses`) and the shared hook dispatcher in P0? | **"Links in P0, hook later":** `Uses` and `api.plugins.open` are in P0; the shared `__namecall` dispatcher waits for round 3b. |
| Q13 | Spy on C methods: `hookfunction` or `oth.hook`? | **Open**, for round 3b. The proposal is `oth.hook` for remote methods and `hookfunction` for Luau functions. |

## Decisions made during the Plugins stage (18–20 Oct 2026)

- **Web loader** (20 Oct, "set up the github repo to be loaded via executor loadstring"). `loader.luau` at the repo root is run with `loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/main/loader.luau" }).Body)()`.
  - It installs or updates `workspace/Tungsten/` from `release.txt` (made by `tools/make_release.py`), downloading only files whose hash changed or that were edited, then runs `Tungsten.luau` from the folder.
  - Tungsten itself still runs from local files and downloads nothing. That keeps the "everything local" rule for everything after start-up, and `getcustomasset` icons, `listfiles` and plugins keep working.
  - The loader uses `request`, which has a Volt doc page; `game:HttpGet` has none.
  - All files are downloaded before any is written, so a failed update leaves the workspace copy as it was and runs it. Offline, it runs the workspace copy.
  - It writes only listed files plus its record `base/installed.txt`, and deletes only files it installed that a newer list drops. Settings, logs, saved files and other plugins are never touched.
  - Options: `loadstring(...)({ Branch, Owner, Repo, Run = false })`.
  - The repository must be public for raw.githubusercontent.com to serve it.

- **Path bar shows paths inside scripts** (19 Oct). A function or table inside a script shows as `script path › require()` (or `getsenv()`) `› keys › value` (`base/access`).
  - The path comes with the load, or is searched for: required modules' tables first, then running scripts' globals.
  - Copy gives the code (`require(game.X.M).a.b`); Highlight selects the script.
  - Typed paths and `/load` accept that code. It is only walked, never run, and a module the game hasn't required is never required.
- **Back button** (19 Oct): ← right of the ⌄ menu button. It loads what was loaded before. History is 50 entries with no repeats; destroyed Instances are skipped. It is greyed when there is nothing to go back to, with a tooltip "Back to …". There is no forward button.
- **Editing in the Script Viewer happens through dropdown forms** (19 Oct, "add all necessary functionality in dropdown forms").
  - The right-click menu `scriptviewer.row` offers Change value…, Set to nil / Remove entry (danger), Add entry…, Rename key…, Look into it (to be renamed Inspect), Keep in a variable…, Copy value and Copy path.
  - Double-clicking a row that doesn't open edits it. The Table view is editable with Apply / Revert.
  - Constants keep their type unless the setting "Constants may change type" is on.
  - A script's constants are written to its running functions (same `getfunctionhash` and constants), never only to the recompiled copy. They are refused when nothing runs, or when several different running functions match.
- **Script Viewer layout** (19 Oct, user): **remove the Overview**. Sub-tabs are Source (first), Constants, Upvalues, Functions, Contents. A summary line under the title (e.g. `LocalScript · running`) shows the notes on hover.
- **A script's upvalues come from its running functions** (the recompiled main function has none). They are found by `filtergc` Environment, then `filtergc` Source re-checked, then `getgc` by source name. Upvalues don't need the recompiled copy.
- **Work waits while the tab is closed.** The subject is worked out lazily, decompiling happens only when the Source sub-tab is open, and a shown list is redrawn when the tab opens.
- **Rename** (18 Oct): "object viewer" became **"instance viewer"** (prime id `instanceviewer`, folder `InstanceViewer`).
- **Scale = window size** (18 Oct, user picked option a): the scale makes the window bigger or smaller like resizing it. Spacing grows, not element size; text, buttons, menus and popups keep their size. `Scale.factor()` is 1.
- **Plugins tab list** must not overlap the heading (card outline padding fixed).
- **Tests always run in both modes**, normal and `SHIFT = 58`; the user asked.

## Stage 5 decisions (from the handoff, still in force)

- **P1/P3:** New plugins start off. On/off takes effect at the next start.
- **P2:** Tungsten ships no plugins, except the primes (Q5).
- **P4:** Plugins may depend only on the primes (`Requires`; `Uses` is the soft form). Prime ids are reserved and primes load first.
- **P5:** Faults are reported under the plugin's name and counted; nothing is turned off automatically.
- **P6/P7:** Only program and plugin preferences persist. Reset all doesn't touch plugins (`base/plugins.json`).
- **P8/P9:** Plugins may use the whole Tungsten folder. Reload is for a plugin with a problem; there is no file watching.
- **P10:** One side-bar tab per plugin; more views are sub-tabs.
- There is no `api.data`: plugins persist only `api.settings`. Variables are flat names with an owner.
- Scale is the one universal setting (see above for its current meaning).

## Standing UI decisions (from earlier stages)

- **Clean slate:** start on the Console tab with the explorer open and unfrozen; only preferences persist.
- **Default tabs:** Console, Plugins, Documentation, a divider, then plugin tabs.
- **Explorer:** joined to the window, 200 px at scale 1; services can't be moved; read-only for plugins (except what Q6 may grant primes).
- **Right-click:** Object ›, Function ›, Variable ›, Save ›; plugins add to Function ›.
- **Path bar dropdown (⌄):** only Copy and Highlight (a fixed menu).
- **Clipboard:** the explorer has its own instance clipboard (`/clipboard`); `/copy` uses the computer's clipboard.
- **Freeze:** session only. Added objects are held back, deleted ones show red, moved ones light blue.
- **Command bar:** key `'` (changeable), fixed size, closes on an outside click, keeps no text.
- The only mouse-resizable element is the explorer's tree / properties splitter.
- Colours: a darker grey background with the accent rgb(240, 150, 60).
