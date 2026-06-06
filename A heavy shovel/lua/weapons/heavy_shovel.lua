AddCSLuaFile()

SWEP.PrintName = "Heavy Shovel"
SWEP.Author = "You"
SWEP.Instructions = "Left Click: Swing | Right Click: Charge"
SWEP.Category = "Custom Melee"
SWEP.WepSelectIcon = surface.GetTextureID("vgui/entities/heavy_shovel")

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/props_junk/shovel01a.mdl" 
SWEP.WorldModel = "models/props_junk/shovel01a.mdl"
SWEP.UseHands = false 
SWEP.HoldType = "melee2"

SWEP.ViewModelOffset = Vector(10, 5, -5)
SWEP.ViewModelAngleOffset = Angle(180, 0, 0) 

SWEP.Offset = {
    Pos = { Up = 2, Right = 1, Forward = 4 },
    Ang = { Up = 0, Right = 360, Forward = 0 }
}

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = true
SWEP.Secondary.Ammo = "none"

function SWEP:ViewModelDrawn()
    return false 
end

function SWEP:GetViewModelPosition(pos, ang)
    pos = pos + (ang:Forward() * self.ViewModelOffset.x)
    pos = pos + (ang:Right() * self.ViewModelOffset.y)
    pos = pos + (ang:Up() * self.ViewModelOffset.z)
    
    ang:RotateAroundAxis(ang:Right(), self.ViewModelAngleOffset.p)
    ang:RotateAroundAxis(ang:Up(), self.ViewModelAngleOffset.y)
    ang:RotateAroundAxis(ang:Forward(), self.ViewModelAngleOffset.r)
    
    return pos, ang
end

function SWEP:PrimaryAttack()
    if self:GetIsCharging() then return end
    local owner = self:GetOwner()
    if IsValid(owner) then owner:SetAnimation(PLAYER_ATTACK1) end
    self:SetNextPrimaryFire(CurTime() + 0.8)
    self:MeleeStrike(10, 30)
end

function SWEP:SecondaryAttack()
    if not self:GetIsCharging() then
        self:SetNextSecondaryFire(CurTime() + 0.5) 
        self:SetIsCharging(true)
        self:SetChargeStartTime(CurTime())
    end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    if self:GetIsCharging() and not owner:KeyDown(IN_ATTACK2) then
        self:SetIsCharging(false)
        self:SetNextPrimaryFire(CurTime() + 1)
        local chargeTime = CurTime() - self:GetChargeStartTime()
        local isTap = chargeTime < 0.3
        local calculatedDmg = isTap and 5 or 10 + math.Clamp((chargeTime / 10) * 35, 0, 35)
        local calculatedChance = isTap and 0 or 30 + math.Clamp((chargeTime / 5) * 65, 0, 65)
        self:MeleeStrike(calculatedDmg, calculatedChance)
    end
end

function SWEP:MeleeStrike(damage, ragdollChance)
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    owner:LagCompensation(true)
    
    local tr = util.TraceHull({
        start = owner:GetShootPos(),
        endpos = owner:GetShootPos() + (owner:GetAimVector() * 75),
        filter = owner,
        mins = Vector(-10, -10, -10),
        maxs = Vector(10, 10, 10),
        mask = MASK_SHOT_HULL
    })
    
    owner:LagCompensation(false)
    
    if IsFirstTimePredicted() then
        if tr.Hit then self:EmitSound("physics/metal/metal_solid_impact_bullet1.wav", 75, 80) else self:EmitSound("weapons/iceaxe/iceaxe_swing1.wav") end
    end
    
    if SERVER and tr.Hit and IsValid(tr.Entity) then
        local finalDamage = damage
        if tr.Entity:GetClass():find("headcrab") then finalDamage = math.min(finalDamage, 8) end

        local dmginfo = DamageInfo()
        dmginfo:SetAttacker(owner)
        dmginfo:SetInflictor(self)
        dmginfo:SetDamage(finalDamage)
        dmginfo:SetDamageType(DMG_CLUB)
        dmginfo:SetDamageForce(owner:GetAimVector() * (finalDamage * 100))
        tr.Entity:TakeDamageInfo(dmginfo)

        if tr.Entity:GetClass() == "prop_physics" then
            local phys = tr.Entity:GetPhysicsObject()
            if IsValid(phys) then phys:ApplyForceCenter(owner:GetAimVector() * (finalDamage * 250) + Vector(0, 0, 200)) end
        end

        if tr.Entity:IsNPC() and tr.Entity:Health() > 0 and not tr.Entity.IsRagdolled then
            if math.random(1, 100) <= ragdollChance then self:RagdollNPC(tr.Entity, finalDamage) end
        end
    end
end

