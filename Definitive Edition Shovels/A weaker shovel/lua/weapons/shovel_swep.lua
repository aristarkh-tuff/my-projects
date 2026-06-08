AddCSLuaFile()

SWEP.PrintName          = "Charged Shovel"
SWEP.Author             = "Aristarkh"
SWEP.Instructions       = "Left Click: Normal swing (10 Dmg, 10% Ragdoll)\nHold Right Click: Charge heavy swing (Up to 30 Dmg, up to 30% Ragdoll)"
SWEP.Category           = "Custom Melees"
SWEP.Spawnable          = true
SWEP.AdminOnly          = false

SWEP.ViewModel          = "models/weapons/c_crowbar.mdl" 
SWEP.UseHands           = true

if file.Exists("models/weapons/w_models/w_shovel.mdl", "GAME") then
    SWEP.WorldModel     = "models/weapons/w_models/w_shovel.mdl"
else
    SWEP.WorldModel     = "models/weapons/w_crowbar.mdl"
end

SWEP.Primary.ClipSize       = -1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic      = false
SWEP.Primary.Ammo           = "none"

SWEP.Secondary.ClipSize     = -1
SWEP.Secondary.DefaultClip  = -1
SWEP.Secondary.Automatic    = true
SWEP.Secondary.Ammo         = "none"

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "ChargeStartTime")
    self:NetworkVar("Bool", 0, "IsCharging")
end

function SWEP:Initialize()
    self:SetHoldType("melee2")
end

