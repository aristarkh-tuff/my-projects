AddCSLuaFile()

if SERVER then
    util.AddNetworkString("ShovelKOEvent")
end

SWEP.PrintName = "Heavy Shovel"
SWEP.Author = "Aristarkh"
SWEP.Instructions = "Left Click: Swing | Right Click: Charge & Release | if it turns light blue = 5 percent 1 min knock out| if turns very light blue 50 percent 1 minute knock out"
SWEP.Category = "Custom Melee"

SWEP.Spawnable = true
SWEP.AdminOnly = false

if CLIENT and surface then
    SWEP.WepSelectIcon = surface.GetTextureID("vgui/entities/thashovel")
end

SWEP.ViewModel = "models/props_junk/shovel01a.mdl" 
SWEP.WorldModel = "models/props_junk/shovel01a.mdl"
SWEP.SwingDuration = 0.4
SWEP.ChargeBackDuration = 1.0
SWEP.UseHands = false 
SWEP.HoldType = "melee2"

SWEP.ViewModelOffset = Vector(28, 8, -10)
SWEP.ViewModelAngleOffset = Angle(180, -22, 0) 

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

local LastKOTime = 0

if CLIENT then
    net.Receive("ShovelKOEvent", function()
        LastKOTime = CurTime()
    end)
end

function SWEP:Initialize()
    self:SetWeaponHoldType(self.HoldType)
    self.IsSwinging = false
    self.SwingStartTime = 0
    self.SwingDuration = 0.4
    self.ChargeViewActive = false
    self.ChargeHeld = false
    self.ChargeStartTime = 0
    self.ChargeViewStartTime = 0
    self.ChargeBackDuration = 1.0
    self.ChargeBackAmount = 16
end

-- --- FIXED DROP HOOK ---
function SWEP:OnDrop()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    local spawnPos = owner:GetShootPos() + (owner:GetAimVector() * 30)
    
    local shovelProp = ents.Create("prop_physics")
    if not IsValid(shovelProp) then return end

    shovelProp:SetModel(self.WorldModel)
    shovelProp:SetPos(spawnPos)
    shovelProp:SetAngles(owner:GetAngles())
    
    shovelProp:Spawn()
    shovelProp:Activate() 
    
    shovelProp:PhysicsInit(SOLID_VPHYSICS)
    shovelProp:SetMoveType(MOVETYPE_VPHYSICS)
    shovelProp:SetSolid(SOLID_VPHYSICS)
    
    local phys = shovelProp:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(true)
        phys:SetVelocity(owner:GetAimVector() * 200)
    end

    shovelProp:SetUseType(SIMPLE_USE)
    
    function shovelProp:Use(activator)
        if activator:IsPlayer() then
            activator:Give("weapon_heavyshovel") 
            self:Remove()
        end
    end
end

-- --- MELEE LOGIC ---
function SWEP:ShouldDrawViewModel()
    return self.IsSwinging or self.ChargeViewActive
end

function SWEP:GetViewModelPosition(pos, ang)
    pos = pos + (ang:Forward() * self.ViewModelOffset.x)
    pos = pos + (ang:Right() * self.ViewModelOffset.y)
    pos = pos + (ang:Up() * self.ViewModelOffset.z)
    ang:RotateAroundAxis(ang:Right(), self.ViewModelAngleOffset.p)
    ang:RotateAroundAxis(ang:Up(), self.ViewModelAngleOffset.y)
    ang:RotateAroundAxis(ang:Forward(), self.ViewModelAngleOffset.r)

    if self.ChargeViewActive then
        local chargeBackDuration = self.ChargeBackDuration or 1.0
        local chargeStart = self.ChargeViewStartTime or self.ChargeStartTime or CurTime()
        local elapsed = math.Clamp((CurTime() - chargeStart) / chargeBackDuration, 0, 1)
        local back = math.sin(elapsed * (math.pi / 2))
        pos = pos + (ang:Forward() * (10 * back))
        pos = pos + (ang:Right() * (-6 * back))
        ang:RotateAroundAxis(ang:Right(), 20 * back)
        ang:RotateAroundAxis(ang:Up(), -12 * back)
    end

    if self.IsSwinging then
        local swingDuration = self.SwingDuration or 0.4
        local elapsed = math.Clamp((CurTime() - self.SwingStartTime) / swingDuration, 0, 1)
        local swing = math.sin(elapsed * math.pi)
        pos = pos + (ang:Forward() * (-10 * swing))
        pos = pos + (ang:Right() * (5 * swing))
        ang:RotateAroundAxis(ang:Right(), -35 * swing)
        ang:RotateAroundAxis(ang:Up(), 15 * swing)
    end

    return pos, ang
