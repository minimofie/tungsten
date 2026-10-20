# Console

The Console tab is a terminal for Tungsten. Type into the line at the bottom and press **Enter**. Everything you run is echoed as a `[>]` line, followed by what it printed.

## Starting up

Tungsten starts with a splash screen: the brand icon, the name and a progress bar. The card fades in, the bar fills over 3 seconds and stays full a moment, then the card fades out. Tungsten loads behind it; the window, the explorer and the command bar key only appear once the splash has faded away. The load time in the welcome line doesn't count the splash.

The first lines show the version and executor, how long Tungsten took to load, how many plugins were loaded and how long they took (counted apart), how many didn't start (see `/plugins`), and the **integrity** check:

- **files**: every file Tungsten ships with is there and unchanged (a list of them comes with Tungsten)
- **executor**: the Volt functions Tungsten uses exist; a missing one names what stops working
- **settings**: `settings.json` loaded without anything being dropped
- **data**: the bundled class and property list is readable

Problems are listed under it. `/integrity` runs the checks again and lists every problem.

## Undo

`/undo` takes back the last change Tungsten made, **Ctrl+Z** in the explorer tree does the same. It covers property and attribute edits, renames, moves (dragging, Paste Into after Cut, `/move`), inserts, duplicates, pastes, groups, deletes, and variable changes made by commands and the explorer's Variable menu.

| Command | What it does |
|---|---|
| `/undo` | the newest step |
| `/undo 3` | the three newest steps |
| `/undo list` | what can be undone, newest first |
| `/undo clear` | forget the steps |

Code you run with `>` or `=` isn't recorded, because Tungsten can't know what it changed. The list keeps the last 100 steps and is gone when Tungsten closes.

## The command bar

Press **'** (the apostrophe key) anywhere in the game (the window open or minimized) for a see-through bar near the top of the screen. Whatever you type there runs in the console exactly as if typed here (`/commands`, `> code`, `$variables`, `&&` chains) without opening the window, and the newest output shows under the bar.

Typing works the same as in the console input: the same suggestion list with the same hints opens as you type a `/command`, `:plugin.command` or `$name`, and you can click a suggestion.

| Key | What it does |
|---|---|
| **Enter** | run; the bar stays open for the next input |
| **Tab** | complete, or take the highlighted suggestion |
| **Up** / **Down** | move through the suggestions; with none open, earlier inputs |
| **Escape** | close the suggestions; again to close the bar |
| **'** on an empty bar, or a click anywhere else | close |

The bar never keeps anything: it always opens empty, with no output under it.

`/bar` opens it; `/bar key F8` uses another key (it is remembered). The key works even when the game has its own use for it; only a focused text box (the chat, the console input) keeps it from opening the bar. On keyboards where ' is not a key of its own, pick another with `/bar key` (`/bar key BackSlash` brings back the old \\ key).

The console input and the command bar show no key hints; **Up** / **Down** walk the history in both (see the tables here).

## Typing

| Key | What it does |
|---|---|
| Enter | run the input |
| Up / Down | go back and forward through earlier inputs |
| Tab | complete a command, `$variable` or command argument |
| Up / Down (list open) | move through the suggestion list |
| Escape | close the suggestion list |

While you type a `/command`, `:plugin.command`, `?command` or `$name`, a list of matches opens above the input. **Tab** takes the highlighted match. With several matches, Tab first fills in the part they share.

> The input remembers the last 200 entries for this session. `/history` lists them and `!!` runs the last one again.

## What you can type

```
/help
/set a = 5
> $a * 2
= workspace
?set
!!
# checked the spawn area
/set a = 1 && /inc a && /get a
```

- `/name` runs a command. `/help` lists them all, `/help name` explains one.
- `> code` runs Luau and shows the result: `> 1 + 1` shows `2 <number>`.
- `= code` runs Luau and shows the result in full: tables expanded, Instances with their path.
- `$name` anywhere is a variable. An input that starts with `$` is run as Luau.
- `?name` is help for a command, `!` runs something from the history, `#` writes a note.
- `&&` joins inputs: they run in order and stop at the first one that fails. `||` runs the next input only when the one before failed.

