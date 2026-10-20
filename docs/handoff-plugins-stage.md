# Tungsten — Handoff for the Plugins stage (original, text of the PDF)

> Extracted word for word from `Tungsten_Handoff_Plugins.pdf` (18 Oct 2026), the document this work started from. Sections 5–6 (decisions, conventions, Volt facts) still apply. Where later decisions differ, `docs/decisions.md` wins (e.g. `objectviewer` is now `instanceviewer`; P2 "ships no plugins" was changed by Q5: primes ship, off).

```text
Tungsten — Handoff for the Plugins stage
Client-side Luau script for the Volt executor · Stages 1–5 built · Stage 5 (the plugin system) complete in source,
in-game checklists pending · next: the Plugins stage (two platform changes, then the plugins themselves)
Prepared 18 Oct 2026 · version in source 0.4.0 + Stage 5 · 85 Luau modules · offline tests: 20 suites, 2,454
checks (normal and SHIFT = 58 )
Embedded in this PDF (attachments panel): Tungsten_stage5c.zip , Tungsten_tests_stage5c.zip ,
 Tungsten_stage5c_testplugins.zip , Tungsten_Stage5_Decisions.md ,
 Tungsten_Stage5A/B/C_Checklist.md , ref.txt (the original spec)


1 Starting the next conversation
1. Run the three Stage 5 checklists (A 46 items, B 33, C 21) in Volt if you haven't, and note any failures.
2. Start a new conversation (cheaper than continuing a long one).
3. Attach this PDF, Tungsten_stage5c.zip , Tungsten_tests_stage5c.zip and ref.txt (all four are also
   embedded here).
4. Paste the message below, filling in the Stage 5 result and the details of the first plugin.
  I'm building Tungsten, a client-side Luau script for the Volt executor (Roblox).

  Attached:
  - Tungsten_Handoff_Plugins.pdf (this handoff: the plan, every decision so far,
    the plugin system, conventions, Volt facts; zips and spec embedded)
  - Tungsten_stage5c.zip      (the current Tungsten folder - my copy is the master)
  - Tungsten_tests_stage5c.zip (offline mock runtime + 20 suites; tools/run_all.sh)
  - ref.txt                   (the original spec; also Appendix A)

  Stage 5 in-game result: [PASSED / list failing items as A12, B4, C7 ...]

  Start the PLUGINS STAGE, following section 2 of the handoff:
  first the two platform changes (round P0), then the plugins in order,
  one per round. I will give each plugin's details when its round starts.
  Ask me the open decisions in section 2.3 before coding.

  Rules:
  - Use the study-volt-doc skill / Volt docs (docs.voltbz.net) before coding,
    and check every Volt function a change uses on its doc page.
  - Luau only. Target Volt's documented API; no fallbacks for other executors.
  - Never mention reference projects (any explorer, spy or scanner it is
    modelled on) in code, comments, UI, docs, logs or file names.
  - Everything local under workspace/Tungsten/ - no downloads at runtime.
  - Images: draw in SVG (send the .svg plus a PNG copy).
  - Follow the conventions and standing decisions in sections 5-6.
  - Work in small stages; stop at a clean point after each and wait for me.
  - Extend the offline tests for every change; run all suites (normal and
    SHIFT = 58) before sending anything.
  - After each round send the changed files, a full zip and that round's
    checklist, then STOP and wait for my test results.
  - If Stage 5 has failures, fix those first and send them before round P0.


 Test loop. Copy the round's folder into workspace/Tungsten/ , run Tungsten.luau in Volt, go through
 the checklist and report pass/fail per item; for failures include what you saw, any [x] line ( /trace
 gives the details) and the newest file in Tungsten/logs/ . Only failures are re-tested after fixes. Keep
 every round's zip — your copies are the master.




                                          Tungsten handoff · Plugins stage · page 1 of 8
2 What the Plugins stage builds
2.1 Round P0 — two platform changes (before any plugin)
Change                      What it means                                                    Where it lands
1. One loaded instance      Loading an instance into the path bar                             base/ui/pathbar.luau (one shared
for every tab               (Explorer › Load, the path bar's arrow, a                        loaded instance instead of per-tab
                            typed path, /load -style commands) makes                         overrides),
                            it the instance every tab works on. Every tab                    base/explorer/explorer.luau
                            — built-in and plugin, and every sub-tab —                       ( Explorer.load ),
                            sees the same loaded instance and is told                        base/registry.luau / tab bar
                            when it changes. Today each tab keeps its                        ( OnLoad for every tab),
                            own path-bar object ( PathBar.show(obj,                           base/api.luau ( api.loaded get /
                            tabId, subTabId?) ) and Load goes only to                        Changed; api.pathbar ), console
                            the open tab ( OnLoad ).                                          $loaded , docs (Explorer, UI, Plugins),
                                                                                             tests (pathbar, 4c, 5h)
2. Sub-tabs in the main     The sub-tab strip inside a plugin's tab should base/ui/components/subtabs.luau ,
UI's style                  look like Tungsten's own UI (the side bar /    its tests (5h), the UI and Plugins topics,
                            title bar language: accent marks, hover,       a picture of the new look for approval
                            rounded surfaces, icons) instead of the
                            current plain underline strip.
3. Prime load order         The plugins' order changed (see 2.2): the                        base/plugins.luau , docs, test 5b
                            prime list in base/plugins.luau
                            ( Plugins.Prime ) becomes script viewer,
                            instance viewer, scanner.

2.2 Then the plugins, one round each, in this order
#      Plugin                                      Notes for planning
1      Script / module viewer and editor           Details of each plugin are given by the user at the start of its round;
       (prime id scriptviewer )                    this handoff deliberately carries none. Each is a prime plugin: a
                                                   folder in Tungsten/plugins/ with Prime = true , built only with
2      Instance viewer / editor (prime id
                                                   the plugin api (section 4), its views as sub-tabs of its one tab, its
        objectviewer )
                                                   shared functions in Exports . Plugins link to each other through
3      Universal scanner / spy (prime id            Requires + api.plugins.get(id) . Each round: plan → open
       scanner )                                   decisions → build → tests → zip + checklist → stop.
Shipping. Standing decision P2 says Tungsten ships no plugins. The prime plugins are the exception the
user will confirm in 2.3 (Q5): whether they ship inside Tungsten/plugins/ (and start off or on), or are
delivered as separate folders.
2.3 Open decisions to ask first
#      Question                                           Proposal
Q1     What does "loading" a single instance              Load the selection as a list; the path bar shows the first and a
       mean when several are selected — load              count; tabs get the whole list.
       the list or the first?
Q2     Does selecting in the explorer also load,          Only explicit loads (Load, path bar arrow, typed path,
       or only Explorer › Load / the path bar?            commands); selection stays $sel .
Q3     Keep per-tab path bar objects at all?              No: one loaded instance; api.pathbar.show becomes "load
                                                          this" (shared), per-sub-tab overrides removed.
Q4     Sub-tab style: which part of the main UI to Rounded pill buttons like the title-bar buttons, accent tint on the
       mirror?                                     open one, icon + text, hover like side-bar tabs; show a drawn
                                                   picture before building.


                                            Tungsten handoff · Plugins stage · page 2 of 8
Q5       Do prime plugins ship with Tungsten, and            Ship in plugins/ , start off like any plugin (P1), turned on from
         start on?                                           the Plugins tab.
Q6       Prime plugins need explorer rights plugins Add api.explorer.select / setProperty (undoable)
         don't have (set the selection, write       available only with Prime = true ; decide in the first round
         properties).                               that needs them.
Q7       Prime load order with the new list.                 scriptviewer , objectviewer , scanner (change 3).



3 Where things stand
 Planning · passed → 1 Foundation & window · passed → 2 UI components · passed → 3 Console,
 variables, types, errors, docs · passed → 4 Explorer complete · passed (98/98) → 5 Plugin system ·
 built, in-game checklists pending → Plugins stage (next) → Docs, icons, polish

Stage 5 round          What it built
A1 scale               One UI scale for everything (window, explorer, every popup, plugin UI) except the command
                       bar and its suggestions, the minimized pill and the splash. Scale changes only when the user
                       changes it, capped to what fits at that moment. base/datastore.luau keeps Tungsten's
                       and plugins' settings.
A2–A3 host              base/plugins.luau : discovery, P context, checks, states (off / on / failed / problem), on/off
                       at the next start, Load in its own thread (5 s limit), prime plugins + Requires + Exports ,
                       reload, rescan, id locks; started by the loader, stopped first on shutdown; faults [x]
                       <Plugin>: … failed counted per plugin; /plugins , /plugin on|off|reload|info .

A3b variables          Every variable has an owner (you or a plugin); a plugin changes only its own; watches get
                       by ; owner-aware undo.

B Plugins tab          Cards with state chips, search, multi-select, plugins.entry menu, badge, empty state; a
                       page per plugin (Enabled switch, actions, adds, settings + Reset, problems / faults).
C api + guide          Owned connect / spawn / delay / every / bin ; owner set automatically on everything
                       a plugin registers; api.files ; SubTabs and Page components; path bar per sub-tab;
                        api.tab ; Documentation › Plugins is the authoring guide with a template (tested by running
                       it).


4 The plugin system (what every plugin is built on)
4.1 Folder, definition, lifecycle
Part                     What it is
Folder                    Tungsten/plugins/<Folder>/plugin.luau (required); optional lib/*.luau
                         ( P.import ), icon.png , docs.md ; settings.json written by Tungsten. Folders starting
                         with _ are skipped.
Definition               { Name, Id?, Version?, Author?, Description?, Icon?, Order?, Settings?,
                         Commands?, Functions?, Tab = { Title, Icon?, Build(page, api) }?, Docs?,
                         Requires?, Prime?, Exports?, Load?(api), Unload?(api) } , checked by
                         Api.checkDefinition . Taken ids: tungsten core console plugins documentation
                         and the prime ids (only with Prime = true ).
 P                       P.Folder , P.Path , P.Version , P.import("lib/x") , P.read(rel) , P.file(rel) .
                         The top level only builds the definition (it runs to show off plugins too); work starts in Load .




                                               Tungsten handoff · Plugins stage · page 3 of 8
Lifecycle                 read → (on at start) api made → Commands, Functions, Tab, Docs registered →
                           Load(api) in its own thread, ≤ 5 s → running (tab built when first opened) → stop:
                           Unload(api) then api:remove() (everything owned goes; settings saved). Reload =
                          stop, re-read, start. On/off take effect at the next start.
States                    off, on, failed (threw while starting or Load > 5 s), problem (doesn't compile, bad
                          definition, id taken or reserved, a Requires not met).

4.2 The api (base/api.luau)
Part                           What it gives
 api.console                    register / unregister commands ( :id.cmd , and /cmd while unique), print
                               success warn error value , run , onLine , reporter

 api.variables                 read all; set / unset its own; get ref owner list names info selection
                               watch Changed

 api.explorer                  read-only: getSelection SelectionChanged getProperties find isFrozen
                               frozenState FrozenChanged ; addFunction addInsertGroup addFilterGroup

 api.pathbar , api.tab ,       path bar for its tab / sub-tab (to change in P0); its own tab: select badge update
 api.tabs                      isOpen ; more side-bar tabs (discouraged)

 api.ui                        new on filter + tab pieces page section row field placeholder panes
                               subtabs

Registries                     api.menus prompt notify tooltip editors types classes picker docs undo
                               icons — owner/origin set automatically

Owned helpers                  api.connect(signal, fn) , spawn , delay , every(sec, fn) → Stop() , bin —
                               guarded, stopped with the plugin
Other                           api.settings (toggle number choice color action), api.files (in its folder),
                                api.plugins.get(id) (prime Exports via Requires)



5 Decisions in force
5.1 Stage 5 decisions
#           Decision
P1/P3       New plugins start off; turning on or off takes effect at the next start (a plugin turned off keeps running
            until then).
P2          Tungsten ships no plugins (the guide holds the template). Prime plugins: see Q5.
P4          Plugins may depend only on the prime plugins ( scriptviewer , objectviewer , scanner ); prime ids
            are reserved; primes load first.
P5          No fault protocol: faults are reported under the plugin's name and counted; nothing is turned off
            automatically.
P6/P7       Only program and plugin preferences persist. Reset all doesn't touch plugins (which are on lives in
            base/plugins.json ).

P8/P9       Plugins may use the whole Tungsten folder ( api.files is relative to their own). Reload is for a plugin
            that ran into a problem; no file watching.
P10         One side-bar tab per plugin; more views are sub-tabs inside it.
—           No api.data : plugins persist only api.settings .
—           Scale is the one universal setting (everything but the command bar, pill and splash); never changes on its
            own.


                                               Tungsten handoff · Plugins stage · page 4 of 8
—          Variables: flat names with an owner; a plugin can't take a name someone has; you may change any.
—          Work in small stages, stopping at clean points to confirm.

5.2 Standing decisions from earlier stages
Decision                      Detail
Clean slate                   Tungsten always starts on the Console tab, explorer open and unfrozen; only
                              preferences persist.
Default tabs                  Console, Plugins, Documentation, a divider, then plugin tabs.
Explorer                      Joined to the window, 200 px at scale 1; services can't be moved; read-only for
                              plugins (except what Q6 grants primes).
Right-click                   Object ›, Function ›, Variable ›, Save ›; plugins add to Function ›.
Path bar dropdown             Only Copy and Highlight.
Clipboard                     Explorer has its own instance clipboard ( /clipboard ); /copy is the computer's.
Freeze                        Session only; added objects held back, deleted red, moved light blue.
Command bar                   Key ' (changeable), fixed size, closes on outside click, keeps no text.
Only mouse-resizable          The explorer's tree / properties splitter (panes in plugin pages are fixed).
element


6 Conventions and Volt facts
6.1 Conventions
  Layout pixels. Lay UI out at scale 1; UIScales draw it bigger or smaller. Turn screen values (mouse,
   AbsolutePosition , AbsoluteSize ) into layout offsets with Create.layoutSize / toLocal / scaleOf ;
  popups through Overlay.place / open take on-screen anchors. Command-bar popups use the fixed
  layer ( Fixed = true ).
  Ownership. Everything registered carries an owner; UI.removeOwner cascades through every registry.
  A new registry must join that cascade and the every-registry test.
  Popups via Overlay / ContextMenu / Dropdown / CellEditor / Prompt with an Owner; dialogs sit inside
  the window; value popups end with Cancel / Accept.
  Menus are named ( Menus.define / add ); greyed when not applicable; danger red.
  Faults from anything a plugin hands Tungsten go through Reporter.ownerFault (counted by the host).
  Console output through reporters; failures as error records.
  Text plain by default; rich text only with Create.escape . Values from text via Types.parse , paths via
   Types.resolvePath (never execute text).
  Undo. Changes to the game record an Undo step; Delete is Parent = nil .
  Lifetime. Everything in a bin; re-running Tungsten must not add listeners (tested).
  Docs. Topics in documentation/topics/NN_id.md ; every feature documented when built; plugin docs
  via Docs / docs.md .
  Packaging. python3 tools/make_manifest.py Tungsten , then zip without logs/ saved/
  base/settings.json base/plugins.json plugins/<Folder>/… (until Q5 decides about primes); check
  every manifest file and import.
  Testing. Extend the offline tests; run all with tools/run_all.sh (normal and SHIFT = 58 ); write a
  failing test first when fixing a reported bug; a test file stays under Luau's 200 locals per function (wrap
  sections in do … end ).




                                            Tungsten handoff · Plugins stage · page 5 of 8
6.2 Volt facts the build relies on
 Area                Fact
 UI                   gethui() ; cloneref copies aren't == (use compareinstances ); getcustomasset(path)
                     for local images.
 Files               Paths relative to Volt's workspace. listfiles(dir) gives direct children prefixed with the
                     folder, / -joined, folders without a trailing slash. loadfile returns nil + message on a compile
                     error but throws for a missing file. writefile / makefolder create parent folders. Also
                      appendfile delfile delfolder isfile isfolder .

 Code                loadstring(code, chunkname?) ; getgenv() persists across executions; setfenv /
                     getfenv available.

 Explorer             saveinstance(root, SaveInstanceOptions.new()) ; decompile yields and errors on
                     failure; getscriptbytecode , getscriptclosure , debug.getprotos , debug.getinfo ;
                      fireclickdetector , fireproximityprompt , firetouchinterest(part, target, 0/1) .

 Hooks               hookmetamethod(game, "__namecall", newcclosure(fn)) , getnamecallmethod ,
                     checkcaller ; one shared hook kept in getgenv (re-runs don't stack). A plugin that hooks must
                     chain to the original.
 Clipboard           setclipboard only; reading the clipboard isn't possible.

For the plugins: check the relevant Volt library pages before relying on any function — each round's plan should list the
Volt functions it uses and the integrity check should name them.

7 Test kit and numbers
Offline: 20 suites, all passing in normal and SHIFT = 58 mode, 2,454 checks each: Stage 3 440 · Stage 4
175 / 237 / 261 / 363 · Components 146 · Menus 91 · UI 86 · Reporter 48 · Path bar 72 · Smoke 16 · Stage
5: scale 154, host 88, host in Tungsten 53, variables 33, list 55, page 35, api 35, tab pieces 32, guide 34.
The mock ( tests/harness.luau ) models Roblox UIScale geometry, Volt's loadfile , virtual time for
 task , and bundles plugin fixtures from tests/fixtures/plugins/ . tests/README.md lists every suite and
mock behaviour. Plugins get their own suites with fixtures; the prime plugins can be tested by installing
their folders into Tungsten/plugins/ in a suite, as the Stage 5 suites do.

8 Effort estimate
                                                                                                 Fix          Your
 Round                                                  Size
                                                                                                 rounds       testing
 P0 · loaded instance, sub-tab style, prime             800–1,500 lines incl. tests              1–2          30 min
 order
 Each plugin                                            depends on its details (given per        2–4          45–90 min
                                                        round)
Estimates only. Starting each round in a fresh conversation and reporting all of a round's failures at once keeps usage
down most.




                                              Tungsten handoff · Plugins stage · page 6 of 8
Appendix A — the original spec (ref.txt), word for word
 create a new client local script targeted to volt based off of elements of those
 resources/sourcecodes entirely in luau with the following:

 Name, style, color scheme, and goal:
 1. it will be named Tungsten
 2. darker grey background, rgb(240, 150, 60) style color
 3. hydroxide style ui but with plugins adding most functionality. not mentioning any of the
 references is essential in keeping the script self-contained
 4. serve as a base for plugins to exist in, visually contained in tabs
 5. retain as much functionality from the dark dex explorer as possible without mentioning dex or
 using it directly, due to dark dex serving as the basis for which plugins reference, features
 such as teleport and click select are unnecessary

 File structure:
 1. a file structure like that of hydroxide, but more focus on plugins.
 2. a main localscript responsible for importing all elements from locally store modules, similar
 to hydroxide
 3. the structure/catagories consists of 5 main folders: base (includes the settings, ui, and
 basic functionality) plugins (for plugins) console (all console commands and functionalities)
 documentation (for documentation) and logs (for internal logging)
 4. every file should go in its respective folder
 5. all elements and functions should be stored locally, with no downloads required
 6. easy use of setting and referencing variables

 UI/Interface:
 1. a ui derived from hydroxide, designed for 3 main functionalities: text editing, lists, and
 dropdowns.
 2. a tab bar on the left similar to hydroxide but with scroll functionality and functionality for
 plugins to add tabs
 3. a modular design with a barebones base but capability to be massively expanded
 4. rounded corners, smooth design, and animations for every relevant ui element
 5. "Tungsten" plugin, which in the later mentioned plugins tab, contains the settings for the
 base script
 6. a path bar on the top, with a dropdown button on the left and an right arrow button on the
 right. This will behave similarly to the file path bar in windows explorer
 7. ability to minimize the main ui into a small button on the top center of screen, which when
 pressed reopens the main ui.
 8. draggable main ui, but no elements inside of main ui separate from main ui.
 9. 3 included tabs: 1. console (a terminal like console, which displays a welcome message on
 startup) 2. documentation (displays a list of all topics and documentation) 3. plugins (a plugin
 manager, displaying plugins and options for plugins)
 10. ai drawn icons for every feature that needs them
 11. dropdowns are not contained by the ui and can exceed its boundaries
 12. dropdowns, lists, the path bar, and anything that has elements that exceed its boundary of
 would go off screen use scroll wheels

 Explorer:
 1. an explorer derived from dark dex on the right of the main ui with 2 aspects from dark dex: an
 instance tree on the top and a properties tab on the bottom.
 2. ability to minimize the explorer into the main ui with a small button on the bottom right of
 the explorer sidebar. button remains visible inside the boundaries of the main ui and can be
 clicked to reopen explorer.
 3. retains all dark dex right-click functions from the right click dropdown with respect to the
 catagories
 4. ports the dark dex instance tree and properties ui into a hydroxide style
 5. explorer sits on right of main ui, with 1/3 the X dimension of the main ui, but same y
 dimension.
 6. right clicking on an object in the explorer opens a dropdown that has 3 catagories, which each
 have their respective sublists which contain their functions: 1. object, 2. function, 3.
 variable.
 7. search bar at the top like found in dark dex



                                    Tungsten handoff · Plugins stage · page 7 of 8
8. instances and properties are easily referenceable by plugins
9. object category in dropdown contains the basic dark dex dropdown functions
10. function category contains plugin functions, thus plugins need to be able to add functions to
the function category
11. variable category has functions such as: set variable, unset variable, view variable, etc
12. resizeable boundary between instance tree and properties (note: only mouse-resizable element
in entire ui)

Console:
1. plugins can add commands to the console folder,
2. displays welcome message on startup
3. runs commands which can reference variables
4. broad functionality
5. prefixes set for different types of commands or outputs

Required Functionality:
1. all list must have multi-select functionality
changes i want:
	1. loading something to the path is universal across all tabs, such that if you load an instance into the path bar, all tabs are working on that instance
	2. plugin sub tabs fit the visual style of the main ui


new list for plugins in order of implementation:

	1. script/module viewer
	2. instance viewer/editor
	3. universal scanner/spy

plugin features:

	script + module viewer/editor:
		show upvalues, constants, and their respective references
		easily change constants and upvalues
		different view modes such as: table, function, list, etc..

	universal spy/scanner
		scans watched things
		universal scanning modes
		garbage collector connections scanner/spy
		scanner features mostly based off of hydroxide features
		spy features mostly based off of cobalt features
	
	object view/editor
		3d view, attribute view, view everything relevant with links to scanner or script viewer
		3d view shows n/a if it isn't an object
		view an instances attributes
		expanded properties view
		this is where you edit properties
		display info that links to the script viewer that when interacted with or clicked takes you to that info in the script viewer tab.
		gives a good overview of selected instances info overall
Shell cwd was reset to /home/claude```