end

function SWEP:PrimaryAttack()
    if self:GetIsCharging() then
        self:SetIsCharging(false)
        self.ChargeHeld = false
        self.ChargeViewActive = false
    end
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    owner:SetAnimation(PLAYER_ATTACK1)
    self.IsSwinging = true
    self.SwingStartTime = CurTime()
    self:MeleeStrike(10, 0, false)
    self:SetNextPrimaryFire(CurTime() + 0.6)
end

function SWEP:SecondaryAttack()
    if self:GetIsCharging() then return end
    self:SetIsCharging(true)
    self.ChargeHeld = true
    self:SetChargeStartTime(CurTime())
    self.ChargeViewActive = true
    self.ChargeViewStartTime = CurTime()
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    if self.IsSwinging and CurTime() >= self.SwingStartTime + self.SwingDuration then
        self.IsSwinging = false
    end

    if self:GetIsCharging() and owner:KeyDown(IN_ATTACK2) then
        self.ChargeViewActive = true
    end

    if self.ChargeHeld and self:GetIsCharging() and not owner:KeyDown(IN_ATTACK2) then
        local chargeTime = math.Clamp(CurTime() - self:GetChargeStartTime(), 0, 10)
        local chargeRatio = chargeTime / 10
        self.ChargeViewActive = false
        self.ChargeHeld = false
        
        local isTap = chargeTime < 0.3
        local calculatedDmg = isTap and 5 or 10 + math.Clamp(chargeRatio * 40, 0, 40)
        local calculatedChance = isTap and 0 or 30 + math.Clamp((chargeTime / 5) * 65, 0, 65)
        
        local roll = math.random(1, 100)
        local isLuckyKO = false
        
        if chargeRatio >= 1.0 then
            isLuckyKO = (roll <= math.random(50, 100))
        elseif chargeRatio >= 0.5 then
            isLuckyKO = (roll <= math.random(25, 50))
        end
        
        owner:SetAnimation(PLAYER_ATTACK1)
        self.IsSwinging = true
        self.SwingStartTime = CurTime()
        self:MeleeStrike(calculatedDmg, calculatedChance, isLuckyKO)
        self:SetIsCharging(false)
        self:SetNextPrimaryFire(CurTime() + 0.5)
    end
end

function SWEP:MeleeStrike(damage, ragdollChance, forceFullKO)
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
            self:EmitSound("physics/metal/metal_canister_impact_hard1.wav", 75, 65) 
        else 
            self:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 75, 60) 
        end
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
            if (math.random(1, 100) <= ragdollChance) or forceFullKO then 
                self:RagdollNPC(tr.Entity, finalDamage, forceFullKO) 
            end
        end
    end
end

