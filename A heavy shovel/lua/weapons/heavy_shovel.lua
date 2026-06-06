AddCSLuaFile()

SWEP.PrintName = "Heavy Shovel"
SWEP.Author = "You"
SWEP.Instructions = "Left Click: Swing | Right Click: Charge"
SWEP.Category = "Custom Melee"
-- Make sure this texture exists or it will error
SWEP.WepSelectIcon = surface.GetTextureID("vgui/entities/heavy_shovel") 

SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/props_junk/shovel01a.mdl" 
SWEP.WorldModel = "models/props_junk/shovel01a.mdl"
SWEP.UseHands = true
SWEP.HoldType = "melee2"

-- NEW: Use this to adjust your viewmodel position/angle
SWEP.ViewModelOffset = Vector(10, 5, -5)
SWEP.ViewModelAngleOffset = Angle(0, 0, 0)

-- World Model Offset
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

-- FIXED: This moves the model in your view
function SWEP:GetViewModelPosition(pos, ang)
    pos = pos + (ang:Forward() * self.ViewModelOffset.x)
    pos = pos + (ang:Right() * self.ViewModelOffset.y)
    pos = pos + (ang:Up() * self.ViewModelOffset.z)
    
    ang:RotateAroundAxis(ang:Forward(), self.ViewModelAngleOffset.r)
    ang:RotateAroundAxis(ang:Right(), self.ViewModelAngleOffset.p)
    ang:RotateAroundAxis(ang:Up(), self.ViewModelAngleOffset.y)
    
    return pos, ang
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
    
    local right = ang:Right()
    local up = ang:Up()
    local forward = ang:Forward()
    
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

function SWEP:PrimaryAttack()
    if self:GetIsCharging() then return end
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    
    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:SetAnimation(PLAYER_ATTACK1)
    end
    
    self:SetNextPrimaryFire(CurTime() + 0.8)
    self:MeleeStrike(10, 30)
end

function SWEP:SecondaryAttack()
    if not self:GetIsCharging() then
        self:SetIsCharging(true)
        self:SetChargeStartTime(CurTime())
    end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    if self:GetIsCharging() and not owner:KeyDown(IN_ATTACK2) then
        self:SetIsCharging(false)
        local chargeTime = CurTime() - self:GetChargeStartTime()
        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
        owner:SetAnimation(PLAYER_ATTACK1)
        self:SetNextPrimaryFire(CurTime() + 1)
        
        local calculatedDmg = 10 + math.Clamp((chargeTime / 10) * 35, 0, 35)
        local calculatedChance = 30 + math.Clamp((chargeTime / 5) * 65, 0, 65)
        
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
        if tr.Hit then 
            self:EmitSound("physics/metal/metal_solid_impact_bullet1.wav", 75, 80) 
        else 
            self:EmitSound("weapons/iceaxe/iceaxe_swing1.wav") 
        end
    end
    
    if SERVER and tr.Hit and IsValid(tr.Entity) then
        local dmginfo = DamageInfo()
        dmginfo:SetAttacker(owner)
        dmginfo:SetInflictor(self)
        dmginfo:SetDamage(damage)
        dmginfo:SetDamageType(DMG_CLUB)
        dmginfo:SetDamageForce(owner:GetAimVector() * (damage * 100))
        
        tr.Entity:TakeDamageInfo(dmginfo)

        if tr.Entity:IsNPC() and tr.Entity:Health() > 0 and not tr.Entity.IsRagdolled then
            if math.random(1, 100) <= ragdollChance then 
                self:RagdollNPC(tr.Entity) 
            end
        end
    end
end

if SERVER then
    function SWEP:RagdollNPC(npc)
        if not IsValid(npc) or npc.IsRagdolled then return end
        
        npc.IsRagdolled = true
        npc:SetNoDraw(true)
        npc:SetSolid(SOLID_NONE)
        
        local ragdoll = ents.Create("prop_ragdoll")
        ragdoll:SetModel(npc:GetModel())
        ragdoll:SetPos(npc:GetPos())
        ragdoll:SetAngles(npc:GetAngles())
        ragdoll:SetSkin(npc:GetSkin())
        ragdoll:SetColor(npc:GetColor())
        ragdoll:SetMaterial(npc:GetMaterial())
        ragdoll:Spawn()
        
        for i = 0, npc:GetNumBodyGroups() - 1 do 
            ragdoll:SetBodygroup(i, npc:GetBodygroup(i)) 
        end
        
        local owner = self:GetOwner()
        if IsValid(owner) then
            local physObjects = ragdoll:GetPhysicsObjectCount()
            for i = 0, physObjects - 1 do
                local phys = ragdoll:GetPhysicsObjectNum(i)
                if IsValid(phys) then
                    phys:SetVelocity(owner:GetAimVector() * 400 + Vector(0, 0, 100))
                end
            end
        end

        local timerID = "ShovelRagdoll_" .. ragdoll:EntIndex()
        local duration = math.random(4, 7)
        local wakeUpTime = CurTime() + duration

        timer.Create(timerID, 0, 0, function()
            if not IsValid(ragdoll) or not IsValid(npc) or npc:Health() <= 0 then
                if IsValid(ragdoll) then ragdoll:Remove() end
                if IsValid(npc) then
                    npc:SetNoDraw(false)
                    npc:SetSolid(SOLID_BBOX)
                    npc.IsRagdolled = false
                    if npc:Health() <= 0 then
                        npc:TakeDamage(1, owner, self) 
                    end
                end
                timer.Remove(timerID)
                return
            end

            local physBone = ragdoll:GetPhysicsObjectNum(0)
            if IsValid(physBone) then
                npc:SetPos(physBone:GetPos())
            else
                npc:SetPos(ragdoll:GetPos())
            end
            npc:SetAngles(ragdoll:GetAngles())

            if CurTime() >= wakeUpTime then
                timer.Remove(timerID)
                
                if IsValid(npc) and IsValid(ragdoll) then
                    npc:SetPos(ragdoll:GetPos())
                    ragdoll:Remove()
                    npc:SetNoDraw(false)
                    npc:SetSolid(SOLID_BBOX)
                    npc.IsRagdolled = false
                end
            end
        end)

        function ragdoll:OnTakeDamage(dmginfo)
            if IsValid(npc) then
                npc:TakeDamageInfo(dmginfo)
                local effectdata = EffectData()
                effectdata:SetOrigin(dmginfo:GetDamagePosition())
                effectdata:SetMagnitude(1)
                util.Effect("BloodImpact", effectdata)
            end
        end
    end
end