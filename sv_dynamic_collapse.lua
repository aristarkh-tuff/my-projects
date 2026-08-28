if CLIENT then return end

local DynamicCollapseEnabled = CreateConVar(
    "npc_bleed_dynamic_collapse_enabled",
    "1",
    FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Enable dynamic NPC collapse behavior"
)

local function IsDynamicCollapseEnabled()
    return DynamicCollapseEnabled:GetBool()
end

-- ⚙️ CONFIGURATION
local RAGDOLL_GUN_DAMAGE_SCALE  = 2.5    -- Guns deal 2.5x damage to collapsed ragdolls only
local RAGDOLL_PHYS_DAMAGE_SCALE = 0.25   -- Physical/crush damage resistance (0.25x damage taken)
local HEADCRAB_PHYS_DAMAGE_SCALE = 0.05 -- Headcrabs take only 5% damage from physical impacts
local RAGDOLL_GENERIC_SCALE     = 1.0    -- Multiplier for standard damage (explosions, fire, etc.)
local RAGDOLL_HEALTH_MULTIPLIER = 2.5    -- Ragdolls receive 2.5x base health

local COLLAPSE_LEG_DAMAGE       = 8      -- Minimum leg damage to trigger collapse
local HEAVY_LEG_DAMAGE          = 15     -- Leg damage threshold to break legs permanently
local COLLAPSE_FALL_DAMAGE      = 10     -- Minimum fall damage to trigger collapse
local COLLAPSE_SHOTGUN_DAMAGE   = 10     -- Minimum shotgun/buckshot damage to trigger collapse
local COLLAPSE_INSTANT_DAMAGE   = 19     -- Immediate collapse threshold for a single large hit
local COLLAPSE_DAMAGE_STACK_WINDOW = 2.5  -- Time window for damage to stack before resetting

local MID_AIR_FALL_SPEED        = 400    -- Downward Z velocity to trigger fall ragdoll
local TRIP_SPEED_THRESHOLD      = 110    -- Minimum movement velocity to trigger a prop trip
local TRIP_CHANCE               = 40     -- Percentage chance to trip over a prop
local SMALL_SUPPORT_MAX_SIZE    = 42     -- Maximum horizontal size of a small prop surface
local SMALL_SUPPORT_MAX_HEIGHT  = 36     -- Maximum height of a small prop surface
local EDGE_TRIP_CHANCE          = 25     -- Percentage chance to trip when approaching an edge

local SLOPE_ANGLE_THRESHOLD     = 28     -- Base angle in degrees (e.g. 30 deg roof) to trigger slipping
local HEADCRAB_DROWN_DAMAGE     = 6      -- Damage taken per second while headcrab thrashes in water
local HEADCRAB_DROWN_GRACE_MIN  = 10     -- Minimum seconds before water damage begins
local HEADCRAB_DROWN_GRACE_MAX  = 20     -- Maximum seconds before water damage begins
local HEADCRAB_SHORE_MIN_NORMAL_Z = 0.75 -- Reject steep surfaces that cannot support a headcrab
local HEADCRAB_LANDING_CHANCE    = 40     -- Normal chance for a headcrab to land safely
local HEADCRAB_BELLY_LANDING_CHANCE = 99  -- Chance when the belly faces the ground
local HEADCRAB_FAST_RECOVERY_MIN  = 0.8   -- Minimum recovery time after a safe landing
local HEADCRAB_FAST_RECOVERY_MAX  = 1.5   -- Maximum recovery time after a safe landing
local FIRE_COLLAPSE_DELAY       = 3.0    -- Seconds an NPC must burn before collapsing
local FIRE_THRASH_DURATION      = 4.0    -- Seconds of gentle fire panic motion
local RAGDOLL_SELF_SHOT_INTERVAL = 0.9   -- Seconds between shots fired at a living ragdoll

local MIN_RECOVERY_TIME         = 3.0    -- Minimum seconds knocked out (legs NOT broken)
local MAX_RECOVERY_TIME         = 10.0   -- Maximum seconds knocked out (legs NOT broken)
local MEDKIT_OVERHEAL_DURATION  = 8.0    -- Seconds for medkit over-heal to fade away

local ZOMBINE_GRENADE_CHANCE    = 40     -- Percentage chance for Zombine grenade on collapse
local BLEND_DURATION            = 1.4    -- Seconds to transition back upright

-- 🛠️ VJ BASE DETECTION HELPER
local function IsVJBaseNPC(ent)
    if not IsValid(ent) then return false end
    return (ent.IsVJBase == true) 
        or (ent.IsVJBase_SNPC == true) 
        or (ent.VJ_IsHugeNPC ~= nil) 
        or (ent.VJBase ~= nil)
end

-- 🎯 SPECIFIC NPC DEATH TRACKER (Filtered for VJ Base duplicate issues)
local RecentNPCDeaths = {}

local function RegisterNPCDeath(npc, isInstant, ragdoll)
    if not IsValid(npc) then return end
    RecentNPCDeaths[npc:EntIndex()] = {
        model = npc:GetModel(),
        pos = npc:GetPos(),
        instant = isInstant or false,
        ragdoll = ragdoll or nil,
        isVJ = IsVJBaseNPC(npc),
        time = CurTime()
    }
end

timer.Create("DynamicCollapse_CleanRecentDeaths", 1.0, 0, function()
    local now = CurTime()
    for idx, info in pairs(RecentNPCDeaths) do
        if now - info.time > 1.5 then
            RecentNPCDeaths[idx] = nil
        end
    end
end)

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

local function IsPhysicalDamage(dmginfo)
    if not dmginfo or dmginfo:IsBulletDamage() or dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT) then
        return false
    end

    return dmginfo:IsDamageType(DMG_FALL)
        or dmginfo:IsDamageType(DMG_CRUSH)
        or dmginfo:IsDamageType(DMG_PHYSGUN)
        or dmginfo:IsDamageType(DMG_CLUB)
