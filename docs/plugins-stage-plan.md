# Tungsten — Plugins Stage Plan

Oct 18, 2026 · @mini

## Summary

The Plugins stage is four rounds: **P0** (platform changes), then **scriptviewer**, **instanceviewer** and **scanner**, one round each. Each round follows the handoff loop: plan → open decisions → build → offline tests (normal and `SHIFT = 58`) → zip + checklist → stop.

Your new list matches the handoff's order and adds detail the handoff left to each round. Three things in it change P0's scope beyond what the handoff planned:

- **The loaded thing is not always an Instance.** The instance viewer shows "n/a" in its 3D view for non-objects, and the scanner hands closures, tables and connections to the script viewer. P0 should make the shared loaded value a *target* (Instance, or a function / table / connection / call record), not only an Instance.
- **Plugins link to each other's views.** "Click to go to that info in the script viewer" needs a standard way to open another plugin's tab at a specific item. That belongs in P0 so all three primes use one mechanism.
- **instanceviewer links to scanner, which is built after it.** Under P4, a missing `Requires` makes a plugin a problem. Links need a soft dependency (works when present, greyed when not).

Already in place and reused: the plugin host and api (Stage 5), `SubTabs` / `Page`, the text editor + Luau lexer, the properties view with attributes, the type editors, the shared `__namecall` hook in `base/explorer/remoteblock.luau`, and the prime-id reservation (`Plugins.Prime`).

The reference scripts you attached (the module table editor, the spy, the explorer and the scanner suite) are used for feature ideas only. Per the rules, none of their names appear in code, UI, docs or file names.

## Round P0 — platform changes

