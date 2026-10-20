# Tungsten: project memory for Claude Code

Tungsten is a client-side **Luau** script for the **Volt** Roblox executor. It is an explorer-and-console base that plugins extend, each in its own side-bar tab. Everything it runs lives under Volt's `workspace/Tungsten/`.

The user tests in-game in Volt. You build, run the offline tests, then hand over files plus a checklist. Read this file first, then the docs it points to.

## Where we are (20 Oct 2026)

- **Stages 1–5 are done** and passed in-game: foundation, UI components, console, explorer and plugin system.
- **Plugins stage.**
  - Round P0 (platform changes) is built.
  - **Round 1, the Script Viewer** (prime plugin `scriptviewer`), is built up to part 1.6, plus four follow-ups:
    - 1.6b: upvalue discovery fix
    - path bar back button
    - paths inside scripts (`base/access`)
  - Rounds 2 (`instanceviewer`) and 3 (`scanner`) are not started.
- **Latest build:** `Tungsten_tables.zip` (revamp + upvalues fix + inside tables, 20 Oct), checklists `Tungsten_Revamp_Checklist.md`, `Tungsten_Upvalues_Checklist.md`, `Tungsten_Tables_Checklist.md`. Not tested in-game yet.
- **Offline tests:** 39 suites, all passing in normal and `SHIFT = 58` mode, 3,250 checks each.
- **The 12-item revamp of the Script Viewer is built** (request and design in `docs/next-request.md`; what was built in `docs/stage-status.md`). Waiting for the user's in-game results.
- **Web loader:** `loader.luau` at the repo root (see Code map).
- **No in-game results yet.** None of the Plugins-stage checklists in `checklists/` has been reported back. A reload symptom (P1_5b item D1) is still undescribed.

## Rules from the user (word for word from the handoff, still in force)

- Use the study-volt-doc skill / Volt docs (docs.voltbz.net) before coding, and check every Volt function a change uses on its doc page.
- Luau only. Target Volt's documented API; no fallbacks for other executors.
- Never mention reference projects (any explorer, spy or scanner it is modelled on) in code, comments, UI, docs, logs or file names.
  - This covers everything under `Tungsten/` and `tests/`.
  - The planning docs in `docs/` quote the user's own words, which name some of them. Never carry those names into the product.
- Everything local under workspace/Tungsten/ - no downloads at runtime.
  - Since 20 Oct the user asked for a web loader (`loader.luau`): it may download into `workspace/Tungsten/` before Tungsten starts. Tungsten itself still downloads nothing (`docs/decisions.md`).
- Images: draw in SVG (send the .svg plus a PNG copy).
- Follow the conventions and standing decisions in sections 5-6 (now in `docs/handoff-plugins-stage.md` and `docs/decisions.md`).
- Work in small stages; stop at a clean point after each and wait for me.
- Extend the offline tests for every change; run all suites (normal and SHIFT = 58) before sending anything.
- After each round send the changed files, a full zip and that round's checklist, then STOP and wait for my test results.

The user's latest request also said: "find a good stopping point and pause if usage approaches a limit."

## How a round goes

1. Read the relevant Volt doc pages (see `docs/volt-api-notes.md`; re-check any function you newly use).
2. Make small changes. Write a failing test first when fixing a reported bug.
3. Run `tools/run_all.sh` from the repo root. It must print every suite in both modes with `0 failed, 0 runtime errors` and exit 0.
4. Update the docs:
   - the in-game documentation topics in `Tungsten/documentation/topics/`
   - `tests/README.md` (every suite and mock behaviour)
   - `docs/stage-status.md`
5. Package:
   ```sh
   python3 tools/make_manifest.py Tungsten     # integrity manifest (sizes); rerun after ANY change in Tungsten/
   python3 tools/make_release.py               # release.txt for the web loader; rerun after make_manifest
   python3 tools/package.py out/Tungsten_<round>.zip
   zip -qr out/Tungsten_tests_<round>.zip tests tools
   ```
6. Write `checklists/Tungsten_<Round>_Checklist.md` in the same style as the existing ones:
   - install line
   - grouped items with ids (A1, B2…), each a concrete in-game action and expected result
   - "for a failure send …" line
7. Hand over the changed files, the full zip, the tests zip and the checklist. Then stop and wait for pass/fail results.

The user's test loop: copy the zip's `Tungsten/` folder into Volt's `workspace/Tungsten/`, run `Tungsten.luau` in Volt, and report pass/fail per item. For failures they send what they saw, any `[x]` line (`/trace` gives details) and the newest file in `Tungsten/logs/`.

## Commands

- `tools/run_all.sh [suite.luau ...]`: runs suites in normal mode and with `SHIFT = 58` prepended (a UI offset mode). It needs `python3` and the `luau` CLI on PATH.
  - Get the CLI from the github.com/luau-lang/luau releases, e.g. `luau-ubuntu.zip`, and put `luau` in `/usr/local/bin`.
