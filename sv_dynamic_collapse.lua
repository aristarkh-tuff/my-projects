-- sv_dynamic_collapse.lua
if CLIENT then return end

-- ⚙️ CONFIGURATION
local RAGDOLL_DAMAGE_SCALE      = 0.3    -- Multiplier for incoming damage to ragdolls
local RAGDOLL_HEALTH_MULTIPLIER = 2.5    -- Ragdolls receive 2.5x base health

local COLLAPSE_LEG_DAMAGE       = 8      -- Minimum leg damage to trigger collapse
local HEAVY_LEG_DAMAGE          = 15     -- Leg damage threshold to break legs permanently (accumulates over multiple shots)
local COLLAPSE_FALL_DAMAGE      = 10     -- Minimum fall damage to trigger collapse
local COLLAPSE_SHOTGUN_DAMAGE   = 10     -- Minimum shotgun/buckshot damage to trigger collapse

local MID_AIR_FALL_SPEED        = 400    -- Downward Z velocity to trigger fall ragdoll
local TRIP_SPEED_THRESHOLD      = 110    -- Minimum movement velocity to trigger a prop trip
local TRIP_CHANCE               = 40     -- Percentage chance to trip over a prop

local SLOPE_ANGLE_THRESHOLD     = 28     -- Base angle in degrees (e.g. 30 deg roof) to trigger slipping
local HEADCRAB_DROWN_DAMAGE     = 6      -- Damage taken per second while headcrab thrashes in water

local MIN_RECOVERY_TIME         = 3.0    -- Minimum seconds knocked out (legs NOT broken)
local MAX_RECOVERY_TIME         = 10.0   -- Maximum seconds knocked out (legs NOT broken)

local ZOMBINE_GRENADE_CHANCE    = 40     -- Percentage chance for Zombine grenade on collapse
local BLEND_DURATION            = 1.4    -- Seconds to transition back upright

-- 🛡️ SAFE WATER LEVEL HELPER (Prevents NULL Entity errors)
local function SafeWaterLevel(ent)
    if not IsValid(ent) then return 0 end
    local ok, lvl = pcall(function() return ent:WaterLevel() end)
    return (ok and lvl) or 0
end

local function IsCombineMachinery(npc)
    if not IsValid(npc) then return false end
    local cls = string.lower(npc:GetClass() or "")
    return string.find(cls, "manhack") 
        or string.find(cls, "scanner") 
        or string.find(cls, "turret") 
        or string.find(cls, "rollermine") 
        or string.find(cls, "gunship") 
        or string.find(cls, "dropship") 
        or string.find(cls, "strider") 
        or string.find(cls, "helicopter")
end

local function IsMetrocop(npc)
    if not IsValid(npc) then return false end
    return string.find(string.lower(npc:GetClass() or ""), "metro") ~= nil
end

local function IsOverwatch(npc)
    if not IsValid(npc) then return false end
    local cls = string.lower(npc:GetClass() or "")
    return string.find(cls, "combine") ~= nil and not string.find(cls, "metro")
end

local function IsWeaponCapableNPC(npc)
    if not IsValid(npc) then return false end
    local cls = string.lower(npc:GetClass() or "")
    return string.find(cls, "combine") 
        or string.find(cls, "metro") 
        or string.find(cls, "citizen") 
        or string.find(cls, "alyx") 
        or string.find(cls, "barney")
end

local function IsZombieNPC(ent)
    if not IsValid(ent) then return false end
    local cls = string.lower(ent:GetClass() or "")
    return string.find(cls, "zombie") ~= nil or string.find(cls, "zombine") ~= nil
end

local function IsHeadcrabNPC(ent)
    if not IsValid(ent) then return false end
    local cls = string.lower(ent:GetClass() or "")
    return string.find(cls, "headcrab") ~= nil
end

-- Helper to get maximum health for an NPC
local function GetNPCMaxHealth(npc)
    if not IsValid(npc) then return 100 end
    if not npc.MaxHealthLimit or npc.MaxHealthLimit <= 0 then
        local maxHp = npc:GetMaxHealth()
        npc.MaxHealthLimit = (maxHp > 0) and maxHp or math.max(npc:Health(), 100)
    end
    return npc.MaxHealthLimit
end

-- Forward declaration of stand-up transition
local TransitionToStand

-- 🏖️ SHOREFINDER: Scans 360 degrees for nearest dry land
local function FindNearestShorePos(pos)
    local bestPos = nil
    local bestDistSqr = 2500 * 2500
    local numDirections = 12

    for i = 1, numDirections do
        local angleRad = (i / numDirections) * math.pi * 2
        local testDir = Vector(math.cos(angleRad), math.sin(angleRad), 0.15):GetNormalized()

        local tr = util.TraceLine({
            start = pos + Vector(0, 0, 20),
            endpos = pos + (testDir * 1800),
            mask = MASK_SOLID
        })

        if tr.Hit and not tr.AllSolid then
            local waterCheck = util.PointContents(tr.HitPos + Vector(0, 0, 15))
            if bit.band(waterCheck, CONTENTS_WATER) == 0 then
                local distSqr = pos:DistToSqr(tr.HitPos)
                if distSqr < bestDistSqr then
                    bestDistSqr = distSqr
                    bestPos = tr.HitPos
                end
            end
        end
    end

    if not bestPos then
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() and SafeWaterLevel(ply) < 2 then
                local dSqr = pos:DistToSqr(ply:GetPos())
                if dSqr < bestDistSqr then
                    bestDistSqr = dSqr
                    bestPos = ply:GetPos()
                end
            end
        end
    end

    return bestPos
end

-- 🩺 MEDICAL PICKUP & HEALING SYSTEM
local function ApplyHealthItem(npc, item)
    if not IsValid(npc) or not IsValid(item) then return end

    local cls = item:GetClass()
    local isVial = (cls == "item_healthvial")
    local isKit  = (cls == "item_healthkit")

    if not (isVial or isKit) then return end

    local currentHP = npc:Health()
    local brokenLegs = npc.BrokenLegsCount or (npc.LegsBroken and 1 or 0)
    local healAmount = 0
    local soundName = isVial and "items/smallmedkit1.wav" or "items/medshot4.wav"

    if isVial then
        healAmount = 10
        if brokenLegs > 0 then
            brokenLegs = math.max(0, brokenLegs - 1)
        end
    elseif isKit then
        healAmount = 25
        if brokenLegs > 0 then
            healAmount = healAmount + 10
            brokenLegs = 0
        end
    end

    npc.BrokenLegsCount = brokenLegs
    if brokenLegs <= 0 then
        npc.LegsBroken = false
        npc.LeftLegBroken = false
        npc.RightLegBroken = false
        npc.LeftLegDamage = 0
        npc.RightLegDamage = 0
    end

    local newHP = currentHP + healAmount
    npc:SetHealth(newHP)

    if IsValid(npc.LinkedRagdoll) then
        npc.LinkedRagdoll.RagdollHealth = newHP * RAGDOLL_HEALTH_MULTIPLIER
    end

    item:EmitSound(soundName, 75, 100)
    item:Remove()

    if not npc.LegsBroken and npc.IsCollapsing and IsValid(npc.LinkedRagdoll) then
        if not IsHeadcrabNPC(npc) then
            TransitionToStand(npc, npc.LinkedRagdoll)
        end
    end
