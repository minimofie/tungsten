# Tungsten — back button checklist (8 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_6c.zip`.
Report pass / fail per item; for a failure say what you saw, any `[x]` line
(`/trace`) and the newest file in `Tungsten/logs/`.

- **K1** The path bar has a ← button right of the ⌄ button, the same size and look. The path field starts after it and the → arrow is still on the right.
- **K2** After a fresh start (nothing loaded) ← is greyed and pressing it does nothing.
- **K3** Load Door, then Lamp (explorer › Load, a crumb or a typed path). Press ←: Door is loaded again (path bar and tabs follow). Greyed again.
- **K4** Load three things in a row and press ← twice: you step back through them in order.
- **K5** Load a value (e.g. a function in the Script Viewer › Look into it), press ←: back to what was loaded before it.
- **K6** `/load none` (or clear the bar), press ←: what was loaded comes back.
- **K7** Hover ←: the tooltip says "Back to …" with the path it will load.
- **K8** Click the bar to type a path, then press ←: typing stops and it goes back.
