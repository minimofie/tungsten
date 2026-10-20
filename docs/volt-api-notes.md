# Volt API notes

These are taken from docs.voltbz.net pages read during this stage. The docs often leave error cases undocumented, so guard every call with `pcall` and re-check what comes back. Before using a function for the first time, read its page: `https://docs.voltbz.net/docs/<library>/<name>`. The libraries are `debug`, `closures`, `scripts`, `environment`, `miscellaneous` and others; the index is at `/docs`.

## Scripts

- **`getscriptclosure(script: LocalScript | ModuleScript | Script) -> function | string`**
  - Compiles a **new** closure from the script's bytecode. It is "not the closure currently running in the game", and for a ModuleScript it isn't what `require` returned either.
  - Returns a string when compilation fails. Raises an error when the bytecode can't be read.
  - Alias: `getscriptfunction`.
  - So: constants and nested functions read from it are the script's, but **changing them changes nothing in the game**. Edits must go to the running functions (see `Edit.constantTargets`).
- **`getsenv(script) -> table?`**: the script's global environment (no locals). Returns nil when unavailable, which isn't defined further. The docs only show it with `getrunningscripts()` results. Tungsten asks for it even when the script isn't listed as running.
- **`getrunningscripts()`**: the scripts that are running.
- **`getloadedmodules() -> {ModuleScript}`**: "currently loaded" modules. The docs don't define "loaded"; Tungsten treats them as required by the game, so `require` returns the cached value without running anything.
- **`getscripthash(script)`**: nil when the script has no bytecode.
- **`decompile(script)`**: yields, errors on failure, and doesn't support server Scripts. Run it in a thread with `pcall`.

## Closures

The library lists: `checkcaller`, `clonefunction`, `getfunctionhash`, `hookfunction`, `hookmetamethod`, `hookproto`, `iscclosure`, `isexecutorclosure`, `isfunctionhooked`, `islclosure`, `isnewcclosure`, `isprotohooked`, `newcclosure`, `newlclosure`, `restorefunction`, `restoreproto`, `setstackhidden`, `trampoline_call`.

- **`getfunctionhash(func: function) -> string`**: a 96-hex-character SHA-384 digest of a Luau closure's **instructions and constants**. It throws for C closures and accepts functions only (not a ProtoProxy).
  - A fresh copy and the running function hash the same until one of them is edited. Tungsten edits both, so they stay equal.
- **`iscclosure` / `islclosure` / `isexecutorclosure`**
- **`hookproto(proxy, hook)`**: hooks every current and future closure of a nested function until `restoreproto`. The hook must have **zero upvalues**, so it reports through a `getgenv` table. Planned for round 3.
- **`hookmetamethod`**: wraps the hook in `newcclosure` itself and returns the original. Several objects can share one metatable, so a hook must check the class and method.
- **`oth` library:** `oth.hook(cfn, luauHook)`, `oth.unhook`, `oth.get_root_callback`, `oth.is_hook_thread`. This is the alternative for C methods (Q13).
- **`getcallbackmember`** is the canonical callback reader; `getcallbackvalue` is an alias.

## Debug

The library lists: `getcallstack`, `getconstant`, `getconstants`, `getinfo`, `getproto`, `getprotos`, `getstack`, `getupvalue`, `getupvalues`, `setconstant`, `setinfo`, `setstack`, `setupvalue`, `validlevel` (alias `isvalidlevel`), and `ProtoProxy`.

- **`debug.getconstants(func)`**: 1-based, with **nil holes**, Luau closures only.
- **`debug.setconstant(func: function | number | ProtoProxy, index, value) -> function`**: 1-based.
  - The docs' cautions: unexpected behaviour if the constant is used in several places, if an incompatible type is set, or if the bytecode expects a specific value.
  - This backs the same-type default.
