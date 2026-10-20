# Tungsten — stage status

**Current:** Plugins stage, round 1 (`scriptviewer`) parts 1.1–1.6 built, plus the 12-item **revamp** (20 Oct 2026; `Tungsten_revamp.zip`, checklist `Tungsten_Revamp_Checklist.md`) and the web loader. Round P0 built; its in-game checklists (P0a 28, P0b 12, P0c 8) and the round 1 checklists (1.1 16, 1.2 14, 1.3 13, 1.4 11, 1.5 10, fixes 12, 1.6 16, 1.6b 8, back button 8, script paths 10) are still to be run; the reload symptom (fixes D1) is still to be described. **Next:** 1.7 links / menus / docs; then round 2 `instanceviewer`, round 3 `scanner` (plan: the "Tungsten — Plugins Stage Plan" doc), then Stage 6.

## The user's list (new_list_for_tungsten.txt) — keep every round aligned to it
- Changes: one loaded thing for every tab (done, P0a); plugin sub-tabs in the main UI's style (done, P0b).
- Script/module viewer: show upvalues, constants and their references (shown: 1.2; references: 1.5); easily change constants and upvalues (done, 1.6: right-click menu + dropdown forms, Table view Apply); view modes such as table, function, list (1.4; revamp: Tree to explore, List to search and filter, Table for bulk changes; the Function view became the scope "With nested functions").
- Universal scanner/spy: scans watched things (Q9 open), universal scanning modes, GC connections scanner/spy, scanner features after the scanner suite, spy features after the spy (round 3).
- Instance viewer/editor: 3D view (n/a when not an object), attributes, expanded properties, edit properties here, links into the script viewer / scanner, a good overview of the selected instance (round 2).

## Plugins stage decisions
- Prime plugins, in load order: `scriptviewer`, `instanceviewer` (renamed from "object viewer" 18 Oct), `scanner`. They ship in `Tungsten/plugins/<ScriptViewer|InstanceViewer|Scanner>/` and start off (Q5); `tools/package.py` zips them, `make_manifest.py` lists them.
- Q1 several loaded objects: the list is loaded; path bar shows the first + "+N". Q2 only explicit loads. Q3 one loaded target, no per-tab path bars. Q7 order as above. Q8 non-Instance targets (`Loaded.target`). Q12 `Uses` + `api.plugins.open` in P0; shared `__namecall` dispatcher in round 3b. Q4 pill sub-tabs approved.
- Q10 (19 Oct): yes — a read-only table may be made writable to edit it, only after a confirm, then made read-only again (part 1.6).
- Scale = window size (18 Oct): makes the window bigger or smaller like resizing it; contents and popups keep their size.
- Still open: Q6 (prime explorer rights, round 2), Q9 (what "scans watched things" means, round 3), Q11 (hidden properties, round 2), Q13 (`oth.hook` vs `hookfunction`, round 3b).