The **Prefixes** topic explains every prefix and every kind of output line.

## When something goes wrong

Errors show as `[x]` lines with a red tint and `[?]` hints underneath: a missing part of a path, a close name you may have meant, or where a syntax error is. Double-click an error for everything about it, or use `/errors` and `/trace`. The **Errors** topic explains them.

## Results and types

Results show their type after the value: `5 <number>`, `"hi" <string>`. Instances show their class and the nearest useful base class, for example `Baseplate Part <BasePart>`, with the class icon in front.

The newest result is kept in `$last`, so `> $last * 2` carries on from it.

## The output

- Click a line to select it, **Ctrl+click** to add lines, **Shift+click** for a range.
- **Ctrl+C** copies the selected lines and **Ctrl+A** selects everything while the pointer is over the output.
- Double-click an `[>]` line to put that input back in the input line.
- Right-click for copy, copy without prefixes, select all, clear, and the game output and timestamp switches.

The output keeps the newest 5,000 lines. When you scroll up it stops following new lines; scroll back to the bottom and it follows again.

Text from the game is shown exactly as printed. Something like `<b>bold</b>` appears literally, never as formatting.

## Messages from plugins and the explorer

Plugins and the explorer write to the console with their name in front:

```
[plugin] Teleporter: 3 spots saved
[!] Teleporter: spot "Base" is out of the map
[x] Teleporter: couldn't read spots.json
[+] Explorer: deleted 2 objects
[x] Explorer: couldn't delete Terrain: The Parent property of Terrain is locked
```

Their errors are real error records: they appear in `/errors`, `/trace` shows the details (and a traceback when there is one), and `$err` holds the newest. When something a plugin handed Tungsten fails (a command, a menu entry, its tab, a hook…), the console says so under the plugin's name rather than staying silent, and the Plugins tab counts it on the plugin's page. The same warning or error repeated many times in a second is written once, then "repeated N times".

## Game output

`/game on` (or **Show game output** in the right-click menu) mirrors the game's own `print`, `warn` and errors as `[game]` lines. Warnings are yellow and errors red. The switch is saved with your settings.

`print` and `warn` inside console code write to the console directly (as `[*]` and `[!]`), not to the game. Console code can also use `tungsten` to reach Tungsten's own modules (see **Variables**).

## Settings that are kept

The **Plugins** tab's first entry, **tungsten** (with the accent outline), is the program's settings page. It isn't a plugin and adds no tab. It holds **window size** (**−** / **+**, in percent), **tooltips**, the **command bar key**, the explorer's **services first, then A–Z** order, and **Reset all settings**. Other settings are changed where they are used: the accent color with `/accent`, console options from the output's right-click menu (timestamps), `/traceback` and `/game on`, the properties panel's options from its ⋯ button, the explorer split by dragging the line, and the tab order from the side bar's right-click menu. **Reset all settings** puts every one of them back.

**Window size** makes the window (and the explorer joined to it) bigger or smaller, like resizing it. Text, icons, buttons, rows, menus, dialogs and toasts keep their size; lists, panes, the path bar and the console get more room (or less). The command bar, the minimized pill and the splash screen are never affected. The scale only changes when you change it (here, `/scale` or `/settings Scale`); **+** stops at the biggest size that fits your screen at that moment, and a smaller screen later never changes it.

Only preferences are saved: window scale, accent color, game output, timestamps, tracebacks, the explorer's sort and split, property options (decimals, deprecated, hidden), the tab order and hidden tabs, the command bar key and tooltips. Everything else starts fresh each time Tungsten runs: it always opens on the Console, with the explorer open, no filter, every property category unfolded, and no variables, aliases, watches or history.
