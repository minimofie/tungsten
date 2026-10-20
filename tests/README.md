# Tungsten offline tests

A mock of the Roblox engine and Volt's functions, so Tungsten can be run and
checked outside the game. It is not part of Tungsten and is never copied into
workspace/Tungsten.

Files
- harness.luau      the mock: instances, layout (list/grid/padding/auto-size),
                    input, tweens, task scheduler, files, getgenv, gethui...
- build_test.py     bundles the Tungsten folder (.luau, .json, .md) + harness + a test file into one script
- test_smoke.luau   boots Tungsten and opens every built-in tab
- test_components.luau  UI components on a blank page (the former test tab is
                    fixtures/component_page.luau): scale, menus, list,
                    dropdowns, pickers, editor, scrolling, re-run
- test_stage3.luau  Stage 3 checks (console input/output, prefixes, every
                    command group, variables, types, [game] mirror and
                    escaping, completion, history, documentation tab, re-run)
- test_menus.luau   the menu framework (sections, context, checks, submenus,
                    Provide/Include, fixed menus, owners, faults), custom row
                    kinds, picker kinds, List/editor menus, addFunction, and
                    every shipped menu's full entry list
- test_ui.luau      the UI framework: registry, UI.new, events and filters per
                    component, own/all scope, order, faults, registered value
                    types, classes and categories, removeOwner, /ui
- test_reporter.luau reporters (plugin and explorer messages, error records,
                    try/wrap, folding) and every fault the frameworks report
- test_access.luau   values inside scripts in the path bar: base/access
                    (require / getsenv paths, found, typed, /load, Copy),
                    the script viewer passing paths on
- test_pathback.luau  the path bar's back button (base/loaded history)
- test_pathreload.luau the path bar's reload button (Loaded.reload: values
                    inside scripts read again, not remembered for back),
                    typed $variables, paths to nested functions
                    (debug.getproto(f, n) and (f, n, true)[k]): code,
                    crumbs, resolve, parse, the path bar and /load
- test_svviews.luau Script Viewer revamp: the scrolling work area (list at
                    least View.ListMin), References toggle, view switches
                    deferred and guarded (newer wins, failure says why),
                    List search and type filter, the Table text cap
- test_svinspect.luau Script Viewer: Inspect (replaces Look into it) and
                    Copy path only with a real path (code reaching it)
