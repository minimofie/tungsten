# Tungsten — part 1.6b checklist: upvalues (8 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_6b.zip`.
For any failure, send the **grey line under the Upvalues buttons** (hover it for
the full text, or read the middle of the empty list), the line under the title
(e.g. `LocalScript · running`), any `[x]` line (`/trace`) and the newest file in
`Tungsten/logs/`.

- **U1** Load a LocalScript that is running and has functions using outer locals (e.g. one in PlayerScripts with a loop or connections). Open **Upvalues**: a heading per running function (`name   line N`) with its upvalues under it.
- **U2** The pill on Upvalues shows the same count as the grey line.
- **U3** Right-click an upvalue › Change value…, change it: the row shows the new value, and the script uses it (e.g. a number it prints or a flag it checks).
- **U4** `/undo` puts it back.
- **U5** Load a ModuleScript the game has required: Upvalues shows its running functions the same way.
- **U6** Load a function directly (`> fn = require(game.ReplicatedStorage.SomeModule).SomeFunction`, `/load $fn`): Upvalues lists its upvalues; changing one works.
- **U7** Load a script that has finished (no functions left alive): the list says "no running functions of this script were found …" in full.
- **U8** Hover the grey line on any data sub-tab: the full text shows.
