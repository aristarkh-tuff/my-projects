if CLIENT then return end

local blacklistedModelFolders = {
    "models/props_junk/",
    "models/props_vehicles/",
}

local function IsBlacklistedModel(mdl)
    if not mdl then return false end
    mdl = string.lower(mdl)
    for _, prefix in ipairs(blacklistedModelFolders) do
        if string.StartWith(mdl, prefix) then
            return true
        end
    end
    return false
end

-- ⚙️ CONFIGURATION SUITE 
local MIN_IMPACT_SPEED   = 550  -- Physics impact speed required for a basic corpse splash
local BLEED_INTERVAL     = 0.5  -- Standard delay between blood drips (Higher = less blood frequency)
local ALIVE_BLEED_CHANCE = 60   -- % chance a living NPC drips/stains on a tick (0-100)
local CORPSE_BLEED_CHANCE= 40   -- % chance a dead ragdoll drips/stains on a tick (0-100)
local LIMB_REDUCTION     = 0.3  -- Multiply bleed chance by this if shot in arm/leg (70% less blood)

-- 🦴 BONE SNAP CONFIGURATION
local BONE_SNAP_SPEED    = 650  -- Speed threshold for a ragdoll collision to snap a limb
local HIGH_POWER_DAMAGE  = 40   -- Damage threshold to snap a limb with a gun (e.g., Revolver/Magnum)

-- 💥 EXPLOSION SHRAPNEL CONFIGURATION
local EXPLOSION_MIN_WOUNDS = 3  -- Minimum random puncture points on an explosion death ragdoll
local EXPLOSION_MAX_WOUNDS = 6  -- Maximum random puncture points on an explosion death ragdoll

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

local function IsVJBaseEntity(ent)
    if not IsValid(ent) then return false end
    if ent.IsVJBaseSNPC or ent.IsVJBaseCorpse or ent.IsVJBaseSNPC_Corpse or ent.IsVJInherited then return true end
    local cls = ent:GetClass()
    if string.StartWith(cls, "npc_vj_") or string.StartWith(cls, "sent_vj_") then return true end
    return false
end

local function GetBloodDecal(ent)
    if IsPlayerControlledRagdoll(ent) or IsVJBaseEntity(ent) then return "None" end
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
                ent.BleedDecalType = "FadingScorch"
            else
                ent.BleedDecalType = "Blood"
            end
        end
        return ent.BleedDecalType
    end
    
    if IsBlacklistedModel(ent:GetModel()) then
        ent.BleedDecalType = "None"
        return "None"
    end

    local mdl = string.lower(ent:GetModel() or "")
    if ent:GetClass() == "prop_ragdoll" then
        if string.find(mdl, "antlion") or string.find(mdl, "headcrab") or string.find(mdl, "vortigaunt") or string.find(mdl, "barnacle") then
            ent.BleedDecalType = "YellowBlood"
        elseif string.find(mdl, "scanner") or string.find(mdl, "manhack") or string.find(mdl, "rollermine") then
            ent.BleedDecalType = "FadingScorch"
        else
            ent.BleedDecalType = "Blood" 
        end
        return ent.BleedDecalType
    end

    if string.find(mdl, "wood") or string.find(mdl, "box") or string.find(mdl, "crate") or string.find(mdl, "wagon") or string.find(mdl, "pallet") or string.find(mdl, "cardboard") then
        ent.BleedDecalType = "Impact.Wood"
        return ent.BleedDecalType
    end
    if string.find(mdl, "metal") or string.find(mdl, "cart") or string.find(mdl, "vehicle") or string.find(mdl, "engine") or string.find(mdl, "car") then
        ent.BleedDecalType = "Impact.Metal"
        return ent.BleedDecalType
    end

    ent.BleedDecalType = "None"
    return "None"
end

local function LoosenLimb(ent, physObj)
    if not IsValid(ent) or not IsValid(physObj) then return end
    physObj:SetDamping(0, 0.02)
    physObj:AddAngleVelocity(VectorRand() * 400)
    physObj:ApplyForceCenter(VectorRand() * 250)
end

hook.Add("ScaleNPCDamage", "BleedOutTrackHitgroups", function(npc, hitgroup, dmginfo)
    if IsValid(npc) then
        npc.CustomLastHitGroup = hitgroup
    end
end)

