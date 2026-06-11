-- masr_npc_scare.lua
-- Fixed: Removed the crashing SetTarget line. 
-- Uses ClearEnemy() which is the safe, native way to stop the "staring."
-- Added: Friendly NPC disposition check so allies don't betray you.

timer.Create("MASR_NPCS_Scare_Logic", 0.5, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local wep = ply:GetActiveWeapon()
        
        -- Check if player holds the MASR and laser is ON
        if not IsValid(wep) or not wep.IsMASR or not wep:GetNWBool("MASR_Laser", false) then
            continue
        end

        local trace = util.TraceLine({
            start = ply:GetShootPos(),
            endpos = ply:GetShootPos() + ply:GetAimVector() * 15000,
            filter = ply
        })
        
        local laserHitPos = trace.HitPos

        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(npc) or npc:Health() <= 0 or not npc:IsNPC() then continue end

            -- NEW SAFETY CHECK: Ignore friendly NPCs (D_LI means "Like")
            -- This prevents allies from treating you as a hostile threat.
            if npc.Disposition and npc:Disposition(ply) == D_LI then continue end

            -- Distance check
            if npc:GetPos():DistToSqr(laserHitPos) > 1000000 then continue end 

            -- Facing check
            local toDot = (laserHitPos - npc:EyePos()):GetNormalized()
            if npc:GetForward():Dot(toDot) < 0.3 then continue end

            -- Line of Sight check
            local losTrace = util.TraceLine({
                start = npc:EyePos(),
                endpos = laserHitPos,
                filter = {npc, ply}
            })

            if not losTrace.HitWorld and not losTrace.HitSky then
                
                -- 1. Make them Fear you (D_FR)
                if npc.AddEntityRelationship then
                    npc:AddEntityRelationship(ply, D_FR, 99) 
                end
                
                -- 2. BREAK THE STARE (Safely)
                -- ClearEnemy() tells the NPC to drop their current threat.
                if npc.ClearEnemy then npc:ClearEnemy() end
                
                -- 3. Clear current brain state
                if npc.ClearSchedule then npc:ClearSchedule() end
                
                -- 4. Force panic (16 = SCHED_RUN_FROM_ENEMY)
                if npc.SetSchedule then
                    npc:SetSchedule(16) 
                end
            end
        end
    end
end)