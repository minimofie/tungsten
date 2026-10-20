# Commands

Every command, by group. `<angle brackets>` are required, `[square brackets]` are optional. Other names for a command are listed after it. `/help name` in the console explains any command, including plugin commands.

These tables are made from the commands themselves, so they are always complete: a command a plugin adds shows up in its group (with the plugin's name), and a group of its own gets its own table under **Other groups**.

## Console

{{commands:Console}}

## Variables

{{commands:Variables}}

## Errors

The **Errors** topic explains error records, hints and tracebacks.

{{commands:Errors}}

## Tools

{{commands:Tools}}

## Explorer

A target is a variable (`$door`, or a table of instances), a path (`game.Workspace.Door`, `workspace.Map["Spawn 1"]`) or nothing for the explorer selection. For `/props`, `/setprop` and `/attrs` the target comes first and can be left out (`/setprop Transparency 0.5` sets it on the selection). `/find` and `/select` searches follow the explorer filter (`/filter`).

{{commands:Explorer}}

## Game

These only read; they change nothing in the game.

{{commands:Game}}

## Window

{{commands:Window}}

## Other groups

{{commands-other}}

## Examples

```
/set spawn = workspace.SpawnLocation
/get spawn
/vars Part
/text greeting hello $who
/inc kills && /get kills
/bench 10000 > math.sqrt(2)
/alias where = = workspace.CurrentCamera.CFrame.Position
/repeat 3 /echo hi
/settings ConsoleTimestamps on
/setas home Vector3 0, 10, 0
> double = function(n) return n * 2 end
/call double 21
/echo half of $a is ${$a / 2}
```

> Right-click a code block in this documentation and pick **Run in the console** to try it.

## Commands from plugins

{{plugin-commands}}

A plugin can also add a section to this page (or any other) with `Docs.addSection("commands", { Title = …, Source = … })`; see **Documentation for plugins** in the **UI framework** topic.

## Adding commands

Every `.luau` file in `Tungsten/console/commands/` is loaded at start-up. A file returns a list of commands:

```
local T = ...
return {
	{
		Name = "hello",
		Group = "Tools",
		Usage = "/hello [name]",
		Description = "say hello",
		Run = function(ctx)
			ctx.success("hello " .. (ctx.Args[1] or "there"))
		end,
	},
}
```

`ctx` has:

- the arguments: `ctx.Args` (words, quotes removed) and `ctx.Raw` (the text after the command name)
- output: `ctx.info`, `ctx.success`, `ctx.warn`, `ctx.error`, `ctx.detail`, and `ctx.value(kind, label, value)` for a value with its type
- `ctx.resolve(word)`: `$a` gives the variable, `$a.Name` or `$t[1]` is evaluated, other words stay text
- `ctx.eval(code)`: runs Luau with variables (fails the command on an error)
- `ctx.interpolate(text)`: replaces `$name` and `${code}` in text
- `ctx.fail(message)` and `ctx.usage()`: stop with an `[x]` line
- `ctx.Variables`, `ctx.Types`, `ctx.Console` and `ctx.T` (all of Tungsten)

A value returned from `Run` becomes `$last`. `Complete = function(ctx, argIndex, partial) return { ... } end` gives Tab completion for arguments.