----------------------------------------------------
-- Advanced Recovery Knockdown & Shove Engine
----------------------------------------------------
local function KnockdownTarget(target, duration, damage, attacker)
    if not SERVER or not IsValid(target) then return end
    if target.IsShovelRagdolled then return end

    local pushDirection = Vector(0, 0, 0)
    if IsValid(attacker) then
        pushDirection = attacker:GetAimVector()
    end

    local forceMultiplier = 120 + (damage * 12) 

    if target:IsPlayer() then
        if target.RagmodKnockout or _G.Ragmod or (RM and RM.Knockout) then
            if target.RagmodKnockout then
                target:RagmodKnockout(true)
            elseif _G.Ragmod and _G.Ragmod.Knockout then
                _G.Ragmod.Knockout(target, true)
            end
            
            local targetRagdoll = target:GetRagdollEntity()
            if IsValid(targetRagdoll) then
                for i = 0, targetRagdoll:GetPhysicsObjectCount() - 1 do
                    local phys = targetRagdoll:GetPhysicsObjectNum(i)
                    if IsValid(phys) then phys:SetVelocity(pushDirection * forceMultiplier) end
                end
            end

            local timerID = "ShovelRagmodWake_" .. target:UserID() .. "_" .. CurTime()
            timer.Create(timerID, duration, 1, function()
                if IsValid(target) and target.RagmodKnockout then 
                    target:RagmodKnockout(false) 
                end
            end)
            return
        end

        target.IsShovelRagdolled = true
        local ragdoll = ents.Create("prop_ragdoll")
        ragdoll:SetModel(target:GetModel())
        ragdoll:SetPos(target:GetPos())
        ragdoll:SetAngles(target:GetAngles())
        ragdoll:Spawn()
        ragdoll:Activate()

        ragdoll:SetSkin(target:GetSkin())
        for i = 0, target:GetNumBodyGroups() - 1 do
            ragdoll:SetBodygroup(i, target:GetBodygroup(i))
        end

        for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
            local phys = ragdoll:GetPhysicsObjectNum(i)
            if IsValid(phys) then phys:SetVelocity(pushDirection * forceMultiplier) end
        end

        target:SetNoDraw(true)
        target:SetNotSolid(true)
        target:Freeze(true)
        target:Spectate(OBS_MODE_CHASE)
        target:SpectateEntity(ragdoll)
        target.ShovelRagdollEntity = ragdoll

        ragdoll.OnTakeDamage = function(ent, dmginfo)
            if IsValid(target) then 
                local phys = ent:GetPhysicsObjectNum(dmginfo:GetPhysicsBone())
                if IsValid(phys) then
                    phys:ApplyForceOffset(dmginfo:GetDamageForce(), dmginfo:GetDamagePosition())
                end
                ent:BloodSpray(dmginfo:GetDamagePosition(), dmginfo:GetDamageForce(), 4, 4)
                target:TakeDamageInfo(dmginfo) 
            end
        end

        local timerID = "ShovelStandUp_Player_" .. target:UserID() .. "_" .. CurTime()
        timer.Create(timerID, duration, 1, function()
            if IsValid(target) then
                target:UnSpectate()
                target:SetNoDraw(false)
                target:SetNotSolid(false)
                target:Freeze(false)
                if IsValid(ragdoll) then
                    target:SetPos(ragdoll:GetPos() + Vector(0, 0, 10))
                    ragdoll:Remove()
                end
                target.IsShovelRagdolled = false
            elseif IsValid(ragdoll) then
                ragdoll:Remove()
            end
        end)

    elseif target:IsNPC() then
        target.IsShovelRagdolled = true
        local ragdoll = ents.Create("prop_ragdoll")
        ragdoll:SetModel(target:GetModel())
        ragdoll:SetPos(target:GetPos())
        ragdoll:SetAngles(target:GetAngles())
        ragdoll:Spawn()
        ragdoll:Activate()

        ragdoll:SetSkin(target:GetSkin())
        for i = 0, target:GetNumBodyGroups() - 1 do
            ragdoll:SetBodygroup(i, target:GetBodygroup(i))
        end

        for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
            local phys = ragdoll:GetPhysicsObjectNum(i)
            if IsValid(phys) then phys:SetVelocity(pushDirection * (forceMultiplier * 1.3)) end
        end

        target:SetMaterial("vgui/clear")
        target:DrawShadow(false)
        target:SetNoDraw(true)
        target:SetNotSolid(true)
        target:SetMoveType(MOVETYPE_NONE) 
        target:ClearSchedule()
        target:ClearGoal()
        if target.SetEnemy then target:SetEnemy(nil) end 

        ragdoll.OnTakeDamage = function(ent, dmginfo)
            if IsValid(target) then 
                local phys = ent:GetPhysicsObjectNum(dmginfo:GetPhysicsBone())
                if IsValid(phys) then
                    phys:ApplyForceOffset(dmginfo:GetDamageForce(), dmginfo:GetDamagePosition())
                end
                ent:BloodSpray(dmginfo:GetDamagePosition(), dmginfo:GetDamageForce(), 4, 4)
                target:TakeDamageInfo(dmginfo)
                if target:Health() <= 0 then
                    ragdoll.OnTakeDamage = nil
                    local timerName = "ShovelSync_NPC_" .. target:EntIndex()
                    timer.Remove(timerName)
                    if IsValid(target) then target:Remove() end
                end
            end
        end

        local timerName = "ShovelSync_NPC_" .. target:EntIndex()
        timer.Create(timerName, 0.05, 0, function()
            if IsValid(target) and IsValid(ragdoll) then
                target:SetPos(ragdoll:GetPos()) 
            else
                timer.Remove(timerName)
            end
        end)

        local timerID = "ShovelStandUp_NPC_" .. ragdoll:EntIndex() .. "_" .. CurTime()
        timer.Create(timerID, duration, 1, function()
            timer.Remove(timerName) 
            if IsValid(target) and IsValid(ragdoll) and target:Health() > 0 then
                local finalPos = ragdoll:GetPos()
                ragdoll:Remove()
                target:SetPos(finalPos + Vector(0, 0, 5))
                target:SetMaterial("") 
                target:DrawShadow(true) 
                target:SetNoDraw(false)
                target:SetNotSolid(false)
                target:SetMoveType(MOVETYPE_STEP) 
                target.IsShovelRagdolled = false
                target:ClearSchedule()
                target:ClearGoal()
                target:SetCondition(COND_LIGHT_DAMAGE)
                local sequence = target:LookupSequence("slump_b")
                if sequence and sequence > 0 then
                    target:ResetSequence(sequence)
                else
                    target:ResetSequence(0)
                end
                if target.ClearEnemyMemory then target:ClearEnemyMemory() end
            elseif IsValid(ragdoll) then
                ragdoll:Remove()
            end
        end)
    end
