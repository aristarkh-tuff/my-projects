--[[ 
    Weapon: Prop Possessor 
    Type: Single-file SWEP
]]--

if SERVER then
    AddCSLuaFile()
end

SWEP.PrintName = "Prop Possessor"
SWEP.Author = "AI Assistant"
SWEP.Instructions = "Left Click a prop/ragdoll to possess. (WASD push, Shift sprint, Space jump, R taunt, Ctrl leave)"
SWEP.Category = "Custom Weapons"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Slot = 3
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

-- Clear out the models
SWEP.ViewModel = "models/weapons/v_pistol.mdl" 
SWEP.WorldModel = ""

function SWEP:Initialize()
    self:SetHoldType("normal")
end

-- Completely blocks the engine from rendering any traces of the viewmodel
function SWEP:PreDrawViewModel(vm, weapon, ply)
    return true
end

if SERVER then
    -- Table of all valid entities that can be possessed
    local ValidPossessClasses = {
        ["prop_physics"] = true,
        ["prop_physics_multiplayer"] = true,
        ["prop_physics_respawnable"] = true,
        ["func_physbox"] = true,
        ["prop_ragdoll"] = true
    }
    
    -- Table of random funny sounds for taunting
    local TauntSounds = {
        "vo/npc/male01/hacks01.wav",
        "vo/npc/male01/hahaha02.wav",
        "vo/npc/male01/overhere01.wav",
        "vo/npc/male01/question26.wav",
        "npc/crow/alert2.wav",
        "ambient/creatures/town_zombie_call1.wav",
        "vo/coast/bugbait/sandy_help.wav",
        "npc/headcrab/headbite.wav"
    }

    -- Handles releasing a player from a prop safely
    local function UnpossessProp(ply, prop, destroyed, alreadyRemoving)
        if not IsValid(ply) then return end
        ply:UnSpectate()
        ply:Spawn() 
        
        if IsValid(prop) then
            local pos = prop:GetPos()
            local maxs = prop:OBBMaxs()
            ply:SetPos(pos + Vector(0, 0, maxs.z + 10))
            
            prop:SetNWEntity("PossessorPlayer", NULL)
            
            if destroyed and not alreadyRemoving then
                prop:Remove()
            elseif not destroyed and not alreadyRemoving then
                if prop.OldHealth and prop.OldHealth > 0 then
                    prop:SetHealth(prop.OldHealth)
                    if prop.OldMaxHealth then prop:SetMaxHealth(prop.OldMaxHealth) end
                else
                    prop:SetHealth(0) 
                end
            end
        end
        
        ply:SetNWEntity("PossessedProp", NULL)
        
        -- Restore original weapons and exact clip / reserve ammo states
        timer.Simple(0.1, function()
            if IsValid(ply) then
                ply:StripWeapons()
                
                for _, wepData in ipairs(ply.SavedWeapons or {}) do
                    ply:Give(wepData.class)
                end
                
                ply:RemoveAllAmmo()
                for ammoID, ammoAmt in pairs(ply.SavedAmmo or {}) do
                    ply:SetAmmo(ammoAmt, ammoID)
                end
                
                for _, wepData in ipairs(ply.SavedWeapons or {}) do
                    local wep = ply:GetWeapon(wepData.class)
                    if IsValid(wep) then
                        wep:SetClip1(wepData.clip1)
                        wep:SetClip2(wepData.clip2)
                    end
                end
            end
        end)
    end

    function SWEP:PrimaryAttack()
        self:SetNextPrimaryFire(CurTime() + 1)
        
        local ply = self:GetOwner()
        if IsValid(ply:GetNWEntity("PossessedProp")) then return end

        local tr = ply:GetEyeTrace()
        local ent = tr.Entity
        
        if IsValid(ent) and ValidPossessClasses[ent:GetClass()] and tr.HitPos:Distance(ply:GetPos()) < 2000 then
            
            -- Save current loadout
            ply.SavedWeapons = {}
            for _, wep in ipairs(ply:GetWeapons()) do
                table.insert(ply.SavedWeapons, {
                    class = wep:GetClass(),
                    clip1 = wep:Clip1(),
                    clip2 = wep:Clip2()
                })
            end
            
            ply.SavedAmmo = {}
            for ammoID, ammoAmt in pairs(ply:GetAmmo() or {}) do
                ply.SavedAmmo[ammoID] = ammoAmt
            end
            
            ply:SetNWEntity("PossessedProp", ent)
            ent:SetNWEntity("PossessorPlayer", ply)
            
            ent.OldHealth = ent:Health()
            ent.OldMaxHealth = ent:GetMaxHealth()
            ent:SetHealth(50)
            ent:SetMaxHealth(50)
            
            ply:SetNWFloat("PossessTime", CurTime())
            ply:SetNWFloat("NextTauntTime", CurTime()) -- Ready to taunt immediately
            ply:SetNWFloat("PunchOMeter", 100)
            ply.NextPropPush = 0 
            ply.NextPropJump = 0
            
            ply:StripWeapons()
            ply:Spectate(OBS_MODE_CHASE)
            ply:SpectateEntity(ent)
            
            ply:ChatPrint("Possessed! WASD to move, Space to jump, R to taunt, Ctrl to leave.")
        end
    end

    -- Hook: Intercept inputs to run movement/jumping perfectly and block exploits
    hook.Add("StartCommand", "PropPossessor_InputHandler", function(ply, cmd)
        local prop = ply:GetNWEntity("PossessedProp")
        if IsValid(prop) then
            local physCount = prop:GetPhysicsObjectCount()
            local meter = ply:GetNWFloat("PunchOMeter", 100)
            
            if physCount > 0 then
                -- 1. WASD Movement Processing
                local dir = Vector(0,0,0)
                local ang = ply:EyeAngles()
                ang.p = 0 
                local fwd = ang:Forward()
                local rgt = ang:Right()
                
                if cmd:KeyDown(IN_FORWARD) then dir = dir + fwd end
                if cmd:KeyDown(IN_BACK) then dir = dir - fwd end
                if cmd:KeyDown(IN_MOVERIGHT) then dir = dir + rgt end
                if cmd:KeyDown(IN_MOVELEFT) then dir = dir - rgt end
                
                if dir:LengthSqr() > 0 and meter > 0 then
                    ply.IsMovingProp = true
                    if (ply.NextPropPush or 0) < CurTime() then
                        dir:Normalize()
                        
                        local currentForce = 65
                        local currentCost = 5 
                        
                        if cmd:KeyDown(IN_SPEED) then
                            currentForce = 220 
                            currentCost = 10   
                        end
                        
                        for i = 0, physCount - 1 do
                            local subphys = prop:GetPhysicsObjectNum(i)
                            if IsValid(subphys) then
                                subphys:Wake()
                                subphys:ApplyForceCenter(dir * subphys:GetMass() * currentForce)
                            end
                        end
                        
                        meter = math.max(0, meter - currentCost) 
                        ply:SetNWFloat("PunchOMeter", meter)
                        ply.NextPropPush = CurTime() + 1 
                    end
                else
                    ply.IsMovingProp = false
                end
                
                -- 2. Jump Processing (With Headcrab Super Jump detection)
                if cmd:KeyDown(IN_JUMP) and (ply.NextPropJump or 0) < CurTime() and meter >= 15 then
                    local center = prop:WorldSpaceCenter()
                    local halfHeight = (prop:OBBMaxs().z - prop:OBBMins().z) / 2
                    
                    local tr = util.TraceLine({
                        start = center,
                        endpos = center - Vector(0, 0, halfHeight + 20),
                        filter = {prop, ply}
                    })
                    
                    if tr.Hit then
                        local jumpForce = 250 
                        
                        local mdl = prop:GetModel()
                        if mdl and string.find(string.lower(mdl), "headcrab") then
                            jumpForce = 650 
                        end

                        for i = 0, physCount - 1 do
                            local subphys = prop:GetPhysicsObjectNum(i)
                            if IsValid(subphys) then
                                subphys:Wake()
                                subphys:ApplyForceCenter(Vector(0, 0, subphys:GetMass() * jumpForce))
                            end
                        end
                        
                        meter = math.max(0, meter - 15) 
                        ply:SetNWFloat("PunchOMeter", meter)
                        ply.NextPropJump = CurTime() + 1
                    end
                end
            end

            -- 3. Taunt Processing (Sound, Heal, Meter Refill)
            if cmd:KeyDown(IN_RELOAD) then
                if CurTime() >= ply:GetNWFloat("NextTauntTime", 0) then
                    ply:SetNWFloat("NextTauntTime", CurTime() + 5)
                    
                    if SERVER then
                        local snd = TauntSounds[math.random(#TauntSounds)]
                        local vol = math.Rand(0.5, 1.0)
                        local pitch = math.random(70, 130)
                        
                        prop:EmitSound(snd, 75, pitch, vol)
                        
                        -- Heal based on volume: 0.5 vol = 5 HP, 1.0 vol = 10 HP
                        local healAmt = math.Round(5 + ((vol - 0.5) * 10))
                        local newHp = math.min(prop:GetMaxHealth(), prop:Health() + healAmt)
                        prop:SetHealth(newHp)
                        
                        -- Refill Punch-O-Meter fully
                        ply:SetNWFloat("PunchOMeter", 100)
                        
                        -- Optional: Add a little flash to show they got healed
                        prop:SetColor(Color(100, 255, 100))
                        timer.Simple(0.15, function() if IsValid(prop) then prop:SetColor(Color(255,255,255)) end end)
                    end
                end
            end

            -- 4. Intercept Ctrl (IN_DUCK) Leaving Logic
            if cmd:KeyDown(IN_DUCK) then
                local enterTime = ply:GetNWFloat("PossessTime", 0)
                if CurTime() - enterTime < 10 then
                    if (ply.NextExitWarn or 0) < CurTime() then
                        ply:ChatPrint(string.format("Wait %d more seconds before leaving!", math.ceil(10 - (CurTime() - enterTime))))
                        ply.NextExitWarn = CurTime() + 2
                    end
                else
                    if not ply.IsExitingProp then
                        ply.IsExitingProp = true
                        UnpossessProp(ply, prop, false, false)
                        timer.Simple(0.5, function() if IsValid(ply) then ply.IsExitingProp = false end end)
                    end
                end
            end

            -- 5. Strip action buttons from engine to stop spectator camera interference
            local buttons = cmd:GetButtons()
            buttons = bit.band(buttons, bit.bnot(IN_DUCK))
            buttons = bit.band(buttons, bit.bnot(IN_ATTACK))
            buttons = bit.band(buttons, bit.bnot(IN_ATTACK2))
            buttons = bit.band(buttons, bit.bnot(IN_USE)) -- Stripping IN_USE stops them from grabbing themselves
            buttons = bit.band(buttons, bit.bnot(IN_JUMP)) 
            buttons = bit.band(buttons, bit.bnot(IN_RELOAD)) 
            cmd:SetButtons(buttons)
        end
    end)

    -- Hook: Meter Regeneration
    hook.Add("Think", "PropPossessor_RegenLogic", function()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply:GetNWEntity("PossessedProp")) and not ply.IsMovingProp then
                local meter = ply:GetNWFloat("PunchOMeter", 100)
                meter = math.min(100, meter + FrameTime() * 15)
                ply:SetNWFloat("PunchOMeter", meter)
            end
        end
    end)

    -- Hook: Block ONLY the possessing player from pressing E (Others can pick them up now)
    hook.Add("PlayerUse", "PropPossessor_BlockUse", function(ply, ent)
        -- If the player is currently possessing a prop, they cannot interact with anything
        if IsValid(ply:GetNWEntity("PossessedProp")) then 
            return false 
        end
        -- Note: We removed the block for target entities so OTHER players can grab you with E!
    end)

    -- Hook: Handle Damage & Selective Ragdoll Physical Immunity
    hook.Add("EntityTakeDamage", "PropPossessor_Damage", function(target, dmginfo)
        local ply = target:GetNWEntity("PossessorPlayer")
        if IsValid(ply) then
            if target:GetClass() == "prop_ragdoll" then
                if dmginfo:IsDamageType(DMG_CRUSH) or dmginfo:IsDamageType(DMG_FALL) then
                    dmginfo:SetDamage(0)
                    return true 
                end
            end

            local hp = target:Health() - dmginfo:GetDamage()
            target:SetHealth(hp)
            
            target:SetColor(Color(255, 100, 100))
            timer.Simple(0.1, function() if IsValid(target) then target:SetColor(Color(255,255,255)) end end)
            
            if hp <= 0 then
                UnpossessProp(ply, target, true, false)
            end
        end
    end)
    
    -- Hook: Safe Spawning on External Deletions
    hook.Add("EntityRemoved", "PropPossessor_SafeSpawnAndDisconnect", function(ent)
        if ent:IsPlayer() then
            local prop = ent:GetNWEntity("PossessedProp")
            if IsValid(prop) then
                if prop.OldHealth then prop:SetHealth(prop.OldHealth) end
                prop:SetNWEntity("PossessorPlayer", NULL)
            end
        elseif IsValid(ent) and ValidPossessClasses[ent:GetClass()] then
            local ply = ent:GetNWEntity("PossessorPlayer")
            if IsValid(ply) then
                UnpossessProp(ply, ent, false, true)
            end
        end
    end)
end

if CLIENT then
    surface.CreateFont("PropPossessFont", {
        font = "Roboto",
        size = 22,
        weight = 800,
    })
    
    -- Draw Custom HUD for the Possessor
    hook.Add("HUDPaint", "PropPossessor_HUD", function()
        local ply = LocalPlayer()
        local prop = ply:GetNWEntity("PossessedProp")
        if not IsValid(prop) then return end
        
        local w, h = ScrW(), ScrH()
        local cx = w / 2
        
        -- Punch-O-Meter
        local meter = ply:GetNWFloat("PunchOMeter", 100)
        draw.RoundedBox(6, cx - 150, h - 100, 300, 28, Color(0, 0, 0, 180))
        draw.RoundedBox(6, cx - 148, h - 98, (meter / 100) * 296, 24, Color(255, 150, 0))
        draw.SimpleText("PUNCH-O-METER", "PropPossessFont", cx, h - 86, Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        -- Prop/Ragdoll Health Display
        local hp = prop:Health()
        draw.RoundedBox(6, cx - 150, h - 135, 300, 28, Color(0, 0, 0, 180))
        if prop:GetClass() == "prop_ragdoll" then
            draw.RoundedBox(6, cx - 148, h - 133, math.max(0, (hp / 50)) * 296, 24, Color(0, 150, 255))
            draw.SimpleText("RAGDOLL HP (PHYS IMMUNE): " .. hp, "PropPossessFont", cx, h - 121, Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.RoundedBox(6, cx - 148, h - 133, math.max(0, (hp / 50)) * 296, 24, Color(255, 50, 50))
            draw.SimpleText("PROP HEALTH: " .. hp, "PropPossessFont", cx, h - 121, Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        -- Exit Timer
        local enterTime = ply:GetNWFloat("PossessTime", 0)
        local timeLeft = math.max(0, 10 - (CurTime() - enterTime))
        
        draw.RoundedBox(6, cx - 100, h - 170, 200, 28, Color(0, 0, 0, 180))
        if timeLeft > 0 then
            draw.SimpleText(string.format("Wait %d s to leave", math.ceil(timeLeft)), "PropPossessFont", cx, h - 156, Color(255, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("Press CTRL to leave", "PropPossessFont", cx, h - 156, Color(100, 255, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        -- Taunt Cooldown Indicator
        local nextTaunt = ply:GetNWFloat("NextTauntTime", 0)
        local tauntLeft = math.max(0, nextTaunt - CurTime())
        
        draw.RoundedBox(6, cx - 100, h - 205, 200, 28, Color(0, 0, 0, 180))
        if tauntLeft > 0 then
            draw.SimpleText(string.format("Taunt Cooldown: %ds", math.ceil(tauntLeft)), "PropPossessFont", cx, h - 191, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("TAUNT READY (R)", "PropPossessFont", cx, h - 191, Color(255, 200, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end)
    
    -- Ensure player model isn't drawn while spectating
    hook.Add("ShouldDrawLocalPlayer", "PropPossessor_HidePlayer", function(ply)
        if IsValid(ply:GetNWEntity("PossessedProp")) then
            return false
        end
    end)
end
