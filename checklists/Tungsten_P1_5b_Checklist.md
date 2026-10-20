# Tungsten — round 1 fixes checklist (12 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_5b.zip`.
Keep the Script Viewer on. Report pass / fail per item; for a failure say what
you saw, any `[x]` line (`/trace`) and the newest file in `Tungsten/logs/`.

## A. Layout
- **A1** The Script Viewer's sub-tabs are Source, Constants, Upvalues, Functions, Contents. No Overview.
- **A2** Source is first and open when the tab opens.
- **A3** Under the title, a short line says what is loaded (e.g. `LocalScript · running`, `ModuleScript · required`, `Luau function`). Hovering it shows the notes.

## B. Source
- **B1** With the Script Viewer tab closed, load a big script: no hitch. Open the tab: it decompiles then.
- **B2** With the tab open on Source, loading another script decompiles it straight away.

## C. Upvalues
- **C1** Load a running LocalScript (one with functions that use outer locals, e.g. from PlayerScripts), open Upvalues: a heading per running function (`name   line N`), open, with that function's upvalues under it; the bar says `N upvalues · M functions`.
- **C2** The Upvalues pill shows the same number of upvalues as the bar.
- **C3** Load a required ModuleScript: Upvalues shows its running functions the same way.
- **C4** Load a function directly (`> fn = require(game.ReplicatedStorage.SomeModule).SomeFunction`, `/load $fn`): Upvalues shows that function's upvalues.
- **C5** Double-clicking headings in the Function view is instant (no search each time).

## D. Reloading
- **D1** With the Script Viewer tab open, `/plugin reload scriptviewer`, then open the tab again: it works (Source shows code, other sub-tabs fill). If it doesn't, describe exactly what you see (blank tab? old content? an error?) and send the `[x]` lines.
- **D2** Run `Tungsten.luau` again with the tab open: the tab comes back working.
