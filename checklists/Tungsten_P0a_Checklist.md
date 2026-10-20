# Tungsten — Plugins stage, round P0a checklist (28 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p0.zip`
(keep your `base/settings.json` and `base/plugins.json` if you like). For part E
also copy `Viewer/` and `Linker/` from `Tungsten_p0_testplugins.zip` into
`workspace/Tungsten/plugins/`, turn both on in the Plugins tab and restart
Tungsten. Remove them after testing (they stand in for the real primes).

Report pass / fail per item; for a failure say what you saw, any `[x]` line
(`/trace` for details) and the newest file in `Tungsten/logs/`.

## A. One loaded target for every tab
- **A1** Start Tungsten: the welcome line shows `integrity ok`, no `[x]` lines.
- **A2** In the explorer, right-click a Part: **Load** shows `every tab` on its right. Click it.
- **A3** The console prints `loaded <Part>` and `loaded = <Part>`; `$loaded` is the Part.
- **A4** Open Documentation: the path bar shows the same Part; the docs page is that class's page.
- **A5** Open Plugins: the path bar still shows the same Part.
- **A6** Select two objects › **Load**: the bar shows the first object and `+1`; `$loaded` is a table of both.
- **A7** Selecting something else in the explorer does **not** change the bar.
- **A8** Click a parent part of the path: it is loaded, on every tab.
- **A9** Click the empty part of the bar, type `game.Workspace`, Enter: loaded on every tab.
- **A10** Click a `›` and pick a child: loaded.
- **A11** With something selected, click the arrow: the selection is loaded.
- **A12** Load a Part, then delete it (explorer › Object › Delete): the bar empties.
- **A13** Load two Parts, delete the first: the bar shows the second, without `+1`.

## B. /load
- **B1** `/load game.Workspace` loads it (bar and `$loaded`).
- **B2** `/load` with nothing selected prints `loaded: game.Workspace`.
- **B3** `> f = function() end` then `/load $f`: the bar shows one part `$f (function)`; ⌄ › Copy and Highlight are greyed.
- **B4** `/load none` empties the bar and prints `nothing loaded`.
- **B5** `/load game.Workspace.Nope` prints an `[x]` line and changes nothing.

## C. Values from scripts
- **C1** In the console: `> tungsten.Loaded.load(tungsten.Loaded.target(print, { Label = "print", Origin = game.Workspace }))`.
  The bar shows `game › Workspace › print`; the last part is highlighted.
- **C2** Copy / Highlight are greyed for it; clicking `Workspace` in the bar loads Workspace.

## D. Prime order and plugin info
- **D1** `/plugin info linker` (after part E's install) lists `uses (when on) scriptviewer, instanceviewer`.
- **D2** `> tungsten.Plugins.Prime` lists `scriptviewer`, `instanceviewer`, `scanner` in that order.

## E. Test plugins (Viewer + Linker)
- **E1** Both are **on** in the Plugins tab; Linker is on even though `instanceviewer` isn't installed.
- **E2** Load a Part while on the Console tab: `> getgenv().ViewerLoads` counted it; `getgenv().ViewerGot[1]` is the Part.
- **E3** `> getgenv().LinkerApi.plugins.open("scriptviewer", { Panel = "constants" })` returns `true`, opens the Script Viewer tab, and `getgenv().ViewerRevealed.Panel` is `"constants"`.
- **E4** `> getgenv().LinkerApi.plugins.open("instanceviewer")` returns `false` and `'instanceviewer' isn't installed`.
- **E5** `> getgenv().LinkerApi.loaded.set(workspace)` loads Workspace on every tab.

## F. Clean up
- **F1** Run `Tungsten.luau` again: one window, the welcome line once, no `[x]` lines; loading still works.