P0 replaces per-tab path bar objects with one shared loaded target, restyles sub-tabs, reorders primes and adds the link mechanism. Estimated 1,200–1,800 lines including tests (the handoff's 800–1,500 plus the two additions).

| Step | Change | Files |
| --- | --- | --- |
| P0.1 | **One loaded target.** New `base/loaded.luau` holds the single loaded value: `Loaded.set(list)`, `Loaded.get()`, `Loaded.list()`, `Loaded.Changed(list, by)`. Every entry point routes through it: explorer › Load, path bar arrow and crumbs, typed path, `/load`. The `overrides` table and `PathBar.setSubTab` are removed; the path bar just shows `Loaded.get()`. A destroyed instance unloads. | `base/loaded.luau` (new), `base/ui/pathbar.luau`, `base/explorer/explorer.luau` (`Explorer.load`), console `$loaded` |
| P0.2 | **Every tab told.** `Explorer.load` no longer targets one tab: it sets the loaded target, then calls `OnLoad` on every registered tab (built-in and plugin) and fires `Loaded.Changed`. Faults per tab go through `Reporter.ownerFault`. Sub-tabs subscribe through their tab. | `base/registry.luau`, `base/ui/tabbar.luau`, `console/console.luau`, `documentation/documentation.luau` |
| P0.3 | **Non-Instance targets.** A target is an Instance or a value with a label: `{ Kind = "function" \| "table" \| "connection" \| "call", Value, Label, Origin? }`. The path bar shows an Instance as crumbs and a value as one crumb (e.g. `function onTouched · Door.Script`) with its origin script as the parent crumb when known. | `base/loaded.luau`, `base/ui/pathbar.luau` |
| P0.4 | **api.** `api.loaded.get() / list() / set(target) / Changed`. `api.pathbar.show` becomes "load this" (shared), with a deprecation note in docs. | `base/api.luau`, topic 09 |
| P0.5 | **Sub-tab restyle.** Rounded pill buttons matching the title-bar buttons; open one tinted `AccentSoft` with an `Accent` icon; hover `SurfaceHover` like side-bar tabs; icon + text. A drawn SVG + PNG mock-up is sent for approval before coding. | `base/ui/components/subtabs.luau`, topic 08 |
| P0.6 | **Prime order.** `Plugins.Prime = { "scriptviewer", "instanceviewer", "scanner" }`. | `base/plugins.luau`, docs, test 5b |
| P0.7 | **Cross-plugin links (new).** `api.plugins.open(id, focus)` switches to a prime's tab and calls its `Exports.reveal(focus)`. Soft dependency: definition field `Uses = { "scanner" }` gives `api.plugins.get` access without making the plugin a problem when the other is off; links show greyed with "turn on Scanner" instead. | `base/plugins.luau`, `base/api.luau`, topic 09 |
| P0.8 | **Shared hook dispatcher (new, can move to round 3).** Generalise the remote-block `__namecall` hook into `base/hooks.luau`: one hook in `getgenv`, ordered subscribers (block, then spy), always chaining to the original. Prime-only subscription. | `base/hooks.luau` (new), `base/explorer/remoteblock.luau` |

**Tests.** Extend the path bar suite (72) and stage 4c / 5h: load from each entry point reaches every tab; non-Instance target renders; destroy unloads; sub-tab strip geometry at scale 0.75 / 1 / 1.75; `Uses` vs `Requires` states; hook dispatcher re-run doesn't stack. Checklist about 25 items.

## Round 1 — Script / module viewer (`scriptviewer`)

The script viewer opens whatever is loaded — a LocalScript, ModuleScript, function or table — and shows its constants, upvalues and nested functions with where each is referenced, editable in place. Proposed in three sub-rounds so each can be tested before the next.

**What it accepts**

| Loaded target | Root shown |
| --- | --- |
| LocalScript / client Script | its main function (`getscriptclosure`), plus globals (`getsenv`) |
| ModuleScript | the returned value (`require`, cached) and the main function |
| function | that function (Luau closure; C closures show name and "no constants or upvalues") |
| table | that table |
| anything else | an empty state: "load a script, function or table" |

**Sub-tabs (one plugin tab, P10)**

- **Overview** — name, source, line, counts, hash, Luau or C, origin script; links to each panel.
- **Constants** — index, type, value; nil slots hidden by default.
- **Upvalues** — index, type, value; tables and functions expand.
- **Functions** — the nested function tree. `debug.getprotos` returns ProtoProxy handles, not callable functions: a proxy shows constants and info (and allows `setconstant`) but has no upvalues. "Live closures" under each proto come from `debug.getproto(f, i, true)`; one of those opens as a full new root with upvalues.
- **Table** — the root table, or a selected upvalue/constant table.
- **Source** — decompiled text, read-only, in the existing text editor with the Luau lexer.

**View modes** (a dropdown in each data sub-tab, saved per sub-tab in `api.settings`): *Tree* (expandable), *List* (flat rows with paths), *Function* (grouped by the function that owns each value) and *Text* (the serialised Luau table, editable like the attached module editor: unwritable values kept as a placeholder, save applies only the differences and keeps nested table identity).

**Editing**

- Constants: `debug.setconstant`, limited to the same type by default (a setting allows other types, with the doc page's caution shown).
- Upvalues: `debug.setupvalue`, any type, through the type editors (`api.editors`).
- Tables: `rawset`; frozen / read-only tables refused with a reason (offer to make writable only if Q10 allows).
- Every change records an Undo step (owner `scriptviewer`) and a console success line; nothing is written to the script's source.

**References.** For a selected value, "Referenced by" lists other functions holding the same upvalue or constant (`filtergc` with `Upvalues` / `Constants`), and tables holding it. Results are capped (default 200) and the scan runs in its own thread.

**Exports** (for the other primes): `reveal({ Target, Panel?, Index? })`, `describe(value) -> string`, `serialize(table) -> string`.

| Part | Delivers | State |
| --- | --- | --- |
| 1.1 | Plugin ships in `plugins/ScriptViewer` (off), target handling, Overview, integrity entries | built |
| 1.2 | Constants, Upvalues, Functions sub-tabs (Tree / List), read-only | built |
| 1.3 | Source (decompiled when looked at) and Contents (a table, or what a required module returns) | built |
| 1.4 | Views from the user's list: Table (rows as a Luau table) and Function (rows by function); Table sub-tab renamed Contents | built |
| 1.5 | References of constants and upvalues | next |
| 1.6 | Editing constants, upvalues and tables, Undo (read-only tables: confirm, then locked again, Q10) |  |
| 1.7 | Links from the other plugins, right-click entries, docs page |  |

**Volt functions to check on their doc pages before coding:** `getscriptclosure`, `getsenv`, `decompile`, `getloadedmodules`, `debug.getconstants` / `setconstant` (1-based, nil slots, Luau only), `debug.getupvalues` / `setupvalue`, `debug.getprotos` / `getproto`, `debug.getinfo`, `islclosure`, `iscclosure`, `getfunctionhash`, `filtergc`, `isreadonly` / `setreadonly`.

**Volt notes that shape round 1** (from the doc pages):

- `decompile(script | bytecode, options?)` yields and throws on failure, and doesn't support server Scripts. The Source sub-tab runs it in a thread with `pcall` and shows the error in place.
- `debug.getconstants` is 1-based with nil slots and Luau-only. `debug.setconstant` warns about constants shared across uses, incompatible types and values the bytecode expects. This backs the same-type default.
- `debug.setupvalue` changes the shared variable, so every closure that captures it sees the new value. The edit confirm says how many closures share it.
- The canonical callback reader is `getcallbackmember` (`getcallbackvalue` is an alias).

## Round 2 — Instance viewer / editor (`instanceviewer`)

The instance viewer is the overview of whatever is loaded: a 3D preview, every property and attribute, and links into the script viewer and scanner. It is also where properties are edited, which needs the Q6 prime write right.

**Sub-tabs**

- **Overview** — class (with icon), full path, parent, child and descendant counts, tags, network owner (`isnetworkowner`, parts only), and a "Related" block: scripts inside or referencing it, remotes inside it, connections on its signals. Each entry is a link.
- **3D** — a `ViewportFrame` with a cloned copy: BasePart wrapped in a model, Model cloned with a primary-part fallback. Drag to orbit, wheel to zoom, optional auto-rotate and auto-refresh rate (settings). Shows **n/a** for non-objects (functions, tables), for non-visual instances, and for anything that can't be cloned, with the reason.
- **Properties** — the expanded list: every readable property (`getproperties`, hidden ones marked), grouped by category like the explorer, with search. Editing uses the existing editors; non-scriptable properties through `sethiddenproperty` only if Q11 allows.
- **Attributes** — name, type, value; add, rename, change type, remove. Reuses `base/explorer/attributeform.luau`.
- **Scripts** (only for script instances) — a short summary with "Open in script viewer".

**Links.** A script, function or value shown here is a link: click calls `api.plugins.open("scriptviewer", { Target, Panel, Index })`. Connection and remote rows link to the scanner the same way, greyed until the scanner exists or is on (P0.7 soft dependency).

**Editing rules.** Every property and attribute change goes through the prime `setProperty` (Q6), records an Undo step, and refreshes live via `Changed` / `AttributeChanged`. Multi-select edits (Q1) apply to all loaded objects that have the property; a mixed value shows "—".

| Sub-round | Delivers |
| --- | --- |
| 2a | Overview, Properties (read), Attributes (read), 3D with n/a states |
| 2b | Property and attribute editing, multi-object edits, Undo |
| 2c | Related block, links to script viewer / scanner, docs page |

**Volt functions to check:** `getproperties`, `gethiddenproperties`, `gethiddenproperty`, `sethiddenproperty`, `isscriptable`, `isnetworkowner`, `getconnections` (for the Related count), `cloneref`, `compareinstances`.

## Round 3 — Universal scanner / spy (`scanner`)

The scanner is the largest plugin: one search engine over everything the garbage collector can see, plus spies that log calls as they happen. Scanner features follow the scanner suite you attached; spy features follow the spy. Planned as four sub-rounds.

**Scan (one form, "universal" modes)**

| Choice | Options |
| --- | --- |
| Look in | Upvalues · Constants · Tables (keys / values) · Script globals · Loaded modules · Scripts · Connections |
| Scope | Everything (`getgc` / `filtergc`) · the loaded target only · the watch list |
| Match | equals · contains · starts / ends with · type is · number within range |
| Options | deep (search inside nested tables, depth limit) · include Tungsten / executor functions (off) · result cap |

Results are grouped by owning function or table, each row a link into the script viewer (`reveal`) and editable in place through it. Scans run in a thread, yield every N items so the game doesn't freeze, and can be cancelled.

**Watch list.** Any value, function, table or signal can be added to a watch list (right-click › Watch, or from the other primes). Watched things are re-checked on an interval and every change is logged with old → new value and time. This is my reading of "scans watched things" — see Q9.

**Garbage collector connections.** For a signal on the loaded instance, or every signal of it: list connections (`getconnections`) with Luau / C, enabled state, function and thread. Actions: open function in script viewer, Fire, Disable / Enable, Disconnect (danger red, Undo where possible). A connection spy logs each firing of a watched connection's function.

**Spies**

- **Remote spy** — outgoing `FireServer` / `InvokeServer` (and bindables, optional) through the shared hook (P0.8) plus `hookfunction` on the methods for direct calls; incoming `OnClientEvent` via connections and `OnClientInvoke` via `getcallbackvalue`. Each call: remote, direction, arguments (expandable, typed), time, calling script (`getcallingscript`), calling function info.
- **Call filters** — conditions on remote name / path / class / argument count / argument values (==, \~=, <, >, contains, starts/ends with, type), joined with AND / OR; actions: ignore, block, highlight. Auto-ignore very frequent calls (setting).
- **Call actions** — replay, copy calling code (as Luau), copy remote path, open calling script, create filter from call, export calls to a file in `Tungsten/` (via `api.files`).
- **Function spy** — hook a chosen Luau function (`hookfunction`, restored with `restorefunction` on stop), log arguments and returns; "spy the calling function".

| Sub-round | Delivers |
| --- | --- |
| 3a | Scan form, all "Look in" modes, scopes, results with script viewer links |
| 3b | Shared hook (if not in P0), remote spy, call list with paging |
| 3c | Call filters, call actions, export |
| 3d | Connections, connection and function spies, watch list, docs page |

**Not planned unless you ask:** anti-cheat bypass toggles, actor capture, RakNet hooks, relaunch-after-teleport.

**Volt functions to check:** `getgc`, `filtergc`, `getconnections` (connection fields), `firesignal`, `hookmetamethod`, `getnamecallmethod`, `hookfunction`, `restorefunction`, `isfunctionhooked`, `newcclosure`, `checkcaller`, `getcallingscript`, `getcallbackvalue`, `getloadedmodules`, `getscripts`, `getrunningscripts`, `getsenv`, `getnilinstances`.

**Volt notes that shape round 3** (from the doc pages):

- `getgc()` returns functions only; `getgc(true)` adds tables, userdata and threads, and the docs warn it is slow. Table scans use `filtergc("table", { Keys / Values / KeyValuePairs })` first and fall back to `getgc(true)` only for "contains" matches.
- `filtergc` skips Volt-created functions by default (`IgnoreExecutor = true`), which already covers "exclude Tungsten's own functions". Its `Constants`, `Upvalues` and `Hash` filters don't apply to C closures.
- `hookmetamethod` wraps the hook in `newcclosure` itself and returns the original. Several objects can share one metatable, so the hook must check the class and method before it logs anything.
- For C methods called directly (`remote.FireServer(remote, ...)`), Volt has the `oth` library (`oth.hook(cfn, luauHook)`, `oth.unhook`, `oth.get_root_callback`, `oth.is_hook_thread`) next to `hookfunction`. Q13 picks one.
- `hookproto(proxy, hook)` hooks every current and future closure of a nested function, until `restoreproto`. The hook must have zero upvalues, so it reports through a `getgenv` table instead of a captured local. The function spy can use it for nested functions that have no live closure yet.
- `getconnections` entries have `Function` and `Thread` set to nil for foreign/C connections. Those rows show "C connection" and offer only Enable / Disable / Disconnect.

## Open decisions

Q1–Q7 come from the handoff; Q8–Q12 are new from your list. Proposals are what I'd build if you accept them as written.

| # | Question | Proposal | Needed by |
| --- | --- | --- | --- |
| Q1 | Loading several selected objects: load the list or the first? | The list; path bar shows the first + "(+N)"; tabs get the whole list | P0 |
| Q2 | Does selecting in the explorer also load? | No — only explicit loads; selection stays `$sel` | P0 |
| Q3 | Keep per-tab path bar objects? | No — one loaded target; `api.pathbar.show` means "load this" | P0 |
| Q4 | Which part of the main UI should sub-tabs mirror? | Title-bar pill buttons, accent tint on the open one, icon + text, side-bar hover; picture first | P0 |
| Q5 | Do primes ship with Tungsten, and start on? | Ship in `plugins/`, start off like any plugin (P1) | P0 (packaging) |
| Q6 | Prime-only explorer rights? | `api.explorer.select` and `setProperty` (undoable) with `Prime = true` | Round 2 |
| Q7 | Prime load order | `scriptviewer`, `instanceviewer`, `scanner` | P0 |
| Q8 | Can the loaded target be a non-Instance (function, table, connection, call)? | Yes, as P0.3 — needed for scanner → script viewer and the 3D "n/a" case | P0 |
| Q9 | What does "scans watched things" mean? | A watch list re-checked on an interval with a change log (round 3) — or did you mean Tungsten's variable watches? | Round 3 |
| Q10 | May the script viewer make a read-only table writable to edit it? | Only after a confirm, and restored after the write | Round 1b |
| Q11 | Edit non-scriptable / hidden properties? | Read always; write behind a per-edit confirm | Round 2b |
| Q12 | Soft links between primes (`Uses`) and the shared hook dispatcher in P0? | Both in P0, so later rounds build on one mechanism | P0 |

Q13 — Spying on C methods called directly: use `hookfunction` (one API for Luau and C) or `oth.hook` (C only, gives the root original even after other hooks)? Proposal: `oth.hook` for the remote methods, `hookfunction` for Luau functions; decide in round 3b after checking both pages in Volt.

## Risks and estimates

The biggest risks are in round 3 (hooks and full-memory scans); P0's risk is breaking the 2,454 existing checks that assume per-tab path bars.

| Risk | Mitigation |
| --- | --- |
| Removing per-tab overrides breaks path bar / 4c / 5h tests | Rewrite those checks first (failing), then change code |
| Full `getgc` scans freeze the game | Prefer `filtergc`; yield every N items; cancel button; result cap |
| A second `__namecall` hook stacks on re-run or breaks remote blocking | One dispatcher in `getgenv` (P0.8), always chaining to the original; re-run test |
| `setconstant` with a wrong type crashes game code | Same-type by default; caution shown; Undo restores |
| Volt doc pages give little detail on errors and C closures | Each round's plan lists the functions; the integrity check names them; guard every call with `pcall` |
| The offline mock has no GC, hooks or viewports | Extend `tests/harness.luau` with fakes for `getgc` / `filtergc`, `getconnections`, `hookfunction`, `debug.*` per round |

| Round | Size incl. tests | Fix rounds | Your testing |
| --- | --- | --- | --- |
| P0 | 1,200–1,800 lines | 1–2 | 30–45 min |
| 1 scriptviewer (1a–1c) | 2,500–3,500 lines | 2–4 | 60–90 min |
| 2 instanceviewer (2a–2c) | 1,800–2,500 lines | 2–3 | 45–75 min |
| 3 scanner (3a–3d) | 4,000–5,500 lines | 3–5 | 90–120 min |

Estimates only, scaled from the handoff's numbers. Start each round in a fresh conversation with the latest zip, the handoff PDF and this plan.
