if CLIENT then return end

local MIN_IMPACT_SPEED = 400 

-- Make a custom decal immune to TF2 / CS:S asset overrides
game.AddDecal("OilSplat", "decals/smscorch1")

local npcBloodTypes = {
    ["npc_headcrab"] = "YellowBlood",
    ["npc_headcrab_fast"] = "YellowBlood",
    ["npc_headcrab_black"] = "YellowBlood",
    ["npc_headcrab_poison"] = "YellowBlood",
    ["npc_antlion"] = "YellowBlood",
    ["npc_antlionguard"] = "YellowBlood",
    ["npc_antlion_worker"] = "YellowBlood",
    ["npc_barnacle"] = "YellowBlood",
    
    ["npc_cscanner"] = "OilSplat", 
    ["npc_clawscanner"] = "OilSplat",
    ["npc_manhack"] = "OilSplat",
    ["npc_rollermine"] = "OilSplat",
    ["npc_turret_floor"] = "OilSplat",
    ["npc_combine_camera"] = "OilSplat",
}

local function GetBloodDecal(ent)
    if ent.BleedDecalType then return ent.BleedDecalType end
    
    if ent:IsNPC() then
        local cls = ent:GetClass()
        if npcBloodTypes[cls] then
            ent.BleedDecalType = npcBloodTypes[cls]
        else
            local bColor = ent:GetBloodColor()
            if bColor == BLOOD_COLOR_YELLOW or bColor == BLOOD_COLOR_GREEN or bColor == BLOOD_COLOR_ANTLION then
                ent.BleedDecalType = "YellowBlood"
            elseif bColor == BLOOD_COLOR_MECH then
                ent.BleedDecalType = "OilSplat"
            else
                ent.BleedDecalType = "Blood"
            end
        end
        return ent.BleedDecalType
    end
    
    local mdl = string.lower(ent:GetModel() or "")
    if string.find(mdl, "antlion") or string.find(mdl, "headcrab") or string.find(mdl, "vortigaunt") or string.find(mdl, "barnacle") then
        ent.BleedDecalType = "YellowBlood"
    elseif string.find(mdl, "scanner") or string.find(mdl, "manhack") or string.find(mdl, "rollermine") then
        ent.BleedDecalType = "OilSplat"
    else
        ent.BleedDecalType = "Blood"
    end
    
    return ent.BleedDecalType
end

-- 1. Transfer blood type on death
hook.Add("CreateEntityRagdoll", "TransferNPCBloodType", function(owner, ragdoll)
    if IsValid(owner) and IsValid(ragdoll) then
        ragdoll.BleedDecalType = GetBloodDecal(owner)
    end
end)

-- 2. Ragdoll High-Speed Wall Impacts
hook.Add("OnEntityCreated", "RagdollImpactBleedSetup", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) and ent:GetClass() == "prop_ragdoll" then
            
            ent:AddCallback("PhysicsCollide", function(collider, colData)
                if colData.Speed > MIN_IMPACT_SPEED and colData.DeltaTime > 0.2 then
                    local pos = colData.HitPos
                    local norm = colData.HitNormal
                    local decalType = GetBloodDecal(collider)

                    util.Decal(decalType, pos + norm * 5, pos - norm * 10)
                    util.Decal(decalType, pos - norm * 10, pos + norm * 10)
                end
            end)

        end
    end)
end)

-- 3. Universal Damage & Splatter Hook
hook.Add("EntityTakeDamage", "UnifiedShotBleed", function(target, dmginfo)
    if target:IsNPC() or target:GetClass() == "prop_ragdoll" then
        
        local decalType = GetBloodDecal(target)
        local bleedsRed = (decalType == "Blood")
        
        local validDamage = dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT) or dmginfo:IsDamageType(DMG_SLASH) or dmginfo:IsDamageType(DMG_CLUB)
        
        if validDamage or bleedsRed then
            
            local hitPos = dmginfo:GetDamagePosition()
            if hitPos == vec3_origin then 
                hitPos = target:WorldSpaceCenter() 
            end

            -- EFFECT 1: Floor puddle 
            local trFloor = util.TraceLine({
                start = hitPos,
                endpos = hitPos - Vector(0, 0, 150),
                filter = target
            })
            if trFloor.Hit then
                util.Decal(decalType, trFloor.HitPos + trFloor.HitNormal, trFloor.HitPos - trFloor.HitNormal * 10)
            end

            -- EFFECT 2: The Tarantino Package (Red Blood Only)
            if bleedsRed then
                local forceDir = dmginfo:GetDamageForce():GetNormalized()
                if forceDir:Length() < 0.1 then forceDir = VectorRand() end
                
                local trWall = util.TraceLine({
                    start = hitPos,
                    endpos = hitPos + (forceDir * 120), 
                    filter = target
                })
                if trWall.Hit then
                    util.Decal(decalType, trWall.HitPos + trWall.HitNormal, trWall.HitPos - trWall.HitNormal * 10)
                end

                local ed = EffectData()
                ed:SetOrigin(hitPos)
                ed:SetColor(BLOOD_COLOR_RED)
                util.Effect("BloodImpact", ed)
            end
            
        end
    end
end)