# History of the Plugins stage

The stage started 18 Oct 2026 from `docs/handoff-plugins-stage.md` (Stages 1–5 had all passed in-game). Each entry lists what was built, why, and its checklist in `checklists/`. **None of these checklists has been reported back yet.**

## The user's list (from `new_list_for_tungsten.txt`, given at the start)

Keep every round aligned to it.

- Changes:
  1. loading something to the path is universal across all tabs
  2. plugin sub tabs fit the visual style of the main UI
- Plugins in order:
  1. script/module viewer
  2. instance viewer/editor
  3. universal scanner/spy
- **Script + module viewer/editor:** show upvalues, constants, and their respective references; easily change constants and upvalues; different view modes such as table, function, list, etc.
- **Instance view/editor:** 3D view (n/a if not an object), attribute view, expanded properties view, edit properties here, info linking to the script viewer (click to go to that info in the script viewer tab), good overview of the selected instance.
- **Universal spy/scanner:** scans watched things; universal scanning modes; GC connections scanner/spy; scanner features based on the scanner suite the user supplied; spy features based on the spy the user supplied.

The user also attached reference scripts (a spy, a module table editor, an explorer, a scanner suite) for **feature ideas only**. None of their names may appear in Tungsten.

## Rounds

| Round | Built | Checklist |
| --- | --- | --- |
| **P0a** | `base/loaded.luau`: one loaded target for every tab, the path bar showing it (+N, value crumbs), `/load`, `api.loaded`, plugin `Tab.OnLoad`, prime order, `Uses`, `api.plugins.open` → `Exports.reveal` | P0a (28) |
| **P0b** | Sub-tab pills on a Chrome band, badges, sideways scrolling (mock-up approved first) | P0b (12) |
| **P0c** fixes | The Plugins list overlapped its heading. Scale was redone as window size (the user's option a). | P0c (8) |
| **1.1** | ScriptViewer ships (off); `lib/inspect` (what a loaded item is), view, Overview, 12 integrity entries | P1_1 (16) |
| **1.2** | `lib/rows`: Constants, Upvalues, Functions (Tree / List), tables and functions open, cycles, 500-entry cap, pill counts | P1_2 (14) |
| **1.3** | `lib/source`: Source (decompile on demand, threaded, cached by hash) and Contents (a loaded table or a required module's value) | P1_3 (13) |
| **1.4** | Views: Tree, List, Table (`lib/serialize`, a Luau literal with KEEP), Function (by owning function); Table sub-tab renamed Contents | P1_4 (11) |
| **1.5** | `lib/refs`: references of constants and upvalues (filtergc, re-checked, threaded, cap 200, open one) | P1_5 (10) |
| **Fixes** ("remove the overview and make the source the first sub tab… upvalues dont seem to work. reloading the plugin seems to break the tab. run over this for bugs") | No Overview; Source first and decompiled only while open; a script's upvalues from running functions; lazy work while the tab is closed; reload-safe | P1_5b (12). D1 asks for the in-game reload symptom: **still unknown** (couldn't reproduce offline). |
| **1.6** ("there is still no functionality for editing values. please add all necessary functionality in dropdown forms.") | `lib/edit` + `lib/actions`: right-click menu, forms, double-click to edit, editable Table view with Apply / Revert, Undo, read-only confirm (Q10), a script's constants written to its running functions, integrity 49 | P1_6 (16) |
| **1.6b** ("upvalue functionality still doesnt work and upvalues are still not being displayed") | Running functions found three ways (filtergc Environment, then Source re-checked, then getgc); getsenv asked even when not listed as running; Upvalues independent of the copy; empty lists show why; getgc added (integrity 50) | P1_6b (8) |
| **Back button** ("add a back button to the right of the path bar dropdown button which returns you to the previous path or instance") | ← button, `Loaded` history, `arrow_left` icon, `api.loaded.back` | Back (8) |
| **Script paths** ("display there path by their require reference. for example: require(game.workspace.module) and then the functions path within the script") | `base/access.luau`; path bar crumbs `script › require() › keys`; Copy as code; typed paths and `/load` parse it; Script Viewer passes paths on; `api.loaded.access` | ScriptPaths (10) |
| **Next** | The 12-item Script Viewer revamp: see `docs/next-request.md` | — |

## Remaining after the revamp

- **Round 1** has one part left, **1.7**: links from the other plugins, menu entries, and a docs page for the Script Viewer (partly overlapped by the revamp).
- **Round 2, `instanceviewer`:** sub-rounds 2a–2c in `docs/plugins-stage-plan.md`. Decide Q6 and Q11 first.
- **Round 3, `scanner`:** sub-rounds 3a–3d. Decide Q9 and Q13 first.
- **Then Stage 6:** docs, icons and polish.