- To run one suite by hand:
  ```sh
  python3 tests/build_test.py . tests/test_x.luau /tmp/run.luau
  luau /tmp/run.luau
  ```
  Use this to see a runtime error's stack.
- `python3 tools/make_manifest.py Tungsten`: rewrites `Tungsten/base/data/manifest.luau`. The integrity check fails (stage4c, p1a…) if it is stale.
- `python3 tools/make_release.py`: rewrites `release.txt` at the repo root (`<sha1 12> <size> <path>` per shipped file), which `loader.luau` downloads by. `test_loader` fails if it is stale.
- `python3 tools/package.py out.zip`: zips what ships. It leaves out `logs/`, `saved/`, `base/settings.json`, `base/plugins.json`, plugin `settings.json` files, and plugin folders other than the primes (`ScriptViewer`, `InstanceViewer`, `Scanner`).
- `python3 tools/svg2png.py icon.svg`: renders a 64×64 PNG next to an SVG (Playwright Chromium).
  - Icons live in `Tungsten/base/data/icons/` as `name.svg` + `name.png`, drawn white (tinted at runtime).

## Code map

The **web loader** is `loader.luau` at the repo root: `loadstring(request({ Url = "https://raw.githubusercontent.com/minimofie/tungsten/HEAD/loader.luau" }).Body)()` installs or updates `workspace/Tungsten/` from `release.txt`, then runs it. Options: `({ Branch, Owner, Repo, Run = false })`.

The loader is `Tungsten/Tungsten.luau`. It builds the context `T` (`T.import("base/x")` loads a module once) and sets `T.Access`, `T.Loaded`, `T.Variables`, `T.Explorer`, `T.PathBar`, `T.Console`, `T.Plugins`, `T.Menus`, `T.Undo`, `T.UI`, `T.Tabs` and others.

**Platform (`Tungsten/base/`)**
- `loaded.luau`: the **one loaded target** every tab works on.
  - API: `Loaded.load(items, {By})`, `clear`, `get`, `list`, `value(s)`, `target(value, {Kind, Label, Origin, Access})`, `Changed(items, by)`.
  - History for the back button: `back`, `canGoBack`, `previous`, `history`, `clearHistory` (50 entries, no repeats, destroyed Instances skipped).
  - Every tab's `OnLoad(values, tab, items)` runs, the open tab first.
- `access.luau`: how a value inside a script is reached: `require(module)` or `getsenv(script)` root, then key, upvalue, proto (nested function) and closure (running copy) steps.
  - API: `code`, `crumbs`, `parse` (only walks, never runs; refuses unrequired modules), `resolve`, `find` (breadth-first search over required modules' tables, then running scripts' globals; depth 5; budget 20,000; cached), `findFrom`, `root`, `key`, `upvalue`, `prefix`.
- `ui/pathbar.luau`: the path bar.
  - Buttons left to right: ⌄ menu (fixed: Copy and Highlight only), ← back, the field (crumbs, or a text box when clicked), → go, ⟳ reload (`Loaded.reload`).
  - Values inside scripts show as `script › require() › key › … › value`; Copy gives the code.
  - Typed paths and `/load` accept `require(…)`, `getsenv(…)`, `debug.getupvalues(…)[n]`, `debug.getproto(…, n)`, `debug.getproto(…, n, true)[k]`; the path bar also takes `$name`.
- `api.luau`: the plugin api.
  - Includes `api.loaded` (with `access`, `back`, `canGoBack`, `previous`), `api.plugins` (`get`, `open`, `isOn`), `api.ui` (`new`, `page`, `subtabs`…), `api.prompt` (`confirm`, `input`, `form`, `registerFieldKind`…), `api.menus`, `api.undo`, `api.variables`, `api.types`, `api.settings`, `api.tooltip`, `api.connect`, `api.spawn`.
- `plugins.luau`: the plugin host. `Plugins.Prime = { "scriptviewer", "instanceviewer", "scanner" }`; primes ship in `Tungsten/plugins/<Folder>/` and start off; supports `Uses` and `Requires`.
- `integrity.luau`: the list of executor functions Tungsten relies on (51 now). The welcome line says `51/51 executor functions`; tests assert the count, so update them when adding one.
- `ui/components/*`: the UI components:
  - List (virtualized), Dropdown, TextEditor (virtualized)
  - SubTabs (pills, badges), Scroll, Input, Toggle, Button, Label, Page
  - Prompt (`form` / `confirm` / `input`; custom field kinds), Tooltip, Overlay, Menus
- `types.luau`: `Types.parse`, `resolvePath`, `path`, `literal`, `display`, `hint`.
- `undo.luau`, `variables.luau`, `scale.luau` (scale = window size).

**Console:** `Tungsten/console/`. Commands are in `console/commands/*.luau`, e.g. `/load <path | require(path).key | $var | none>`.