- test_svfunctions.luau Script Viewer: the Functions sub-tab and its details
                    pane, nested functions as subjects (constants through
                    the proxy, running copies' upvalues), running copies,
                    a script's running functions and bytecode
- test_svforms.luau Script Viewer: the value field (only the types that
                    fit, a variable picker), values from variables,
                    suggested variable names
- test_svupvalues.luau Script Viewer upvalues: a moved script's running
                    functions found by getfenv(fn).script, a loaded table's
                    (and ModuleScript's) functions' upvalues by key path,
                    paths through rows (Up), Search all functions (text,
                    numbers, inside tables), results changed and refreshed
- test_svdeep.luau  Script Viewer: the Contents Deep view (tables only):
                    functions open into Constants / Upvalues / Nested
                    functions, all changeable, with paths; a table's
                    Constants and Functions sub-tabs by key path
- test_loader.luau  the web loader (loader.luau): release.txt is current with
                    Tungsten/; fresh install, nothing new, update (changed,
                    same-size, dropped, added, hand-edited files), a failed
                    download writes nothing, offline, unsafe paths, Run = false
- test_pathbar.luau the path bar: dropdown, Copy, Highlight, arrow, crumbs and
                    child lists, typing paths, long paths, overrides
- test_stage4a.luau explorer panel, tree, search, selection and $sel, path bar,
                    right-click menu, explorer commands, collapse, re-run
- test_stage4b.luau API data, the new value types, the properties model, the
                    panel (switches, lists, text, parts, CFrame, colors,
                    palette, references and pick mode, sequences, filter,
                    categories, options, splitter, attributes, tags), the
                    property menu, /props /setprop /attrs, plugin editors,
                    many objects, re-run
- test_stage4c.luau explorer filter (panel, groups, classes, hide, search,
                    /find, path bar lists, /filter, plugin groups), filter
                    words in every search, modular documentation (topics,
                    sections, directives, class pages), Explorer › Load,
                    tabs and icons for plugins, tooltips, prompts, toasts,
                    the command bar, the pill and fade, welcome + integrity
- test_stage4d.luau Stage 4 Round C: right-click actions, clipboard, freeze,
                    var(), /undo, /decompile, /save, the plugin api groundwork
- test_stage5a.luau one UI scale (window, explorer, popups; command bar, pill
                    and splash fixed), no automatic scale changes, the data
                    store, the mock's UIScale geometry
- test_stage5b.luau the plugin host: discovery, P context, checks, states,
                    on/off at the next start, Load thread and time limit,
                    prime plugins / Requires / Exports, reload, rescan, locks
- test_stage5c.luau the host in Tungsten: start-up and welcome line, faults
                    under the plugin's name, /plugins and /plugin, every
                    registry cleaned, re-runs and /exit
- test_stage5d.luau variables across plugins: owners, refused names, by,
                    owned watches, owner-aware undo
- test_stage5e.luau the Plugins tab list: cards, chips, live sync, search,
                    multi-select, plugins.entry menu, badge, empty state
- test_stage5f.luau a plugin's page: Enabled switch, state, buttons, adds,
                    settings + Reset, problems / Details / faults
- test_stage5g.luau the plugin api: owned connect/spawn/delay/every/bin,
                    owners set for it, api.files, nothing left behind
- test_stage5h.luau tab pieces: page, section, row, field, placeholder,
                    panes, sub-tabs, one path bar for every tab, api.tab
- test_stage5i.luau the authoring guide: its template and tab example run
                    as real plugins
- test_p0a.luau     Plugins stage P0a: one loaded target for every tab
                    (base/loaded), +N, values that aren't Instances, /load,
                    Tab.OnLoad, api.loaded, prime order, Uses,
                    api.plugins.open (fixtures Viewer, Linker, Overreach)
- test_p1a.luau     Plugins stage round 1, part 1.1: the shipped script
                    viewer (off until on), its tab, the Overview of scripts,
                    modules, functions, tables; missing Volt functions; reveal
- test_p1b.luau     part 1.2: Constants, Upvalues and Functions sub-tabs
                    (Tree / List, opening tables and functions, cycles,
                    empty slots, pill counts, views kept in settings)
- test_p1c.luau     part 1.3: Source (decompiled when looked at, in a thread,
                    once per script, stale results dropped, Copy) and Table
                    (loaded tables, what required modules return; now Contents)
- test_p1d.luau     part 1.4 (revamped): views Tree / List / Table (rows as
                    a Luau table, KEEP for what can't be written), the scope
                    With nested functions (it replaced the Function view);
                    the Table sub-tab renamed Contents
- test_p1e.luau     part 1.5: references of constants and upvalues (filtergc,
                    re-checked, threaded, capped at 200, opening one)
- test_p1f.luau     round 1 fixes: no Overview, Source first (decompiled only
                    while the tab is open), a script's upvalues from its
                    running functions, reload / re-run with the tab open,
                    no fault lines from the plugin
- test_p1g.luau     part 1.6: editing. Right-click menu on rows
                    (scriptviewer.row), forms with Type dropdowns for
                    constants / upvalues / entries, add / rename / remove,
                    Keep in a variable, the Table view's Apply / Revert,
                    Undo, read-only tables only after a confirm (Q10), a
                    script's constants written to its running functions
- Shipped prime plugins (Tungsten/plugins/ScriptViewer, …) are set aside by
  the harness for every suite; a suite that tests them calls H.keepPrimes()
  before H.run. Volt stand-ins for the script viewer read H.FN[fn]
  (Constants, Upvalues, Protos, Info, Hash, C, Executor), H.SCRIPT_CLOSURES,
  H.RUNNING, H.SENV, H.SCRIPT_HASH, H.MODULE_VALUES; decompile counts
  H.DECOMPILED and waits H.DECOMPILE_WAIT seconds when set; filtergc searches
  H.GC (H.FN[fn].Env matches Environment; H.FILTERGC_LOOSE returns everything,
  H.FILTERGC_WAIT yields). debug.setconstant / debug.setupvalue write H.FN[fn]
  (H.SETCONSTANT_FAIL refuses); setreadonly / isreadonly use H.READONLY.
  getgc returns H.GC; debug.info(fn, "s") returns H.FN[fn].Source when set;
  H.FILTERGC_ENV_MISS / H.FILTERGC_SOURCE_MISS make those filtergc options find nothing.
  Protos are tables { Info, Constants, Protos, Closures, Line, Source, CodeHash };
  handed out by getprotos / getproto they become ProtoProxy (typeof, via
  H.proto). debug.getproto(f, i, activated) returns the proto or a copy of
  its Closures (H.GETPROTO_CALLS counts); debug.info on a proto reads
  Source / Line / Info.name / Info.numparams.
- test_p0b.luau     Plugins stage P0b: sub-tabs in Tungsten's style (pills,
                    open / hover / badge looks, sideways scrolling, scales)
- fixtures/plugins/ test plugins (copied into Tungsten/plugins by the Stage 5
                    suites; never shipped)

Before running, refresh the file list the integrity check uses:
    python3 tools/make_manifest.py Tungsten

Run (needs the luau CLI from github.com/luau-lang/luau releases)
    python3 build_test.py <folder containing Tungsten/> test_components.luau run.luau
    (echo "SHIFT = 58"; cat test_components.luau) > t.luau   # optional: top-bar offset mode
    luau run.luau

Mock behaviour that matches Roblox (learned in Stage 2)
- A GUI object's InputBegan fires before UserInputService.InputBegan.
- MouseEnter reaches every object under the pointer, even covered ones.
- AbsolutePosition can be measured from below the top bar (SHIFT = 58 mode),
  while GetMouseLocation counts from the top of the screen.
- AbsoluteSize change events fire after layout.
- LogService.MessageOut is a plain signal (H.services.LogService) so tests
  can play game output.

Added for the explorer
- game is a DataModel instance with Workspace, ReplicatedStorage, Lighting and
  StarterGui as children; workspace.Parent == game.
- Parent changes fire ChildAdded / ChildRemoved, AncestryChanged,
  DescendantAdded / DescendantRemoving like the engine.
- H.NIL is what getnilinstances() returns, H.LOADED what getloadedmodules()
  returns; compareinstances compares by identity.
- build_test.py also bundles tests/fixtures/*.luau as FILES["fixtures/<name>"].

Added for the properties panel
- CFrame (with rotations, ToOrientation, fromOrientation), NumberRange, Rect,
  Vector2int16/Vector3int16, NumberSequence/ColorSequence (+ keypoints),
  Faces, Axes, Font, PhysicalProperties, Ray, Content, BrickColor (a small
  palette); Color3 ToHSV/fromHSV/fromHex; enums list their items.
- H.part(name, parent, props) makes a Part with typed properties (wrong
  types and read-only properties error like the engine).
- Property changes fire Changed(name); attributes (GetAttributes,
  AttributeChanged, name rules) and tags (AddTag, GetTags, ...).
- gethiddenproperty / sethiddenproperty / getproperties; H.HIDDEN marks
  hidden names. H.CLASS_PARENTS lets a test add classes.

Added for Stage 5
- UIScale like the engine: a UIScale in a GuiObject multiplies its size
  (about its AnchorPoint) and every offset inside it; AbsoluteSize /
  AbsolutePosition report on-screen pixels; TextService:GetTextSize is not
  scaled. H.scaleOf(obj) gives the combined scale.
- loadfile throws for a missing file and returns nil + message for a
  compile error, like Volt. delfolder removes a folder and its files.
- build_test.py also bundles tests/fixtures/plugins/<Folder>/** as
  FILES["fixtures/plugins/<Folder>/<file>"]; the suites copy what they need
  into Tungsten/plugins/.
- build_test.py also bundles the repo root's loader.luau and release.txt as
  FILES["loader.luau"] / FILES["release.txt"]. H.run(path, ...) passes extra
  arguments to the chunk (the loader's options). request() has no stand-in:
  test_loader sets E_.request to serve a stand-in repository.
- H.clickObjectLeft(obj, button?, inset?) clicks near the left end of a wide
  row (the mock doesn't clip; the engine does).
- Run every suite in both modes from the folder holding Tungsten/ and tests/:
  tools/run_all.sh   (or name suites: tools/run_all.sh test_stage5a.luau). By hand:
  python3 build_test.py <root> test_stage5a.luau run.luau && luau run.luau