if SERVER then
    function SWEP:RagdollNPC(npc, damage)
        if not IsValid(npc) or npc.IsRagdolled then return end
        
        npc.IsRagdolled = true
        npc:SetNoDraw(true)
        npc:SetSolid(SOLID_NONE)
        npc:SetMoveType(MOVETYPE_NONE) -- This stops the NPC from trying to stand up
        
        local ragdoll = ents.Create("prop_ragdoll")
        ragdoll:SetModel(npc:GetModel())
        ragdoll:SetPos(npc:GetPos())
        ragdoll:SetAngles(npc:GetAngles())
        ragdoll:SetSkin(npc:GetSkin())
        ragdoll:SetColor(npc:GetColor())
        ragdoll:SetMaterial(npc:GetMaterial())
        ragdoll:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        ragdoll:Spawn()
        
        for i = 0, npc:GetNumBodyGroups() - 1 do ragdoll:SetBodygroup(i, npc:GetBodygroup(i)) end
        
        local owner = self:GetOwner()
        if IsValid(owner) then
            local phys = ragdoll:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(owner:GetAimVector() * (damage * 15) + Vector(0, 0, 100)) end
        end

        local timerID = "ShovelRagdoll_" .. ragdoll:EntIndex()
        local wakeUpTime = CurTime() + math.random(4, 7)

        -- INTERCEPT DAMAGE: If lethal, clean up instantly so the NPC dies naturally
        function ragdoll:OnTakeDamage(dmginfo)
            if IsValid(npc) then
                if npc:Health() - dmginfo:GetDamage() <= 0 then
                    -- PRE-DEATH CLEANUP
                    if IsValid(ragdoll) then ragdoll:Remove() end
                    npc:SetNoDraw(false)
                    npc:SetSolid(SOLID_BBOX)
                    npc:SetMoveType(MOVETYPE_STEP)
                    npc.IsRagdolled = false
                    -- Now apply the lethal damage
                    npc:TakeDamageInfo(dmginfo)
                else
                    -- Non-lethal, just pass damage to NPC
                    npc:TakeDamageInfo(dmginfo)
                end
            end
        end

        timer.Create(timerID, 0, 0, function()
            -- 1. Check if NPC died from something else (e.g., world damage)
            if not IsValid(npc) or npc:Health() <= 0 then
                if IsValid(ragdoll) then ragdoll:Remove() end
                if IsValid(npc) then
                    npc:SetNoDraw(false)
                    npc:SetSolid(SOLID_BBOX)
                    npc:SetMoveType(MOVETYPE_STEP)
                    npc.IsRagdolled = false
                end
                timer.Remove(timerID)
                return
            end

            -- 2. If proxy is missing, restore NPC
            if not IsValid(ragdoll) then
                if IsValid(npc) then
                    npc:SetNoDraw(false)
                    npc:SetSolid(SOLID_BBOX)
                    npc:SetMoveType(MOVETYPE_STEP)
                    npc.IsRagdolled = false
                end
                timer.Remove(timerID)
                return
            end

            -- 3. Sync positions
            local physBone = ragdoll:GetPhysicsObjectNum(0)
            if IsValid(physBone) then npc:SetPos(physBone:GetPos()) else npc:SetPos(ragdoll:GetPos()) end
            npc:SetAngles(ragdoll:GetAngles())

            -- 4. Wake up logic
            if CurTime() >= wakeUpTime then
                timer.Remove(timerID)
                if IsValid(npc) and IsValid(ragdoll) then
                    npc:SetPos(ragdoll:GetPos())
                    ragdoll:Remove()
                    npc:SetNoDraw(false)
                    npc:SetSolid(SOLID_BBOX)
                    npc:SetMoveType(MOVETYPE_STEP)
                    npc.IsRagdolled = false
                end
            end
        end)
    end
end

function SWEP:DrawHUD()
    if self:GetIsCharging() then
        local chargeTime = CurTime() - self:GetChargeStartTime()
        local dmgRatio = math.Clamp(chargeTime / 10, 0, 1)
        local currentDmg = math.Round(10 + (dmgRatio * 35))
        local currentChance = math.Round(30 + (math.Clamp(chargeTime / 5, 0, 1) * 65))
        local scrW, scrH = ScrW(), ScrH()
        local barW, barH = 250, 25
        local x, y = (scrW - barW) / 2, scrH - 150
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawRect(x, y, barW, barH)
        surface.SetDrawColor(255, 140, 0, 255)
        surface.DrawRect(x, y, barW * dmgRatio, barH)
        surface.DrawOutlinedRect(x, y, barW, barH)
        draw.SimpleText("Shovel Charge", "DermaDefaultBold", x + barW/2, y - 18, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        draw.SimpleText("Dmg: " .. currentDmg .. " | KO: " .. currentChance .. "%", "DermaDefault", x + barW/2, y + barH/2 - 6, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

function SWEP:DrawWorldModel()
    local owner = self:GetOwner()
    if not IsValid(owner) then self:DrawModel() return end
    local boneIndex = owner:LookupBone("ValveBiped.Bip01_R_Hand")
    if not boneIndex then self:DrawModel() return end
    local pos, ang = owner:GetBonePosition(boneIndex)
    local right, up, forward = ang:Right(), ang:Up(), ang:Forward()
    pos = pos + (forward * self.Offset.Pos.Forward) + (right * self.Offset.Pos.Right) + (up * self.Offset.Pos.Up)
    ang:RotateAroundAxis(ang:Up(), self.Offset.Ang.Up)
    ang:RotateAroundAxis(ang:Right(), self.Offset.Ang.Right)
    ang:RotateAroundAxis(ang:Forward(), self.Offset.Ang.Forward)
    self:SetRenderOrigin(pos)
    self:SetRenderAngles(ang)
    self:DrawModel()
end

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "IsCharging")
    self:NetworkVar("Float", 0, "ChargeStartTime")
end

function SWEP:Initialize()
    self:SetWeaponHoldType(self.HoldType)
end