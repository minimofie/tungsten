# Prefixes

A prefix is the first character of an input. It decides how the input runs. Output lines start with a prefix too, so you can tell at a glance what each line is.

## Input prefixes

| Prefix | Example | What it does |
|---|---|---|
| `/` | `/help` | run a command |
| `:` | `:viewer.open` | run a plugin's command (`:plugin.command`) |
| `>` | `> 1 + 1` | run Luau and show the result on one line |
| `=` | `= workspace` | run Luau and show the result in full |
| `$` | `$a * 2` | Luau that starts with a variable |
| `?` | `?set` | help for a command; `?` alone lists every command |
| `!` | `!!` `!3` `!-2` `!/set` | run again from the history |
| `#` | `# reached wave 3` | write a note line; nothing runs |
| `&&` | `/set a = 1 && /get a` | run the next input only if this one worked |
| `\|\|` | `> risky() \|\| /echo it failed` | run the next input only if this one failed |

Without a prefix, a word that matches a command still runs it (`help` works like `/help`). Anything else gets a reminder of the prefixes.

### / commands

`/name arguments`. Words are split at spaces; put text with spaces in quotes: `/echo "two words"`. A word like `$a` passes the variable's value to commands that take values.

### : plugin commands

Plugins add commands under their own name: `:plugin.command`. A plugin command also works as `/command` when no built-in command and no other plugin uses that name. The **Commands** topic lists the commands plugins have added.

### > and = Luau

The code runs with every variable available by plain name and as `$name`. Assigning a new global makes a variable:

```
> x = workspace.Baseplate
> x.Transparency = 0.5
> $x.Name
```

`>` shows results on one line. `=` shows tables expanded (three levels), long text in full, and an Instance's path and child count.

Code that only does something (an assignment, a loop, a call that returns nothing) prints nothing except the variables it set.

### $ variables

`$name` reads a variable anywhere: in Luau code, as a command argument (`/get $a`), or inside text (`/echo hi $who`). In arguments `$base.Size` is worked out as code, and in text `${code}` is replaced by its result. Write `$$` for a plain dollar sign. Two names are reserved:

- `$last` is the newest result.
- `$sel` is the explorer selection: the object, or a table of objects when several are selected.
- `$err` is the newest error record (see **Errors**).

### ? help

`?set` is `/help set`. `?prefixes` (or `/help prefixes`) prints both prefix tables in the console.

### ! history

| Input | Runs |
|---|---|
| `!!` | the last input |
| `!3` | history entry 3 (see `/history`) |
| `!-2` | two inputs back |
| `!/set` | the newest input that starts with `/set` |

The input that actually runs is echoed and saved to the history in place of the `!` input.

### # notes

`# text` writes a `[#]` line. Use it to mark what you were doing; `/savelog` keeps it with the rest of the output.

### && and || chains

`a && b && c` runs the parts one after another. If a part fails (an unknown command, a Luau error, a command that reports a problem), the `&&` parts after it are skipped and a `[?]` line says how many. `/wait` pauses a chain: `/echo go && /wait 2 && /echo done`.

`a || b` is the other way round: `b` runs only when `a` failed, so `> risky() || /echo it failed` gives a fallback. They mix: in `a && b || c`, `c` runs if `a` or `b` failed. `/try a && b` runs `b` either way.

`&&` and `||` inside quotes, brackets or Luau strings are left alone. The **Errors** topic has more.

---

## Output prefixes

| Prefix | Meaning |
|---|---|
| `[*]` | information; also `print` from console code |
| `[+]` | worked; results |
| `[!]` | a warning: something was adjusted or skipped; also `warn` from console code |
| `[x]` | something failed; the console keeps working. Each has an error record: double-click it, or see `/errors` |
| `[>]` | the input you ran |
| `[=]` | a result shown in full by `=` |
| `[?]` | help text, and hints under errors explaining what went wrong |
| `[#]` | a note written with `#` |
| `[$]` | a watched variable changed (`/watch`) |
| `[~]` | timings: `/bench`, `/time`, `/fps`, `/ping` |
| `[plugin]` | output from a plugin, as `[plugin] Name: text` |
| `[game]` | the game's own output, when `/game on` |

Lines without a prefix belong to the line above them (lists, tables, details).

> Right-click the output and pick **Copy without prefixes** to copy just the text.