end

local function IsSmallSupport(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    if class ~= "prop_physics" and class ~= "prop_physics_multiplayer" then return false end

    local size = ent:OBBMaxs() - ent:OBBMins()
    return math.max(size.x, size.y) <= SMALL_SUPPORT_MAX_SIZE and size.z <= SMALL_SUPPORT_MAX_HEIGHT
end

local function IsRagdollGrounded(ragdoll)
    if not IsValid(ragdoll) then return false end

    local mins, maxs = ragdoll:OBBMins(), ragdoll:OBBMaxs()
    local tr = util.TraceHull({
        start = ragdoll:GetPos() + Vector(0, 0, 8),
        endpos = ragdoll:GetPos() - Vector(0, 0, 18),
        mins = mins,
        maxs = maxs,
        filter = ragdoll,
        mask = MASK_SOLID
    })

    return tr.Hit and tr.HitNormal.z > 0.35 and math.abs(tr.HitPos.z - ragdoll:GetPos().z) < 32
end

local function StopRagdollMotion(ragdoll)
    if not IsValid(ragdoll) then return end

    for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
        local phys = ragdoll:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetVelocity(vector_origin)
            phys:SetAngleVelocity(vector_origin)
        end
    end
end

local TransitionToStand

local function EvaluateHeadcrabLanding(npc, ragdoll)
    if not IsValid(npc) or not IsValid(ragdoll) or not IsHeadcrabNPC(npc) or npc.HeadcrabLandingChecked then return end

    local phys = ragdoll:GetPhysicsObjectNum(0)
    if not IsValid(phys) then return end

    local bellyDown = phys:GetAngles():Right().z <= -0.55
    local successChance = bellyDown and HEADCRAB_BELLY_LANDING_CHANCE or HEADCRAB_LANDING_CHANCE

    npc.HeadcrabLandingChecked = true
    npc.HeadcrabLandingSuccess = math.random(1, 100) <= successChance

    if npc.HeadcrabLandingSuccess then
        npc.HeadcrabLandingDamageProtected = true
        local pendingFallDamage = npc.HeadcrabPendingFallDamage or 0
        if pendingFallDamage > 0 then
            npc:SetHealth(npc:Health() + pendingFallDamage)
            if IsValid(npc.LinkedRagdoll) then
                npc.LinkedRagdoll.RagdollHealth = (npc.LinkedRagdoll.RagdollHealth or 0) + pendingFallDamage * RAGDOLL_HEALTH_MULTIPLIER
            end
            npc.HeadcrabPendingFallDamage = nil
        end

        timer.Simple(math.Rand(HEADCRAB_FAST_RECOVERY_MIN, HEADCRAB_FAST_RECOVERY_MAX), function()
            if IsValid(npc) and IsValid(ragdoll) and npc.IsCollapsing and npc.LinkedRagdoll == ragdoll then
                StopRagdollMotion(ragdoll)
                TransitionToStand(npc, ragdoll)
            end
        end)
    end
end

local function ResetCollapseDamageStack(npc)
    if not IsValid(npc) then return end
    npc.DynamicCollapseDamageStack = 0
    npc.DynamicCollapseDamageStackResetTime = 0
end

local function AddCollapseDamageStack(npc, damage)
    if not IsValid(npc) or npc.IsCollapsing then return 0 end
    local amount = math.max(0, damage or 0)
    if amount <= 0 then return (npc.DynamicCollapseDamageStack or 0) end

    local now = CurTime()
    if not npc.DynamicCollapseDamageStackResetTime or now >= npc.DynamicCollapseDamageStackResetTime then
        npc.DynamicCollapseDamageStack = 0
    end

    local stack = (npc.DynamicCollapseDamageStack or 0) + amount
    npc.DynamicCollapseDamageStack = stack
    npc.DynamicCollapseDamageStackResetTime = now + COLLAPSE_DAMAGE_STACK_WINDOW
    return stack
end

local function GetNPCMaxHealth(npc)
    if not IsValid(npc) then return 100 end
    if not npc.MaxHealthLimit or npc.MaxHealthLimit <= 0 then
        local maxHp = npc:GetMaxHealth()
        npc.MaxHealthLimit = (maxHp > 0) and maxHp or math.max(npc:Health(), 100)
    end
    return npc.MaxHealthLimit
end

local function ApplyNPCOverhealDecay(npc)
    if not IsValid(npc) then return end
    local overHealAmount = npc.OverhealAmount or 0
    if overHealAmount <= 0 then return end

    local maxHp = GetNPCMaxHealth(npc)
    local currentHp = npc:Health()
    if currentHp <= maxHp then
        npc.OverhealAmount = 0
        npc.OverhealDecayStart = nil
        return
    end

    local elapsed = CurTime() - (npc.OverhealDecayStart or CurTime())
    local remainingOverheal = math.max(0, overHealAmount - (overHealAmount * elapsed / MEDKIT_OVERHEAL_DURATION))
    local targetHp = maxHp + remainingOverheal

    if currentHp > targetHp then
        npc:SetHealth(targetHp)
    end

    if remainingOverheal <= 0 then
        npc.OverhealAmount = 0
        npc.OverhealDecayStart = nil
    end
end

local function AddNPCOverheal(npc, amount)
    if not IsValid(npc) or amount <= 0 then return end

    local maxHp = GetNPCMaxHealth(npc)
    local currentHp = npc:Health()
    if currentHp >= maxHp then
        local extra = amount
        npc.OverhealAmount = (npc.OverhealAmount or 0) + extra
        npc.OverhealDecayStart = CurTime()
        npc:SetHealth(currentHp + extra)
    else
        npc:SetHealth(math.min(maxHp + amount, currentHp + amount))
    end
end

local function FindNearestShorePos(pos)
    local bestPos = nil
    local bestDistSqr = 2500 * 2500
    local numDirections = 12

    for i = 1, numDirections do
        local angleRad = (i / numDirections) * math.pi * 2
        local testDir = Vector(math.cos(angleRad), math.sin(angleRad), -0.3):GetNormalized()

        local tr = util.TraceLine({
            start = pos + Vector(0, 0, 20),
            endpos = pos + (testDir * 1800),
            mask = MASK_SOLID
        })

        if tr.Hit and not tr.AllSolid and tr.HitNormal.z >= HEADCRAB_SHORE_MIN_NORMAL_Z then
            local standPos = tr.HitPos + Vector(0, 0, 2)
            local clearance = util.TraceHull({
                start = standPos,
                endpos = standPos,
                mins = Vector(-14, -14, 0),
                maxs = Vector(14, 14, 32),
                mask = MASK_SOLID
            })
            local waterCheck = util.PointContents(standPos + Vector(0, 0, 15))
            if not clearance.StartSolid and not clearance.AllSolid and not clearance.Hit and bit.band(waterCheck, CONTENTS_WATER) == 0 then
                local distSqr = pos:DistToSqr(standPos)
                if distSqr < bestDistSqr then
                    bestDistSqr = distSqr
                    bestPos = standPos
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

local function ApplyHealthItem(npc, item)
    if not IsValid(npc) or not IsValid(item) then return end
    if npc.HeadshotKilled or npc.IsInstantKilled then return end

    local cls = item:GetClass()
    local isVial = (cls == "item_healthvial")
    local isKit  = (cls == "item_healthkit")

    if not (isVial or isKit) then return end

    local currentHP = npc:Health()
    local brokenLegs = npc.BrokenLegsCount or (npc.LegsBroken and 1 or 0)
    local healAmount = 0
    local soundName = isVial and "items/smallmedkit1.wav" or "items/medshot4.wav"
    local hadSingleBrokenLeg = brokenLegs == 1

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
    end

    local newHP = currentHP + healAmount
    if isKit and hadSingleBrokenLeg then
        newHP = newHP + 10
        AddNPCOverheal(npc, 10)
    end
    npc:SetHealth(newHP)

    if IsValid(npc.LinkedRagdoll) then
        npc.LinkedRagdoll.RagdollHealth = newHP * RAGDOLL_HEALTH_MULTIPLIER
    end

    item:EmitSound(soundName, 75, 100)
    item:Remove()

    if not npc.LegsBroken and npc.IsCollapsing and IsValid(npc.LinkedRagdoll) then
        TransitionToStand(npc, npc.LinkedRagdoll)
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
    if not IsValid(npc) or npc.IsSurrendering or npc.IsCollapsing or npc.IsSpared or npc.HeadshotKilled or npc.IsInstantKilled then return end
    
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
    if cls == "npc_crow" then return "NPC_Crow.Die" end
    if cls == "npc_pigeon" then return "NPC_Pigeon.Die" end
    if cls == "npc_seagull" then return "NPC_Seagull.Die" end
    if string.find(cls, "poison") and string.find(cls, "headcrab") then return "NPC_PoisonHeadcrab.Pain" end
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
    if cls == "npc_crow" then return "NPC_Crow.Die" end
    if cls == "npc_pigeon" then return "NPC_Pigeon.Die" end
    if cls == "npc_seagull" then return "NPC_Seagull.Die" end
    if string.find(cls, "poison") and string.find(cls, "headcrab") then return "NPC_PoisonHeadcrab.Die" end
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

local function TransferBonemergeChildrenToRagdoll(npc, ragdoll)
    if not IsValid(npc) or not IsValid(ragdoll) then return end

    local searchPos = npc:GetPos()
    for _, ent in ipairs(ents.FindInSphere(searchPos, 256)) do
        if not IsValid(ent) then continue end
        if ent:IsNPC() then continue end
        if ent:GetParent() ~= npc then continue end

        local cls = string.lower(ent:GetClass() or "")
        local mdl = string.lower(ent:GetModel() or "")

        if string.find(cls, "headcrab") or string.find(mdl, "headcrab") then
            ent._DynamicCollapse_OldParent = npc
            ent._DynamicCollapse_Transfered = true
            ent:SetParent(ragdoll)
        end
    end
end

local function RestoreBonemergeChildrenFromRagdoll(npc, ragdoll)
    if not IsValid(npc) or not IsValid(ragdoll) then return end

    local searchPos = ragdoll:GetPos()
    for _, ent in ipairs(ents.FindInSphere(searchPos, 512)) do
        if not IsValid(ent) then continue end
        if ent:IsNPC() then continue end
        if not ent._DynamicCollapse_Transfered then continue end
        if ent._DynamicCollapse_OldParent ~= npc then continue end

        ent:SetParent(npc)
        ent._DynamicCollapse_Transfered = nil
        ent._DynamicCollapse_OldParent = nil
    end
end

local function DropNPCWeaponForCollapse(npc)
    if not IsValid(npc) or not npc.GetActiveWeapon then return nil end

    local weapon = npc:GetActiveWeapon()
    if not IsValid(weapon) or not weapon:IsWeapon() then return nil end

    if npc.DropWeapon then
        npc:DropWeapon(weapon)
    else
        weapon:SetOwner(NULL)
    end

    if IsValid(weapon) and weapon:GetOwner() == npc then
        weapon:SetOwner(NULL)
    end

    if IsValid(weapon) then
        weapon:SetPos(npc:WorldSpaceCenter())
        weapon:SetVelocity(npc:GetVelocity())
        npc.DroppedWeapon = weapon
    end

    return weapon
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

local function TryTriggerZombineGrenade(npc, ragdoll)
    if not IsZombine(npc) or not IsValid(ragdoll) or ragdoll.HasGrenade then return end
    if npc.HeadshotKilled or npc.IsInstantKilled then return end
    if math.random(1, 100) > ZOMBINE_GRENADE_CHANCE then return end

    ragdoll.HasGrenade = true

    timer.Simple(0.5, function()
        if not IsValid(ragdoll) or not IsValid(npc) or npc:Health() <= 0 or npc.HeadshotKilled or npc.IsInstantKilled then return end

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

local function StartZombieCrawlLogic(npc, ragdoll)
    if not IsValid(ragdoll) then return end
    if npc.HeadshotKilled or npc.IsInstantKilled then return end

    local crawlTimer = "ZombieCrawl_" .. ragdoll:EntIndex()
    
    timer.Create(crawlTimer, 0.8, 0, function()
        if not IsValid(ragdoll) or not IsValid(npc) or npc:Health() <= 0 or npc.HeadshotKilled or npc.IsInstantKilled then
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

            local spineBone = ragdoll:LookupBone("ValveBiped.Bip01_Spine2") or ragdoll:LookupBone("ValveBiped.Bip01_Pelvis")
            local spinePhysNum = spineBone and ragdoll:TranslateBoneToPhysBone(spineBone) or 0
            local phys = ragdoll:GetPhysicsObjectNum(spinePhysNum)

            if IsValid(phys) then
                local currentVel = phys:GetVelocity()
                if currentVel:LengthSqr() < (300 * 300) then
                    phys:ApplyForceCenter(dir * 5000 + Vector(0, 0, 800))
                end
            end

            ragdoll:EmitSound("physics/flesh/flesh_scrape_rough_ground" .. math.random(1, 2) .. ".wav", 65, math.random(90, 105))
            if math.random(1, 3) == 1 then
                ragdoll:EmitSound("npc/zombie/zombie_voice_idle" .. math.random(1, 3) .. ".wav", 75, math.random(85, 100))
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

local function StartGenericNPCCrawlLogic(npc, ragdoll)
    if not IsValid(ragdoll) then return end
    if npc.HeadshotKilled or npc.IsInstantKilled then return end

    local crawlTimer = "NPCCrawl_" .. ragdoll:EntIndex()

    timer.Create(crawlTimer, 0.75, 0, function()
        if not IsValid(ragdoll) or not IsValid(npc) or npc:Health() <= 0 or npc.HeadshotKilled or npc.IsInstantKilled then
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
        local shouldCrawlTowardPlayer = IsHeadcrabNPC(npc) and (npc.LegsBroken or (npc.BrokenLegsCount or 0) > 0)

        if shouldCrawlTowardPlayer then
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
                moveTargetPos = closestPly:GetPos()
            end
        elseif npc.LegsBroken or (npc.BrokenLegsCount or 0) > 0 then
            local threatTarget = nil
            local threatPos = nil
            local enemy = npc:GetEnemy()

            if IsValid(enemy) then
                threatTarget = enemy
                threatPos = enemy:GetPos()
            end

            if not threatPos then
                for _, ply in ipairs(player.GetAll()) do
                    if IsValid(ply) and ply:Alive() and npc:Disposition(ply) == D_HT then
                        threatTarget = ply
                        threatPos = ply:GetPos()
                        break
                    end
                end
            end

            if not threatPos then
                for _, ply in ipairs(player.GetAll()) do
                    if IsValid(ply) and ply:Alive() then
                        threatTarget = ply
                        threatPos = ply:GetPos()
                        break
                    end
                end
            end

            if threatPos then
                local retreatDir = (ragPos - threatPos):GetNormalized()
                retreatDir.z = 0.05
                moveTargetPos = ragPos + (retreatDir * 300)
            end
        elseif npc:Health() < GetNPCMaxHealth(npc) then
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

            local spineBone = ragdoll:LookupBone("ValveBiped.Bip01_Spine2") or ragdoll:LookupBone("ValveBiped.Bip01_Pelvis")
            local spinePhysNum = spineBone and ragdoll:TranslateBoneToPhysBone(spineBone) or 0
            local phys = ragdoll:GetPhysicsObjectNum(spinePhysNum)

            if IsValid(phys) then
                local currentVel = phys:GetVelocity()
                if currentVel:LengthSqr() < (250 * 250) then
                    phys:ApplyForceCenter(dir * 4500 + Vector(0, 0, 600))
                end
            end

            ragdoll:EmitSound("physics/flesh/flesh_scrape_rough_ground" .. math.random(1, 2) .. ".wav", 60, math.random(95, 105))
            
            if math.random(1, 3) == 1 then
                ragdoll:EmitSound(GetNPCPainSound(npc), 75, math.random(90, 105))
            end
        end
    end)
end

local function StartFireThrashLogic(npc, ragdoll)
    if not IsValid(npc) or not IsValid(ragdoll) then return end

    local thrashTimer = "NPCFireThrash_" .. ragdoll:EntIndex()
    ragdoll.FireThrashing = true
    ragdoll.FireThrashUntil = CurTime() + FIRE_THRASH_DURATION

    timer.Create(thrashTimer, 0.16, 0, function()
        if not IsValid(npc) or not IsValid(ragdoll) or npc:Health() <= 0 or npc.HeadshotKilled or npc.IsInstantKilled then
            timer.Remove(thrashTimer)
            return
        end

        if CurTime() >= (ragdoll.FireThrashUntil or 0) or not ragdoll:IsOnFire() then
            ragdoll.FireThrashing = false
            timer.Remove(thrashTimer)
            return
        end

        local phase = CurTime() * 8
        local spineBone = ragdoll:LookupBone("ValveBiped.Bip01_Spine2") or ragdoll:LookupBone("ValveBiped.Bip01_Pelvis")
        local spinePhys = spineBone and ragdoll:GetPhysicsObjectNum(ragdoll:TranslateBoneToPhysBone(spineBone))

        if IsValid(spinePhys) then
            local velocity = spinePhys:GetVelocity()
            if velocity:LengthSqr() < (75 * 75) then
                spinePhys:ApplyForceCenter(Vector(math.sin(phase) * 45, math.cos(phase * 0.7) * 45, 35))
            end

            if not IsHeadcrabNPC(npc) then
                spinePhys:ApplyTorqueCenter(Vector(0, math.sin(phase * 0.65) * 28, math.cos(phase) * 12))
            end
        end

        local handNames = {"ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_L_Hand"}
        for _, boneName in ipairs(handNames) do
            local bone = ragdoll:LookupBone(boneName)
            local phys = bone and ragdoll:GetPhysicsObjectNum(ragdoll:TranslateBoneToPhysBone(bone))
            if IsValid(phys) and phys:GetVelocity():LengthSqr() < (55 * 55) then
                phys:ApplyForceCenter(VectorRand() * 30 + Vector(0, 0, 22))
            end
        end
    end)
end

local function StartRagdollSelfShootLogic(npc, ragdoll)
    if not IsValid(npc) or not IsValid(ragdoll) or not npc.RagdollCanShoot then return end

    local hitbox = ents.Create("npc_bullseye")
    if not IsValid(hitbox) then return end

    hitbox:SetPos(ragdoll:WorldSpaceCenter())
    hitbox:SetKeyValue("spawnflags", "65536")
    hitbox:Spawn()
    hitbox:SetNoDraw(true)
    hitbox:SetCollisionBounds(Vector(-18, -18, -28), Vector(18, 18, 28))
    hitbox:SetHealth(1000000)
    hitbox.RagdollTarget = ragdoll
    hitbox.RagdollShooter = npc
    ragdoll.ShootingHitbox = hitbox
    npc.RagdollShootTarget = hitbox
    npc:AddEntityRelationship(hitbox, D_HT, 99)
    npc:SetEnemy(hitbox)
    npc:UpdateEnemyMemory(hitbox, hitbox:GetPos())

    local shootTimer = "NPC_RagdollSelfShoot_" .. ragdoll:EntIndex()
    timer.Create(shootTimer, RAGDOLL_SELF_SHOT_INTERVAL, 0, function()
        if not IsValid(npc) or not IsValid(ragdoll) or not IsValid(hitbox) or npc:Health() <= 0 or not npc.IsCollapsing or npc.LinkedRagdoll ~= ragdoll then
            if IsValid(hitbox) then hitbox:Remove() end
            timer.Remove(shootTimer)
            return
        end

        hitbox:SetPos(ragdoll:WorldSpaceCenter())
        npc:SetEnemy(hitbox)
        npc:UpdateEnemyMemory(hitbox, hitbox:GetPos())
        npc:SetNPCState(NPC_STATE_COMBAT)
        npc:SetSchedule(SCHED_RANGE_ATTACK1)
    end)
end

TransitionToStand = function(npc, ragdoll)
    if not IsValid(npc) then return end
    if npc.LegsBroken or npc.HeadshotKilled or npc.IsInstantKilled then return end

    if IsValid(ragdoll) and not IsRagdollGrounded(ragdoll) then
        local retryName = "NPC_GetUpRetry_" .. npc:EntIndex()
        if not timer.Exists(retryName) then
            timer.Create(retryName, 0.25, 1, function()
                if IsValid(npc) and IsValid(ragdoll) then
                    TransitionToStand(npc, ragdoll)
                end
            end)
        end
        return
    end

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
    
    RestoreBonemergeChildrenFromRagdoll(npc, ragdoll)
    
    if IsValid(ragdoll.ShootingHitbox) then ragdoll.ShootingHitbox:Remove() end
    npc.RagdollShootTarget = nil
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
    if not IsDynamicCollapseEnabled() or not IsValid(npc) or npc.IsCollapsing or npc.IsInstantKilled or npc:Health() <= 0 or IsCombineMachinery(npc) or npc.HeadshotKilled or hitgroup == HITGROUP_HEAD then return end
    
    npc.IsCollapsing = true
    ResetCollapseDamageStack(npc)
    npc.IsSurrendering = false

    DropNPCWeaponForCollapse(npc)

    if IsWeaponCapableNPC(npc) then
        local activeWep = npc:GetActiveWeapon()
        npc.RagdollCanShoot = IsValid(activeWep)
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

    -- Register death/collapse event specifically for this NPC
    RegisterNPCDeath(npc, false, ragdoll)

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

    if IsHeadcrabNPC(npc) then
        EvaluateHeadcrabLanding(npc, ragdoll)
    end

    if hitgroup then
        ApplyInjuryHoldConstraint(ragdoll, hitgroup)
    end

    if npc.CapabilitiesGet and not npc.RagdollCanShoot then
        npc.StoredCapabilities = npc:CapabilitiesGet()
        npc:CapabilitiesClear()
    end
    FreezeNPC_AI(npc)
    
    TransferBonemergeChildrenToRagdoll(npc, ragdoll)

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

        if not npc.RagdollCanShoot then FreezeNPC_AI(npc) end
    end)

    local isZombie = IsZombieNPC(npc)
    
    if isZombie then
        TryTriggerZombineGrenade(npc, ragdoll)
    end

    if npc.FireCollapseTriggered then
        StartFireThrashLogic(npc, ragdoll)
    end

    StartRagdollSelfShootLogic(npc, ragdoll)

    if npc.LegsBroken then
        if isZombie then
            StartZombieCrawlLogic(npc, ragdoll)
        else
            StartGenericNPCCrawlLogic(npc, ragdoll)
        end
    else
        local randomDelay = math.Rand(MIN_RECOVERY_TIME, MAX_RECOVERY_TIME)
        timer.Simple(randomDelay, function()
            if IsValid(npc) and npc:Health() > 0 and not npc.HeadshotKilled and not npc.IsInstantKilled and IsValid(ragdoll) and SafeWaterLevel(ragdoll) < 3 then
                TransitionToStand(npc, ragdoll)
            end
        end)
    end
end

-- 🏊 SUBMERGED RAGDOLL REALISTIC SWIM LOGIC
timer.Create("DynamicCollapse_SubmergedRagdollSwimLogic", 0.1, 0, function()
    if not IsDynamicCollapseEnabled() then return end

    for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
        if IsValid(ragdoll) and IsValid(ragdoll.LinkedNPC) then
            local npc = ragdoll.LinkedNPC
            if npc.HeadshotKilled or npc.IsInstantKilled then continue end

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

                    if not npc.LegsBroken and not npc.HeadshotKilled and not npc.IsInstantKilled then
                        timer.Simple(0.8, function()
                            if IsValid(ragdoll) and IsValid(npc) and npc:Health() > 0 and not npc.HeadshotKilled and not npc.IsInstantKilled and SafeWaterLevel(ragdoll) < 2 then
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

-- 🏃 WEAPON & HEALTH PICKUP LOGIC
timer.Create("DynamicCollapse_UnarmedAndWeaponPickupLogic", 0.6, 0, function()
    if not IsDynamicCollapseEnabled() then return end

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and npc:IsNPC() and not npc.IsCollapsing and not npc.HeadshotKilled and not npc.IsInstantKilled then
            ApplyNPCOverhealDecay(npc)
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
    if not IsDynamicCollapseEnabled() then return end

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and npc:IsNPC() and npc:Health() > 0 and not npc.HeadshotKilled and not npc.IsInstantKilled then
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
    if not IsDynamicCollapseEnabled() then return end

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
    if not IsDynamicCollapseEnabled() then return end

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
    if not IsDynamicCollapseEnabled() then return end

    for _, ent in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(ent) and ent:IsNPC() and not ent.HeadshotKilled and not ent.IsInstantKilled then
            local waterLevel = SafeWaterLevel(ent)

            if ent:IsOnFire() and not ent.IsCollapsing then
                ent.FireStartedAt = ent.FireStartedAt or CurTime()
                if CurTime() - ent.FireStartedAt >= FIRE_COLLAPSE_DELAY then
                    ent.FireCollapseTriggered = true
                    TriggerDynamicCollapse(ent, Vector(0, 0, 12))
                end
            elseif not ent:IsOnFire() then
                ent.FireStartedAt = nil
            end

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
                    if CurTime() > (ent.NextTripCheck or 0) then
                        ent.NextTripCheck = CurTime() + 0.5

                        local supportTrace = util.TraceLine({
                            start = ent:GetPos() + Vector(0, 0, 18),
                            endpos = ent:GetPos() - Vector(0, 0, 30),
                            filter = ent,
                            mask = MASK_SOLID
                        })

                        if supportTrace.Hit and IsSmallSupport(supportTrace.Entity) then
                            ent:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 3) .. ".wav", 75, 100)
                            TriggerDynamicCollapse(ent, Vector(0, 0, 80), HITGROUP_LEFTLEG)
                            continue
                        end

                        if speed > TRIP_SPEED_THRESHOLD then
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

                        local edgeDirection = speed > 0 and vel:GetNormalized() or nil
                        if edgeDirection then
                            local edgeTrace = util.TraceHull({
                                start = ent:GetPos() + edgeDirection * 28 + Vector(0, 0, 18),
                                endpos = ent:GetPos() + edgeDirection * 28 - Vector(0, 0, 42),
                                mins = Vector(-8, -8, -2),
                                maxs = Vector(8, 8, 2),
                                filter = ent,
                                mask = MASK_SOLID
                            })

                            if not edgeTrace.Hit and speed > 25 and math.random(1, 100) <= EDGE_TRIP_CHANCE then
                                ent:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 3) .. ".wav", 75, 100)
                                TriggerDynamicCollapse(ent, vel * 1.2 + Vector(0, 0, 70), HITGROUP_RIGHTLEG)
                                continue
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
    if not IsDynamicCollapseEnabled() then return end

    for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
        if IsValid(ragdoll) and IsValid(ragdoll.LinkedNPC) and IsHeadcrabNPC(ragdoll.LinkedNPC) then
            local npc = ragdoll.LinkedNPC
            if npc.HeadshotKilled or npc.IsInstantKilled then continue end

            local waterLvl = SafeWaterLevel(ragdoll)
            local inWater = (waterLvl > 0) or (bit.band(util.PointContents(ragdoll:WorldSpaceCenter()), CONTENTS_WATER) ~= 0)

            if inWater then
                ragdoll.WasInWater = true
                if not ragdoll.WaterEnteredAt then
                    ragdoll.WaterEnteredAt = CurTime()
                    ragdoll.WaterDrownTime = CurTime() + math.Rand(HEADCRAB_DROWN_GRACE_MIN, HEADCRAB_DROWN_GRACE_MAX)
                end

                for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                    local phys = ragdoll:GetPhysicsObjectNum(i)
                    if IsValid(phys) then
                        phys:ApplyForceCenter(VectorRand() * 180 + Vector(0, 0, 40))
                    end
                end

                if CurTime() >= (ragdoll.WaterDrownTime or 0) and CurTime() > (ragdoll.NextWaterDrownTick or 0) then
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
                    ragdoll.WaterEnteredAt = nil
                    ragdoll.WaterDrownTime = nil

                    timer.Simple(1.2, function()
                        if IsValid(ragdoll) and IsValid(npc) and npc:Health() > 0 and not npc.HeadshotKilled and not npc.IsInstantKilled and SafeWaterLevel(ragdoll) == 0 then
                            StopRagdollMotion(ragdoll)
                            TransitionToStand(npc, ragdoll)
                        end
                    end)
                end
            end
        end
    end
end)

