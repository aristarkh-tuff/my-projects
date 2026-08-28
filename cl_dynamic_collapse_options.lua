if not CLIENT then return end

hook.Add("PopulateToolMenu", "DynamicCollapse_AddOptions", function()
    spawnmenu.AddToolMenuOption(
        "Utilities",
        "User",
        "DynamicCollapseOptions",
        "NPC Bleed",
        "",
        "",
        function(panel)
            panel:ClearControls()
            panel:CheckBox("Enable dynamic NPC collapse", "npc_bleed_dynamic_collapse_enabled")
        end
    )
end)