end

local function IsPlayerAwareOrNearby(npc)
    if not IsValid(npc) then return false end
    local npcPos = npc:GetPos()
    local npcCenter = npc:WorldSpaceCenter()

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local distSqr = npcPos:DistToSqr(ply:GetPos())

            if distSqr <= (500 * 500) then return true end

            if distSqr <= (1200 * 1200) then
                local aimDir = ply:GetAimVector()
                local dirToNPC = (npcCenter - ply:GetEyePos()):GetNormalized()

                if aimDir:Dot(dirToNPC) > 0.5 then
                    local tr = util.TraceLine({
                        start = ply:GetEyePos(),
                        endpos = npcCenter,
                        filter = {ply, npc}
                    })

                    if not tr.Hit then return true end
                end
            end
        end
    end

    return false
end

local function TriggerMetrocopSurrender(npc)
    if not IsValid(npc) or npc.IsSurrendering or npc.IsCollapsing or npc.IsSpared then return end
    
    npc.IsSurrendering = true
    npc:ClearSchedule()
    npc:StopMoving()
    npc:SetEnemy(nil)

    local seq = npc:LookupSequence("yield01")
    if seq == -1 then seq = npc:LookupSequence("handsup") end
    if seq == -1 then seq = npc:LookupSequence("gesture_agree") end

    if seq and seq > -1 then
        npc:ResetSequence(seq)
        npc:SetCycle(0)
        npc:SetPlaybackRate(1)
    end

    npc:SetSchedule(SCHED_WAIT_FOR_SCRIPT)
    npc:EmitSound("npc/metropolice/vo/holdit.wav", 75, 100)
end

local function MakeMetrocopPanic(npc, attacker)
    if not IsValid(npc) or not npc.IsSurrendering then return end
    
    npc.IsSurrendering = false
    npc.IsPanicked = true
    npc.IsSpared = true

    if IsValid(attacker) then
        npc:SetEnemy(attacker)
    end

    npc:SetSchedule(SCHED_RUN_FROM_ENEMY)
    npc:EmitSound("npc/metropolice/vo/shit.wav", 75, 100)
end

local function GetNPCPainSound(npc)
    if not IsValid(npc) then return "NPC_Citizen.Pain" end
    local cls = string.lower(npc:GetClass())
    if string.find(cls, "combine") then return "NPC_Combine.Pain" end
    if string.find(cls, "metro") then return "NPC_MetroPolice.Pain" end
    if string.find(cls, "zombie") then return "NPC_Zombie.Pain" end
    if string.find(cls, "alyx") then return "NPC_Alyx.Pain" end
    if string.find(cls, "barney") then return "NPC_Barney.Pain" end
    if string.find(cls, "antlion") then return "NPC_Antlion.Pain" end
    if string.find(cls, "headcrab") then return "NPC_Headcrab.Pain" end
    if string.find(cls, "vortigaunt") then return "NPC_Vortigaunt.Pain" end
    return "NPC_Citizen.Pain"
end

local function GetNPCDeathSound(npc)
    if not IsValid(npc) then return "NPC_Citizen.Die" end
    local cls = string.lower(npc:GetClass())
    if string.find(cls, "combine") then return "NPC_Combine.Die" end
    if string.find(cls, "metro") then return "NPC_MetroPolice.Die" end
    if string.find(cls, "zombie") then return "NPC_Zombie.Die" end
    if string.find(cls, "alyx") then return "NPC_Alyx.Die" end
    if string.find(cls, "barney") then return "NPC_Barney.Die" end
    if string.find(cls, "antlion") then return "NPC_Antlion.Death" end
    if string.find(cls, "headcrab") then return "NPC_Headcrab.Die" end
    if string.find(cls, "vortigaunt") then return "NPC_Vortigaunt.Die" end
    return "NPC_Citizen.Die"
end

local function FreezeNPC_AI(npc)
    if not IsValid(npc) then return end
    if npc.ClearSchedule then npc:ClearSchedule() end
    if npc.ClearGoal then npc:ClearGoal() end
    if npc.StopMoving then npc:StopMoving() end
    if npc.SetEnemy then npc:SetEnemy(nil) end
    if npc.SetNPCState then npc:SetNPCState(NPC_STATE_NONE) end
end

local function CleanResetBones(npc)
    if not IsValid(npc) then return end
    for i = 0, npc:GetBoneCount() - 1 do
        npc:ManipulateBoneAngles(i, angle_zero)
        npc:ManipulateBonePosition(i, vector_origin)
    end
end

local function GetZombieSwipeDamage(npc)
    if not IsValid(npc) then return 15 end
    local cls = string.lower(npc:GetClass())
    if string.find(cls, "fast") then return 8 end
    if string.find(cls, "poison") then return 25 end
    return 15
end

local function IsZombine(npc)
    if not IsValid(npc) then return false end
    local cls = string.lower(npc:GetClass())
    local mdl = string.lower(npc:GetModel() or "")
    return string.find(cls, "zombine") ~= nil or string.find(mdl, "zombie_soldier") ~= nil
end

-- 🩹 INJURY HOLDING SYSTEM
local function ApplyInjuryHoldConstraint(ragdoll, hitgroup)
    if not IsValid(ragdoll) then return end
    if math.random(1, 100) > 65 then return end

    local targetBoneName = nil
    local handBoneName = "ValveBiped.Bip01_R_Hand"

    if hitgroup == HITGROUP_LEFTLEG or hitgroup == HITGROUP_RIGHTLEG then
        targetBoneName = (hitgroup == HITGROUP_LEFTLEG) and "ValveBiped.Bip01_L_Knee" or "ValveBiped.Bip01_R_Knee"
        handBoneName = (hitgroup == HITGROUP_LEFTLEG) and "ValveBiped.Bip01_L_Hand" or "ValveBiped.Bip01_R_Hand"
    elseif hitgroup == HITGROUP_GENERIC or hitgroup == HITGROUP_CHEST or hitgroup == HITGROUP_STOMACH then
        targetBoneName = "ValveBiped.Bip01_Spine"
    elseif hitgroup == HITGROUP_LEFTARM or hitgroup == HITGROUP_RIGHTARM then
        targetBoneName = (hitgroup == HITGROUP_LEFTARM) and "ValveBiped.Bip01_L_Elbow" or "ValveBiped.Bip01_R_Elbow"
        handBoneName = (hitgroup == HITGROUP_LEFTARM) and "ValveBiped.Bip01_R_Hand" or "ValveBiped.Bip01_L_Hand"
    end

    if not targetBoneName then return end

    local targetBone = ragdoll:LookupBone(targetBoneName)
    local handBone = ragdoll:LookupBone(handBoneName)

    if targetBone and handBone then
        local targetPhysNum = ragdoll:TranslateBoneToPhysBone(targetBone)
        local handPhysNum = ragdoll:TranslateBoneToPhysBone(handBone)

        local targetPhys = ragdoll:GetPhysicsObjectNum(targetPhysNum)
        local handPhys = ragdoll:GetPhysicsObjectNum(handPhysNum)

        if IsValid(targetPhys) and IsValid(handPhys) then
            constraint.Elastic(ragdoll, ragdoll, handPhysNum, targetPhysNum, Vector(0,0,0), Vector(0,0,0), 1200, 200, 0, "phys_bone_follow", 0, false)
        end
    end