## Round P0 — what it built
- **P0a:** `base/loaded.luau` (one loaded target; every tab's `OnLoad(values, tab, items)`; `Changed(items, by)`; destroyed Instances drop out), path bar shows it (+N, value crumbs), `/load`, `api.loaded`, plugin `Tab.OnLoad`, prime reorder, `Uses`, `api.plugins.open(id, focus)` → `Exports.reveal`.
- **P0b:** pill sub-tabs on a Chrome band, badges (`tabs:Badge`), sideways scrolling.
- **Fixes:** Plugins list padding; scale redone as window size (`Scale.factor()` = 1, `Scale.get()` = the stored scale).

## Round 1 — script viewer (`plugins/ScriptViewer`)
- **1.1:** `lib/inspect` (what a loaded item is; Volt calls guarded; never requires an unrequired module), `lib/view`, Overview; 12 Volt functions added to the integrity list (45 total).
- **1.2:** `lib/rows`; Constants, Upvalues, Functions sub-tabs; tables / functions open; cycles; 500-entry cap; pill counts.
- **1.3:** `lib/source` — Source (decompile only when looked at, in a thread, cached by script hash, stale results dropped, Copy); Contents (loaded table / required module's table).
- **1.4:** views per data sub-tab, kept in settings: Tree, List, Table (`lib/serialize`, Luau table literal with KEEP for unwritable values), Function (rows grouped by owning function). The "Table" sub-tab renamed Contents.
- **1.5:** `lib/refs` — references of a constant / upvalue / entry (filtergc, results re-checked, capped at 200, in a thread), opening one loads it.
- **Fixes (19 Oct):** Overview removed; sub-tabs Source, Constants, Upvalues, Functions, Contents (Source first; decompiles only while open); a summary line under the title; a script's / module's upvalues from its running functions (filtergc Environment); lazy work while the tab is closed; reload / re-run safe.
- **1.6:** `lib/edit` + `lib/actions` — right-click menu `scriptviewer.row` (Change value…, Set to nil / Remove entry, Add entry…, Rename key…, Look into it, Keep in a variable…, Copy value, Copy path); forms with Type dropdowns (constants keep their type unless "Constants may change type" is on); double-click edits a row that doesn't open; Add entry button on Contents; Table view editable with Apply / Revert (only differences written, KEEP keeps a value, all or none); every change an Undo step; read-only tables after a confirm (Q10), frozen never. A script's constants (read from getscriptclosure's copy) are written to its running functions with the same getfunctionhash / constants, and refused when none runs. Integrity list 49.
- **1.6b (19 Oct, user: upvalues still not shown):** a script's running functions found three ways — filtergc Environment (getsenv), then filtergc Source = full name (re-checked with debug.info), then getgc by source name; getsenv asked even when getrunningscripts doesn't list the script; Upvalues no longer needs the compiled copy; an empty list shows why in full, the bar's text on hover. getgc added (integrity 50).
- **Back button (19 Oct, user request):** ← right of the path bar's ⌄ button; `base/loaded` remembers every load and clear (50, no repeats, destroyed Instances skipped): `Loaded.back / canGoBack / previous / history / clearHistory`, `api.loaded.back / canGoBack / previous`. Greyed when nothing to go back to; tooltip "Back to …". Icon `arrow_left` (svg + png).
- **Paths inside scripts (19 Oct, user request):** `base/access` (T.Access) — a value is reached as `require(module)` / `getsenv(script)` + keys + `debug.getupvalues(…)[n]`; targets carry `Access`; the path bar shows script path › require() › keys › value (found when not given: required modules' tables, then running scripts' globals, BFS 5 deep, budget 20,000, cached), step crumbs load that table, Copy = code, Highlight = script; typed paths and `/load` parse it (walked, never run; unrequired modules refused); Script Viewer Look into it passes the path; `api.loaded.access`.

- **Revamp (20 Oct, user's 12 items):**
  - Path bar: ⟳ reload button right of → (`Loaded.reload`: values inside scripts read again, not remembered for back); typed `$name`; `base/access` steps for nested functions `debug.getproto(f, n)` and running copies `debug.getproto(f, n, true)[k]` (integrity 51).
  - Data sub-tabs: a scrolling work area (list ≥ 420 px), References as a toggle (off by default), views Tree / List (search + type filter + "N of M") / Table (capped at 20,000 entries), scope This function / With nested functions on Constants and Upvalues; view and scope switches deferred and guarded (item 2).
  - Menus: **Inspect** replaces Look into it (tables, functions, nested functions, Instances; opens the sub-tab that fits); Copy path only when Inspect applies and code reaches the value.
  - Functions: running functions + In the bytecode for scripts, nested functions for functions; Line column; details pane (facts, Inspect, Load, Running copy…, Keep in a variable…, Copy path, Copy hash).
  - Nested functions as subjects (kind "proto"): constants through the ProtoProxy, Upvalues = running copies (editable), Functions = its nested ones; from a script's bytecode copy: matched to the script's running functions.
  - Forms: one value field (`scriptviewer_value`): only relevant types + "variable" with a variable picker; Keep in a variable suggests a name.
  - `docs.md` for the Script Viewer; topics 06 and 09 updated.

## Stage 5 decisions (P1–P10)
- P1/P3 on/off at the next start. P2 ships no plugins except primes. P4 depend only on primes (`Requires` / `Uses`). P5 faults reported and counted, never auto-off. P6/P7 only preferences persist; Reset all leaves plugins alone. P8 plugins may use the whole folder. P9 reload for a plugin with a problem. P10 one side-bar tab per plugin; views are sub-tabs. No `api.data`. Variables: flat names with an owner.
- Work in small stages, stopping at clean points to confirm.

## Numbers
- Offline tests, all passing in normal and SHIFT = 58 mode: 3,191 each in 37 suites (… + P1a 55, P1b 41, P1c 33, P1d 42, P1e 25, P1f 48, P1g 88, pathback 26, access 44, loader 53, pathreload 48, svviews 33, svinspect 19, svfunctions 44, svforms 29).
- The test harness sets the shipped prime plugins aside for older suites; suites that test them call `H.keepPrimes()`.
- Package: `python3 tools/make_manifest.py Tungsten`, `python3 tools/make_release.py`, then `python3 tools/package.py <out.zip>`.
- Web loader (20 Oct): `loader.luau` + `release.txt` at the repo root; `test_loader` (53).