local function TriggerArterialLeak(ent, duration, decalType, boneName, localPos, isLimb, customInterval)
    if not IsValid(ent) then return end
    if decalType == "None" or decalType == "Impact.Wood" or decalType == "Impact.Metal" then return end

    ent.LeakWounds = ent.LeakWounds or {}
    ent.NextWoundID = (ent.NextWoundID or 0) + 1
    
    local woundID = ent.NextWoundID
    local timerName = "ArterialWound_" .. ent:EntIndex() .. "_" .. woundID
    
    local actualDuration = isLimb and (duration * 0.5) or duration
    local endTime = CurTime() + actualDuration
    local activeInterval = customInterval or BLEED_INTERVAL

    timer.Create(timerName, activeInterval, 0, function()
        if not IsValid(ent) then
            timer.Remove(timerName)
            return
        end

        if CurTime() > endTime then
            timer.Remove(timerName)
            return
        end

        local isNPC = ent:IsNPC()

        if isNPC and ent:Health() > 0 then
            local bleedDmg = DamageInfo()
            bleedDmg:SetDamage(1)
            bleedDmg:SetDamageType(DMG_GENERIC) 
            bleedDmg:SetAttacker(game.GetWorld())
            bleedDmg:SetInflictor(game.GetWorld())
            ent:TakeDamageInfo(bleedDmg)
        end

        local baseChance = isNPC and ALIVE_BLEED_CHANCE or CORPSE_BLEED_CHANCE
        if isLimb then baseChance = baseChance * LIMB_REDUCTION end
        
        if math.random(1, 100) <= baseChance then
            local boneID = ent:LookupBone(boneName) or 0
            local bonePos, boneAng = ent:GetBonePosition(boneID)
            
            if not bonePos then 
                bonePos = ent:GetPos() 
                boneAng = ent:GetAngles() 
            end

            local currentWoundPos = LocalToWorld(localPos, angle_zero, bonePos, boneAng)

            local ed = EffectData()
            ed:SetOrigin(currentWoundPos)
            if decalType == "Blood" then
                ed:SetColor(BLOOD_COLOR_RED)
                util.Effect("BloodImpact", ed)
            elseif decalType == "YellowBlood" then
                ed:SetColor(BLOOD_COLOR_YELLOW)
                util.Effect("BloodImpact", ed)
            elseif decalType == "FadingScorch" then
                ed:SetMagnitude(1)
                ed:SetScale(0.4)
                util.Effect("Sparks", ed)
            end

            local tr = util.TraceLine({
                start = currentWoundPos,
                endpos = currentWoundPos - Vector(0, 0, 175),
                filter = ent
            })
            if tr.Hit then
                util.Decal(decalType, tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal * 10)
            end

            local stainStart = currentWoundPos + VectorRand() * 2 + Vector(0, 0, 4)
            local stainEnd = currentWoundPos - Vector(0, 0, 16)
            util.Decal(decalType, stainStart, stainEnd, nil) 
        end
    end)

    table.insert(ent.LeakWounds, {
        endTime = endTime,
        boneName = boneName,
        localPos = localPos,
        isLimb = isLimb,
        interval = activeInterval
    })
end

hook.Add("CreateEntityRagdoll", "TransferNPCBloodType", function(owner, ragdoll)
    if IsValid(owner) and IsValid(ragdoll) then
        if owner.IsVJBaseSNPC then
            ragdoll.IsVJInherited = true
            ragdoll.BleedDecalType = "None"
            return
        end
        
        local decalType = GetBloodDecal(owner)
        ragdoll.BleedDecalType = decalType
        
        if owner.LeakWounds then
            for _, wound in ipairs(owner.LeakWounds) do
                if wound.endTime > CurTime() then
                    local remTime = wound.endTime - CurTime()
                    TriggerArterialLeak(ragdoll, remTime, decalType, wound.boneName, wound.localPos, wound.isLimb, wound.interval)
                end
            end
        end

        if owner.DiedFromExplosion and decalType ~= "None" then
            local boneCount = ragdoll:GetBoneCount()
            if boneCount > 0 then
                local totalWounds = math.random(EXPLOSION_MIN_WOUNDS, EXPLOSION_MAX_WOUNDS)
                
                local cls = owner:GetClass()
                local mdl = string.lower(owner:GetModel() or "")
                local interval = BLEED_INTERVAL
                if string.find(cls, "headcrab") or string.find(mdl, "headcrab") then
                    interval = BLEED_INTERVAL * 0.4 
                end

                for i = 1, totalWounds do
                    local randomBoneID = math.random(0, boneCount - 1)
                    local boneName = ragdoll:GetBoneName(randomBoneID)
                    
                    if boneName and boneName ~= "__invalid" then
                        local isLimb = false
                        local bNameLower = string.lower(boneName)
                        if string.find(bNameLower, "arm") or string.find(bNameLower, "leg") or string.find(bNameLower, "hand") or string.find(bNameLower, "calf") or string.find(bNameLower, "thigh") or string.find(bNameLower, "foot") then
                            isLimb = true
                        end
                        
                        local localWoundPos = VectorRand() * math.Rand(2, 6)
                        local leakDuration = math.Rand(8.0, 22.0)
                        
                        TriggerArterialLeak(ragdoll, leakDuration, decalType, boneName, localWoundPos, isLimb, interval)
                    end
                end
            end
        end

        if owner.BrokenLimbs then
            ragdoll.BrokenLimbs = table.Copy(owner.BrokenLimbs)
            for i = 0, ragdoll:GetBoneCount() - 1 do
                local bName = ragdoll:GetBoneName(i)
                if owner.BrokenLimbs[bName] then
                    local physBone = ragdoll:TranslateBoneToPhysBone(i)
                    if physBone >= 0 then
                        local phys = ragdoll:GetPhysicsObjectNum(physBone)
                        LoosenLimb(ragdoll, phys)
                    end
                end
            end
        end
    end
end)