-- Hook 1: Ragdoll Damage Sync (Guns deal 2.5x damage; Physical damage is resisted)
hook.Add("EntityTakeDamage", "DynamicCollapse_RagdollDamageSync", function(target, dmginfo)
    if not IsDynamicCollapseEnabled() then return end

    if IsValid(target) and target:GetClass() == "npc_bullseye" and IsValid(target.RagdollTarget) then
        target.RagdollTarget:TakeDamageInfo(dmginfo)
        dmginfo:SetDamage(0)
        return
    end

    if IsValid(target) and target:GetClass() == "prop_ragdoll" and IsValid(target.LinkedNPC) then
        local npc = target.LinkedNPC

        if IsHeadcrabNPC(npc) and dmginfo:IsDamageType(DMG_DROWN) then
            dmginfo:SetDamage(0)
            return
        end

        local hitPos = dmginfo:GetDamagePosition()

        local damageScale = RAGDOLL_GENERIC_SCALE
        if dmginfo:IsBulletDamage() or dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_BUCKSHOT) then
            damageScale = IsHeadcrabNPC(npc) and RAGDOLL_GENERIC_SCALE or RAGDOLL_GUN_DAMAGE_SCALE
        elseif IsPhysicalDamage(dmginfo) then
            if target.FireThrashing then
                damageScale = 0
            elseif IsHeadcrabNPC(npc) then
                damageScale = HEADCRAB_PHYS_DAMAGE_SCALE
            else
                damageScale = RAGDOLL_PHYS_DAMAGE_SCALE
            end
        end

        local damage = dmginfo:GetDamage() * damageScale

        if dmginfo:IsDamageType(DMG_ALWAYSGIB) then
            dmginfo:SetDamageType(bit.band(dmginfo:GetDamageType(), bit.bnot(DMG_ALWAYSGIB)))
        end

        if dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_SLOWBURN) then
            if not npc:IsOnFire() then npc:Ignite(5) end
        end

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

        if target.RagdollHealth <= 0 or newNPCHealth <= 0 or npc.HeadshotKilled or npc.IsInstantKilled then
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