end

-- 💣 ZOMBINE RAGDOLL SUICIDE GRENADE SYSTEM
local function TryTriggerZombineGrenade(npc, ragdoll)
    if not IsZombine(npc) or not IsValid(ragdoll) or ragdoll.HasGrenade then return end
    if math.random(1, 100) > ZOMBINE_GRENADE_CHANCE then return end

    ragdoll.HasGrenade = true

    timer.Simple(0.5, function()
        if not IsValid(ragdoll) or not IsValid(npc) or npc:Health() <= 0 then return end

        local handBone = ragdoll:LookupBone("ValveBiped.Bip01_R_Hand")
        if not handBone then return end

        local handPos, handAng = ragdoll:GetBonePosition(handBone)
        
        local grenade = ents.Create("prop_physics")
        grenade:SetModel("models/weapons/w_grenade.mdl")
        grenade:SetPos(handPos)
        grenade:SetAngles(handAng)
        grenade:SetCollisionGroup(COLLISION_GROUP_WORLD)
        grenade:Spawn()
        grenade:FollowBone(ragdoll, handBone)

        ragdoll:EmitSound("npc/zombie_soldier/zombine_charge01.wav", 85, 100)

        local armPhys = ragdoll:GetPhysicsObjectNum(ragdoll:TranslateBoneToPhysBone(handBone))
        if IsValid(armPhys) then
            armPhys:ApplyForceCenter(Vector(0, 0, 300))
        end

        local beeps = 0
        local beepTimer = "ZombineBeep_" .. ragdoll:EntIndex()
        
        timer.Create(beepTimer, 0.35, 7, function()
            if not IsValid(ragdoll) then
                if IsValid(grenade) then grenade:Remove() end
                timer.Remove(beepTimer)
                return
            end

            ragdoll:EmitSound("npc/zombie_soldier/g_beep.wav", 80, 100 + (beeps * 4))
            beeps = beeps + 1

            if beeps >= 7 then
                local expPos = IsValid(grenade) and grenade:GetPos() or ragdoll:GetPos()

                local ed = EffectData()
                ed:SetOrigin(expPos)
                util.Effect("Explosion", ed)
                ragdoll:EmitSound("ambient/explosions/explode_4.wav", 95, 100)

                util.BlastDamage(IsValid(grenade) and grenade or game.GetWorld(), IsValid(npc) and npc or game.GetWorld(), expPos, 220, 110)

                for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                    local phys = ragdoll:GetPhysicsObjectNum(i)
                    if IsValid(phys) then
                        local forceVec = (phys:GetPos() - expPos):GetNormalized() * math.random(4000, 8000)
                        phys:ApplyForceCenter(forceVec + Vector(0, 0, 2000))
                    end
                end

                ragdoll:Ignite(8)

                if IsValid(grenade) then grenade:Remove() end
                if IsValid(npc) then
                    ragdoll:EmitSound(GetNPCDeathSound(npc), 85, 100)
                    hook.Run("OnNPCKilled", npc, game.GetWorld(), game.GetWorld())
                    npc:Remove()
                end
            end
        end)
    end)
end

-- 🧟 ZOMBIE RAGDOLL DRAGGING & SWIPING (Tuned tick rate & impulse force)
local function StartZombieCrawlLogic(npc, ragdoll)
    if not IsValid(ragdoll) then return end
    local crawlTimer = "ZombieCrawl_" .. ragdoll:EntIndex()
    
    -- Ticks every 0.2s instead of 0.8s for smooth, persistent dragging
    timer.Create(crawlTimer, 0.2, 0, function()
        if not IsValid(ragdoll) or not IsValid(npc) or npc:Health() <= 0 then
            timer.Remove(crawlTimer)
            return
        end

        if SafeWaterLevel(ragdoll) == 3 then return end

        local ragPos = ragdoll:GetPos()

        for _, item in ipairs(ents.FindInSphere(ragPos, 60)) do
            if IsValid(item) and (item:GetClass() == "item_healthvial" or item:GetClass() == "item_healthkit") then
                ApplyHealthItem(npc, item)
                break
            end
        end

        local closestTarget = nil
        local closestDist = 900 * 900

        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                local distSqr = ragPos:DistToSqr(ply:GetPos())
                if distSqr < closestDist then
                    closestDist = distSqr
                    closestTarget = ply
                end
            end
        end

        if IsValid(closestTarget) then
            local targetPos = closestTarget:GetPos()
            local dir = (targetPos - ragPos):GetNormalized()
            dir.z = 0.05

            -- Focus force on the pelvis phys object (center of mass)
            local pelvisBone = ragdoll:LookupBone("ValveBiped.Bip01_Pelvis") or ragdoll:LookupBone("ValveBiped.Bip01_Spine2")
            local pelvisPhysNum = pelvisBone and ragdoll:TranslateBoneToPhysBone(pelvisBone) or 0
            local phys = ragdoll:GetPhysicsObjectNum(pelvisPhysNum)

            if IsValid(phys) then
                local currentVel = phys:GetVelocity()
                if currentVel:LengthSqr() < (400 * 400) then
                    -- Strong forward impulse + vertical pop to break floor friction
                    phys:ApplyForceCenter(dir * 9500 + Vector(0, 0, 1400))
                end
            end

            -- Sound throttling so audio doesn't spam every 0.2 seconds
            if CurTime() > (ragdoll.NextDragSound or 0) then
                ragdoll.NextDragSound = CurTime() + 0.75
                ragdoll:EmitSound("physics/flesh/flesh_scrape_rough_ground" .. math.random(1, 2) .. ".wav", 65, math.random(90, 105))
                if math.random(1, 3) == 1 then
                    ragdoll:EmitSound("npc/zombie/zombie_voice_idle" .. math.random(1, 3) .. ".wav", 75, math.random(85, 100))
                end
            end

            local dist = ragPos:Distance(targetPos)
            if dist <= 65 and CurTime() > (ragdoll.NextSwipeTime or 0) then
                ragdoll.NextSwipeTime = CurTime() + 1.6

                local armName = (math.random(1, 2) == 1) and "ValveBiped.Bip01_R_Hand" or "ValveBiped.Bip01_L_Hand"
                local armBone = ragdoll:LookupBone(armName)

                if armBone then
                    local armPhysNum = ragdoll:TranslateBoneToPhysBone(armBone)
                    local armPhys = ragdoll:GetPhysicsObjectNum(armPhysNum)

                    if IsValid(armPhys) then
                        armPhys:ApplyForceCenter(-dir * 1200 + Vector(0, 0, 600))
                        ragdoll:EmitSound("npc/zombie/zo_attack2.wav", 75, math.random(90, 110))

                        timer.Simple(0.15, function()
                            if not IsValid(ragdoll) or not IsValid(closestTarget) then return end
                            
                            if IsValid(armPhys) then
                                armPhys:ApplyForceCenter(dir * 3000 + Vector(0, 0, 800))
                            end

                            if ragdoll:GetPos():Distance(closestTarget:GetPos()) <= 75 then
                                ragdoll:EmitSound("npc/zombie/claw_strike" .. math.random(1, 3) .. ".wav", 80, math.random(95, 105))

                                local dmginfo = DamageInfo()
                                dmginfo:SetDamage(GetZombieSwipeDamage(npc))
                                dmginfo:SetDamageType(DMG_SLASH)
                                dmginfo:SetAttacker(npc)
                                dmginfo:SetInflictor(ragdoll)
                                dmginfo:SetDamageForce(dir * 300 + Vector(0, 0, 100))
                                closestTarget:TakeDamageInfo(dmginfo)
                            else
                                ragdoll:EmitSound("npc/zombie/claw_miss" .. math.random(1, 2) .. ".wav", 70, math.random(95, 105))
                            end
                        end)
                    end
                end
            end
        end
    end)