hook.Add("OnEntityCreated", "RagdollImpactBleedSetup", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) and ent:GetClass() == "prop_ragdoll" then
            ent:AddCallback("PhysicsCollide", function(collider, colData)
                
                if colData.Speed > BONE_SNAP_SPEED and colData.DeltaTime > 0.3 then
                    local hitPhys = colData.PhysicsObject
                    if IsValid(hitPhys) then
                        local physIndex = -1
                        for i = 0, ent:GetPhysicsObjectCount() - 1 do
                            if ent:GetPhysicsObjectNum(i) == hitPhys then
                                physIndex = i
                                break
                            end
                        end

                        if physIndex >= 0 then
                            for i = 0, ent:GetBoneCount() - 1 do
                                if ent:TranslateBoneToPhysBone(i) == physIndex then
                                    local bName = ent:GetBoneName(i) or ""
                                    local bNameLower = string.lower(bName)
                                    if string.find(bNameLower, "arm") or string.find(bNameLower, "leg") or string.find(bNameLower, "hand") or string.find(bNameLower, "calf") or string.find(bNameLower, "thigh") or string.find(bNameLower, "foot") then
                                        ent.BrokenLimbs = ent.BrokenLimbs or {}
                                        if not ent.BrokenLimbs[bName] then
                                            ent.BrokenLimbs[bName] = true
                                            LoosenLimb(ent, hitPhys)
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                if colData.Speed > MIN_IMPACT_SPEED and colData.DeltaTime > 0.4 then
                    local pos = colData.HitPos
                    local norm = colData.HitNormal
                    local decalType = GetBloodDecal(collider)
                    if decalType ~= "None" and decalType ~= "Impact.Wood" and decalType ~= "Impact.Metal" then
                        util.Decal(decalType, pos + norm * 5, pos - norm * 10)
                    end
                end 
            end)
        end
    end)
end)