end

----------------------------------------------------
-- SYSTEM INTEGRATION HOOKS
----------------------------------------------------
hook.Add("NPCThink", "ShovelPreventNPCAttacks", function(npc)
    if npc.IsShovelRagdolled then
        if npc:GetMaterial() ~= "vgui/clear" then
            npc:SetMaterial("vgui/clear")
            npc:DrawShadow(false)
            npc:SetNoDraw(true)
        end
        npc:ClearSchedule()
        npc:ClearGoal()
        if npc.SetEnemy then npc:SetEnemy(nil) end
        npc:SetNextAttack(CurTime() + 1) 
    end
end)

hook.Add("PlayerDisconnected", "ShovelDisconnectCleanup", function(ply)
    if IsValid(ply.ShovelRagdollEntity) then ply.ShovelRagdollEntity:Remove() end
end)

----------------------------------------------------
-- Melee Core Attack Logic
----------------------------------------------------
function SWEP:MeleeAttack(damage, ragdollChance)
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    owner:LagCompensation(true)
    local tr = util.TraceHull({
        start = owner:GetShootPos(),
        endpos = owner:GetShootPos() + owner:GetAimVector() * 75,
        filter = owner,
        mins = Vector(-10, -10, -10),
        maxs = Vector(10, 10, 10)
    })
    owner:LagCompensation(false)

    self:EmitSound("weapon_crowbar.single")
    self:SendWeaponAnim(ACT_VM_MISSCENTER)
    owner:SetAnimation(PLAYER_ATTACK1)

    if tr.Hit then
        if IsValid(tr.Entity) then
            self:EmitSound("physics/metal/metal_box_impact_hard3.wav", 75, 95)
            
            if SERVER then
                local isRagdolling = math.random() <= ragdollChance
                
                local dmginfo = DamageInfo()
                dmginfo:SetDamage(damage)
                dmginfo:SetAttacker(owner)
                dmginfo:SetInflictor(self)
                dmginfo:SetDamageType(DMG_CLUB)
                
                local forceMultiplier = isRagdolling and (damage * 1200) or 200
                dmginfo:SetDamageForce(owner:GetAimVector() * forceMultiplier)
                dmginfo:SetDamagePosition(tr.HitPos)
                
                tr.Entity:TakeDamageInfo(dmginfo)
                
                if tr.Entity:Health() > 0 then
                    if isRagdolling then
                        local standUpTime = math.Rand(2, 10)
                        KnockdownTarget(tr.Entity, standUpTime, damage, owner)
                    else
                        if tr.Entity:IsNPC() and tr.Entity:GetMoveType() == MOVETYPE_STEP then
                            local shoveForce = owner:GetAimVector() * 100
                            shoveForce.z = 0 
                            tr.Entity:SetVelocity(shoveForce)
                        end
                    end
                end
            end
        else
            self:EmitSound("weapon_crowbar.meleehit") 
        end
    end
end

function SWEP:PrimaryAttack()
    if self:GetIsCharging() then return end
    -- Faster attack speed: 0.5s interval
    self:SetNextPrimaryFire(CurTime() + 0.5)
    self:SetNextSecondaryFire(CurTime() + 0.5)
    self:MeleeAttack(10, 0.1) 
end

function SWEP:SecondaryAttack()
    if self:GetIsCharging() then return end
    self:SetIsCharging(true)
    self:SetChargeStartTime(CurTime())
end

function SWEP:Think()
    if self:GetIsCharging() then
        local owner = self:GetOwner()
        if IsValid(owner) then
            if not owner:KeyDown(IN_ATTACK2) then
                local holdTime = CurTime() - self:GetChargeStartTime()
                holdTime = math.Clamp(holdTime, 0, 8) 
                
                local damage = 10 + ((holdTime / 8) * 20)
                local ragdollChance = 0.1 + ((holdTime / 8) * 0.2)
                
                self:MeleeAttack(damage, ragdollChance)
                self:SetIsCharging(false)
                -- Faster reset speed: 0.5s interval
                self:SetNextPrimaryFire(CurTime() + 0.5)
                self:SetNextSecondaryFire(CurTime() + 0.5)
            end
        else
            self:SetIsCharging(false)
        end
    end
