AddCSLuaFile()

SWEP.PrintName = "Remote Combine Turret"
SWEP.Author = "Aristarkh"
SWEP.Instructions = "LMB: Spawn/Shoot. RMB: Control. R: Explode. E: Pick up."
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Category = "Half-Life 2"

SWEP.ViewModel = ""
SWEP.WorldModel = ""
SWEP.UseHands = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:SetupDataTables()
    self:NetworkVar("Entity", 0, "ActiveTurret")
    self:NetworkVar("Bool", 0, "IsControlling")
    self:NetworkVar("Bool", 1, "ThirdPerson")
end

function SWEP:Initialize()
    self:SetHoldType("normal")
    self.NextMessage = 0
end

function SWEP:PrimaryAttack()
    if self:GetIsControlling() then return end
    if not IsFirstTimePredicted() then return end
    
    local ply = self:GetOwner()
    
    if SERVER then
        local turret = self:GetActiveTurret()
        if IsValid(turret) then
            if CurTime() > (self.NextMessage or 0) then
                ply:ChatPrint("Turret already deployed. Press RMB to control.")
                self.NextMessage = CurTime() + 2
            end
            return
        end

        local tr = ply:GetEyeTrace()
        local newTurret = ents.Create("npc_turret_floor")
        if not IsValid(newTurret) then return end

        newTurret:SetPos(tr.HitPos)
        newTurret:SetAngles(Angle(0, ply:EyeAngles().y, 0))
        newTurret:SetSkin(math.random(0, 1))
        
        newTurret:Spawn()
        newTurret:Activate()
        
        newTurret:SetNPCState(NPC_STATE_IDLE)
        newTurret:SetMoveType(MOVETYPE_VPHYSICS)
        
        newTurret:AddFlags(FL_NOTARGET)
        newTurret:Fire("Disable") 
        
        newTurret:SetNWInt("TurretAmmo", 650)
        newTurret:SetNWFloat("TurretHeat", 0)
        newTurret.NextAmmoRegen = CurTime()
        newTurret.NextShootTime = CurTime()
        newTurret.IsSelfDestructing = false

        self:SetActiveTurret(newTurret)
    end
end

function SWEP:SecondaryAttack()
    if not IsFirstTimePredicted() then return end
    local turret = self:GetActiveTurret()
    if not IsValid(turret) or turret.IsSelfDestructing then return end

    if SERVER then
        local newState = not self:GetIsControlling()
        self:SetIsControlling(newState)
        
        if newState then
            turret:SetMoveType(MOVETYPE_NONE) 
        else
            turret:SetMoveType(MOVETYPE_VPHYSICS)
        end
    end
end

function SWEP:Reload()
    local turret = self:GetActiveTurret()
    if not IsValid(turret) or not SERVER or turret.IsSelfDestructing then return end

    turret.IsSelfDestructing = true
    self:SetIsControlling(false)
    turret:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetActiveTurret(NULL)
    
    turret:EmitSound("npc/turret_floor/panic1.wav", 100, 100)
    self:GetOwner():ChatPrint("Self-Destruct in 2 seconds!")

    timer.Simple(2, function()
        if IsValid(turret) then
            local effectdata = EffectData()
            effectdata:SetOrigin(turret:GetPos())
            util.Effect("Explosion", effectdata)
            util.BlastDamage(turret, self:GetOwner(), turret:GetPos(), 200, 150)
            turret:Remove()
        end
    end)
end

