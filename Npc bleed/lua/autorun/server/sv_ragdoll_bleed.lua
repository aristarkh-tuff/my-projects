if CLIENT then return end

local MIN_IMPACT_SPEED = 550 

local npcBloodTypes = {
    ["npc_headcrab"] = "YellowBlood",
    ["npc_headcrab_fast"] = "YellowBlood",
    ["npc_headcrab_black"] = "YellowBlood",
    ["npc_headcrab_poison"] = "YellowBlood",
    ["npc_antlion"] = "YellowBlood",
    ["npc_antlionguard"] = "YellowBlood",
    ["npc_antlion_worker"] = "YellowBlood",
    ["npc_barnacle"] = "YellowBlood",
    
    ["npc_cscanner"] = "FadingScorch", 
    ["npc_clawscanner"] = "FadingScorch",
    ["npc_manhack"] = "FadingScorch",
    ["npc_rollermine"] = "FadingScorch",
    ["npc_turret_floor"] = "FadingScorch",
    ["npc_combine_camera"] = "FadingScorch",
}

-- VIP 1: Player-controlled ragdolls (Keep the mattress clean)
local function IsPlayerControlledRagdoll(ent)
    if not IsValid(ent) or ent:IsPlayer() then return false end

    if ent.IsRagMod or ent.RagMod or ent.RagmodRagdoll or ent.isRagmod or ent.is_ragmod then return true end
    if ent:GetNWBool("RagMod", false) or ent:GetNWBool("IsRagMod", false) or ent:GetNWBool("is_ragmod", false) then return true end

    local owner = ent:GetOwner()
    if IsValid(owner) and owner:IsPlayer() then return true end

    local nwOwner = ent:GetNWEntity("RagdollOwner")
    if IsValid(nwOwner) and nwOwner:IsPlayer() then return true end
    
    local rmOwner = ent:GetNWEntity("rm_owner")
    if IsValid(rmOwner) and rmOwner:IsPlayer() then return true end

    if IsValid(ent.RagdollOwner) or IsValid(ent.Player) then return true end

    return false
end

-- VIP 2: VJ Base Sovereign Territory (Living SNPCs, custom corpses, and Xen Fauna)
local function IsVJBaseEntity(ent)
    if not IsValid(ent) then return false end

    -- DrVrej's internal entity identity flags
    if ent.IsVJBaseSNPC or ent.IsVJBaseCorpse or ent.IsVJBaseSNPC_Corpse or ent.IsVJInherited then 
        return true 
    end

    -- Catch-all for custom VJ spawners or un-flagged sub-classes
    local cls = ent:GetClass()
    if string.StartWith(cls, "npc_vj_") or string.StartWith(cls, "sent_vj_") then 
        return true 
    end

    return false
end

local function GetBloodDecal(ent)
    -- Gatekeeper: If it's a sleeping player OR a VJ Base creature, grant total immunity.
    if IsPlayerControlledRagdoll(ent) or IsVJBaseEntity(ent) then 
        return "None" 
    end

    if ent.BleedDecalType then return ent.BleedDecalType end
    
    -- CATEGORY 1: True Living Vanilla NPCs
    if ent:IsNPC() then
        local cls = ent:GetClass()
        if npcBloodTypes[cls] then
            ent.BleedDecalType = npcBloodTypes[cls]
        else
            local bColor = ent:GetBloodColor()
            if bColor == BLOOD_COLOR_YELLOW or bColor == BLOOD_COLOR_GREEN or bColor == BLOOD_COLOR_ANTLION then
                ent.BleedDecalType = "YellowBlood"
            elseif bColor == BLOOD_COLOR_MECH then
                ent.BleedDecalType = "FadingScorch"
            else
                ent.BleedDecalType = "Blood"
            end
        end
        return ent.BleedDecalType
    end
    
    local mdl = string.lower(ent:GetModel() or "")
    local isRagdoll = (ent:GetClass() == "prop_ragdoll")

    -- CATEGORY 2: Cardboard & Wood
    if string.find(mdl, "cardboard") or string.find(mdl, "box") or string.find(mdl, "crate") or string.find(mdl, "wood") then
        ent.BleedDecalType = "Impact.Wood"
        return ent.BleedDecalType
    end

    -- CATEGORY 3: Q-Menu Vanilla Ragdolls
    if isRagdoll then
        if string.find(mdl, "antlion") or string.find(mdl, "headcrab") or string.find(mdl, "vortigaunt") or string.find(mdl, "barnacle") then
            ent.BleedDecalType = "YellowBlood"
        elseif string.find(mdl, "scanner") or string.find(mdl, "manhack") or string.find(mdl, "rollermine") then
            ent.BleedDecalType = "FadingScorch"
        else
            ent.BleedDecalType = "Blood" 
        end
        return ent.BleedDecalType
    end

    -- CATEGORY 4: Inanimate junk
    ent.BleedDecalType = "None"
    return "None"
