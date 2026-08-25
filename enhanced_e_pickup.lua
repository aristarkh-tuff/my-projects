if SERVER then
    util.AddNetworkString("EPickup_Sync")
    util.AddNetworkString("EPickup_TryPickup")
    util.AddNetworkString("EPickup_Drop")
    util.AddNetworkString("EPickup_Throw")
    util.AddNetworkString("EPickup_IgniteFlare")
    util.AddNetworkString("EPickup_ToggleUnweld")
    util.AddNetworkString("EPickup_Rotate")
    util.AddNetworkString("EPickup_Distance")
    util.AddNetworkString("EPickup_Settings")
    util.AddNetworkString("EPickup_RequestSettings")
    util.AddNetworkString("EPickup_SaveSettings")

    -- Realistic Human Carry & Reach Limits
    local MAX_MASS = 120       -- Max weight in kg
    local NO_RUN_MASS = 40
    local MAX_DIMENSION = 120  -- Max size dimension in units
    local MAX_THROW_DIMENSION = 40 -- Props larger than this can be dropped, not thrown
    local MAX_REACH = 90       -- Max reach in units
    local DROP_REACH = MAX_REACH + 5
    local MIN_HOLD_DISTANCE = 45
    local SETTINGS_FILE = "enhanced_prop_pickup/settings.json"
    local pickupSettings = {
        enabled = true,
        unweldEnabled = true,
        staticPropPickupEnabled = false,
        blacklist = {
            prop_vehicle_prisoner_pod = true
        }
    }

    file.CreateDir("enhanced_prop_pickup")
    local savedSettings = util.JSONToTable(file.Read(SETTINGS_FILE, "DATA") or "")
    if istable(savedSettings) then
        if isbool(savedSettings.enabled) then
            pickupSettings.enabled = savedSettings.enabled
        end
        if isbool(savedSettings.unweldEnabled) then
            pickupSettings.unweldEnabled = savedSettings.unweldEnabled
        end
        if isbool(savedSettings.staticPropPickupEnabled) then
            pickupSettings.staticPropPickupEnabled = savedSettings.staticPropPickupEnabled
        end

        if istable(savedSettings.blacklist) then
            pickupSettings.blacklist = {}
            for _, className in pairs(savedSettings.blacklist) do
                if isstring(className) then
                    pickupSettings.blacklist[className] = true
                end
            end
        end
    end

    local function SavePickupSettings()
        local blacklist = {}
        for className in pairs(pickupSettings.blacklist) do
            blacklist[#blacklist + 1] = className
        end
        table.sort(blacklist)
        file.Write(SETTINGS_FILE, util.TableToJSON({
            enabled = pickupSettings.enabled,
            unweldEnabled = pickupSettings.unweldEnabled,
            staticPropPickupEnabled = pickupSettings.staticPropPickupEnabled,
            blacklist = blacklist
        }, true))
    end

    local function SendPickupSettings(target)
        local blacklist = {}
        for className in pairs(pickupSettings.blacklist) do
            blacklist[#blacklist + 1] = className
        end
        table.sort(blacklist)

        net.Start("EPickup_Settings")
            net.WriteBool(pickupSettings.enabled)
            net.WriteBool(pickupSettings.unweldEnabled)
            net.WriteBool(pickupSettings.staticPropPickupEnabled)
            net.WriteUInt(#blacklist, 8)
            for _, className in ipairs(blacklist) do
                net.WriteString(className)
            end
        if target then
            net.Send(target)
        else
            net.Broadcast()
        end
    end

    local function CanEditPickupSettings(ply)
        return game.SinglePlayer() or ply:IsAdmin()
    end

    local function IsValidBlacklistEntry(entry)
        return isstring(entry)
            and #entry > 0
            and #entry <= 96
            and (string.match(entry, "^[%w_]+$") ~= nil
                or string.match(entry, "^models/[%w_/%-%.]+$") ~= nil)
    end

    local function IsConvertibleDebris(ent)
        local className = string.lower(ent:GetClass() or "")
        local model = string.lower(ent:GetModel() or "")
        local isDebris = string.find(className, "gib", 1, true) ~= nil
            or string.find(className, "debris", 1, true) ~= nil
            or string.find(model, "gib", 1, true) ~= nil
            or string.find(model, "debris", 1, true) ~= nil
        local isNonPhysicsFlare = string.find(model, "flare", 1, true) ~= nil
            and className ~= "prop_physics"
            and className ~= "prop_physics_multiplayer"

        return isDebris or isNonPhysicsFlare
    end

    local function IsStaticProp(ent)
        local className = string.lower(ent:GetClass() or "")
        return className == "prop_static"
            or className == "func_detail"
            or ent:GetMoveType() == MOVETYPE_NONE
    end

    local function ConvertToPhysicsProp(ent)
        if not IsValid(ent) or ent.EnhancedE_Converted then return end

        local model = ent:GetModel()
        if not isstring(model) or model == "" or not util.IsValidModel(model) then return end

        local position = ent:GetPos()
        local angles = ent:GetAngles()
        local velocity = ent:GetVelocity()
        local oldPhys = ent:GetPhysicsObject()
        local angularVelocity = IsValid(oldPhys) and oldPhys:GetAngleVelocity() or vector_origin
        local wasOnFire = ent:IsOnFire()
        local replacement = ents.Create("prop_physics")
        if not IsValid(replacement) then return end

        replacement.EnhancedE_Converted = true
        replacement:SetModel(model)
        replacement:SetPos(position)
        replacement:SetAngles(angles)
        replacement:Spawn()
        replacement:Activate()
        replacement:SetSkin(ent:GetSkin() or 0)
        replacement:SetColor(ent:GetColor())

        local phys = replacement:GetPhysicsObject()
        if not IsValid(phys) then
            replacement:Remove()
            return
        end

        phys:SetVelocity(velocity)
        phys:AddAngleVelocity(angularVelocity)
        if wasOnFire then
            replacement:Ignite(30)
        end

        ent:Remove()
    end

    local function GetPhysicsEntity(ent)
        if not IsValid(ent) then return nil end

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then return ent end

        local model = ent:GetModel()
        if not isstring(model) or model == "" or not util.IsValidModel(model) then return nil end
        local isFlare = string.find(string.lower(model), "flare", 1, true) ~= nil
        if ent:IsPlayer() or ent:IsNPC() or (ent:IsWeapon() and not isFlare) then return nil end
        if IsStaticProp(ent) and not pickupSettings.staticPropPickupEnabled and not isFlare then return nil end

        local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
        local size = maxs - mins
        if math.max(size.x, size.y, size.z) > MAX_DIMENSION then return nil end

        local position = ent:GetPos()
        local angles = ent:GetAngles()
        local velocity = ent:GetVelocity()
        local oldPhys = ent:GetPhysicsObject()
        local angularVelocity = IsValid(oldPhys) and oldPhys:GetAngleVelocity() or vector_origin
        local wasOnFire = ent:IsOnFire()
        local replacement = ents.Create("prop_physics")
        if not IsValid(replacement) then return nil end

        replacement.EnhancedE_Converted = true
        replacement:SetModel(model)
        replacement:SetPos(position)
        replacement:SetAngles(angles)
        replacement:Spawn()
        replacement:Activate()
        replacement:SetSkin(ent:GetSkin() or 0)
        replacement:SetColor(ent:GetColor())
        replacement:SetCollisionGroup(COLLISION_GROUP_NONE)

        local replacementPhys = replacement:GetPhysicsObject()
        if not IsValid(replacementPhys) then
            replacement:Remove()
            return nil
        end

        replacementPhys:SetVelocity(velocity)
        replacementPhys:AddAngleVelocity(angularVelocity)
        replacementPhys:EnableGravity(true)
        if wasOnFire then replacement:Ignite(30) end
        ent:Remove()
        return replacement
    end

    hook.Add("OnEntityCreated", "EnhancedE_ConvertDebris", function(ent)
        timer.Simple(0, function()
            if IsValid(ent) and IsConvertibleDebris(ent) then
                ConvertToPhysicsProp(ent)
            end
        end)
    end)

    -- Disable standard engine pickup
    hook.Add("AllowPlayerPickup", "EnhancedE_DisableDefault", function(ply, ent)
        if pickupSettings.enabled then
            return false
        end
    end)

    local function RestoreWeaponVisibility(ply)
        if IsValid(ply.EnhancedE_HiddenWep) then
            ply.EnhancedE_HiddenWep:SetNoDraw(false)
            ply.EnhancedE_HiddenWep = nil
        end
    end

    local function HideActiveWeapon(ply)
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) then
            if ply.EnhancedE_HiddenWep ~= wep then
                RestoreWeaponVisibility(ply)
            end
            wep:SetNoDraw(true)
            ply.EnhancedE_HiddenWep = wep
        end
    end

    local function RestoreCarryMovement(ply)
        if ply.EnhancedE_BaseWalkSpeed then
            ply:SetWalkSpeed(ply.EnhancedE_BaseWalkSpeed)
            ply:SetRunSpeed(ply.EnhancedE_BaseRunSpeed)
            ply.EnhancedE_BaseWalkSpeed = nil
            ply.EnhancedE_BaseRunSpeed = nil
        end
        ply.EnhancedE_CarryMass = nil
    end

    local function ApplyCarryMovement(ply, mass)
        ply.EnhancedE_BaseWalkSpeed = ply:GetWalkSpeed()
        ply.EnhancedE_BaseRunSpeed = ply:GetRunSpeed()
        ply.EnhancedE_CarryMass = mass

        local speedScale = math.Clamp(1 - mass / (MAX_MASS * 1.5), 0.35, 1)
        local walkSpeed = ply.EnhancedE_BaseWalkSpeed * speedScale
        local runSpeed = ply.EnhancedE_BaseRunSpeed * speedScale

        if mass > NO_RUN_MASS then
            runSpeed = walkSpeed
        end

        ply:SetWalkSpeed(walkSpeed)
        ply:SetRunSpeed(runSpeed)
    end

    local function IsPropUnderPlayer(ply, propPos, propAng, mins, maxs)
        local propMins = Vector(math.huge, math.huge, math.huge)
        local propMaxs = Vector(-math.huge, -math.huge, -math.huge)
        local axes = {
            propAng:Forward(),
            propAng:Right(),
            propAng:Up()
        }

        for x = 0, 1 do
            for y = 0, 1 do
                for z = 0, 1 do
                    local corner = Vector(
                        x == 0 and mins.x or maxs.x,
                        y == 0 and mins.y or maxs.y,
                        z == 0 and mins.z or maxs.z
                    )
                    local worldCorner = propPos
                        + axes[1] * corner.x
                        + axes[2] * corner.y
                        + axes[3] * corner.z

                    propMins.x = math.min(propMins.x, worldCorner.x)
                    propMins.y = math.min(propMins.y, worldCorner.y)
                    propMins.z = math.min(propMins.z, worldCorner.z)
                    propMaxs.x = math.max(propMaxs.x, worldCorner.x)
                    propMaxs.y = math.max(propMaxs.y, worldCorner.y)
                    propMaxs.z = math.max(propMaxs.z, worldCorner.z)
                end
            end
        end

        local playerMins, playerMaxs = ply:WorldSpaceAABB()
        local propIsOverPlayer = propMaxs.x > playerMins.x
            and propMins.x < playerMaxs.x
            and propMaxs.y > playerMins.y
            and propMins.y < playerMaxs.y
        local propTopDistance = playerMins.z - propMaxs.z

        local propReachesPlayer = propTopDistance >= -4

        return propIsOverPlayer and propReachesPlayer
    end

    local function DropProp(ply)
        local ent = ply.EnhancedE_Ent
        if IsValid(ent) then
            ent:SetCustomCollisionCheck(false)
            ent:CollisionRulesChanged()
        end
        RestoreCarryMovement(ply)
        ply.EnhancedE_Ent = nil
        ply.EnhancedE_RelMat = nil
        ply.EnhancedE_PickupCooldown = CurTime() + 0.4
        RestoreWeaponVisibility(ply)
        net.Start("EPickup_Sync")
            net.WriteEntity(NULL)
        net.Send(ply)
    end

    local function ThrowProp(ply, charge)
        local ent = ply.EnhancedE_Ent
        if IsValid(ent) then
            ent:SetCustomCollisionCheck(false)
            ent:CollisionRulesChanged()
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
                local size = maxs - mins
                local maxDim = math.max(size.x, size.y, size.z)
                if maxDim <= MAX_THROW_DIMENSION then
                    local massScale = math.Clamp(1 - phys:GetMass() / (MAX_MASS * 2), 0.35, 1)
                    local sizeScale = math.Clamp(1 - maxDim / (MAX_DIMENSION * 2), 0.5, 1)
                    local throwScale = 1 + math.Clamp(tonumber(charge) or 0, 0, 1) * 2.2
                    local throwSpeed = 260 * throwScale * massScale * sizeScale
                    local throwVel = ply:GetAimVector() * throwSpeed + ply:GetVelocity() * 0.5
                    phys:SetVelocity(throwVel)
                    phys:AddAngleVelocity(VectorRand() * 40)
                end
            end
            RestoreCarryMovement(ply)
            ply.EnhancedE_Ent = nil
            ply.EnhancedE_RelMat = nil
            ply.EnhancedE_PickupCooldown = CurTime() + 0.4
            ply.EnhancedE_WaitAttackRelease = true
            RestoreWeaponVisibility(ply)
            net.Start("EPickup_Sync")
                net.WriteEntity(NULL)
            net.Send(ply)
        end
    end

    net.Receive("EPickup_RequestSettings", function(_, ply)
        if IsValid(ply) then
            SendPickupSettings(ply)
        end
    end)

    net.Receive("EPickup_SaveSettings", function(_, ply)
        if not IsValid(ply) or not CanEditPickupSettings(ply) then return end

        local enabled = net.ReadBool()
        local unweldEnabled = net.ReadBool()
        local staticPropPickupEnabled = net.ReadBool()
        local blacklist = {}
        local blacklistCount = math.min(net.ReadUInt(8), 128)
        for _ = 1, blacklistCount do
            local entry = string.lower(string.Trim(net.ReadString()))
            if IsValidBlacklistEntry(entry) then
                blacklist[entry] = true
            end
        end

        pickupSettings.enabled = enabled
        pickupSettings.unweldEnabled = unweldEnabled
        pickupSettings.staticPropPickupEnabled = staticPropPickupEnabled
        pickupSettings.blacklist = blacklist
        SavePickupSettings()
        SendPickupSettings()

        if not pickupSettings.enabled then
            for _, player in ipairs(player.GetAll()) do
                if IsValid(player.EnhancedE_Ent) or player.EnhancedE_BaseWalkSpeed then
                    DropProp(player)
                end
            end
        end
    end)

    hook.Add("PlayerInitialSpawn", "EnhancedE_SendSettings", function(ply)
        timer.Simple(0, function()
            if IsValid(ply) then
                SendPickupSettings(ply)
            end
        end)
    end)

    hook.Add("PlayerDeath", "EnhancedE_DropOnDeath", function(ply)
        if IsValid(ply.EnhancedE_Ent) then DropProp(ply) end
    end)

    hook.Add("CreateEntityRagdoll", "EnhancedE_DropOnRagdoll", function(ent)
        if IsValid(ent) and ent:IsPlayer() and IsValid(ent.EnhancedE_Ent) then
            DropProp(ent)
        end
    end)

    hook.Add("ShouldCollide", "EnhancedE_NoHolderCollision", function(ent1, ent2)
        if not IsValid(ent1) or not IsValid(ent2) then return end
        if ent1:IsPlayer() and ent1.EnhancedE_Ent == ent2 then
            return false
        end
        if ent2:IsPlayer() and ent2.EnhancedE_Ent == ent1 then
            return false
        end
    end)

    hook.Add("EntityTakeDamage", "EnhancedE_NoHeldPropDamage", function(target, damageInfo)
        if not target:IsPlayer() then return end

        local heldEnt = target.EnhancedE_Ent
        if not IsValid(heldEnt) then return end

        local attacker = damageInfo:GetAttacker()
        if IsValid(attacker)
            and attacker:GetClass() == "npc_zombie"
            and damageInfo:IsDamageType(DMG_SLASH) then
            DropProp(target)
            return
        end

        if damageInfo:GetAttacker() == heldEnt or damageInfo:GetInflictor() == heldEnt then
            return true
        end
    end)

    -- Pickup Request Handler
    net.Receive("EPickup_TryPickup", function(len, ply)
        if not pickupSettings.enabled then return end
        if ply:InVehicle() then return end
        if IsValid(ply.EnhancedE_Ent) then return end
        if ply.EnhancedE_PickupCooldown and CurTime() < ply.EnhancedE_PickupCooldown then return end

        local ent = net.ReadEntity()
        if not IsValid(ent) then return end
        if ent:IsWorld() or ent:IsPlayer() then return end
        if pickupSettings.blacklist[ent:GetClass()]
            or pickupSettings.blacklist[string.lower(ent:GetModel() or "")] then
            return
        end
        if ent:IsNPC() and ent:GetClass() ~= "npc_turret_floor" then return end

        ent = GetPhysicsEntity(ent)
        if not IsValid(ent) then return end
        
        -- Use NearestPoint to account for prop size, add +10 for network tolerance
        if ply:GetShootPos():Distance(ent:NearestPoint(ply:GetShootPos())) > (MAX_REACH + 10) then return end

        local phys = ent:GetPhysicsObject()
        local isStatic = IsStaticProp(ent)
        if not phys:IsMoveable() then
            if not isStatic or not pickupSettings.staticPropPickupEnabled then return end
        end

        if ent:GetClass() == "npc_turret_floor" then
            local pickupAngles = ent:GetAngles()
            pickupAngles.p = 0
            pickupAngles.r = 0
            ent:SetAngles(pickupAngles)
            phys:SetAngles(pickupAngles)
        end

        local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
        local size = maxs - mins
        if phys:GetMass() > MAX_MASS then return end

        local maxDim = math.max(size.x, size.y, size.z)
        if maxDim > MAX_DIMENSION then return end

        if not phys:IsMoveable() then
            phys:EnableMotion(true)
            phys:Wake()
        end

        ent:SetCustomCollisionCheck(true)
        ent:SetCollisionGroup(COLLISION_GROUP_NONE)
        ent:CollisionRulesChanged()
        phys:EnableGravity(true)
        if string.find(string.lower(ent:GetModel() or ""), "flare", 1, true) then
            ent:Extinguish()
        end
        ply.EnhancedE_Ent = ent
        ApplyCarryMovement(ply, phys:GetMass())
        
        local plyMat = Matrix()
        plyMat:SetAngles(ply:EyeAngles())

        local entMat = Matrix()
        entMat:SetAngles(ent:GetAngles())

        ply.EnhancedE_RelMat = plyMat:GetInverse() * entMat

        local currentDist = ply:GetShootPos():Distance(ent:NearestPoint(ply:GetShootPos()))
        local radius = size:Length() * 0.3
        local minDist = math.Clamp(10 + radius, MIN_HOLD_DISTANCE, 70)
        
        ply.EnhancedE_Dist = math.Clamp(currentDist, minDist, MAX_REACH)

        HideActiveWeapon(ply)

        net.Start("EPickup_Sync")
            net.WriteEntity(ent)
        net.Send(ply)
    end)

    net.Receive("EPickup_Drop", function(len, ply) DropProp(ply) end)
    net.Receive("EPickup_Throw", function(len, ply)
        if pickupSettings.enabled then
            ThrowProp(ply, len >= 32 and net.ReadFloat() or 0)
        end
    end)

    net.Receive("EPickup_IgniteFlare", function(_, ply)
        if not pickupSettings.enabled then return end

        local ent = ply.EnhancedE_Ent
        if IsValid(ent) and string.find(string.lower(ent:GetModel() or ""), "flare", 1, true) then
            ent:Ignite(30)
        end
    end)

    net.Receive("EPickup_ToggleUnweld", function(_, ply)
        if not pickupSettings.enabled or not pickupSettings.unweldEnabled then return end

        local ent = ply.EnhancedE_Ent
        if not IsValid(ent) then return end

        constraint.RemoveAll(ent)
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableGravity(true)
        end
    end)

    net.Receive("EPickup_Rotate", function(len, ply)
        if not pickupSettings.enabled then return end
        if not IsValid(ply.EnhancedE_Ent) then return end
        
        local eyeAng = ply:EyeAngles()

        if not ply.EnhancedE_RelMat then
            local pMat = Matrix()
            pMat:SetAngles(eyeAng)
            local eMat = Matrix()
            eMat:SetAngles(ply.EnhancedE_Ent:GetAngles())
            ply.EnhancedE_RelMat = pMat:GetInverse() * eMat
        end

        local dx = net.ReadFloat()
        local dy = net.ReadFloat()

        local currentPlyMat = Matrix()
        currentPlyMat:SetAngles(eyeAng)

        local worldMat = currentPlyMat * ply.EnhancedE_RelMat
        local worldAng = worldMat:GetAngles()

        worldAng:RotateAroundAxis(eyeAng:Up(), -dx * 0.035)
        worldAng:RotateAroundAxis(eyeAng:Right(), dy * 0.035)

        local newWorldMat = Matrix()
        newWorldMat:SetAngles(worldAng)

        ply.EnhancedE_RelMat = currentPlyMat:GetInverse() * newWorldMat
    end)

    net.Receive("EPickup_Distance", function(len, ply)
        if not pickupSettings.enabled then return end
        local ent = ply.EnhancedE_Ent
        if not IsValid(ent) then return end

        local delta = net.ReadFloat()
        local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
        local radius = (maxs - mins):Length() * 0.3

        local minDist = math.Clamp(10 + radius, MIN_HOLD_DISTANCE, 70)
        local maxDist = MAX_REACH

        local currentDist = ply.EnhancedE_Dist or 55
        ply.EnhancedE_Dist = math.Clamp(currentDist + delta, minDist, maxDist)
    end)

    hook.Add("StartCommand", "EnhancedE_BlockWeaponsServer", function(ply, cmd)
        if not pickupSettings.enabled then return end
        if ply.EnhancedE_WaitAttackRelease then
            if cmd:KeyDown(IN_ATTACK) then
                cmd:RemoveKey(IN_ATTACK)
                local wep = ply:GetActiveWeapon()
                if IsValid(wep) then
                    wep:SetNextPrimaryFire(CurTime() + 0.1)
                end
            else
                ply.EnhancedE_WaitAttackRelease = false
            end
        end

        if IsValid(ply.EnhancedE_Ent) then
            cmd:RemoveKey(IN_ATTACK)
            cmd:RemoveKey(IN_ATTACK2)
            cmd:RemoveKey(IN_USE)

            if (ply.EnhancedE_CarryMass or 0) > NO_RUN_MASS then
                cmd:RemoveKey(IN_SPEED)
            end

            local wep = ply:GetActiveWeapon()
            if IsValid(wep) then
                wep:SetNextPrimaryFire(CurTime() + 0.1)
                wep:SetNextSecondaryFire(CurTime() + 0.1)
            end
        end
    end)

    hook.Add("Tick", "EnhancedE_PhysicsTick", function()
        if not pickupSettings.enabled then return end
        for _, ply in ipairs(player.GetAll()) do
            local ent = ply.EnhancedE_Ent
            if IsValid(ent) then
                if ply:GetShootPos():Distance(ent:NearestPoint(ply:GetShootPos())) > DROP_REACH then
                    DropProp(ply)
                    continue
                end

                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    local eyeAng = ply:EyeAngles()
                    local desiredCenter = ply:GetShootPos() + ply:GetAimVector() * ply.EnhancedE_Dist

                    local wallTrace = util.TraceLine({
                        start = ply:GetShootPos(),
                        endpos = ent:GetPos(),
                        filter = {ply, ent},
                        mask = MASK_SOLID_BRUSHONLY
                    })
                    if wallTrace.Hit then
                        DropProp(ply)
                        continue
                    end
                    
                    HideActiveWeapon(ply)

                    if not ply.EnhancedE_RelMat then
                        local pMat = Matrix()
                        pMat:SetAngles(eyeAng)
                        local eMat = Matrix()
                        eMat:SetAngles(ent:GetAngles())
                        ply.EnhancedE_RelMat = pMat:GetInverse() * eMat
                    end

                    local currentPlyMat = Matrix()
                    currentPlyMat:SetAngles(eyeAng)
                    local targetWorldMat = currentPlyMat * ply.EnhancedE_RelMat
                    local targetWorldAng = targetWorldMat:GetAngles()

                    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
                    local localCenter = (mins + maxs) * 0.5
                    local targetCenterWorld = desiredCenter
                    local targetPos = targetCenterWorld
                        - targetWorldAng:Forward() * localCenter.x
                        - targetWorldAng:Right() * localCenter.y
                        - targetWorldAng:Up() * localCenter.z

                    if IsPropUnderPlayer(ply, targetPos, targetWorldAng, mins, maxs) then
                        DropProp(ply)
                        continue
                    end

                    local isRagdoll = ent:GetClass() == "prop_ragdoll"
                    local shadowParams = {
                        secondstoarrive = isRagdoll and 0.18 or 0.08,
                        pos = targetPos,
                        angle = targetWorldAng,
                        maxangular = isRagdoll and 350 or 1000,
                        maxangulardamp = isRagdoll and 3000 or 10000,
                        maxspeed = isRagdoll and 500 or 800,
                        maxspeeddamp = isRagdoll and 700 or 1000,
                        dampfactor = isRagdoll and 0.92 or 0.8,
                        teleportdistance = 0,
                        deltatime = engine.TickInterval()
                    }

                    phys:ComputeShadowControl(shadowParams)
                    phys:Wake()
                else
                    DropProp(ply)
                end
            else
                if ply.EnhancedE_Ent then
                    DropProp(ply)
                else
                    RestoreWeaponVisibility(ply)
                end
            end
        end
    end)
end

if CLIENT then
    local MAX_REACH = 90
    local MAX_THROW_DIMENSION = 40
    local pickupEnabled = true
    local unweldEnabled = true
    local staticPropPickupEnabled = false
    local pickupBlacklist = {}

    net.Receive("EPickup_Settings", function()
        pickupEnabled = net.ReadBool()
        unweldEnabled = net.ReadBool()
        staticPropPickupEnabled = net.ReadBool()
        pickupBlacklist = {}
        for _ = 1, net.ReadUInt(8) do
            pickupBlacklist[net.ReadString()] = true
        end
    end)

    hook.Add("InitPostEntity", "EnhancedE_RequestSettings", function()
        net.Start("EPickup_RequestSettings")
        net.SendToServer()
    end)

    local function IsEnhancedPickupEnabled()
        return pickupEnabled
    end
    local heldEnt = nil
    local isRotating = false
    local attack2Down = false
    local useDown = false
    local reloadDown = false
    local waitAttackRelease = false
        local attackDown = false
        local attackChargeStart = 0
        local attackCharging = false
        local flareIgnited = false
    local pressTime = 0
    local pickupCooldown = 0
    local targetLockedAng = Angle(0, 0, 0)
    local smoothLockedAng = Angle(0, 0, 0)
    local HOLD_THRESHOLD = 0.18

    local function RestoreClientWeapon()
        local ply = LocalPlayer()
        if IsValid(ply) then
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) then
                wep:SetNoDraw(false)
            end
        end
    end

    net.Receive("EPickup_Sync", function()
        heldEnt = net.ReadEntity()
        if not IsValid(heldEnt) then
            isRotating = false
            attack2Down = false
            useDown = false
            reloadDown = false
            attackDown = false
            attackCharging = false
            flareIgnited = false
            pickupCooldown = CurTime() + 0.4
            RestoreClientWeapon()
        end
    end)

    hook.Add("PreDrawViewModel", "EnhancedE_HideViewModel", function(vm, ply, wep)
        if IsEnhancedPickupEnabled() and IsValid(heldEnt) then
            if IsValid(wep) then
                wep:SetNoDraw(true)
            end
            return true
        end
    end)

    hook.Add("PreDrawPlayerHands", "EnhancedE_HideHands", function(hands, vm, ply, wep)
        if IsEnhancedPickupEnabled() and IsValid(heldEnt) then return true end
    end)

    hook.Add("DrawPhysgunBeam", "EnhancedE_HidePhysgunBeam", function(ply, wep, enabled, target, bone, hitPos)
        if IsEnhancedPickupEnabled() and IsValid(heldEnt) and ply == LocalPlayer() then return false end
    end)

    hook.Add("PlayerBindPress", "EnhancedE_BlockWeaponSwitch", function(ply, bind, pressed)
        if IsEnhancedPickupEnabled() and IsValid(heldEnt) and attack2Down then
            if string.find(bind, "invnext") or string.find(bind, "invprev") or string.find(bind, "slot") then
                return true
            end
        end
    end)

    hook.Add("StartCommand", "EnhancedE_StartCommand", function(ply, cmd)
        if not IsEnhancedPickupEnabled() then return end
        if waitAttackRelease then
            if cmd:KeyDown(IN_ATTACK) then
                cmd:RemoveKey(IN_ATTACK)
                local wep = ply:GetActiveWeapon()
                if IsValid(wep) then
                    wep:SetNextPrimaryFire(CurTime() + 0.1)
                end
            else
                waitAttackRelease = false
            end
        end

        local isUsePressed = cmd:KeyDown(IN_USE)

        if isUsePressed and not useDown then
            useDown = true
            if IsValid(heldEnt) then
                cmd:RemoveKey(IN_USE)
                pickupCooldown = CurTime() + 0.4
                net.Start("EPickup_Drop")
                net.SendToServer()
                return
            else
                if CurTime() < pickupCooldown then return end

                local tr = ply:GetEyeTrace()
                local ent = tr.Entity
                
                -- Removed unreliable client-side physics check here so it works instantly after restarts
                if IsValid(ent) and not ent:IsWorld() and not ent:IsPlayer()
                    and (not ent:IsNPC() or ent:GetClass() == "npc_turret_floor") then
                    if tr.HitPos:Distance(ply:GetShootPos()) <= MAX_REACH then
                        cmd:RemoveKey(IN_USE)
                        net.Start("EPickup_TryPickup")
                            net.WriteEntity(ent)
                        net.SendToServer()
                        return
                    end
                end
            end
        elseif not isUsePressed then
            useDown = false
        end

        if not IsValid(heldEnt) then return end

        cmd:RemoveKey(IN_USE)

        local isReload = cmd:KeyDown(IN_RELOAD)
        if isReload and not reloadDown then
            reloadDown = true
            if unweldEnabled then
                cmd:RemoveKey(IN_RELOAD)
                net.Start("EPickup_ToggleUnweld")
                net.SendToServer()
            end
        elseif not isReload then
            reloadDown = false
        end

            local isAttack = cmd:KeyDown(IN_ATTACK)
            if isAttack and not attackDown then
                attackDown = true
                attackChargeStart = CurTime()
                attackCharging = false
                flareIgnited = false
            end

            if isAttack then
            cmd:RemoveKey(IN_ATTACK)
                local heldFor = CurTime() - attackChargeStart
                if heldFor >= HOLD_THRESHOLD then
                    attackCharging = true
                    if string.find(string.lower(heldEnt:GetModel() or ""), "flare", 1, true) and not flareIgnited then
                        flareIgnited = true
                        net.Start("EPickup_IgniteFlare")
                        net.SendToServer()
                    end
                end
            elseif attackDown then
                local heldFor = CurTime() - attackChargeStart
                local charge = 0
                if attackCharging and not string.find(string.lower(heldEnt:GetModel() or ""), "flare", 1, true) then
                    charge = math.Clamp((heldFor - HOLD_THRESHOLD) / 1, 0, 1)
                end

                attackDown = false
                attackCharging = false
                flareIgnited = false
                net.Start("EPickup_Throw")
                    net.WriteFloat(charge)
                net.SendToServer()
                heldEnt = nil
                isRotating = false
                attack2Down = false
                waitAttackRelease = true
                pickupCooldown = CurTime() + 0.4
                RestoreClientWeapon()
                return
        end

        local isAttack2 = cmd:KeyDown(IN_ATTACK2)
        cmd:RemoveKey(IN_ATTACK2)

        local wep = ply:GetActiveWeapon()
        if IsValid(wep) then
            wep:SetNextPrimaryFire(CurTime() + 0.1)
            wep:SetNextSecondaryFire(CurTime() + 0.1)
        end

        if isAttack2 and not attack2Down then
            attack2Down = true
            pressTime = CurTime()
        end

        if attack2Down and isAttack2 then
            if (CurTime() - pressTime) >= HOLD_THRESHOLD then
                if not isRotating then
                    isRotating = true
                    targetLockedAng = ply:EyeAngles()
                    smoothLockedAng = ply:EyeAngles()
                end
            end

            local wheel = cmd:GetMouseWheel()
            if wheel ~= 0 then
                local delta = (wheel > 0) and 4 or -4
                net.Start("EPickup_Distance")
                    net.WriteFloat(delta)
                net.SendToServer()
            end
        end

        if not isAttack2 and attack2Down then
            attack2Down = false
            if isRotating then
                isRotating = false
            else
                pickupCooldown = CurTime() + 0.4
                net.Start("EPickup_Drop")
                net.SendToServer()
            end
        end
    end)

    hook.Add("InputMouseApply", "EnhancedE_LockCamera", function(cmd, x, y, ang)
        if IsEnhancedPickupEnabled() and IsValid(heldEnt) and isRotating then
            if x ~= 0 or y ~= 0 then
                net.Start("EPickup_Rotate")
                    net.WriteFloat(x)
                    net.WriteFloat(y)
                net.SendToServer()
            end

            smoothLockedAng = LerpAngle(FrameTime() * 25, smoothLockedAng, targetLockedAng)
            cmd:SetViewAngles(smoothLockedAng)
            return true
        end
    end)

        hook.Add("HUDPaint", "EnhancedE_ThrowCharge", function()
            if not IsEnhancedPickupEnabled() or not IsValid(heldEnt) or not attackCharging then return end
            if string.find(string.lower(heldEnt:GetModel() or ""), "flare", 1, true) then return end

            local mins, maxs = heldEnt:OBBMins(), heldEnt:OBBMaxs()
            local size = maxs - mins
            if math.max(size.x, size.y, size.z) > MAX_THROW_DIMENSION then return end

            local charge = math.Clamp((CurTime() - attackChargeStart - HOLD_THRESHOLD) / 1, 0, 1)
            local width, height = 260, 22
            local x, y = (ScrW() - width) * 0.5, ScrH() - 110
            local color = Color(255, 210 - 210 * charge, 0, 255)
            surface.SetDrawColor(20, 20, 20, 220)
            surface.DrawRect(x - 3, y - 3, width + 6, height + 6)
            surface.SetDrawColor(color)
            surface.DrawRect(x, y, width * charge, height)
            draw.SimpleText("THROW POWER", "DermaDefaultBold", ScrW() * 0.5, y - 18, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end)

    local function SavePickupSettings(enabled, unweld, staticProps, blacklist)
        local classNames = {}
        for className in pairs(blacklist) do
            classNames[#classNames + 1] = className
        end
        table.sort(classNames)

        net.Start("EPickup_SaveSettings")
            net.WriteBool(enabled)
            net.WriteBool(unweld)
            net.WriteBool(staticProps)
            net.WriteUInt(math.min(#classNames, 128), 8)
            for index = 1, math.min(#classNames, 128) do
                net.WriteString(classNames[index])
            end
        net.SendToServer()
    end

    hook.Add("PopulateToolMenu", "EnhancedE_PopulateOptions", function()
        spawnmenu.AddToolMenuOption("Options", "Enhanced Prop Pickup", "Enhanced Prop Pickup",
            "Enhanced Prop Pickup", "", "", function(panel)
            panel:ClearControls()

            local canEdit = game.SinglePlayer() or LocalPlayer():IsAdmin()
            panel:Help(canEdit and "Enhanced prop pickup settings" or "Only server admins can edit these settings")

            local enabledCheck = panel:CheckBox("Enable enhanced prop pickup")
            enabledCheck:SetValue(pickupEnabled and 1 or 0)
            enabledCheck:SetEnabled(canEdit)
            enabledCheck.OnChange = function(_, value)
                if canEdit then
                    pickupEnabled = value
                    SavePickupSettings(pickupEnabled, unweldEnabled, staticPropPickupEnabled, pickupBlacklist)
                end
            end

            local unweldCheck = panel:CheckBox("Allow reload key to unweld held props")
            unweldCheck:SetValue(unweldEnabled and 1 or 0)
            unweldCheck:SetEnabled(canEdit)
            unweldCheck.OnChange = function(_, value)
                if canEdit then
                    unweldEnabled = value
                    SavePickupSettings(pickupEnabled, unweldEnabled, staticPropPickupEnabled, pickupBlacklist)
                end
            end

            local staticPropCheck = panel:CheckBox("Allow pickup of frozen map props")
            staticPropCheck:SetValue(staticPropPickupEnabled and 1 or 0)
            staticPropCheck:SetEnabled(canEdit)
            staticPropCheck.OnChange = function(_, value)
                if canEdit then
                    staticPropPickupEnabled = value
                    SavePickupSettings(pickupEnabled, unweldEnabled, staticPropPickupEnabled, pickupBlacklist)
                end
            end

            panel:Help("Add an entity class or model path to block it from pickup")
            local blacklistList = vgui.Create("DListView")
            blacklistList:AddColumn("Entity class or model")
            blacklistList:SetTall(160)
            for className in pairs(pickupBlacklist) do
                blacklistList:AddLine(className)
            end
            panel:AddItem(blacklistList)

            local classEntry = panel:TextEntry("Entity class or model path")
            classEntry:SetEnabled(canEdit)

            local addButton = panel:Button("Add to blacklist")
            addButton:SetEnabled(canEdit)
            addButton.DoClick = function()
                local className = string.lower(string.Trim(classEntry:GetValue()))
                local isClass = string.match(className, "^[%w_]+$") ~= nil
                local isModel = string.match(className, "^models/[%w_/%-%.]+$") ~= nil
                if not isClass and not isModel then return end
                if pickupBlacklist[className] then return end

                pickupBlacklist[className] = true
                blacklistList:AddLine(className)
                classEntry:SetValue("")
                SavePickupSettings(pickupEnabled, unweldEnabled, staticPropPickupEnabled, pickupBlacklist)
            end

            local removeButton = panel:Button("Remove selected")
            removeButton:SetEnabled(canEdit)
            removeButton.DoClick = function()
                local selected = blacklistList:GetSelected()[1]
                if not IsValid(selected) then return end

                local className = selected:GetValue(1)
                pickupBlacklist[className] = nil
                blacklistList:RemoveLine(selected:GetID())
                SavePickupSettings(pickupEnabled, unweldEnabled, staticPropPickupEnabled, pickupBlacklist)
            end
            end)
        end)
end