end

-- 🏃 GENERIC HUMANOID/NPC CRAWL LOGIC
local function StartGenericNPCCrawlLogic(npc, ragdoll)
    if not IsValid(ragdoll) then return end
    local crawlTimer = "NPCCrawl_" .. ragdoll:EntIndex()

    -- Ticks every 0.25s for better responsiveness
    timer.Create(crawlTimer, 0.25, 0, function()
        if not IsValid(ragdoll) or not IsValid(npc) or npc:Health() <= 0 then
            timer.Remove(crawlTimer)
            return
        end

        if SafeWaterLevel(ragdoll) == 3 then return end

        local ragPos = ragdoll:GetPos()

        for _, item in ipairs(ents.FindInSphere(ragPos, 60)) do
            if IsValid(item) and (item:GetClass() == "item_healthvial" or item:GetClass() == "item_healthkit") then
                ApplyHealthItem(npc, item)
                break
            end
        end

        local moveTargetPos = nil

        if npc.LegsBroken or npc:Health() < GetNPCMaxHealth(npc) then
            local nearestHealth = nil
            local nearestHealthDist = 600 * 600

            for _, ent in ipairs(ents.FindInSphere(ragPos, 600)) do
                if IsValid(ent) and (ent:GetClass() == "item_healthvial" or ent:GetClass() == "item_healthkit") then
                    local dSqr = ragPos:DistToSqr(ent:GetPos())
                    if dSqr < nearestHealthDist then
                        nearestHealthDist = dSqr
                        nearestHealth = ent
                    end
                end
            end

            if IsValid(nearestHealth) then
                moveTargetPos = nearestHealth:GetPos()
            end
        end

        if not moveTargetPos and IsValid(npc.DroppedWeapon) and not IsValid(npc.DroppedWeapon:GetOwner()) then
            moveTargetPos = npc.DroppedWeapon:GetPos()
        end

        if not moveTargetPos then
            local closestPly = nil
            local closestDist = 1200 * 1200

            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and ply:Alive() then
                    local distSqr = ragPos:DistToSqr(ply:GetPos())
                    if distSqr < closestDist then
                        closestDist = distSqr
                        closestPly = ply
                    end
                end
            end

            if IsValid(closestPly) then
                local awayDir = (ragPos - closestPly:GetPos()):GetNormalized()
                moveTargetPos = ragPos + (awayDir * 300)
            end
        end

        if moveTargetPos then
            local dir = (moveTargetPos - ragPos):GetNormalized()
            dir.z = 0.05

            local pelvisBone = ragdoll:LookupBone("ValveBiped.Bip01_Pelvis") or ragdoll:LookupBone("ValveBiped.Bip01_Spine2")
            local pelvisPhysNum = pelvisBone and ragdoll:TranslateBoneToPhysBone(pelvisBone) or 0
            local phys = ragdoll:GetPhysicsObjectNum(pelvisPhysNum)

            if IsValid(phys) then
                local currentVel = phys:GetVelocity()
                if currentVel:LengthSqr() < (350 * 350) then
                    phys:ApplyForceCenter(dir * 8500 + Vector(0, 0, 1200))
                end
            end

            if CurTime() > (ragdoll.NextDragSound or 0) then
                ragdoll.NextDragSound = CurTime() + 0.8
                ragdoll:EmitSound("physics/flesh/flesh_scrape_rough_ground" .. math.random(1, 2) .. ".wav", 60, math.random(95, 105))
                if math.random(1, 3) == 1 then
                    ragdoll:EmitSound(GetNPCPainSound(npc), 75, math.random(90, 105))
                end
            end
        end
    end)
end

-- 🧍 STAND UP TRANSITION (Fixes Floor Noclipping)
TransitionToStand = function(npc, ragdoll)
    if not IsValid(npc) then return end
    if npc.LegsBroken then return end

    timer.Remove("NPC_CollapseTrack_" .. npc:EntIndex())

    if not IsValid(ragdoll) then
        CleanResetBones(npc)
        npc:SetNoDraw(false)
        npc:SetSolid(SOLID_BBOX)
        npc:SetMoveType(MOVETYPE_STEP)
        if npc.StoredCapabilities and npc.CapabilitiesClear then
            npc:CapabilitiesClear()
            npc:CapabilitiesAdd(npc.StoredCapabilities)
        end
        if npc.SetNPCState then npc:SetNPCState(NPC_STATE_ALERT) end
        npc.IsCollapsing = false
        return
    end

    CleanResetBones(npc)

    local phys = ragdoll:GetPhysicsObjectNum(0)
    local pelvisBone = ragdoll:LookupBone("ValveBiped.Bip01_Pelvis")
    
    local ragPos, ragAng
    if pelvisBone then
        ragPos, ragAng = ragdoll:GetBonePosition(pelvisBone)
    elseif IsValid(phys) then
        ragPos = phys:GetPos()
        ragAng = phys:GetAngles()
    else
        ragPos = ragdoll:GetPos()
        ragAng = ragdoll:GetAngles()
    end

    local mins, maxs = npc:OBBMins(), npc:OBBMaxs()
    local tr = util.TraceHull({
        start = ragPos + Vector(0, 0, 35),
        endpos = ragPos - Vector(0, 0, 40),
        mins = mins,
        maxs = maxs,
        filter = {ragdoll, npc}
    })
    
    local standPos = tr.Hit and (tr.HitPos + Vector(0, 0, 6)) or (ragPos + Vector(0, 0, 10))

    local startAngle = ragAng or ragdoll:GetAngles()
    local targetAngle = Angle(0, startAngle.y, 0)

    npc:SetPos(standPos)
    npc:SetAngles(startAngle)

    npc:SetNoDraw(false)
    npc:SetSolid(SOLID_BBOX)
    npc:DropToFloor()
    
    ragdoll:Remove()

    local startTime = CurTime()
    local timerName = "NPC_GetUpBlend_" .. npc:EntIndex()

    timer.Create(timerName, 0.02, 0, function()
        if not IsValid(npc) then
            timer.Remove(timerName)
            return
        end

        local fraction = (CurTime() - startTime) / BLEND_DURATION

        if fraction >= 1 then
            npc:SetAngles(targetAngle)
            npc:SetMoveType(MOVETYPE_STEP)
            
            if npc.StoredCapabilities and npc.CapabilitiesClear then
                npc:CapabilitiesClear()
                npc:CapabilitiesAdd(npc.StoredCapabilities)
            end
            if npc.SetNPCState then npc:SetNPCState(NPC_STATE_ALERT) end
            npc.IsCollapsing = false
            
            if IsValid(npc.DroppedWeapon) and not IsValid(npc.DroppedWeapon:GetOwner()) then
                if npc:GetPos():Distance(npc.DroppedWeapon:GetPos()) <= 120 then
                    npc:PickupWeapon(npc.DroppedWeapon)
                    npc.DroppedWeapon = nil
                end
            end

            timer.Remove(timerName)
        else
            local smoothProgress = math.ease.InOutCubic(fraction)
            local currentAngle   = LerpAngle(smoothProgress, startAngle, targetAngle)
            
            npc:SetAngles(currentAngle)
        end
    end)