function SWEP:Think()
    local ply = self:GetOwner()
    local turret = self:GetActiveTurret()

    if CLIENT and ply:KeyPressed(IN_WALK) then
        self:SetThirdPerson(not self:GetThirdPerson())
    end

    if not IsValid(turret) then 
        if self:GetIsControlling() then 
            self:SetIsControlling(false)
            self:SetActiveTurret(NULL)
        end
        return 
    end

    if SERVER and not turret.IsSelfDestructing then
        -- Ammo Regeneration
        if CurTime() > (turret.NextAmmoRegen or 0) then
            turret:SetNWInt("TurretAmmo", math.Clamp(turret:GetNWInt("TurretAmmo") + 2, 0, 650))
            turret.NextAmmoRegen = CurTime() + 1
        end

        -- SQUARE PICKUP TRIGGER
        -- Follows the turret because it uses current turret position
        local tPos = turret:GetPos()
        local size = 45 -- 45 units in all directions
        local entities = ents.FindInBox(tPos + Vector(-size, -size, 0), tPos + Vector(size, size, 60))

        for _, ent in pairs(entities) do
            if ent:GetClass() == "item_ammo_ar2" then
                local current = turret:GetNWInt("TurretAmmo")
                if current < 650 then
                    turret:SetNWInt("TurretAmmo", math.Clamp(current + 100, 0, 650))
                    ent:EmitSound("items/ammo_pickup.wav")
                    turret:EmitSound("items/ammo_pickup.wav", 75, 100)
                    ent:Remove()
                end
            end
        end

        if ply:KeyPressed(IN_USE) and ply:GetEyeTrace().Entity == turret and ply:GetPos():Distance(turret:GetPos()) < 100 then
            turret:Remove()
            self:SetActiveTurret(NULL)
            self:SetIsControlling(false)
            return
        end

        if self:GetIsControlling() then
            local targetAng = ply:EyeAngles()
            
            turret:SetAngles(Angle(0, targetAng.y, 0))
            turret:SetPoseParameter("aim_pitch", math.Clamp(targetAng.p, -45, 45))
            turret:SetPoseParameter("aim_yaw", 0) 

            if ply:KeyDown(IN_ATTACK) and turret:GetNWInt("TurretAmmo") > 0 then
                if CurTime() > turret.NextShootTime then
                    local muzzleID = turret:LookupAttachment("muzzle")
                    local attach = turret:GetAttachment(muzzleID)
                    local shootPos = attach and attach.Pos or turret:GetPos() + Vector(0,0,45)

                    turret:FireBullets({
                        Attacker = ply, Damage = 3, Force = 1, Distance = 4000,
                        Num = 1, Tracer = 1, TracerName = "AR2Tracer",
                        Src = shootPos, Dir = targetAng:Forward(), Spread = Vector(0.08, 0.08, 0)
                    })
                    
                    local soundPath = (math.random(1, 2) == 1) and "npc/turret_floor/shoot1.wav" or "npc/turret_floor/shoot2.wav"
                    turret:EmitSound(soundPath, 80, 100)
                    
                    turret:SetNWInt("TurretAmmo", turret:GetNWInt("TurretAmmo") - 1)
                    turret:SetNWFloat("TurretHeat", math.Clamp(turret:GetNWFloat("TurretHeat") + 2, 0, 100))
                    turret.NextShootTime = CurTime() + 0.1
                end
            end
            local heat = turret:GetNWFloat("TurretHeat")
            if heat > 0 then turret:SetNWFloat("TurretHeat", math.Clamp(heat - (FrameTime() * 10), 0, 100)) end
        end
    end
end

if CLIENT then
    hook.Add("Think", "RebelTurretLocalVisibility", function()
        local ply = LocalPlayer()
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "weapon_rebel_turret" or not wep.GetIsControlling then return end
        
        local turret = wep:GetActiveTurret()
        if IsValid(turret) then
            turret:SetNoDraw(wep:GetIsControlling() and not wep:GetThirdPerson())
        end
    end)

    hook.Add("CalcView", "RebelTurretCamera", function(ply, pos, ang, fov)
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "weapon_rebel_turret" or not wep.GetIsControlling or not wep:GetIsControlling() then return end

        local turret = wep:GetActiveTurret()
        if IsValid(turret) then
            local muzzleID = turret:LookupAttachment("muzzle")
            local attach = turret:GetAttachment(muzzleID)
            local tPos = attach and attach.Pos or (turret:GetPos() + turret:GetUp() * 45)

            local view = {}
            if wep:GetThirdPerson() then
                view.origin = tPos - (turret:GetForward() * 60) + (turret:GetUp() * 20)
            else
                view.origin = tPos
            end
            view.angles = ply:EyeAngles()
            view.fov = fov
            view.drawviewer = true
            return view
        end
    end)

    function SWEP:DrawHUD()
        if not self.GetIsControlling or not self:GetIsControlling() then return end
        local turret = self:GetActiveTurret()
        if not IsValid(turret) then return end

        local scrW, scrH = ScrW(), ScrH()
        local x, y = scrW - 320, scrH - 140

        surface.SetDrawColor(0, 0, 0, 200)
        surface.DrawRect(x, y, 300, 120)
        surface.SetDrawColor(255, 165, 0, 255)
        surface.DrawOutlinedRect(x, y, 300, 120)

        draw.SimpleText("STATUS: LINKED", "Trebuchet24", x + 10, y + 10, Color(255, 165, 0))
        draw.SimpleText("HEALTH: " .. turret:Health(), "Trebuchet24", x + 10, y + 40, Color(255, 165, 0))
        draw.SimpleText("AMMO: " .. turret:GetNWInt("TurretAmmo") .. " / 650", "Trebuchet24", x + 10, y + 65, Color(255, 165, 0))
        
        draw.SimpleText("HEAT:", "Trebuchet18", x + 10, y + 93, Color(255, 165, 0))
        surface.SetDrawColor(50, 50, 50, 255)
        surface.DrawRect(x + 60, y + 95, 220, 15)
        surface.SetDrawColor(255, 165, 0, 255)
        surface.DrawRect(x + 60, y + 95, (turret:GetNWFloat("TurretHeat") / 100) * 220, 15)
        
        surface.DrawLine(scrW/2 - 10, scrH/2, scrW/2 + 10, scrH/2)
        surface.DrawLine(scrW/2, scrH/2 - 10, scrW/2, scrH/2 + 10)

        local tr = util.TraceLine({
            start = EyePos(),
            endpos = EyePos() + LocalPlayer():GetAimVector() * 5000,
            filter = {LocalPlayer(), turret}
        })

        if IsValid(tr.Entity) and tr.Entity:Health() > 0 then
            draw.SimpleText("TARGET HEALTH: " .. tr.Entity:Health(), "Trebuchet24", scrW/2, scrH/2 + 30, Color(255, 0, 0), TEXT_ALIGN_CENTER)
        end
    end
end