end

----------------------------------------------------
-- Hand Rendering & UI Layer Optimization
----------------------------------------------------
if CLIENT then
    function SWEP:PreDrawViewModel(vm, weapon, ply)
        vm:SetMaterial("engine/occlusionproxy") 
    end

    function SWEP:PostDrawViewModel(vm, weapon, ply)
        vm:SetMaterial("")
    end

    local ShovelClientModel = nil
    function SWEP:ViewModelDrawn(vm)
        if not IsValid(vm) then return end
        if not IsValid(ShovelClientModel) then
            ShovelClientModel = ClientsideModel(self.WorldModel)
            if IsValid(ShovelClientModel) then ShovelClientModel:SetNoDraw(true) end
        end
        local bone = vm:LookupBone("valvebiped.bip01_r_hand")
        if bone then
            local matrix = vm:GetBoneMatrix(bone)
            if matrix then
                local pos = matrix:GetTranslation()
                local ang = matrix:GetAngles()
                ang:RotateAroundAxis(ang:Forward(), 90)
                ang:RotateAroundAxis(ang:Right(), 90)
                pos = pos + ang:Forward() * 2 + ang:Right() * -2 + ang:Up() * -1
                ShovelClientModel:SetPos(pos)
                ShovelClientModel:SetAngles(ang)
                ShovelClientModel:SetupBones()
                ShovelClientModel:DrawModel()
            end
        end
    end

    local ShovelWorldModel = nil
    function SWEP:DrawWorldModel()
        local owner = self:GetOwner()
        if IsValid(owner) then
            if not IsValid(ShovelWorldModel) then
                ShovelWorldModel = ClientsideModel(self.WorldModel)
                if IsValid(ShovelWorldModel) then ShovelWorldModel:SetNoDraw(true) end
            end
            local bone = owner:LookupBone("ValveBiped.Bip01_R_Hand")
            if bone then
                local pos, ang = owner:GetBonePosition(bone)
                if pos and ang then
                    ang:RotateAroundAxis(ang:Forward(), 180)
                    ang:RotateAroundAxis(ang:Up(), 90)
                    pos = pos + ang:Forward() * 3 + ang:Right() * 1 + ang:Up() * -3
                    ShovelWorldModel:SetPos(pos)
                    ShovelWorldModel:SetAngles(ang)
                    ShovelWorldModel:SetupBones()
                    ShovelWorldModel:DrawModel()
                    return
                end
            end
        end
        self:DrawModel()
    end

    function SWEP:DrawHUD()
        if self:GetIsCharging() then
            local holdTime = CurTime() - self:GetChargeStartTime()
            local progress = math.Clamp(holdTime / 8, 0, 1)
            local curDamage = math.Round(10 + (progress * 20))
            local curRagdoll = math.Round((0.1 + (progress * 0.2)) * 100)
            local curPercent = math.Round(progress * 100)
            
            local w, h = 240, 16
            local x, y = (ScrW() / 2) - (w / 2), (ScrH() / 2) + 150
            
            surface.SetDrawColor(0, 0, 0, 180)
            surface.DrawRect(x, y, w, h)
            surface.SetDrawColor(255, 255 - (progress * 155), 0, 255)
            surface.DrawRect(x + 2, y + 2, (w - 4) * progress, h - 4)
            
            draw.SimpleText(curPercent .. "%", "DermaDefaultBold", x - 12, y + (h / 2), Color(255, 255, 255), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText("KNOCKDOWN CHANCE: " .. curRagdoll .. "%", "DermaDefaultBold", ScrW() / 2, y - 14, Color(255, 255, 255), TEXT_ALIGN_CENTER)
            draw.SimpleText(curDamage .. " DMG", "DermaDefaultBold", x + w + 12, y + (h / 2), Color(255, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
end