end

local function TriggerDynamicCollapse(npc, force, hitgroup)
    if not IsValid(npc) or npc.IsCollapsing or IsCombineMachinery(npc) then return end
    npc.IsCollapsing = true
    npc.IsSurrendering = false

    if IsWeaponCapableNPC(npc) then
        local activeWep = npc:GetActiveWeapon()
        if IsValid(activeWep) then
            npc:DropWeapon(activeWep)
            if IsValid(activeWep) then
                npc.DroppedWeapon = activeWep
                local phys = activeWep:GetPhysicsObject()
                if IsValid(phys) then
                    phys:ApplyForceCenter((force or Vector(0,0,0)) * 0.5 + npc:GetVelocity())
                end
            end
        end
    end

    npc:EmitSound(GetNPCPainSound(npc))

    local ragdoll = ents.Create("prop_ragdoll")
    ragdoll:SetModel(npc:GetModel())
    ragdoll:SetPos(npc:GetPos())
    ragdoll:SetAngles(npc:GetAngles())
    ragdoll:Spawn()

    ragdoll:SetSkin(npc:GetSkin())
    for i = 0, npc:GetNumBodyGroups() - 1 do
        ragdoll:SetBodygroup(i, npc:GetBodygroup(i))
    end

    ragdoll.RagdollHealth = npc:Health() * RAGDOLL_HEALTH_MULTIPLIER
    ragdoll.LinkedNPC = npc
    npc.LinkedRagdoll = ragdoll

    local appliedVelocity = npc:GetVelocity() + (force * 0.02)
    if appliedVelocity:LengthSqr() > (300 * 300) then
        appliedVelocity = appliedVelocity:GetNormalized() * 300
    end

    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local boneID = ragdoll:TranslatePhysBoneToBone(i)
            if boneID then
                local pos, ang = npc:GetBonePosition(boneID)
                if pos and ang then
                    phys:SetPos(pos)
                    phys:SetAngles(ang)
                end
            end
            phys:SetVelocity(appliedVelocity)
        end
    end

    if hitgroup then
        ApplyInjuryHoldConstraint(ragdoll, hitgroup)
    end

    if npc.CapabilitiesGet then
        npc.StoredCapabilities = npc:CapabilitiesGet()
        npc:CapabilitiesClear()
    end
    FreezeNPC_AI(npc)
    
    npc:SetNoDraw(true)
    npc:SetSolid(SOLID_NONE)
    npc:SetMoveType(MOVETYPE_NONE)

    local trackTimer = "NPC_CollapseTrack_" .. npc:EntIndex()
    timer.Create(trackTimer, 0.05, 0, function()
        if not IsValid(npc) or not IsValid(ragdoll) then
            timer.Remove(trackTimer)
            return
        end
        
        local pelvis = ragdoll:LookupBone("ValveBiped.Bip01_Pelvis")
        local ragPos = pelvis and ragdoll:GetBonePosition(pelvis) or ragdoll:GetPos()
        npc:SetPos(ragPos)
        
        for i = 0, npc:GetNumBodyGroups() - 1 do
            ragdoll:SetBodygroup(i, npc:GetBodygroup(i))
        end

        if ragdoll:IsOnFire() and not npc:IsOnFire() then
            npc:Ignite(5)
        elseif npc:IsOnFire() and not ragdoll:IsOnFire() then
            ragdoll:Ignite(5)
        end

        FreezeNPC_AI(npc)
    end)

    local isZombie = IsZombieNPC(npc)
    
    if isZombie then
        TryTriggerZombineGrenade(npc, ragdoll)
    end

    if npc.LegsBroken then
        if isZombie then
            StartZombieCrawlLogic(npc, ragdoll)
        else
            StartGenericNPCCrawlLogic(npc, ragdoll)
        end
    else
        if not IsHeadcrabNPC(npc) then
            local randomDelay = math.Rand(MIN_RECOVERY_TIME, MAX_RECOVERY_TIME)
            timer.Simple(randomDelay, function()
                if IsValid(npc) and npc:Health() > 0 and IsValid(ragdoll) and SafeWaterLevel(ragdoll) < 3 then
                    TransitionToStand(npc, ragdoll)
                end
            end)
        end
    end
end