-- Hook 2: Leg Damage Tracking
hook.Add("ScaleNPCDamage", "DynamicCollapse_LegShot", function(npc, hitgroup, dmginfo)
    if not IsDynamicCollapseEnabled() then return end

    if not IsValid(npc) or IsCombineMachinery(npc) then return end

    -- Track damage that is already lethal without adding headshot-specific damage.
    if dmginfo:GetDamage() >= npc:Health() then
        npc.IsInstantKilled = true
        RegisterNPCDeath(npc, true, nil)
        return
    end

    if npc.IsCollapsing then return end

    if hitgroup == HITGROUP_LEFTLEG or hitgroup == HITGROUP_RIGHTLEG then
        local damage = dmginfo:GetDamage()
        local damageStack = AddCollapseDamageStack(npc, damage)

        if damageStack >= COLLAPSE_LEG_DAMAGE then
            if damageStack >= HEAVY_LEG_DAMAGE then
                if hitgroup == HITGROUP_LEFTLEG then
                    npc.LeftLegBroken = true
                elseif hitgroup == HITGROUP_RIGHTLEG then
                    npc.RightLegBroken = true
                end

                local count = 0
                if npc.LeftLegBroken then count = count + 1 end
                if npc.RightLegBroken then count = count + 1 end

                npc.BrokenLegsCount = math.max(npc.BrokenLegsCount or 0, count)
                if npc.BrokenLegsCount == 0 then npc.BrokenLegsCount = 1 end
                npc.LegsBroken = true

                npc:EmitSound("physics/body/body_medium_break1.wav", 80, 90)
            end

            TriggerDynamicCollapse(npc, dmginfo:GetDamageForce(), hitgroup)
        end
    end
end)

