# Tungsten — paths inside scripts checklist (10 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_6d.zip`.
Report pass / fail per item; for a failure say what you saw (the path bar's
text), any `[x]` line (`/trace`) and the newest file in `Tungsten/logs/`.

Pick a ModuleScript the game has required that returns a table with functions
in it (e.g. one in ReplicatedStorage). Below it is `game.ReplicatedStorage.Mod`
with a function `Mod.Sub.fn`; use your own names.

- **S1** `> f = require(game.ReplicatedStorage.Mod).Sub.fn` then `/load $f`: the path bar shows `game › ReplicatedStorage › Mod › require() › Sub › fn`, `fn` highlighted.
- **S2** Path bar ⌄ › **Copy**: the clipboard holds `require(game.ReplicatedStorage.Mod).Sub.fn`. **Highlight** selects Mod in the explorer.
- **S3** Click `Sub` in the bar: the `Sub` table is loaded (bar ends in `Sub`). Click `require()`: the module's table is loaded. ← goes back through them.
- **S4** Click the bar to type: the box starts with `require(game.ReplicatedStorage.Mod).Sub`. Type `require(game.ReplicatedStorage.Mod).Sub.fn` + Enter: it loads.
- **S5** `/load require(game.ReplicatedStorage.Mod).Sub.fn` loads it the same way. `/load` alone prints that code.
- **S6** Type `require(<a ModuleScript the game hasn't required>).x`: the bar says it hasn't been required and loads nothing (and the module doesn't run).
- **S7** A running LocalScript with a global function (`function update() … end`, not `local`): `/load getsenv(game.Players.<you>.PlayerScripts.<Script>).update` shows `… › <Script> › getsenv() › update`.
- **S8** Script Viewer: load the ModuleScript, Contents › right-click a table row › **Look into it**: the bar shows its path under `require()`. Again one deeper: one more part.
- **S9** Script Viewer: load a function, Upvalues › right-click a table upvalue › **Look into it**: the bar ends in `› upvalue N`; Copy gives `debug.getupvalues(…)[N]`.
- **S10** A function nothing reaches (`> g = function() end`, `/load $g`): one part as before, Copy and Highlight greyed. Loading things stays quick (no hitch).