-- --- NPC RAGDOLL/KO SYSTEM ---
if SERVER then
    function SWEP:RagdollNPC(npc, damage, isFullKO)
        if not IsValid(npc) or npc.IsRagdolled then return end
        
        local activeWep = npc:GetActiveWeapon()
        if IsValid(activeWep) then npc:DropWeapon(activeWep) end

        for i = 0, npc:GetNumBodyGroups() - 1 do
            local name = string.lower(npc:GetBodygroupName(i))
            if name == "weapon" or name == "gun" or name == "main" then npc:SetBodygroup(i, 0) end
        end
        
        npc:AddSpawnFlags(65536) 
        if npc.IsVJBaseNPC then 
            npc.DisableSound = true 
            npc:SetSoundVolume(0, 4) 
        end
        
        npc:AddEntityRelationship(self:GetOwner(), D_NU, 99)
        npc:SetEnemy(NULL)
        npc:SetNPCState(NPC_STATE_IDLE)
        npc:SetCondition(67)
        npc:CapabilitiesRemove(CAP_USE_WEAPONS)
        if npc.ClearEnemy then npc:ClearEnemy() end
        npc:StopMoving()
        
        npc:Fire("Disable")
        npc:Fire("Close")
        
        npc.IsRagdolled = true
        
        if npc.IsVJBaseNPC then
            npc.IsRagdolledByShowel = true

            local npcDamageHookID = "ShovelRagdollNPCDamage_" .. npc:EntIndex()
            hook.Add("EntityTakeDamage", npcDamageHookID, function(ent, dmginfo)
                if ent ~= npc then return end
                if not npc.IsRagdolledByShowel then 
                    hook.Remove("EntityTakeDamage", npcDamageHookID)
                    return 
                end
                dmginfo:SetDamage(0)
                return true
            end)
        end

        npc:SetNoDraw(true)
        if npc.IsVJBaseNPC then
            npc:SetRenderMode(RENDERMODE_TRANSALPHA)
            npc:SetColor(Color(255, 255, 255, 0))
        end
        npc:SetSolid(SOLID_NONE)
        npc:SetMoveType(MOVETYPE_NONE)
        
        local ragdoll = ents.Create("prop_ragdoll")
        ragdoll:SetModel(npc:GetModel())
        ragdoll:SetPos(npc:GetPos())
        ragdoll:SetAngles(npc:GetAngles())
        ragdoll:SetSkin(npc:GetSkin())
        ragdoll:SetColor(npc:GetColor())
        ragdoll:SetMaterial(npc:GetMaterial())
        
        for i = 0, npc:GetNumBodyGroups() - 1 do ragdoll:SetBodygroup(i, npc:GetBodygroup(i)) end
        
        ragdoll.AttachedNPC = npc
        ragdoll.IsPermanentlyDead = false
        ragdoll:SetCollisionGroup(COLLISION_GROUP_NONE)

        if npc.IsVJBaseNPC then
            local hookName = "ShovelVJRagdollDetect_" .. math.random(1, 999999)
            hook.Add("OnEntityCreated", hookName, function(ent)
                if not IsValid(ent) or ent == ragdoll then return end
                if ent:GetClass() ~= "prop_ragdoll" then return end
                if ent:GetModel() ~= ragdoll:GetModel() then return end
                if ent:GetPos():Distance(ragdoll:GetPos()) > 128 then return end

                timer.Simple(0, function()
                    if not IsValid(ent) then return end
                    local dmginfo = DamageInfo()
                    dmginfo:SetAttacker(self:GetOwner() or ragdoll)
                    dmginfo:SetInflictor(self)
                    dmginfo:SetDamage(1000)
                    dmginfo:SetDamageType(bit.bor(DMG_BLAST, DMG_ALWAYSGIB))
                    dmginfo:SetDamageForce(Vector(0, 0, 10000))
                    dmginfo:SetDamagePosition(ent:GetPos())
                    ent:TakeDamageInfo(dmginfo)
                    if IsValid(ent) then
                        ent:Remove()
                    end
                end)

                hook.Remove("OnEntityCreated", hookName)
            end)

            ragdoll:CallOnRemove("ShovelVJRagdollCleanup", function()
                hook.Remove("OnEntityCreated", hookName)
            end)

            timer.Simple(20, function()
                if IsValid(ragdoll) then
                    hook.Remove("OnEntityCreated", hookName)
                end
            end)
        end

        ragdoll:Spawn()
        local owner = self:GetOwner()
        if IsValid(owner) then
            if isFullKO then
                owner:EmitSound("physics/body/body_medium_impact_hard1.wav", 75, 100)
                net.Start("ShovelKOEvent")
                net.Send(owner)
            end
            
            local phys = ragdoll:GetPhysicsObject()
            if IsValid(phys) then 
                phys:Wake()
                local forceDir = owner:GetAimVector()
                forceDir.z = 0.3
                phys:ApplyForceCenter(forceDir * (damage * 400) + Vector(0, 0, 1000)) 
            end
        end

        ragdoll.LastImpactTime = 0
        ragdoll:AddCallback("PhysicsCollide", function(ent, data)
            if not IsValid(ent) then return end
            if CurTime() < ent.LastImpactTime + 0.2 then return end
            ent.LastImpactTime = CurTime()

            local npc = ent.AttachedNPC
            if not IsValid(npc) or npc.IsPermanentlyDead then return end

            local speed = data.Speed or 0
            local threshold = 300
            if speed <= threshold then return end

            local hitDamage = math.Clamp((speed - threshold) * 0.08, 5, 50)
            local dmginfo = DamageInfo()
            dmginfo:SetAttacker(owner or ent)
            dmginfo:SetInflictor(self)
            dmginfo:SetDamage(hitDamage)
            dmginfo:SetDamageType(DMG_FALL)
            dmginfo:SetDamagePosition(data.HitPos or ent:GetPos())
            npc:TakeDamageInfo(dmginfo)
        end)

        local timerID = "ShovelRagdoll_" .. ragdoll:EntIndex()
        local wakeUpTime = CurTime() + (isFullKO and 60 or math.random(2, 20))
        ragdoll.WaterSlowWake = false
        ragdoll.WaterWakeEndTime = nil

        function ragdoll:OnTakeDamage(dmginfo)
            if self.IsPermanentlyDead then return end
            
            local npc = self.AttachedNPC
            if not IsValid(npc) then return end

            if npc.IsRagdolledByShowel then
                return
            end
            
            local hitPos = dmginfo:GetDamagePosition()
            if not hitPos or hitPos == vector_origin then hitPos = self:GetPos() end

            local isHeadshot = false
            local headBone = self:LookupBone("ValveBiped.Bip01_Head1")
            if headBone then
                local headPos, _ = self:GetBonePosition(headBone)
                if headPos:Distance(hitPos) < 15 then
                    isHeadshot = true
                end
            end

            local damageType = dmginfo:GetDamageType()
            local isBullet = bit.band(damageType, DMG_BULLET) ~= 0
            local isBlunt = bit.band(damageType, DMG_CLUB) ~= 0 or bit.band(damageType, DMG_CRUSH) ~= 0 or bit.band(damageType, DMG_SLASH) ~= 0

            if isBullet and isHeadshot then
                self.IsPermanentlyDead = true
                self:EmitSound("physics/body/body_medium_break2.wav", 75, 100)
                
                local effectdata = EffectData()
                effectdata:SetOrigin(hitPos)
                util.Effect("BloodImpact", effectdata)
                
                util.Decal("Blood", hitPos + Vector(0,0,1), hitPos - Vector(0,0,1))
                
                if IsValid(npc) then
                    npc:SetHealth(0)
                    npc:Remove()
                end
                return
            end

            local impactDamage = dmginfo:GetDamage()
            if isBullet or isBlunt then
                impactDamage = math.max(impactDamage, 5)
            end

            if isHeadshot then
                impactDamage = impactDamage * 1.25
            end

            local newHealth = npc:Health() - impactDamage
            if newHealth < 5 then
                npc:SetHealth(5)
            else
                npc:SetHealth(newHealth)
            end
        end

        timer.Create(timerID, 0, 0, function()
            if not IsValid(ragdoll) then timer.Remove(timerID) return end
            if ragdoll.IsPermanentlyDead then return end
            
            local npc = ragdoll.AttachedNPC
            if not IsValid(npc) then timer.Remove(timerID) return end
            
            local physBone = ragdoll:GetPhysicsObjectNum(0)
            if IsValid(physBone) then npc:SetPos(physBone:GetPos()) else npc:SetPos(ragdoll:GetPos()) end
            
            if not ragdoll.WaterSlowWake then
                local contents = util.PointContents(ragdoll:GetPos())
                if bit.band(contents, CONTENTS_WATER) ~= 0 then
                    ragdoll.WaterSlowWake = true
                    ragdoll.WaterWakeEndTime = CurTime() + 3.0
                end
            end

            if ragdoll.WaterWakeEndTime then
                if CurTime() >= ragdoll.WaterWakeEndTime then
                    timer.Remove(timerID)
                    if IsValid(npc) and IsValid(ragdoll) then
                        npc:RemoveSpawnFlags(65536)
                        if npc.IsVJBaseNPC then 
                            npc.DisableSound = false 
                            npc:SetSoundVolume(1, 4) 
                        end
                        
                        local faceAway = (npc:GetPos() - owner:GetPos()):Angle()
                        faceAway.p = 0
                        faceAway.r = 0
                        
                        npc:SetPos(ragdoll:GetPos())
                        npc:SetAngles(faceAway)
                        ragdoll:Remove()
                        npc:SetNoDraw(false)
                        npc:SetSolid(SOLID_BBOX)
                        npc:SetMoveType(MOVETYPE_STEP)
                        npc.IsRagdolled = false
                        npc.IsRagdolledByShowel = false
                        hook.Remove("EntityTakeDamage", "ShovelRagdollNPCDamage_" .. npc:EntIndex())
                        npc:ClearSchedule()
                        if IsValid(owner) then
                            npc:SetEnemy(owner)
                            npc:AddEntityRelationship(owner, D_HT, 99)
                            if npc.SetNPCState then npc:SetNPCState(NPC_STATE_COMBAT) end
                            if npc.SetSchedule then npc:SetSchedule(SCHED_CHASE_ENEMY) end
                        elseif npc.SetNPCState then
                            npc:SetNPCState(NPC_STATE_ALERT)
                        end
                        npc:CapabilitiesAdd(CAP_USE_WEAPONS)
                        npc:Fire("Enable")
                        npc:Fire("Open")
                        
                        timer.Simple(0.5, function()
                            if not IsValid(npc) then return end
                            if IsValid(owner) then
                                npc:SetEnemy(owner)
                                npc:AddEntityRelationship(owner, D_HT, 99)
                                if npc.SetNPCState then npc:SetNPCState(NPC_STATE_COMBAT) end
                                if npc.SetSchedule then npc:SetSchedule(SCHED_CHASE_ENEMY) end
                            elseif npc.SetNPCState then
                                npc:SetNPCState(NPC_STATE_ALERT)
                            end
                            npc:CapabilitiesAdd(CAP_USE_WEAPONS)
                            npc:Fire("Enable")
                            npc:Fire("Open")
                        end)
                    end
                end
                return
            end

            if CurTime() >= wakeUpTime then
                timer.Remove(timerID)
                if IsValid(npc) and IsValid(ragdoll) then
                    npc:RemoveSpawnFlags(65536)
                    if npc.IsVJBaseNPC then 
                        npc.DisableSound = false 
                        npc:SetSoundVolume(1, 4) 
                    end
                    
                    local faceAway = (npc:GetPos() - owner:GetPos()):Angle()
                    faceAway.p = 0
                    faceAway.r = 0
                    
                    npc:SetPos(ragdoll:GetPos())
                    npc:SetAngles(faceAway)
                    ragdoll:Remove()
                    npc:SetNoDraw(false)
                    npc:SetSolid(SOLID_BBOX)
                    npc:SetMoveType(MOVETYPE_STEP)
                    npc.IsRagdolled = false
                    npc.IsRagdolledByShowel = false
                    hook.Remove("EntityTakeDamage", "ShovelRagdollNPCDamage_" .. npc:EntIndex())
                    npc:ClearSchedule()
                    if IsValid(owner) then
                        npc:SetEnemy(owner)
                        npc:AddEntityRelationship(owner, D_HT, 99)
                        if npc.SetNPCState then npc:SetNPCState(NPC_STATE_COMBAT) end
                        if npc.SetSchedule then npc:SetSchedule(SCHED_CHASE_ENEMY) end
                    elseif npc.SetNPCState then
                        npc:SetNPCState(NPC_STATE_ALERT)
                    end
                    npc:CapabilitiesAdd(CAP_USE_WEAPONS)
                    npc:Fire("Enable")
                    npc:Fire("Open")
                    
                    timer.Simple(0.5, function()
                        if not IsValid(npc) then return end
                        if IsValid(owner) then
                            npc:SetEnemy(owner)
                            npc:AddEntityRelationship(owner, D_HT, 99)
                            if npc.SetNPCState then npc:SetNPCState(NPC_STATE_COMBAT) end
                            if npc.SetSchedule then npc:SetSchedule(SCHED_CHASE_ENEMY) end
                        elseif npc.SetNPCState then
                            npc:SetNPCState(NPC_STATE_ALERT)
                        end
                        npc:CapabilitiesAdd(CAP_USE_WEAPONS)
                        npc:Fire("Enable")
                        npc:Fire("Open")
                    end)
                end
            end
        end)
    end
