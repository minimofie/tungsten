-- test fixture: registers something in every registry Tungsten has, so the
-- tests can check that turning it off leaves nothing behind.
local P = ...
return {
	Id = "everything",
	Name = "Everything",
	Version = "1.0",
	Settings = { { Id = "n", Kind = "number", Text = "N", Default = 1 } },
	Commands = { { Name = "everycmd", Run = function(ctx) ctx.success("every") end } },
	Functions = { { Id = "everyfn", Text = "Every", Run = function() end } },
	Tab = { Title = "Everything", Build = function(page, api) end },
	Docs = { Title = "Everything", Source = "# Everything\n\nAll of it." },
	Load = function(api)
		local T = getgenv().Tungsten.Context
		local id = api.Id
		-- through the api
		api.variables.set("everyvar", 1)
		api.menus.define("everything.menu", { Title = "Everything", Sections = { { Id = "main" } } })
		api.menus.add("everything.menu", { Id = "everyentry", Text = "Every entry", Callback = function() end })
		api.menus.add("console.output", { Id = "everyoutput", Text = "Every output entry", Callback = function() end })
		api.tabs.add({ Id = "everything2", Title = "Everything 2", Build = function() end })
		api.docs.add({ Id = "everything-more", Source = "# More" })
		api.undo.record({ Text = "every step", Undo = function() end })
		api.icons.register("everything.icon", "Tungsten/base/data/icons/save.png")
		api.ui.on("Button", "Clicked", function() end, { Owner = id })
		api.ui.filter("List", "Items", function(items) return items end, { Owner = id })
		-- the other registries (a plugin can reach every module)
		T.import("base/types").registerType("EveryType", {
			Owner = id,
			Is = function(v) return v == "every" end,
			Parse = function(text) return true, text end,
			EditText = function(v) return v end,
			Display = function(v) return v end,
			Default = function() return "every" end,
		})
		T.import("base/data/classes").add("EveryClass", "vehicle", { Owner = id })
		T.import("base/explorer/editors").register("EveryType", { Inline = "text", Owner = id })
		T.import("base/explorer/filter").addGroup("everygroup", { Text = "Every", Test = function() return false end, Owner = id })
		T.import("base/explorer/insert").addGroup({ Id = "everyinsert", Title = "Every", Classes = { "Part" } }, id)
		T.import("base/ui/components/prompt").registerFieldKind("everyfield", { Owner = id, Build = function() return { Get = function() end, Set = function() end } end })
		T.import("base/ui/components/notify").registerKind("everykind", { Icon = "class_remote", Color = "Info", Owner = id })
		T.import("base/ui/components/contextmenu").addKind("everyrow", { Owner = id, Build = function() end })
		T.import("base/ui/components/typepicker").registerKind("everypick", { Owner = id, Options = function() return {} end })
		T.Docs.addDirective("every-live", { Source = function() return "live" end, Owner = id })
		T.Docs.addSection("commands", { Id = "every", Title = "Every", Source = "x", Owner = id })
	end,
}