-- 🏊 SUBMERGED RAGDOLL REALISTIC SWIM LOGIC
timer.Create("DynamicCollapse_SubmergedRagdollSwimLogic", 0.1, 0, function()
    for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
        if IsValid(ragdoll) and IsValid(ragdoll.LinkedNPC) and not IsHeadcrabNPC(ragdoll.LinkedNPC) then
            local npc = ragdoll.LinkedNPC
            local waterLevel = SafeWaterLevel(ragdoll)

            if waterLevel == 3 then
                ragdoll.WasSubmerged = true
                local ragPos = ragdoll:GetPos()

                if not ragdoll.SwimTargetShore or CurTime() > (ragdoll.NextShoreScanTime or 0) then
                    ragdoll.NextShoreScanTime = CurTime() + 1.2
                    ragdoll.SwimTargetShore = FindNearestShorePos(ragPos)
                end

                local targetPos = ragdoll.SwimTargetShore
                local swimDir = targetPos and (targetPos - ragPos):GetNormalized() or Vector(0, 0, 1)

                for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                    local phys = ragdoll:GetPhysicsObjectNum(i)
                    if IsValid(phys) and phys:GetVelocity():LengthSqr() < (250 * 250) then
                        phys:ApplyForceCenter(Vector(0, 0, 120))
                    end
                end

                local spineBone = ragdoll:LookupBone("ValveBiped.Bip01_Spine2") or ragdoll:LookupBone("ValveBiped.Bip01_Pelvis")
                local spinePhysNum = spineBone and ragdoll:TranslateBoneToPhysBone(spineBone) or 0
                local mainPhys = ragdoll:GetPhysicsObjectNum(spinePhysNum)

                if IsValid(mainPhys) and mainPhys:GetVelocity():LengthSqr() < (250 * 250) then
                    mainPhys:ApplyForceCenter(swimDir * 4000 + Vector(0, 0, 600))
                end

                local swimPhase = math.sin(CurTime() * 8)

                local rLeg = ragdoll:LookupBone("ValveBiped.Bip01_R_Foot")
                local lLeg = ragdoll:LookupBone("ValveBiped.Bip01_L_Foot")
                local rArm = ragdoll:LookupBone("ValveBiped.Bip01_R_Hand")
                local lArm = ragdoll:LookupBone("ValveBiped.Bip01_L_Hand")

                if rLeg then
                    local phys = ragdoll:GetPhysicsObjectNum(ragdoll:TranslateBoneToPhysBone(rLeg))
                    if IsValid(phys) then phys:ApplyForceCenter((-swimDir + Vector(0, 0, swimPhase * 1.2)):GetNormalized() * 1200) end
                end
                if lLeg then
                    local phys = ragdoll:GetPhysicsObjectNum(ragdoll:TranslateBoneToPhysBone(lLeg))
                    if IsValid(phys) then phys:ApplyForceCenter((-swimDir - Vector(0, 0, swimPhase * 1.2)):GetNormalized() * 1200) end
                end
                if rArm then
                    local phys = ragdoll:GetPhysicsObjectNum(ragdoll:TranslateBoneToPhysBone(rArm))
                    if IsValid(phys) then phys:ApplyForceCenter((swimDir + Vector(0, 0, -swimPhase)):GetNormalized() * 800) end
                end
                if lArm then
                    local phys = ragdoll:GetPhysicsObjectNum(ragdoll:TranslateBoneToPhysBone(lArm))
                    if IsValid(phys) then phys:ApplyForceCenter((swimDir + Vector(0, 0, swimPhase)):GetNormalized() * 800) end
                end

                if CurTime() > (ragdoll.NextSwimSound or 0) then
                    ragdoll.NextSwimSound = CurTime() + 0.85
                    ragdoll:EmitSound("physics/surfaces/underwater_impact_bullet" .. math.random(1, 3) .. ".wav", 65, math.random(90, 110))
                end
            else
                if ragdoll.WasSubmerged and waterLevel < 2 then
                    ragdoll.WasSubmerged = false
                    ragdoll.SwimTargetShore = nil

                    if not npc.LegsBroken then
                        timer.Simple(0.8, function()
                            if IsValid(ragdoll) and IsValid(npc) and npc:Health() > 0 and SafeWaterLevel(ragdoll) < 2 then
                                TransitionToStand(npc, ragdoll)
                            end
                        end)
                    else
                        if IsZombieNPC(npc) then
                            StartZombieCrawlLogic(npc, ragdoll)
                        else
                            StartGenericNPCCrawlLogic(npc, ragdoll)
                        end
                    end
                end
            end
        end
    end
end)