end

-- --- HUD & RENDER ---
function SWEP:DrawHUD()
    if self:GetIsCharging() then
        local chargeTime = math.Clamp(CurTime() - self:GetChargeStartTime(), 0, 10)
        local chargeRatio = math.Clamp(chargeTime / 10, 0, 1)
        local chargePercent = math.Round(chargeRatio * 100)
        local currentDmg = math.Round(10 + (chargeRatio * 40))
        local currentChance = math.Round(30 + (math.Clamp(chargeTime / 5, 0, 1) * 65))
        local scrW, scrH = ScrW(), ScrH()
        local barW, barH = 250, 25
        local x, y = (scrW - barW) / 2, scrH - 150
        
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawRect(x, y, barW, barH)
        
        if chargeRatio >= 1.0 then 
            surface.SetDrawColor(100, 220, 255, 255) 
        elseif chargeRatio >= 0.5 then 
            surface.SetDrawColor(0, 150, 255, 255) 
        else 
            surface.SetDrawColor(255, 140, 0, 255) 
        end
        
        surface.DrawRect(x, y, barW * chargeRatio, barH)
        surface.DrawOutlinedRect(x, y, barW, barH)
        
        draw.SimpleText("Shovel Charge: " .. chargePercent .. "%", "DermaDefaultBold", x + barW/2, y - 18, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        draw.SimpleText("Dmg: " .. currentDmg .. " | KO: " .. currentChance .. "%", "DermaDefault", x + barW/2, y + barH/2 - 6, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    if CurTime() - LastKOTime < 2.0 then
        local alpha = 255 - ((CurTime() - LastKOTime) * 127)
        draw.SimpleText("KNOCKOUT!", "DermaDefaultBold", ScrW() / 2, ScrH() / 2 + 100, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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