-- Hook 3: Shotgun Blast & Instant One-Shot Damage Check
hook.Add("EntityTakeDamage", "DynamicCollapse_ShotgunAndExplosion", function(ent, dmginfo)
    if not IsDynamicCollapseEnabled() then return end

    if not IsValid(ent) or IsCombineMachinery(ent) then return end
    if not (ent:IsNPC() or (ent.IsNextBot and ent:IsNextBot())) then return end

    if IsHeadcrabNPC(ent) and dmginfo:IsDamageType(DMG_DROWN) then
        dmginfo:SetDamage(0)
        return
    end

    if IsHeadcrabNPC(ent) and dmginfo:IsDamageType(DMG_FALL) and IsValid(ent.LinkedRagdoll) then
        EvaluateHeadcrabLanding(ent, ent.LinkedRagdoll)
        if ent.HeadcrabLandingSuccess then
            dmginfo:SetDamage(0)
            return
        end
    end

    if IsHeadcrabNPC(ent) and IsPhysicalDamage(dmginfo) then
        local scaledDamage = dmginfo:GetDamage() * HEADCRAB_PHYS_DAMAGE_SCALE
        dmginfo:SetDamage(scaledDamage)
        if dmginfo:IsDamageType(DMG_FALL) and ent.IsCollapsing then
            ent.HeadcrabPendingFallDamage = (ent.HeadcrabPendingFallDamage or 0) + scaledDamage
        end
    end

    if dmginfo:GetDamage() >= ent:Health() then
        ent.IsInstantKilled = true
        RegisterNPCDeath(ent, true, nil)
        return
    end

    if ent:Health() <= 0 or ent.HeadshotKilled or ent.IsInstantKilled then return end

    if IsZombieNPC(ent) then
        if dmginfo:IsDamageType(DMG_ALWAYSGIB) then
            dmginfo:SetDamageType(bit.band(dmginfo:GetDamageType(), bit.bnot(DMG_ALWAYSGIB)))
        end
        if dmginfo:IsDamageType(DMG_BLAST) then
            dmginfo:SetDamageType(DMG_GENERIC)
        end
    end

    if IsHeadcrabNPC(ent) and dmginfo:IsDamageType(DMG_ALWAYSGIB) then
        local linkedRagdoll = ent.LinkedRagdoll
        if IsValid(linkedRagdoll) then
            timer.Remove("NPC_CollapseTrack_" .. ent:EntIndex())
            timer.Remove("ZombieCrawl_" .. linkedRagdoll:EntIndex())
            timer.Remove("NPCCrawl_" .. linkedRagdoll:EntIndex())
            timer.Remove("ZombineBeep_" .. linkedRagdoll:EntIndex())
            linkedRagdoll.LinkedNPC = nil
            linkedRagdoll:Remove()
        end
    end

    if ent.IsCollapsing then return end

    local damageAmount = dmginfo:GetDamage()
    local isInstantCollapse = damageAmount >= COLLAPSE_INSTANT_DAMAGE
    local isRelevantDamage = dmginfo:IsDamageType(DMG_BUCKSHOT)
        or dmginfo:IsDamageType(DMG_GENERIC)
        or dmginfo:IsDamageType(DMG_BLAST)
        or dmginfo:IsDamageType(DMG_BULLET)
        or dmginfo:IsDamageType(DMG_SLASH)
        or dmginfo:IsDamageType(DMG_CLUB)
        or dmginfo:IsDamageType(DMG_CRUSH)

    if isRelevantDamage then
        local damageStack = AddCollapseDamageStack(ent, damageAmount)
        if isInstantCollapse or damageStack >= COLLAPSE_SHOTGUN_DAMAGE then
            local subduedForce = dmginfo:GetDamageForce() * 0.005
            TriggerDynamicCollapse(ent, subduedForce)
        end
    elseif isInstantCollapse then
        local subduedForce = dmginfo:GetDamageForce() * 0.005
        TriggerDynamicCollapse(ent, subduedForce)
    end
end)

