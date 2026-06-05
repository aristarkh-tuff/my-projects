AddCSLuaFile()

SWEP.PrintName			= "Charged Shovel"
SWEP.Author				= "AI Collaboration"
SWEP.Instructions		= "Left Click: Normal swing (20 Dmg, 30% Ragdoll)\nHold Right Click: Charge heavy swing (Up to 40 Dmg, up to 90% Ragdoll)"
SWEP.Category			= "Custom Weapons"
SWEP.Spawnable			= true
SWEP.AdminOnly			= false

SWEP.ViewModel			= "models/weapons/c_crowbar.mdl" 
SWEP.UseHands			= true

-- SMART TF2 CHECK: Fallback to HL2 crowbar if TF2 isn't mounted
if file.Exists("models/weapons/w_models/w_shovel.mdl", "GAME") then
    SWEP.WorldModel		= "models/weapons/w_models/w_shovel.mdl" -- TF2 Shovel
else
    SWEP.WorldModel		= "models/weapons/w_crowbar.mdl" -- Safe fallback if they don't have TF2
end

SWEP.Primary.ClipSize		= -1
SWEP.Primary.DefaultClip	= -1
SWEP.Primary.Automatic		= false
SWEP.Primary.Ammo			= "none"

SWEP.Secondary.ClipSize		= -1
SWEP.Secondary.DefaultClip	= -1
SWEP.Secondary.Automatic	= true
SWEP.Secondary.Ammo			= "none"

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

    -- Calculate directional force vector based on where the attacker is looking
    local pushDirection = Vector(0, 0, 0)
    if IsValid(attacker) then
        pushDirection = attacker:GetAimVector()
    end

    -- Dynamic Force Multiplier: Retained the original values for the ragdoll launch
    local forceMultiplier = 120 + (damage * 12) 

    -- PLAYER RAGDOLL LOGIC
    if target:IsPlayer() then
        -- RagMod Compatibility Layer
        if target.RagmodKnockout or _G.Ragmod or (RM and RM.Knockout) then
            if target.RagmodKnockout then
                target:RagmodKnockout(true)
            elseif _G.Ragmod and _G.Ragmod.Knockout then
                _G.Ragmod.Knockout(target, true)
            end
            
            -- Apply knockback force to RagMod physics if possible
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

        -- Base GMod Sandbox Fallback for Players
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

        -- Apply scaling physics launch velocity to the body bones
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
            if IsValid(target) then target:TakeDamageInfo(dmginfo) end
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

    -- NPC / ZOMBIE RAGDOLL LOGIC
    elseif target:IsNPC() then
        target.IsShovelRagdolled = true

        local ragdoll = ents.Create("prop_ragdoll")
        ragdoll:SetModel(target:GetModel())
        ragdoll:SetPos(target:GetPos())
        ragdoll:SetAngles(target:GetAngles())
        ragdoll:Spawn()
        ragdoll:Activate()

        -- Inherit bodygroups / Zombie skin textures flawlessly
        ragdoll:SetSkin(target:GetSkin())
        for i = 0, target:GetNumBodyGroups() - 1 do
            local currentGroup = target:GetBodygroup(i)
            ragdoll:SetBodygroup(i, currentGroup)
        end
        
        -- Headcrab fallback safety guard
        if target:GetClass() == "npc_zombie" and ragdoll:GetBodygroup(1) == 0 then
            ragdoll:SetBodygroup(1, 1) 
        end

        -- Apply structural knockback blast to NPC physics bones
        for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
            local phys = ragdoll:GetPhysicsObjectNum(i)
            if IsValid(phys) then phys:SetVelocity(pushDirection * (forceMultiplier * 1.3)) end
        end

        -- ANTI-ATTACK SAFEGUARDS: Shuts down combat capabilities entirely while invisible
        target:SetNoDraw(true)
        target:SetNotSolid(true)
        target:SetMoveType(MOVETYPE_NONE) -- Glues them completely in place so they don't wander off
        target:ClearSchedule()
        target:ClearGoal()
        if target.SetEnemy then target:SetEnemy(nil) end -- Wipes their tracking target immediately

        ragdoll.OnTakeDamage = function(ent, dmginfo)
            if IsValid(target) then 
                target:TakeDamageInfo(dmginfo)
                if target:Health() <= 0 then
                    ragdoll.OnTakeDamage = nil
                    if IsValid(target) then target:Remove() end
                end
            end
        end

        -- Tracker system to sync the invisible NPC's position with the flying ragdoll
        local timerName = "ShovelSync_NPC_" .. target:EntIndex()
        timer.Create(timerName, 0.05, 0, function()
            if IsValid(target) and IsValid(ragdoll) then
                target:SetPos(ragdoll:GetPos()) -- Continuously update position seamlessly
            else
                timer.Remove(timerName)
            end
        end)

        local timerID = "ShovelStandUp_NPC_" .. ragdoll:EntIndex() .. "_" .. CurTime()
        timer.Create(timerID, duration, 1, function()
            timer.Remove(timerName) -- Stop tracking position upon wakeup
            
            if IsValid(target) and IsValid(ragdoll) and target:Health() > 0 then
                local finalPos = ragdoll:GetPos()
                ragdoll:Remove()

                target:SetPos(finalPos + Vector(0, 0, 5))
                target:SetNoDraw(false)
                target:SetNotSolid(false)
                target:SetMoveType(MOVETYPE_STEP) -- Restores normal physics movement
                target.IsShovelRagdolled = false

                -- AI REBOOT LAYER: Clean state reboot to clear any AI confusion completely
                target:ClearSchedule()
                target:ClearGoal()
                target:SetCondition(COND_LIGHT_DAMAGE)
                
                local sequence = target:LookupSequence("slump_b")
                if sequence and sequence > 0 then
                    target:ResetSequence(sequence)
                else
                    target:ResetSequence(0)
                end
                
                -- Forces the core AI pathways to re-evaluate enemies properly
                if target.ClearEnemyMemory then target:ClearEnemyMemory() end
            elseif IsValid(ragdoll) then
                ragdoll:Remove()
            end
        end)
    end