**In-game docs:** `Tungsten/documentation/topics/NN_id.md`, e.g. 06_explorer has the path bar and 09_plugins has the api.

**Script Viewer (`Tungsten/plugins/ScriptViewer/`)**
- `plugin.luau`: definition, settings and exports.
  - Settings: `constantsView`, `upvaluesView`, `functionsView`, `contentsView` (Tree / List / Table), `constantsScope`, `upvaluesScope`, `showReferences`, `showEmpty`, `constantAnyType`. Docs page `docs.md`.
  - Exports: `reveal({Target, Panel})`, `subject()`, `view()`.
- `lib/inspect.luau`: works out what a loaded item is: script, module, function, proto (a nested function, ProtoProxy), table or value (`Inspect.subject`).
- `lib/rows.luau`: tree nodes for Constants, Upvalues, Functions and Contents.
  - `liveFunctions(subject)` finds a script's running functions. It tries `filtergc` by Environment, then `filtergc` by Source with a re-check, then `getgc` by source name.
- `lib/view.luau`: the tab UI.
  - Sub-tabs: Source (first), Constants, Upvalues, Functions, Contents.
  - Each data sub-tab has a view dropdown (Tree / List / Table), a scope (Constants, Upvalues), Apply/Revert (Table), Add entry (Contents), a References toggle, and a scrolling work area. Switches are deferred and guarded (`_schedule`).
- `lib/details.luau`: the Functions sub-tab's details pane.
- `lib/edit.luau`: writes values.
  - Constants via `debug.setconstant`. A script's constants go to its running functions with the same `getfunctionhash` and constants, and are refused when nothing runs.
  - Upvalues via `debug.setupvalue`; entries via `rawset`.
  - Read-only tables are unlocked only after a confirm, then locked again (Q10).
  - The Table text is applied as a diff (KEEP sentinel, all or none).
- `lib/actions.luau`: the right-click menu `scriptviewer.row` and its forms (value field `scriptviewer_value`: relevant types + variable picker); Inspect, Load, running copies; every change records an Undo step. `accessOf` / `pathOf` give paths.
- `lib/serialize.luau` (Luau table literal), `lib/refs.luau` (references via `filtergc`), `lib/source.luau` (decompile, cached by script hash).

**Tests (`tests/`)**
- `harness.luau` mocks Roblox and Volt, with virtual time (`H.advance`) and `H.FN[fn]` for constants, upvalues, protos, info, hash and source. See `tests/README.md` for every stand-in.
- One file per round: `test_p0a` … `test_p1g`, `test_pathback`, `test_access`, plus older stage suites.
- Shipped primes are set aside unless a suite calls `H.keepPrimes()`.

## Conventions (summary; full text in `docs/handoff-plugins-stage.md` §6)

- Values from text go through `Types.parse`, paths through `Types.resolvePath`. **Never execute text.**
- Changes to the game record an Undo step.
- Faults from plugin-supplied code go through `Reporter.ownerFault`.
- Menus are named (`Menus.define` / `add`), greyed when not applicable, with danger items in red.
- Popups go through Overlay/Prompt with an Owner.
- Lay UI out at scale 1. Everything lives in a bin. Re-running Tungsten must not add listeners.
- Everything registered carries an owner.
- Every feature is documented in a topic when built.
- Test files stay under Luau's 200 locals per function.
- Guard every executor call with `pcall` (helpers: `Inspect.call` / `volt` in the plugin, `call` in `base/access`).
- UI wording is plain and short. Avoid internal jargon in what the user sees.

## Working with this user

- Requests are short and direct. Do what is asked without long preambles.
- When something is ambiguous and expensive, ask with a few concrete options. Otherwise build and say what you decided.
- Every delivery includes:
  - the changed files
  - the full zip
  - the tests zip
  - a numbered checklist
  - a short summary: what changed, what wasn't tested in-game, what's open
- They test in Volt and report back; their copies of the zips are the master.
- They asked for a doc-first habit: check docs.voltbz.net pages for every executor function. Note facts in `docs/volt-api-notes.md`.

## Other docs

- `docs/next-request.md`: the pending 12-item request, word for word, plus the proposed design and order of work.
- `docs/stage-status.md`: detailed status per round (also kept in the claude.ai project "tungsten").
- `docs/history.md`: what each round built, the user feedback that drove it, and the pending checklists.
- `docs/decisions.md`: every decision (Q1–Q13, Stage 5 P1–P10, standing UI decisions, choices made during this stage).
- `docs/volt-api-notes.md`: Volt functions used and what their doc pages say.
- `docs/plugins-stage-plan.md`: the original plan for P0 and rounds 1–3. It has the Round 2 and 3 feature lists.
- `docs/handoff-plugins-stage.md`: the original handoff, with the original spec in Appendix A.
- `checklists/`: every checklist sent; none of the Plugins-stage ones has results yet.
- `assets/`: images sent (SVG + PNG).
