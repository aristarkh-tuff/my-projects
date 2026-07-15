if not SERVER then return end

-- [[ 1. STICK, WELD, AND ALIGN S.L.A.M. ]] --
local function StickySLAM_Collide(ent, data)
    if ent.HasStuck or CurTime() < (ent.StickCooldown or 0) then return end

    local hitEnt = data.HitEntity
    local hitNormal = data.HitNormal
    local hitPos = data.HitPos
    local hitBone = data.HitObject:GetIndex() or 0
    local offsetDistance = -2 

    ent.HasStuck = true

    timer.Simple(0, function()
        if not IsValid(ent) then return end

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocityInstantaneous(Vector(0,0,0))
            phys:AddAngleVelocity(-phys:GetAngleVelocity())
        end

        local ang = hitNormal:Angle()
        ang:RotateAroundAxis(ang:Right(), 90) 
        
        ent:SetPos(hitPos + (hitNormal * offsetDistance))
        ent:SetAngles(ang)

        if not IsValid(hitEnt) or hitEnt:IsWorld() then
            if IsValid(phys) then
                phys:EnableMotion(false)
            end
        elseif hitEnt:IsPlayer() or hitEnt:IsNPC() then
            ent:SetParent(hitEnt)
            ent:SetLocalPos(ent:GetPos() - hitEnt:GetPos())
        else
            constraint.NoCollide(ent, hitEnt, 0, hitBone)
            constraint.Weld(ent, hitEnt, 0, hitBone, 0, true, false)
        end

        ent:EmitSound("weapons/c4/c4_plant.wav", 65, 150)
    end)
end

hook.Add("OnEntityCreated", "StickySLAM_Init", function(ent)
    if not IsValid(ent) or ent:GetClass() ~= "npc_satchel" then return end
    timer.Simple(0, function()
        if IsValid(ent) then
            ent:AddCallback("PhysicsCollide", StickySLAM_Collide)
        end
    end)
end)


-- [[ 2. UNSTICK AND PHYSICALLY CARRY WITH 'E' ]] --
hook.Add("PlayerUse", "StickySLAM_Unstick", function(ply, ent)
    if IsValid(ent) and ent:GetClass() == "npc_satchel" then
        
        if not ply.SLAM_PickupDelay or CurTime() > ply.SLAM_PickupDelay then
            ply.SLAM_PickupDelay = CurTime() + 0.5
            
            if ent.HasStuck then
                constraint.RemoveConstraints(ent, "Weld")
                constraint.RemoveConstraints(ent, "NoCollide")
                ent:SetParent(nil)
                
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:EnableMotion(true)
                    phys:Wake()
                end

                ent.HasStuck = false
                ent.StickCooldown = CurTime() + 1.5 
                ent:EmitSound("weapons/smg1/switch_single.wav", 60, 120)
            end

            timer.Simple(0, function()
                if IsValid(ply) and IsValid(ent) then
                    ply:PickupObject(ent)
                end
            end)
        end
        
        return false 
    end
end)


-- [[ 3. DOOR BREACHING (PROP VS GIB) ]] --
local function BreachDoor(door, blastPos)
    local doorClass = door:GetClass()
    
    -- If it's a standard rotating door, replace with physics prop
    if doorClass == "prop_door_rotating" then
        local model = door:GetModel()
        local pos = door:GetPos()
        local ang = door:GetAngles()
        local skin = door:GetSkin() or 0

        door:EmitSound("physics/wood/wood_furniture_break" .. math.random(1, 2) .. ".wav", 90)
        door:Remove()

        local prop = ents.Create("prop_physics")
        prop:SetModel(model)
        prop:SetPos(pos)
        prop:SetAngles(ang)
        prop:SetSkin(skin)
        prop:Spawn()
        prop:Activate()

        prop:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

        local phys = prop:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            local forceDir = (pos - blastPos):GetNormalized()
            forceDir.z = 0.1 
            phys:ApplyForceOffset(forceDir * 80000, pos + Vector(0, 0, 10))
        end

        SafeRemoveEntityDelayed(prop, 15)
        
    -- If it's a func_door or brush-based door, gib it into junk
    else
        door:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 3) .. ".wav", 90)
        
        -- Create a nice explosion visual
        local effect = EffectData()
        effect:SetOrigin(door:GetPos())
        util.Effect("Explosion", effect)
        
        -- Shatter the brush into junk
        door:GibBreakServer(Vector(0,0,0))
        door:Remove()
    end
end

hook.Add("EntityTakeDamage", "StickySLAM_DoorBreach", function(target, dmginfo)
    if not IsValid(target) then return end
    
    if target.IsBreaching then return end

    if string.find(string.lower(target:GetClass()), "door") then
        if dmginfo:IsDamageType(DMG_BLAST) then
            local inflictor = dmginfo:GetInflictor()
            local blastPos = dmginfo:GetDamagePosition()

            if blastPos == vector_origin and IsValid(inflictor) then
                blastPos = inflictor:GetPos()
            end

            target.IsBreaching = true
            BreachDoor(target, blastPos)
        end
    end
end)