-- Hook 4: Remove Severed Torso Spawns & Detached Headcrabs
hook.Add("OnEntityCreated", "DynamicCollapse_PreventZombieGibsAndHeadcrabs", function(ent)
    if not IsDynamicCollapseEnabled() then return end

    timer.Simple(0, function()
        if not IsValid(ent) then return end
        local cls = string.lower(ent:GetClass() or "")
        
        if cls == "npc_zombie_torso" then
            ent:Remove()
            return
        end

        if string.find(cls, "headcrab") then
            local entPos = ent:GetPos()
            
            for _, ragdoll in ipairs(ents.FindByClass("prop_ragdoll")) do
                if IsValid(ragdoll) and IsValid(ragdoll.LinkedNPC) and ragdoll.LinkedNPC.IsCollapsing then
                    if ragdoll:GetPos():DistToSqr(entPos) < (150 * 150) then
                        local npc = ragdoll.LinkedNPC
                        if IsValid(npc) then
                            local model = npc:GetModel() or ""
                            local isHeadcrabZombie = string.find(string.lower(model), "headcrab") ~= nil
                                or string.find(string.lower(npc:GetClass() or ""), "headcrab") ~= nil

                            if isHeadcrabZombie then
                                local bodygroups = npc:GetBodyGroups()
                                for bodygroup = 0, npc:GetNumBodyGroups() - 1 do
                                    local bodygroupInfo = bodygroups[bodygroup + 1]
                                    local bodygroupName = string.lower(bodygroupInfo and bodygroupInfo.name or "")
                                    if string.find(bodygroupName, "headcrab") ~= nil or string.find(bodygroupName, "head") ~= nil then
                                        npc:SetBodygroup(bodygroup, 1)
                                        if IsValid(ragdoll) then
                                            ragdoll:SetBodygroup(bodygroup, 1)
                                        end
                                    end
                                end
                            end
                        end

                        return
                    end
                end
            end
        end
    end)
end)

