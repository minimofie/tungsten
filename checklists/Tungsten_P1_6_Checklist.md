# Tungsten — part 1.6 checklist: editing (16 items)

Install: replace `workspace/Tungsten/` with the folder from `Tungsten_p1_6.zip`.
Keep the Script Viewer on. Report pass / fail per item; for a failure say what
you saw, any `[x]` line (`/trace`) and the newest file in `Tungsten/logs/`.

Setup for A–C: `> fn = require(game.ReplicatedStorage.SomeModule).SomeFunction` (any
Luau function with constants and upvalues), then `/load $fn`.

## A. The right-click menu
- **A1** Right-click a constant row: a menu with **Change** (Change value…) and **Use** (Keep in a variable…, Copy value, Copy path). No "Set to nil" for a constant.
- **A2** Right-click an upvalue row: also **Set to nil** in red. On a table upvalue: **Add entry to …** and **Look into it**.
- **A3** Open a table row and right-click an entry inside it: Change value…, Remove entry (red), Add entry to …, Rename key….

## B. Forms
- **B1** Change value… on a string constant: a form with a **Type** dropdown (only `string` while "Constants may change type" is off) and **Value**. Change it and press OK: the row shows the new value and the console says what changed.
- **B2** Type bad text into a number constant (`abc`): the form stays open and says why. Fix it: it writes.
- **B3** Plugins › Script Viewer › turn on **Constants may change type**: the Type dropdown offers string, number, boolean, and a constant can change type.
- **B4** Change value… on an upvalue: the Type dropdown offers every type (Vector3, Color3, CFrame, Instance, function…). Set a `Vector3` from `1, 2, 3`; set a function from a `$variable` (plain text like `print` is refused).
- **B5** Double-click a row that doesn't open (a number, a string): the same form opens.
- **B6** Add entry… on a table: Key type, Key, Value type, Value. Add one; Rename key… moves it; Remove entry takes it out.
- **B7** Keep in a variable… then `> print($name)` prints the value.

## C. Undo
- **C1** After any change in A–B, `/undo`: the value is back and the row shows it.

## D. Read-only tables
- **D1** Load a read-only table (e.g. `> t = table.clone({a = 1}) setreadonly(t, true)` then `/load $t`), change `a`: you are asked **Make the table writable?**. Cancel leaves it; Change it writes and `isreadonly(t)` is true again afterwards.

## E. Table view
- **E1** On Contents (or Constants / Upvalues), switch the view to **Table**: the text can be edited, **Apply** and **Revert** show. Change a value and press Apply: written, one `/undo` step. Revert shows the current values again.
- **E2** Text that isn't a table (`{ a =`) or that tries code (`{ a = os.exit() }`) changes nothing and says why.

## F. Scripts
- **F1** Load a running LocalScript and change a constant of one of its functions (Constants › Function view, or a constant the running code still uses, e.g. a string it prints in a loop): the running script uses the new value.
- **F2** Change a constant of a script's main chunk that has already finished: refused with "changing it would change nothing in the game" (the main chunk runs once and is gone; its running functions are under Upvalues).