- **`debug.getupvalues(func: function | number) -> table`**: indices to values. The page doesn't mention ProtoProxy; a proto has no upvalue values.
- **`debug.setupvalue(func, index, value)`**: changes the **shared variable**, so every closure that captures it sees the new value.
- **`debug.getprotos(func: function | number | ProtoProxy) -> {ProtoProxy}`**: one per nested prototype. They can be used with the debug functions but **can't be called**. The page doesn't say whether only direct children are returned.
- **`debug.getproto(func | number | ProtoProxy, index, activated?)`**
  - Without `activated` it returns a ProtoProxy.
  - With `activated = true` it returns a **table of the live closures** using that prototype: the running copies, which have real upvalues. Only closures that exist are returned.
- **`debug.getinfo(func | number | ProtoProxy) -> table`**: there is no options string. Fields: `name` (or ""), `source`, `short_src`, `what` ("Lua" / "C" / "main"), `currentline` (a sentinel when not active), `nups`, `numparams`, `is_vararg` (1 or 0), `func`.
- Luau's own `debug.info(fn, "s" | "l" | "n" | …)` is also used, e.g. source names for matching a script's functions, and line-defined.

## Environment and memory

- **`filtergc(type: "function" | "table", options, returnOne?) -> any? | {any}`**
  - Function options: `Name`, `Constants`, `Upvalues`, `Hash`, `IgnoreExecutor` (default **true**), `Environment`, `StartLine`, `Source`, `UpvalueCount`, `ConstantCount`.
  - Table options: `Keys`, `Values`, `KeyValuePairs`, `Metatable`.
  - How lists are matched isn't documented, so **re-check results**. `Constants`, `Upvalues` and `Hash` don't apply to C closures.
  - Whether the `Environment` table is the same as the `getsenv` table isn't documented. That is why `Rows.liveFunctions` falls back to `Source` and then `getgc`.
- **`getgc(includeTables?) -> table`**: functions only by default. With `true` it adds tables, userdata and threads, which the docs warn is slow.
- **`isreadonly(t)` / `setreadonly(t, bool)`**; `table.isfrozen` covers frozen tables, which can never be written.
- **`getrawmetatable`**, **`getconnections`** (entries have `Function` / `Thread` nil for C connections), **`getnilinstances`**.

## Facts from the handoff (§6.2)

- **UI:** `gethui()`. `cloneref` copies aren't `==` (use `compareinstances`). `getcustomasset(path)` loads local images.
- **Files:** paths are relative to Volt's workspace.
  - `listfiles(dir)` gives direct children prefixed with the folder, `/`-joined, with folders having no trailing slash.
  - `loadfile` returns nil plus a message on a compile error but throws for a missing file.
  - `writefile` and `makefolder` create parent folders.
  - Also: `appendfile`, `delfile`, `delfolder`, `isfile`, `isfolder`.
- **Code:** `loadstring(code, chunkname?)`. `getgenv()` persists across executions. `setfenv` / `getfenv` are available, but `getfenv` de-optimises environments, so avoid it in hot paths.
- **Explorer:** `saveinstance(root, SaveInstanceOptions.new())`, `getscriptbytecode`, `fireclickdetector`, `fireproximityprompt`, `firetouchinterest(part, target, 0/1)`.
- **Hooks:** `hookmetamethod(game, "__namecall", newcclosure(fn))`, `getnamecallmethod`, `checkcaller`. Keep one shared hook in `getgenv` so re-runs don't stack, and always chain to the original.
- **Clipboard:** `setclipboard` only; reading the clipboard isn't possible.

## Functions in Tungsten's integrity list (50)

See `Tungsten/base/integrity.luau`. Script-viewer additions this stage: `getsenv`, `getrunningscripts`, `getscripthash`, `getfunctionhash`, `iscclosure`, `isexecutorclosure`, `isreadonly`, `getrawmetatable`, `debug.getinfo`, `debug.getconstants`, `debug.getupvalues`, `debug.getprotos`, `filtergc`, `debug.setconstant`, `debug.setupvalue`, `setreadonly` and `getgc`. When you add one, bump the `50/50` expectations in `test_stage4c`, `test_p1a` and `test_p1e`, and give the harness a stand-in.
