# Tungsten — Plugins stage, round P0b checklist (12 items)

`Tungsten_p0.zip` holds all of round P0 (P0a + P0b). If you haven't run the
P0a checklist yet, run it on this zip too (same items).

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p0.zip`.
Copy `Pills/` from `Tungsten_p0_testplugins.zip` into `workspace/Tungsten/plugins/`,
turn it on in the Plugins tab and restart Tungsten. Remove it after testing.

Report pass / fail per item; for a failure say what you saw, any `[x]` line
(`/trace` for details) and the newest file in `Tungsten/logs/`.

## A. The look (open the Pills tab)
- **A1** Under the path bar is a darker band (the title bar's colour) holding rounded sub-tab pills.
- **A2** Constants is open: soft orange fill, orange icon, bright text. No underline anywhere.
- **A3** The other pills have no fill and dimmer text.
- **A4** Hovering a closed pill gives it a grey fill and brighter text and icon; leaving takes it away.
- **A5** Clicking Upvalues opens it (fill moves to it) and shows "Upvalues view".
- **A6** Upvalues has an orange badge with `3` after its title.
- **A7** `> getgenv().PillsTabs:Badge("source", 1234)` shows `12+` on Source and the pill widens; `…:Badge("source", 0)` removes it.

## B. Scrolling
- **B1** The pills don't all fit: the band scrolls sideways with the mouse wheel (up = right, down = left), and a thin bar shows.
- **B2** `> getgenv().PillsTabs:Select("extra10")` scrolls the strip so Extra view 10 is in view.
- **B3** Pills scrolled out of view can't be clicked through the edge of the band.

## C. Scale and other tabs
- **C1** `/scale 0.75` and `/scale 1.5`: the band and pills scale with the window; clicking still opens the right pill. `/scale 1` after.
- **C2** Run `Tungsten.luau` again: one window, no `[x]` lines; the Pills tab still looks as above.
