# Errors

When something fails, the console writes an `[x]` line with a faint red background. It never stops working: the next input runs as usual.

Every `[x]` line has an error record behind it, with a number. `/errors` lists them, `/trace` explains one in full, and `$err` holds the newest.

## What you see

```
[>] > workspace.Basepalte.Size
[x] console:1: Basepalte is not a valid member of Workspace "Workspace"
[?] workspace (Workspace <WorldRoot>) has no child or property "Basepalte" · did you mean "Baseplate"?
[?] Roblox names are case-sensitive · = parent shows what is there
```

The same works for tables and variables: `> $cfg.speeed * 2` on a table without `speeed` says `cfg has no "speeed" · did you mean "speed"?`.

- The `[x]` line is the error itself.
- `[?]` lines explain it in plain words. For a path like `a.b.c`, the console finds the part that is missing (without running your code again) and suggests close names.
- For syntax errors, the code is shown with a `^` under the problem:

```
[>] > 1 +
[x] console:1: Expected identifier when parsing expression, got <eof>
    1 +
       ^
[?] the code ends too early: a bracket, quote, then, do or end is missing
```

## Kinds of errors

| Kind | When |
|---|---|
| `syntax` | the Luau can't be read: a typo, a missing `end` or quote |
| `runtime` | the Luau ran and failed: indexing `nil`, calling something that isn't a function |
| `command` | a command refused its input (`usage: …`, an unknown variable) or failed inside itself |
| `unknown` | no such command, or input without a prefix |
| `internal` | Tungsten itself went wrong; the details are in the log (`/logs`) |
| `game` | an error from the game's own output (only while `/game on`) |
| `plugin` | a plugin reported a problem, failed to start (`Load`), or something it handed Tungsten failed (a command, menu entry, explorer function, its tab, a hook, a settings button, an owned connection or thread); the line starts with the plugin's name, and the Plugins tab counts it on the plugin's page |
| `explorer` | an explorer action failed (deleting a locked object, copying without a clipboard); the line starts with `Explorer:` |

`/errors plugin` or `/errors explorer` lists only those. `/trace` shows who reported an error on its `from` line.

## Commands

| Command | What it does |
|---|---|
| `/errors [count \| kind \| clear]` | list recent errors, newest last: `/errors 5`, `/errors runtime`, `/errors clear` |
| `/trace [number]` | everything about an error: message, input, code, caret, hints and traceback (the newest by default) · also `/why`, `/error` |
| `/retry [number]` | run the input of an error again (the newest by default) |
| `/try <input>` | run an input; if it fails you get a warning instead, so a `&&` chain carries on |
| `/traceback [on \| off]` | also print the traceback under each code error (saved as a setting) |

## Tracebacks

A runtime error remembers where it happened. Tungsten's own frames are left out, so the traceback shows only your code: `console:1` lines and functions you made in the console. `/trace` prints it; `/traceback on` prints it under every code error.

## Clicking errors

- Double-click an `[x]` line (or a row in `/errors`) to explain it.
- Right-click it for **Explain this error**, **Copy error with details**, **Run it again** and **Put the input back**.

## Chains and errors

| Input | Runs |
|---|---|
| `a && b` | `b` only if `a` worked |
| `a \|\| b` | `b` only if `a` failed |
| `a && b \|\| c` | `c` if `a` or `b` failed |
| `/try a && b` | `b` either way |

```
> workspace:FindFirstChild("Door").Transparency = 1 || /echo no door here
/try /get maybe && /echo carried on
```

## $err

`$err` is the newest error record, a table you can read in code:

| Field | Holds |
|---|---|
| `Id`, `Time`, `Kind` | its number, when, and which kind |
| `Message` | the error text |
| `Input` | what was typed |
| `Code`, `Command` | the Luau or the command that failed |
| `Caret` | the code line and the `^` marker (syntax errors) |
| `Hints` | the `[?]` explanations |
| `Trace` | the traceback frames |

```
= $err
> $err.Message
```

Plugins can follow errors with `tungsten.Console.Errors.Added:Connect(function(record) … end)`.