-- 🏃 WEAPON & HEALTH PICKUP, METROCOP SURRENDER & OVERWATCH RETREAT
timer.Create("DynamicCollapse_UnarmedAndWeaponPickupLogic", 0.6, 0, function()
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and npc:IsNPC() and not npc.IsCollapsing then
            local npcPos = npc:GetPos()
            local maxHp = GetNPCMaxHealth(npc)

            if npc.LegsBroken or npc:Health() < maxHp then
                local nearestHealth = nil
                local nearestHealthDist = 500 * 500

                for _, ent in ipairs(ents.FindInSphere(npcPos, 500)) do
                    if IsValid(ent) and (ent:GetClass() == "item_healthvial" or ent:GetClass() == "item_healthkit") then
                        local dSqr = npcPos:DistToSqr(ent:GetPos())
                        if dSqr < nearestHealthDist then
                            nearestHealthDist = dSqr
                            nearestHealth = ent
                        end
                    end
                end

                if IsValid(nearestHealth) then
                    if npcPos:Distance(nearestHealth:GetPos()) <= 65 then
                        ApplyHealthItem(npc, nearestHealth)
                    else
                        npc:SetLastPosition(nearestHealth:GetPos())
                        npc:SetSchedule(SCHED_FORCED_GO)
                    end
                end
            end

            if IsWeaponCapableNPC(npc) then
                local activeWep = npc:GetActiveWeapon()

                if IsOverwatch(npc) and (npc:Health() <= 30 or not IsValid(activeWep)) then
                    local closestPly = nil
                    local closestDist = 1200 * 1200
                    for _, ply in ipairs(player.GetAll()) do
                        if IsValid(ply) and ply:Alive() then
                            local dSqr = npc:GetPos():DistToSqr(ply:GetPos())
                            if dSqr < closestDist then
                                closestDist = dSqr
                                closestPly = ply
                            end
                        end
                    end

                    if IsValid(closestPly) then
                        npc:SetEnemy(closestPly)
                        npc:SetSchedule(SCHED_RUN_FROM_ENEMY)
                    end
                elseif not IsValid(activeWep) then
                    if npc.IsSurrendering then
                        npc:StopMoving()
                        npc:SetEnemy(nil)
                    elseif npc.IsSpared then
                        local closestPly = nil
                        local closestDist = 2000 * 2000
                        for _, ply in ipairs(player.GetAll()) do
                            if IsValid(ply) and ply:Alive() then
                                local dSqr = npc:GetPos():DistToSqr(ply:GetPos())
                                if dSqr < closestDist then
                                    closestDist = dSqr
                                    closestPly = ply
                                end
                            end
                        end
                        if IsValid(closestPly) then
                            npc:SetEnemy(closestPly)
                            npc:SetSchedule(SCHED_RUN_FROM_ENEMY)
                        end
                    else
                        local nearestWep = nil
                        local nearestDist = 500 * 500

                        for _, ent in ipairs(ents.FindInSphere(npcPos, 500)) do
                            if IsValid(ent) and ent:IsWeapon() and not IsValid(ent:GetOwner()) then
                                local distSqr = npcPos:DistToSqr(ent:GetPos())
                                if distSqr < nearestDist then
                                    nearestDist = distSqr
                                    nearestWep = ent
                                end
                            end
                        end

                        if IsValid(nearestWep) then
                            if npcPos:Distance(nearestWep:GetPos()) <= 70 then
                                npc:PickupWeapon(nearestWep)
                                if npc.DroppedWeapon == nearestWep then
                                    npc.DroppedWeapon = nil
                                end
                            else
                                npc:SetLastPosition(nearestWep:GetPos())
                                if IsPlayerAwareOrNearby(npc) then
                                    npc:SetSchedule(SCHED_FORCED_GO_RUN)
                                else
                                    npc:SetSchedule(SCHED_FORCED_GO)
                                end
                            end
                        else
                            if IsMetrocop(npc) then
                                if not npc.IsPanicked then
                                    TriggerMetrocopSurrender(npc)
                                end
                            else
                                local closestEnemy = nil
                                local closestEnemyDist = 1200 * 1200

                                for _, ply in ipairs(player.GetAll()) do
                                    if IsValid(ply) and ply:Alive() then
                                        local distSqr = npcPos:DistToSqr(ply:GetPos())
                                        if distSqr < closestEnemyDist then
                                            closestEnemyDist = distSqr
                                            closestEnemy = ply
                                        end
                                    end
                                end

                                if IsValid(closestEnemy) then
                                    npc:SetEnemy(closestEnemy)
                                    npc:SetSchedule(SCHED_RUN_FROM_ENEMY)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- 🩸 OVERHEAL SLOW DECAY TIMER
timer.Create("DynamicCollapse_OverhealDecay", 1.0, 0, function()
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and npc:IsNPC() and npc:Health() > 0 then
            local maxHp = GetNPCMaxHealth(npc)
            if npc:Health() > maxHp then
                local decayedHP = npc:Health() - 1
                npc:SetHealth(decayedHP)
                if IsValid(npc.LinkedRagdoll) then
                    npc.LinkedRagdoll.RagdollHealth = decayedHP * RAGDOLL_HEALTH_MULTIPLIER
                end
            end
        end
    end
end)

-- 🤝 Sparing Surrendering Metrocops
hook.Add("PlayerUse", "DynamicCollapse_SpareMetrocop", function(ply, ent)
    if IsValid(ent) and ent:IsNPC() and ent.IsSurrendering and IsMetrocop(ent) then
        ent.IsSurrendering = false
        ent.IsSpared = true

        ent:EmitSound("npc/metropolice/vo/clearedforthetimebeing.wav", 75, 100)
        ent:SetEnemy(ply)
        ent:SetSchedule(SCHED_RUN_FROM_ENEMY)
    end
end)

-- 💥 Nearby Shot Detector for Metrocops
hook.Add("EntityFireBullets", "DynamicCollapse_ScareSurrenderingMetrocops", function(ent, bullet)
    if not IsValid(ent) then return end
    local src = bullet.Src
    local dir = bullet.Dir
    local dist = bullet.Distance or 2000

    for _, npc in ipairs(ents.FindByClass("npc_metropolice")) do
        if IsValid(npc) and npc.IsSurrendering then
            local npcPos = npc:WorldSpaceCenter()
            if src:DistToSqr(npcPos) <= (400 * 400) or util.DistanceToLine(src, src + dir * dist, npcPos) < 180 then
                MakeMetrocopPanic(npc, ent)
            end
        end
    end
end)

-- 🌌 REAL-TIME THINK HOOK
hook.Add("Think", "DynamicCollapse_MainThinkLogic", function()
    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and ent:IsNPC() then
            local waterLevel = SafeWaterLevel(ent)

            if waterLevel == 3 and not ent.IsCollapsing and not IsCombineMachinery(ent) then
                TriggerDynamicCollapse(ent, Vector(0, 0, 30))
            end

            if not ent.IsCollapsing and not IsCombineMachinery(ent) then
                local vel = ent:GetVelocity()
                local speed = vel:Length2D()

                if not ent:IsOnGround() then
                    if vel.z < -MID_AIR_FALL_SPEED then
                        TriggerDynamicCollapse(ent, Vector(0, 0, vel.z * 2))
                    end
                else
                    if speed > TRIP_SPEED_THRESHOLD and CurTime() > (ent.NextTripCheck or 0) then
                        ent.NextTripCheck = CurTime() + 0.5

                        local tr = util.TraceHull({
                            start = ent:GetPos() + Vector(0, 0, 15),
                            endpos = ent:GetPos() + (vel:GetNormalized() * 38) + Vector(0, 0, 5),
                            mins = Vector(-10, -10, -10),
                            maxs = Vector(10, 10, 15),
                            filter = ent
                        })

                        if tr.Hit and IsValid(tr.Entity) then
                            local hitEnt = tr.Entity
                            local isProp = hitEnt:GetClass() == "prop_physics" or hitEnt:GetClass() == "prop_physics_multiplayer"

                            if isProp and math.random(1, 100) <= TRIP_CHANCE then
                                ent:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 3) .. ".wav", 75, 100)
                                TriggerDynamicCollapse(ent, vel * 1.5, HITGROUP_LEFTLEG)
                            end
                        end
                    end

                    local tr = util.TraceLine({
                        start = ent:GetPos() + Vector(0, 0, 15),
                        endpos = ent:GetPos() - Vector(0, 0, 35),
                        filter = ent
                    })

                    if tr.Hit then
                        local norm = tr.HitNormal
                        local angle = math.deg(math.acos(norm.z))
                        local mat = tr.MatType

                        local isSlipperyMat = (mat == MAT_ICE or mat == MAT_SLOSH)
                        if tr.SurfaceProps then
                            local surfData = util.GetSurfaceData(tr.SurfaceProps)
                            if surfData and surfData.name then
                                local sName = string.lower(surfData.name)
                                if string.find(sName, "wet") or string.find(sName, "ice") or string.find(sName, "glass") or string.find(sName, "slime") then
                                    isSlipperyMat = true
                                end
                            end
                        end

                        if angle >= SLOPE_ANGLE_THRESHOLD then
                            local angleExcess = angle - SLOPE_ANGLE_THRESHOLD
                            local slipChance = math.Clamp(30 + (angleExcess * 4.0), 30, 95)

                            if speed > 15 and math.random(1, 100) <= slipChance then
                                local slideForce = Vector(norm.x, norm.y, -0.6):GetNormalized() * (speed * 2.0 + 180)
                                TriggerDynamicCollapse(ent, slideForce, HITGROUP_LEFTLEG)
                                ent:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 3) .. ".wav", 75, 100)
                            end
                        elseif isSlipperyMat and speed > 60 and math.random(1, 100) <= 50 then
                            TriggerDynamicCollapse(ent, vel * 1.3, HITGROUP_RIGHTLEG)
                            ent:EmitSound("physics/flesh/flesh_squish1.wav", 75, 100)
                        end
                    end
                end
            end
        end
    end
end)

-- 🦀 HEADCRAB WATER THRASHING, DROWNING & RESCUE RECOVERY
timer.Create("DynamicCollapse_HeadcrabWaterLogic", 0.15, 0, function()
    for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
        if IsValid(ragdoll) and IsValid(ragdoll.LinkedNPC) and IsHeadcrabNPC(ragdoll.LinkedNPC) then
            local npc = ragdoll.LinkedNPC
            local waterLvl = SafeWaterLevel(ragdoll)
            local inWater = (waterLvl > 0) or (bit.band(util.PointContents(ragdoll:WorldSpaceCenter()), CONTENTS_WATER) ~= 0)

            if inWater then
                ragdoll.WasInWater = true

                for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                    local phys = ragdoll:GetPhysicsObjectNum(i)
                    if IsValid(phys) then
                        phys:ApplyForceCenter(VectorRand() * 180 + Vector(0, 0, 40))
                    end
                end

                if CurTime() > (ragdoll.NextWaterDrownTick or 0) then
                    ragdoll.NextWaterDrownTick = CurTime() + 1.0

                    local ed = EffectData()
                    ed:SetOrigin(ragdoll:WorldSpaceCenter())
                    ed:SetScale(8)
                    util.Effect("WaterSplash", ed)

                    ragdoll:EmitSound("physics/surfaces/underwater_impact_bullet" .. math.random(1, 3) .. ".wav", 65, 120)

                    local newHP = npc:Health() - HEADCRAB_DROWN_DAMAGE
                    npc:SetHealth(newHP)

                    if newHP <= 0 then
                        timer.Remove("NPC_CollapseTrack_" .. npc:EntIndex())
                        ragdoll:EmitSound(GetNPCDeathSound(npc), 85, 100)
                        hook.Run("OnNPCKilled", npc, game.GetWorld(), game.GetWorld())
                        npc:Remove()
                    end
                end
            else
                if ragdoll.WasInWater then
                    ragdoll.WasInWater = false

                    timer.Simple(1.2, function()
                        if IsValid(ragdoll) and IsValid(npc) and npc:Health() > 0 and SafeWaterLevel(ragdoll) == 0 then
                            TransitionToStand(npc, ragdoll)
                        end
                    end)
                end
            end
        end
    end
end)

