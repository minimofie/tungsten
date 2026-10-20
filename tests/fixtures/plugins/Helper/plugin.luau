-- test fixture: uses every owned helper and owner-setting wrapper (Round C)
return {
	Id = "helper",
	Name = "Helper",
	Load = function(api)
		local g = getgenv()
		local T = g.Tungsten.Context
		g.HelperApi = api
		g.HelperSignal = T.import("base/signal").new()
		g.HelperHeard, g.HelperTicks, g.HelperDelayed, g.HelperSpawned, g.HelperSel = 0, 0, false, false, 0

		-- listeners and threads
		api.connect(g.HelperSignal, function(value)
			if value == "boom" then
				error("connection broke")
			end
			g.HelperHeard += 1
		end)
		api.spawn(function()
			task.wait(0.5)
			g.HelperSpawned = true
		end)
		api.delay(60, function()
			g.HelperDelayed = true
		end)
		g.HelperEvery = api.every(1, function()
			g.HelperTicks += 1
		end)
		api.bin:Add(function()
			g.HelperBinCleaned = true
		end)
		api.explorer.SelectionChanged:Connect(function()
			g.HelperSel += 1
		end)

		-- everything that carries an owner
		g.HelperButton = api.ui.new("Button", { Text = "Helper button" })
		api.ui.on("Button", "Clicked", function() g.HelperClicked = true end)
		api.ui.filter("List", "Items", function(items) return items end)
		api.menus.define("helper.menu", { Title = "Helper", Sections = { { Id = "main" } } })
		api.menus.addMany("helper.menu", { { Id = "a", Text = "A", Callback = function() end }, { Id = "b", Text = "B", Callback = function() end } })
		api.menus.add("console.output", { Id = "helperline", Text = "Helper line", Callback = function() end })
		api.menus.addRowKind("helperrow", { Build = function() end })
		api.notify.registerKind("helperkind", { Icon = "class_remote", Color = "Info" })
		api.prompt.registerFieldKind("helperfield", { Build = function() return { Get = function() end, Set = function() end } end })
		api.editors.register("HelperType", { Inline = "text" })
		api.types.register("HelperType", {
			Is = function(v) return v == "helper" end,
			Parse = function(text) return true, text end,
			EditText = function(v) return v end,
			Display = function(v) return v end,
			Default = function() return "helper" end,
		})
		api.classes.add("HelperClass", "vehicle")
		api.picker.registerKind("helperpick", { Options = function() return {} end })
		api.explorer.addInsertGroup({ Id = "helperinsert", Title = "Helper", Classes = { "Part" } })
		api.explorer.addFilterGroup("helperfilter", { Text = "Helper", Test = function() return false end })
		api.docs.add({ Id = "helper", Title = "Helper", Source = "# Helper" })
		api.docs.addSection("commands", { Id = "helper", Title = "Helper", Source = "x" })
		api.docs.addDirective("helper-live", { Source = function() return "live" end })
		api.icons.register("helper.icon", "Tungsten/base/data/icons/save.png")
	end,
}
