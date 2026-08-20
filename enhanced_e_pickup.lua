if SERVER then
    util.AddNetworkString("EPickup_Sync")
    util.AddNetworkString("EPickup_TryPickup")
    util.AddNetworkString("EPickup_Drop")
    util.AddNetworkString("EPickup_Throw")
    util.AddNetworkString("EPickup_Rotate")
    util.AddNetworkString("EPickup_Distance")

    -- Realistic Human Carry & Reach Limits
    local MAX_MASS = 120       -- Max weight in kg
    local MAX_DIMENSION = 120  -- Max size dimension in units
    local MAX_REACH = 90       -- Max reach in units
    local DROP_REACH = MAX_REACH + 5
    local MIN_HOLD_DISTANCE = 45
    local enhancedPickupEnabled = CreateConVar("enhancede_enabled", "1", {
        FCVAR_ARCHIVE,
        FCVAR_NOTIFY,
        FCVAR_REPLICATED,
        FCVAR_SERVER_CAN_EXECUTE
    }, "Enable the enhanced prop pickup system")

    -- Disable standard engine pickup
    hook.Add("AllowPlayerPickup", "EnhancedE_DisableDefault", function(ply, ent)
        if enhancedPickupEnabled:GetBool() then
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

    local function DropProp(ply)
        ply.EnhancedE_Ent = nil
        ply.EnhancedE_RelMat = nil
        ply.EnhancedE_PickupCooldown = CurTime() + 0.4
        RestoreWeaponVisibility(ply)
        net.Start("EPickup_Sync")
            net.WriteEntity(NULL)
        net.Send(ply)
    end

    local function ThrowProp(ply)
        local ent = ply.EnhancedE_Ent
        if IsValid(ent) then
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                local throwVel = ply:GetAimVector() * 260 + ply:GetVelocity() * 0.5
                phys:SetVelocity(throwVel)
                phys:AddAngleVelocity(VectorRand() * 40)
            end
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

    cvars.AddChangeCallback("enhancede_enabled", function(_, _, newValue)
        if tonumber(newValue) == 0 then
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply.EnhancedE_Ent) then
                    DropProp(ply)
                end
            end
        end
    end, "EnhancedE_Toggle")

    hook.Add("PlayerDeath", "EnhancedE_DropOnDeath", function(ply)
        if IsValid(ply.EnhancedE_Ent) then DropProp(ply) end
    end)

    hook.Add("CreateEntityRagdoll", "EnhancedE_DropOnRagdoll", function(ent)
        if ent:IsPlayer() and IsValid(ent.EnhancedE_Ent) then
            DropProp(ent)
        end
    end)

    hook.Add("ShouldCollide", "EnhancedE_NoHolderCollision", function(ent1, ent2)
        if not IsValid(ent1) or not IsValid(ent2) then return end
        if ent1:IsPlayer() and ent1.EnhancedE_Ent == ent2 then return false end
        if ent2:IsPlayer() and ent2.EnhancedE_Ent == ent1 then return false end
    end)

    -- Pickup Request Handler
    net.Receive("EPickup_TryPickup", function(len, ply)
        if not enhancedPickupEnabled:GetBool() then return end
        if IsValid(ply.EnhancedE_Ent) then return end
        if ply.EnhancedE_PickupCooldown and CurTime() < ply.EnhancedE_PickupCooldown then return end

        local ent = net.ReadEntity()
        if not IsValid(ent) then return end
        if ent:IsWorld() or ent:IsPlayer() or ent:IsNPC() then return end
        
        -- Use NearestPoint to account for prop size, add +10 for network tolerance
        if ply:GetShootPos():Distance(ent:NearestPoint(ply:GetShootPos())) > (MAX_REACH + 10) then return end

        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then return end

        local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
        local size = maxs - mins
        if phys:GetMass() > MAX_MASS then return end

        local maxDim = math.max(size.x, size.y, size.z)
        if maxDim > MAX_DIMENSION then return end

        ply.EnhancedE_Ent = ent
        
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
        if enhancedPickupEnabled:GetBool() then
            ThrowProp(ply)
        end
    end)

    net.Receive("EPickup_Rotate", function(len, ply)
        if not enhancedPickupEnabled:GetBool() then return end
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
        if not enhancedPickupEnabled:GetBool() then return end
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
        if not enhancedPickupEnabled:GetBool() then return end
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

            local wep = ply:GetActiveWeapon()
            if IsValid(wep) then
                wep:SetNextPrimaryFire(CurTime() + 0.1)
                wep:SetNextSecondaryFire(CurTime() + 0.1)
            end
        end
    end)

    hook.Add("Tick", "EnhancedE_PhysicsTick", function()
        if not enhancedPickupEnabled:GetBool() then return end
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

                    local shadowParams = {
                        secondstoarrive = 0.08,
                        pos = targetPos,
                        angle = targetWorldAng,
                        maxangular = 1000,
                        maxangulardamp = 10000,
                        maxspeed = 800,
                        maxspeeddamp = 1000,
                        dampfactor = 0.8,
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
    local function IsEnhancedPickupEnabled()
        local enabledConVar = GetConVar("enhancede_enabled")
        return not enabledConVar or enabledConVar:GetBool()
    end
    local heldEnt = nil
    local isRotating = false
    local attack2Down = false
    local useDown = false
    local waitAttackRelease = false
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
                if IsValid(ent) and not ent:IsWorld() and not ent:IsPlayer() and not ent:IsNPC() then
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

        if cmd:KeyDown(IN_ATTACK) then
            cmd:RemoveKey(IN_ATTACK)
            net.Start("EPickup_Throw")
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
end