-- Hook 1: Ragdoll Damage Sync
hook.Add("EntityTakeDamage", "DynamicCollapse_RagdollDamageSync", function(target, dmginfo)
    if IsValid(target) and target:GetClass() == "prop_ragdoll" and IsValid(target.LinkedNPC) then
        local npc = target.LinkedNPC
        local damage = dmginfo:GetDamage() * RAGDOLL_DAMAGE_SCALE

        if dmginfo:IsDamageType(DMG_ALWAYSGIB) then
            dmginfo:SetDamageType(bit.band(dmginfo:GetDamageType(), bit.bnot(DMG_ALWAYSGIB)))
        end

        if dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_SLOWBURN) then
            if not npc:IsOnFire() then npc:Ignite(5) end
        end

        local hitPos = dmginfo:GetDamagePosition()
        local forceDir = dmginfo:GetDamageForce()
        if hitPos and forceDir then
            local phys = target:GetPhysicsObject()
            if IsValid(phys) then
                phys:ApplyForceOffset(forceDir * 0.015, hitPos)
            end
        end

        if damage > 1 then
            target:EmitSound(GetNPCPainSound(npc))
        end

        target.RagdollHealth = (target.RagdollHealth or 100) - damage
        local newNPCHealth = npc:Health() - damage
        npc:SetHealth(newNPCHealth)

        if target.RagdollHealth <= 0 or newNPCHealth <= 0 then
            timer.Remove("NPC_CollapseTrack_" .. npc:EntIndex())
            timer.Remove("ZombieCrawl_" .. target:EntIndex())
            timer.Remove("NPCCrawl_" .. target:EntIndex())
            timer.Remove("ZombineBeep_" .. target:EntIndex())

            target:EmitSound(GetNPCDeathSound(npc), 85, 100)

            local attacker = dmginfo:GetAttacker()
            local inflictor = dmginfo:GetInflictor()
            if not IsValid(attacker) then attacker = game.GetWorld() end
            if not IsValid(inflictor) then inflictor = attacker end

            hook.Run("OnNPCKilled", npc, attacker, inflictor)

            npc:Remove()
            target.LinkedNPC = nil
            target.IsVJInherited = true
        end
    end
end)

-- Hook 2: Leg Damage Tracking (With Damage Stacking)
hook.Add("ScaleNPCDamage", "DynamicCollapse_LegShot", function(npc, hitgroup, dmginfo)
    if not IsValid(npc) or npc.IsCollapsing or IsCombineMachinery(npc) then return end

    if hitgroup == HITGROUP_LEFTLEG or hitgroup == HITGROUP_RIGHTLEG then
        local damage = dmginfo:GetDamage()

        -- Track/stack leg damage across multiple shots
        npc.LeftLegDamage  = npc.LeftLegDamage or 0
        npc.RightLegDamage = npc.RightLegDamage or 0

        if hitgroup == HITGROUP_LEFTLEG then
            npc.LeftLegDamage = npc.LeftLegDamage + damage
        elseif hitgroup == HITGROUP_RIGHTLEG then
            npc.RightLegDamage = npc.RightLegDamage + damage
        end

        local currentLegDamage = (hitgroup == HITGROUP_LEFTLEG) and npc.LeftLegDamage or npc.RightLegDamage

        -- Check if cumulative leg damage crosses the break threshold
        if currentLegDamage >= HEAVY_LEG_DAMAGE then
            local newlyBroken = false

            if hitgroup == HITGROUP_LEFTLEG and not npc.LeftLegBroken then
                npc.LeftLegBroken = true
                newlyBroken = true
            elseif hitgroup == HITGROUP_RIGHTLEG and not npc.RightLegBroken then
                npc.RightLegBroken = true
                newlyBroken = true
            end

            local count = 0
            if npc.LeftLegBroken then count = count + 1 end
            if npc.RightLegBroken then count = count + 1 end

            npc.BrokenLegsCount = math.max(npc.BrokenLegsCount or 0, count)
            if npc.BrokenLegsCount == 0 then npc.BrokenLegsCount = 1 end
            npc.LegsBroken = true

            if newlyBroken then
                npc:EmitSound("physics/body/body_medium_break1.wav", 80, 90)
            end
        end

        -- Trigger collapse if shot exceeds minimum collapse threshold or leg damage is fully stacked
        if damage >= COLLAPSE_LEG_DAMAGE or currentLegDamage >= HEAVY_LEG_DAMAGE then
            TriggerDynamicCollapse(npc, dmginfo:GetDamageForce(), hitgroup)
            dmginfo:ScaleDamage(0.5)
        end
    end
end)

-- Hook 3: Shotgun Blast Trigger
hook.Add("EntityTakeDamage", "DynamicCollapse_ShotgunAndExplosion", function(ent, dmginfo)
    if not IsValid(ent) or IsCombineMachinery(ent) then return end
    if not (ent:IsNPC() or (ent.IsNextBot and ent:IsNextBot())) then return end

    if IsZombieNPC(ent) then
        if dmginfo:IsDamageType(DMG_ALWAYSGIB) then
            dmginfo:SetDamageType(bit.band(dmginfo:GetDamageType(), bit.bnot(DMG_ALWAYSGIB)))
        end
        if dmginfo:IsDamageType(DMG_BLAST) then
            dmginfo:SetDamageType(DMG_GENERIC)
        end
    end

    if ent.IsCollapsing then return end

    if dmginfo:IsDamageType(DMG_BUCKSHOT) or dmginfo:IsDamageType(DMG_GENERIC) or dmginfo:IsDamageType(DMG_BLAST) then
        if dmginfo:GetDamage() >= COLLAPSE_SHOTGUN_DAMAGE then
            local subduedForce = dmginfo:GetDamageForce() * 0.005
            TriggerDynamicCollapse(ent, subduedForce)
        end
    end
end)

-- Hook 4: Remove Severed Torso Spawns
hook.Add("OnEntityCreated", "DynamicCollapse_PreventZombieGibs", function(ent)
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        local cls = string.lower(ent:GetClass() or "")
        
        if cls == "npc_zombie_torso" then
            ent:Remove()
            return
        end
    end)
end)