hook.Add("EntityTakeDamage", "UnifiedShotBleed", function(target, dmginfo)
    if not IsValid(target) then return end
    
    local cls = target:GetClass()
    
    -- 🛑 REINFORCED PROP FILTER
    -- Explicitly detects if the entity is any variation of a world prop object.
    local isProp = (cls == "prop_physics" or cls == "prop_physics_multiplayer" or cls == "simple_physics_prop" or cls == "prop_dynamic" or cls == "prop_physics_override")

    -- Only allow calculations if it's a living NPC, a biological ragdoll corpse, or a structural physics prop
    if target:IsNPC() or cls == "prop_ragdoll" or isProp then
        
        if dmginfo:IsDamageType(DMG_GENERIC) and dmginfo:GetAttacker() == game.GetWorld() then return end

        local decalType = GetBloodDecal(target)
        local hitPos = dmginfo:GetDamagePosition()
        if hitPos == vec3_origin or not hitPos then hitPos = target:WorldSpaceCenter() end
        
        local forceDir = dmginfo:GetDamageForce():GetNormalized()
        if forceDir:Length() < 0.1 then forceDir = VectorRand() end
        local attacker = dmginfo:GetAttacker()

        -- Initial Surface Splatter: Handles generic impacts safely 
        local selfStart = hitPos - (forceDir * 15)
        local selfEnd = hitPos + (forceDir * 15)
        
        -- If it is a prop, override default biological fallout and treat its impact cleanly
        if isProp then
            if decalType == "Blood" or decalType == "YellowBlood" then decalType = "None" end
            if decalType ~= "None" then
                util.Decal(decalType, selfStart, selfEnd, IsValid(attacker) and attacker or nil)
            end
            return -- ❌ Hard Exit: Absolute separation, preventing props from entering the blood leak timers below.
        end

        -- Double Check Safety Catch for biological flows
        if decalType == "None" or decalType == "Impact.Wood" or decalType == "Impact.Metal" then return end

        local damageAmount = dmginfo:GetDamage()

        if target:IsNPC() and dmginfo:IsDamageType(DMG_BLAST) then
            if target:Health() <= damageAmount then
                target.DiedFromExplosion = true
            end
        end

        if cls == "npc_zombie" and target:IsNPC() then
            local headBone = target:LookupBone("ValveBiped.Bip01_Head1")
            if headBone then
                local bonePos = target:GetBonePosition(headBone)
                if bonePos then
                    if hitPos:DistToSqr(bonePos) < 225 then 
                        -- Headshot: yellow blood (headcrab on the head)
                        decalType = "YellowBlood"
                    else
                        -- Body shot: red blood (zombie flesh)
                        decalType = "Blood"
                    end
                end
            end
        end

        local validDamage = dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT) or dmginfo:IsDamageType(DMG_SLASH) or dmginfo:IsDamageType(DMG_CLUB)
        local isCrush = dmginfo:IsDamageType(DMG_CRUSH)
        local isSignificantCrush = isCrush and (damageAmount >= 25)
        
        if not (validDamage or isSignificantCrush) then return end

        local closestBone = 0
        local closestDist = 999999
        for i = 0, target:GetBoneCount() - 1 do
            local bPos, bAng = target:GetBonePosition(i)
            if bPos then
                local dist = bPos:DistToSqr(hitPos)
                if dist < closestDist then
                    closestDist = dist
                    closestBone = i
                end
            end
        end
        local boneName = target:GetBoneName(closestBone) or "ValveBiped.Bip01_Pelvis"

        local isLimb = false
        local bNameLower = string.lower(boneName)
        if string.find(bNameLower, "arm") or string.find(bNameLower, "leg") or string.find(bNameLower, "hand") or string.find(bNameLower, "calf") or string.find(bNameLower, "thigh") or string.find(bNameLower, "foot") then
            isLimb = true
        end

        local isHighPowerImpact = (validDamage and damageAmount >= HIGH_POWER_DAMAGE) or (isCrush and damageAmount >= 30)
        
        if isLimb and isHighPowerImpact then
            target.BrokenLimbs = target.BrokenLimbs or {}
            if not target.BrokenLimbs[boneName] then
                target.BrokenLimbs[boneName] = true
                
                if cls == "prop_ragdoll" then
                    local physBone = target:TranslateBoneToPhysBone(closestBone)
                    if physBone >= 0 then
                        local phys = target:GetPhysicsObjectNum(physBone)
                        LoosenLimb(target, phys)
                    end
                end
            end
        end

        local shouldLeak = false
        local mdl = string.lower(target:GetModel() or "")

        if target:IsNPC() then
            local maxHP = target:GetMaxHealth()
            local currentHP = target:Health() - damageAmount
            if damageAmount >= 15 or (maxHP > 0 and (currentHP / maxHP) <= 0.6) then
                shouldLeak = true
            end
        elseif cls == "prop_ragdoll" then
            if damageAmount >= 10 then
                shouldLeak = true
            end
        end

        if shouldLeak then
            local leakDuration = math.Clamp(damageAmount * 0.35, 4.0, 30.0) 

            local interval = BLEED_INTERVAL
            if string.find(cls, "headcrab") or string.find(mdl, "headcrab") then
                interval = BLEED_INTERVAL * 0.4 
                leakDuration = math.Clamp(damageAmount * 0.25, 2.0, 10.0)
            end

            local bonePos, boneAng = target:GetBonePosition(closestBone)
            if not bonePos then bonePos = target:GetPos() boneAng = target:GetAngles() end
            
            local localWoundPos = WorldToLocal(hitPos, angle_zero, bonePos, boneAng)
            TriggerArterialLeak(target, leakDuration, decalType, boneName, localWoundPos, isLimb, interval)
        end

        if target:IsNPC() then
            if decalType == "YellowBlood" then
                target:SetBloodColor(BLOOD_COLOR_YELLOW)
            elseif decalType == "Blood" then
                target:SetBloodColor(BLOOD_COLOR_RED)
            else
                target:SetBloodColor(DONT_BLEED) 
            end
        end

        local trFloor = util.TraceLine({start = hitPos, endpos = hitPos - Vector(0, 0, 150), filter = target})
        if trFloor.Hit then util.Decal(decalType, trFloor.HitPos + trFloor.HitNormal, trFloor.HitPos - trFloor.HitNormal * 10) end

        local ed = EffectData()
        ed:SetOrigin(hitPos)
        if decalType == "Blood" then
            ed:SetColor(BLOOD_COLOR_RED)
            util.Effect("BloodImpact", ed)
        elseif decalType == "YellowBlood" then
            ed:SetColor(BLOOD_COLOR_YELLOW)
            util.Effect("BloodImpact", ed)
        end
    end
end)