end

-- Global hook to prevent invisible, ragdolled NPCs from firing weapons or attacking entirely
hook.Add("NPCThink", "ShovelPreventNPCAttacks", function(npc)
    if npc.IsShovelRagdolled then
        npc:ClearSchedule()
        npc:ClearGoal()
        if npc.SetEnemy then npc:SetEnemy(nil) end
        npc:SetNextAttack(CurTime() + 1) -- Pushes back their next attack sequence constantly
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
                local dmginfo = DamageInfo()
                dmginfo:SetDamage(damage)
                dmginfo:SetAttacker(owner)
                dmginfo:SetInflictor(self)
                dmginfo:SetDamageType(DMG_CLUB)
                dmginfo:SetDamageForce(owner:GetAimVector() * 20000)
                
                tr.Entity:TakeDamageInfo(dmginfo)
                
                if tr.Entity:Health() > 0 then
                    -- If they roll a positive chance, execute full ragdoll knockdown
                    if math.random() <= ragdollChance then
                        local standUpTime = math.Rand(2, 5)
                        KnockdownTarget(tr.Entity, standUpTime, damage, owner)
                    else
                        -- NON-RAGDOLL SHOVE: Sends the NPC back just a little bit without putting them down
                        if tr.Entity:IsNPC() and tr.Entity:GetMoveType() == MOVETYPE_STEP then
                            local shoveForce = owner:GetAimVector() * 140
                            shoveForce.z = 0 -- Keep them glued to the ground, just sliding backwards
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
    self:SetNextPrimaryFire(CurTime() + 0.8)
    self:SetNextSecondaryFire(CurTime() + 0.8)
    self:MeleeAttack(20, 0.3)
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
                
                local damage = 20 + ((holdTime / 8) * 20)
                local ragdollChance = 0.3
                if holdTime >= 3 then
                    ragdollChance = 0.9
                else
                    ragdollChance = 0.3 + ((holdTime / 3) * 0.6)
                end
                
                self:MeleeAttack(damage, ragdollChance)
                self:SetIsCharging(false)
                self:SetNextPrimaryFire(CurTime() + 1.0)
                self:SetNextSecondaryFire(CurTime() + 1.0)
            end
        else
            self:SetIsCharging(false)
        end
    end
end

----------------------------------------------------
-- Client Viewmodel Hand Overrides & Render Management
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
            if IsValid(ShovelClientModel) then 
                ShovelClientModel:SetNoDraw(true) 
            end
        end

        local bone = vm:LookupBone("valvebiped.bip01_r_hand")
        if bone then
            local matrix = vm:GetBoneMatrix(bone)
            if matrix then
                local pos = matrix:GetTranslation()
                local ang = matrix:GetAngles()

                ang:RotateAroundAxis(ang:Forward(), 90)
                ang:RotateAroundAxis(ang:Up(), 0)
                ang:RotateAroundAxis(ang:Right(), 90)
                pos = pos + ang:Forward() * 2 + ang:Right() * -2 + ang:Up() * -1

                ShovelClientModel:SetPos(pos)
                ShovelClientModel:SetAngles(ang)
                ShovelClientModel:SetupBones()
                ShovelClientModel:DrawModel()
            end
        end
    end

    function SWEP:DrawHUD()
        if self:GetIsCharging() then
            local holdTime = CurTime() - self:GetChargeStartTime()
            local progress = math.Clamp(holdTime / 8, 0, 1)
            local x, y = ScrW() / 2 - 100, ScrH() / 2 + 150
            
            surface.SetDrawColor(0, 0, 0, 180)
            surface.DrawRect(x, y, 200, 16)
            surface.SetDrawColor(255, 255 - (progress * 155), 0, 255)
            surface.DrawRect(x + 2, y + 2, 196 * progress, 12)
            draw.SimpleText("SHOVEL POWER: " .. math.Round(progress * 100) .. "%", "DermaDefault", ScrW() / 2, y - 18, Color(255, 255, 255), TEXT_ALIGN_CENTER)
        end
    end
end