end

-- 1. Transfer blood type on death
hook.Add("CreateEntityRagdoll", "TransferNPCBloodType", function(owner, ragdoll)
    if IsValid(owner) and IsValid(ragdoll) then
        -- If a VJ NPC somehow bypassed DrVrej's custom corpse spawner and used the Garry hook:
        if owner.IsVJBaseSNPC then
            ragdoll.IsVJInherited = true
            ragdoll.BleedDecalType = "None"
            return
        end
        ragdoll.BleedDecalType = GetBloodDecal(owner)
    end
end)

-- 2. Ragdoll High-Speed Wall Impacts
hook.Add("OnEntityCreated", "RagdollImpactBleedSetup", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) and ent:GetClass() == "prop_ragdoll" then
            
            ent:AddCallback("PhysicsCollide", function(collider, colData)
                if colData.Speed > MIN_IMPACT_SPEED and colData.DeltaTime > 0.4 then
                    local pos = colData.HitPos
                    local norm = colData.HitNormal
                    local decalType = GetBloodDecal(collider)

                    if decalType ~= "None" then
                        util.Decal(decalType, pos + norm * 5, pos - norm * 10)
                        util.Decal(decalType, pos - norm * 10, pos + norm * 10)
                    end
                end 
            end)

        end
    end)
end)

-- 3. Universal 4-Tier Damage & Splatter Hook
hook.Add("EntityTakeDamage", "UnifiedShotBleed", function(target, dmginfo)
    if target:IsNPC() or target:GetClass() == "prop_ragdoll" or target:GetClass() == "prop_physics" then
        
        local decalType = GetBloodDecal(target)
        if decalType == "None" then return end -- VJ Base entities get killed right here.

        local validDamage = dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT) or dmginfo:IsDamageType(DMG_SLASH) or dmginfo:IsDamageType(DMG_CLUB)
        
        local isCrush = dmginfo:IsDamageType(DMG_CRUSH)
        local isSignificantCrush = isCrush and (dmginfo:GetDamage() >= 15)
        
        if not (validDamage or isSignificantCrush) then return end
            
        local hitPos = dmginfo:GetDamagePosition()
        if hitPos == vec3_origin then hitPos = target:WorldSpaceCenter() end

        local forceDir = dmginfo:GetDamageForce():GetNormalized()
        if forceDir:Length() < 0.1 then forceDir = VectorRand() end

        -- Puddle / Sawdust Trace
        local trFloor = util.TraceLine({
            start = hitPos,
            endpos = hitPos - Vector(0, 0, 150),
            filter = target
        })
        if trFloor.Hit then
            util.Decal(decalType, trFloor.HitPos + trFloor.HitNormal, trFloor.HitPos - trFloor.HitNormal * 10)
        end

        -- Exit Splatter Trace
        local trWall = util.TraceLine({
            start = hitPos,
            endpos = hitPos + (forceDir * 120), 
            filter = target
        })
        if trWall.Hit then
            util.Decal(decalType, trWall.HitPos + trWall.HitNormal, trWall.HitPos - trWall.HitNormal * 10)
        end

        -- Material Particle FX
        local ed = EffectData()
        ed:SetOrigin(hitPos)

        if decalType == "Blood" then
            ed:SetColor(BLOOD_COLOR_RED)
            util.Effect("BloodImpact", ed)

        elseif decalType == "YellowBlood" then
            ed:SetColor(BLOOD_COLOR_YELLOW)
            util.Effect("BloodImpact", ed)

        elseif decalType == "FadingScorch" then
            ed:SetMagnitude(2)
            ed:SetScale(1)
            ed:SetRadius(2)
            util.Effect("Sparks", ed)

        elseif decalType == "Impact.Wood" then
            ed:SetScale(0.7)
            util.Effect("WheelDust", ed)
        end
        
    end
end)