-- Hook 5: Targeted VJ Base Ragdoll Cleaner (ONLY affects ragdolls belonging to VJ Base NPCs)
hook.Add("OnEntityCreated", "DynamicCollapse_PreventDuplicateRagdolls", function(ent)
    if not IsDynamicCollapseEnabled() then return end

    if not IsValid(ent) or ent:GetClass() ~= "prop_ragdoll" then return end

    timer.Simple(0, function()
        if not IsValid(ent) then return end

        local entModel = ent:GetModel()
        local entPos = ent:GetPos()

        -- Search specific active NPC death events
        for idx, info in pairs(RecentNPCDeaths) do
            -- STRICTLY apply duplicate/instant-kill ragdoll deletion to VJ Base NPCs ONLY
            if info.isVJ and info.model == entModel and info.pos:DistToSqr(entPos) <= (150 * 150) then
                -- 1. Instant 1-shot kill on VJ NPC: Delete extra VJ corpse
                if info.instant then
                    ent:Remove()
                    return
                end

                -- 2. Duplicate ragdoll check for VJ NPCs: If this NPC already created 1 ragdoll, delete the 2nd one
                if IsValid(info.ragdoll) and info.ragdoll ~= ent then
                    ent:Remove()
                    return
                elseif not IsValid(info.ragdoll) then
                    info.ragdoll = ent
                end
            end
        end
    end)
end)

-- Cleanup: when a ragdoll is removed ensure any transferred bonemerge children are unparented
hook.Add("EntityRemoved", "DynamicCollapse_RagdollChildCleanup", function(ent)
    if not IsDynamicCollapseEnabled() then return end

    if not IsValid(ent) then return end
    if string.lower(ent:GetClass() or "") ~= "prop_ragdoll" then return end

    for _, child in ipairs(ents.FindInSphere(ent:GetPos(), 512)) do
        if not IsValid(child) then continue end
        if child:IsNPC() then continue end
        if child._DynamicCollapse_Transfered and child:GetParent() == ent then
            child:SetParent(nil)
            child._DynamicCollapse_Transfered = nil
            child._DynamicCollapse_OldParent = nil
        end
    end
end)
