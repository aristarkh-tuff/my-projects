AddCSLuaFile()

SWEP.PrintName = "Rebel Turret Remote"
SWEP.Author = "Aristarkh"
SWEP.Description = "LMB: Spawn/Shoot. RMB: Control. Zoom Key: Cycle Zoom (Off/35). E: Toggle Mode/Pickup. Hold R: Explode."
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

function SWEP:Initialize()
    self:SetHoldType("normal")
    self.NextMessage = 0
    self.NextRangeWarning = 0 
end

-- Networking Wrappers
function SWEP:GetPrecisionMode() return self:GetNWBool("PrecisionMode", false) end
function SWEP:SetPrecisionMode(val) self:SetNWBool("PrecisionMode", val) end
function SWEP:GetZoomLevel() return self:GetNWInt("ZoomLevel", 0) end
function SWEP:SetZoomLevel(val) self:SetNWInt("ZoomLevel", val) end
function SWEP:GetIsControlling() return self:GetNWBool("IsControlling", false) end
function SWEP:SetIsControlling(val) self:SetNWBool("IsControlling", val) end
function SWEP:SetActiveTurret(ent) self:SetNWEntity("ActiveTurret", ent) end
function SWEP:GetActiveTurret() return self:GetNWEntity("ActiveTurret", NULL) end

function SWEP:PerformSelfDestruct()
    local turret = self:GetActiveTurret()
    if not IsValid(turret) or not SERVER or turret.IsSelfDestructing then return end

    turret.IsSelfDestructing = true
    self:SetIsControlling(false)
    turret:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetActiveTurret(NULL)
    
    turret:EmitSound("npc/turret_floor/panic1.wav", 100, 100)
    if IsValid(self:GetOwner()) then
        self:GetOwner():ChatPrint("Self-Destruct in 2 seconds!")
    end

    timer.Simple(2, function()
        if IsValid(turret) then
            local effectdata = EffectData()
            effectdata:SetOrigin(turret:GetPos())
            util.Effect("Explosion", effectdata)
            util.BlastDamage(turret, self:GetOwner() or turret, turret:GetPos(), 200, 150)
            turret:Remove()
        end
    end)
end

function SWEP:PrimaryAttack()
    if not IsValid(self:GetOwner()) then return end
    if self:GetIsControlling() then return end
    if not IsFirstTimePredicted() then return end
    
    local ply = self:GetOwner()
    
    if SERVER then
        local turret = self:GetActiveTurret()
        if IsValid(turret) then
            if turret.IsSelfDestructing then return end
            
            if CurTime() > (self.NextMessage or 0) then
                ply:ChatPrint("Turret already deployed. Press RMB to control.")
                self.NextMessage = CurTime() + 2
            end
            return
        end

        local tr = ply:GetEyeTrace()
        
        if ply:GetPos():Distance(tr.HitPos) > 200 then
            if CurTime() > (self.NextRangeWarning or 0) then
                ply:ChatPrint("Too far! Get within 200 units to deploy.")
                self.NextRangeWarning = CurTime() + 1.5
            end
            return
        end

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
        self:SetPrecisionMode(false)
    end
end

function SWEP:SecondaryAttack()
    if not IsValid(self:GetOwner()) then return end
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
            self:SetZoomLevel(0) -- Reset zoom
        end
    end
end

function SWEP:Reload() end

function SWEP:Think()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if ply:KeyDown(IN_RELOAD) then
        if not self.ReloadHoldStart then
            self.ReloadHoldStart = CurTime()
        elseif CurTime() - self.ReloadHoldStart >= 1.0 then
            self:PerformSelfDestruct()
            self.ReloadHoldStart = nil
        end
    else
        self.ReloadHoldStart = nil
    end

    local turret = self:GetActiveTurret()

    -- ADJUSTED: Cycle Zoom: 0 -> 1 -> 0 (Max 35 FOV)
    if IsFirstTimePredicted() and ply:KeyPressed(IN_ZOOM) and self:GetIsControlling() then
        local nextLevel = (self:GetZoomLevel() + 1) % 2
        self:SetZoomLevel(nextLevel)
    end

    if not IsValid(turret) then 
        if self:GetIsControlling() then 
            self:SetIsControlling(false)
            self:SetActiveTurret(NULL)
        end
        return 
    end

    if turret.IsSelfDestructing then return end

    if SERVER then
        if CurTime() > (turret.NextAmmoRegen or 0) then
            turret:SetNWInt("TurretAmmo", math.Clamp(turret:GetNWInt("TurretAmmo") + 2, 0, 650))
            turret.NextAmmoRegen = CurTime() + 1
        end

        local heat = turret:GetNWFloat("TurretHeat")
        if heat > 0 then 
            turret:SetNWFloat("TurretHeat", math.Clamp(heat - (FrameTime() * 10), 0, 100)) 
        end

        for _, ent in pairs(ents.FindInSphere(turret:GetPos(), 60)) do
            local class = ent:GetClass()
            if class == "item_ammo_ar2" or class == "item_ammo_ar2_large" then
                local current = turret:GetNWInt("TurretAmmo")
                if current < 650 then
                    local addAmmo = (class == "item_ammo_ar2_large") and 100 or 30
                    turret:SetNWInt("TurretAmmo", math.Clamp(current + addAmmo, 0, 650))
                    ent:EmitSound("items/ammo_pickup.wav")
                    turret:EmitSound("items/ammo_pickup.wav", 75, 100)
                    ent:Remove()
                end
            end
        end

        if self:GetIsControlling() and ply:KeyPressed(IN_USE) then
            if ply:GetEyeTrace().Entity == turret and ply:GetPos():Distance(turret:GetPos()) < 100 then
                turret:Remove()
                self:SetActiveTurret(NULL)
                self:SetIsControlling(false)
            else
                local newState = not self:GetPrecisionMode()
                self:SetPrecisionMode(newState)
                ply:EmitSound("buttons/button14.wav", 75, 100)
            end
        end

        if self:GetIsControlling() then
            local targetAng = ply:EyeAngles()
            turret:SetAngles(Angle(0, targetAng.y, 0))
            turret:SetPoseParameter("aim_pitch", math.Clamp(targetAng.p, -45, 45))
            turret:SetPoseParameter("aim_yaw", 0) 

            local isPrecision = self:GetPrecisionMode()
            local fireDelay = isPrecision and 0.2 or 0.1
            -- Balanced 95% accuracy spread
            local currentSpread = isPrecision and Vector(0.005, 0.005, 0) or Vector(0.08, 0.08, 0)

            if ply:KeyDown(IN_ATTACK) and turret:GetNWInt("TurretAmmo") > 0 then
                if CurTime() > turret.NextShootTime then
                    local muzzleID = turret:LookupAttachment("muzzle")
                    local attach = turret:GetAttachment(muzzleID)
                    local shootPos = (attach and attach.Pos or turret:GetPos() + Vector(0,0,45)) + Vector(0,0,8)

                    turret:FireBullets({
                        Attacker = ply, Damage = 3, Force = 1, Distance = 4000,
                        Num = 1, Tracer = 1, TracerName = "AR2Tracer", 
                        Src = shootPos, Dir = targetAng:Forward(), Spread = currentSpread,
                        Callback = function(att, tr, dmg)
                            if SERVER then
                                if tr.HitGroup == HITGROUP_HEAD then
                                    local rng = math.random(1, 100)
                                    if rng <= 40 then dmg:SetDamage(20) elseif rng <= 80 then dmg:SetDamage(10) end
                                end
                                util.Decal("Impact.Bullet", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
                                local effectdata = EffectData()
                                effectdata:SetOrigin(tr.HitPos)
                                effectdata:SetNormal(tr.HitNormal)
                                util.Effect("Impact", effectdata)
                                if IsValid(tr.Entity) and tr.Entity:IsNPC() then
                                    tr.Entity:AddEntityRelationship(turret, D_HT, 99)
                                    tr.Entity:UpdateEnemyMemory(turret, tr.HitPos)
                                    if tr.Entity.SetEnemy then tr.Entity:SetEnemy(turret) end
                                    if tr.Entity.SetTarget then tr.Entity:SetTarget(turret) end
                                end
                            end
                        end
                    })
                    
                    local soundPath = (math.random(1, 2) == 1) and "npc/turret_floor/shoot1.wav" or "npc/turret_floor/shoot2.wav"
                    turret:EmitSound(soundPath, 80, 100)
                    turret:SetNWInt("TurretAmmo", turret:GetNWInt("TurretAmmo") - 1)
                    turret:SetNWFloat("TurretHeat", math.Clamp(turret:GetNWFloat("TurretHeat") + 2, 0, 100))
                    turret.NextShootTime = CurTime() + fireDelay
                end
            end
        end
    end
end

if CLIENT then
    -- SENSITIVITY HOOK: Proportional scaling for 35 FOV
    hook.Add("CreateMove", "RebelTurretSensitivity", function(cmd)
        local ply = LocalPlayer()
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "weapon_rebel_turret" or not wep.GetIsControlling or not wep:GetIsControlling() then return end

        local defaultFOV = ply:GetFOV()
        local currentFOV = wep.CurrentFOV or defaultFOV

        if currentFOV < defaultFOV then
            local fovRatio = currentFOV / defaultFOV
            -- Proportional multiplier with a smooth response curve
            local mult = math.Clamp(math.pow(fovRatio, 1.2), 0.1, 1.0)
            
            cmd:SetMouseX(cmd:GetMouseX() * mult)
            cmd:SetMouseY(cmd:GetMouseY() * mult)
        end
    end)

    hook.Add("CalcView", "RebelTurretCamera", function(ply, pos, ang, fov)
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "weapon_rebel_turret" or not wep.GetIsControlling or not wep:GetIsControlling() then 
            wep.CurrentFOV = nil 
            return 
        end

        local turret = wep:GetActiveTurret()
        if IsValid(turret) then
            local muzzleID = turret:LookupAttachment("muzzle")
            local attach = turret:GetAttachment(muzzleID)
            local tPos = attach and attach.Pos or (turret:GetPos() + turret:GetUp() * 45)

            if not wep.CurrentFOV then wep.CurrentFOV = fov end

            -- ADJUSTED: Target zoom is now explicitly capped at 35 FOV
            local level = wep:GetZoomLevel()
            local targetFOV = (level == 1 and 35) or fov
            
            wep.CurrentFOV = Lerp(FrameTime() * 10, wep.CurrentFOV, targetFOV)

            local view = {}
            view.angles = ply:EyeAngles()
            view.fov = wep.CurrentFOV
            view.drawviewer = true
            view.origin = tPos + (turret:GetForward() * 12) + (turret:GetUp() * 8)
            
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
        surface.DrawRect(x, y, 300, 140)
        surface.SetDrawColor(255, 165, 0, 255)
        surface.DrawOutlinedRect(x, y, 300, 140)

        local isPrecision = self:GetPrecisionMode()
        local modeText = isPrecision and "PRECISION" or "RAPID"
        local modeColor = isPrecision and Color(0, 255, 0) or Color(255, 165, 0)

        draw.SimpleText("STATUS: LINKED", "Trebuchet24", x + 10, y + 10, Color(255, 165, 0))
        draw.SimpleText("MODE: " .. modeText, "Trebuchet24", x + 10, y + 35, modeColor)
        draw.SimpleText("HEALTH: " .. turret:Health(), "Trebuchet24", x + 10, y + 60, Color(255, 165, 0))
        draw.SimpleText("AMMO: " .. turret:GetNWInt("TurretAmmo") .. " / 650", "Trebuchet24", x + 10, y + 85, Color(255, 165, 0))
        
        draw.SimpleText("HEAT:", "Trebuchet18", x + 10, y + 113, Color(255, 165, 0))
        surface.SetDrawColor(50, 50, 50, 255)
        surface.DrawRect(x + 60, y + 115, 220, 15)
        surface.SetDrawColor(255, 165, 0, 255)
        surface.DrawRect(x + 60, y + 115, (turret:GetNWFloat("TurretHeat") / 100) * 220, 15)
        
        surface.DrawLine(scrW/2 - 10, scrH/2, scrW/2 + 10, scrH/2)
        surface.DrawLine(scrW/2, scrH/2 - 10, scrW/2, scrH/2 + 10)

        local tr = util.TraceLine({
            start = EyePos(),
            endpos = EyePos() + LocalPlayer():GetAimVector() * 5000,
            filter = {LocalPlayer(), turret}
        })

        if IsValid(tr.Entity) and tr.Entity:Health() > 0 then
            draw.SimpleText("TARGET HP: " .. tr.Entity:Health(), "Trebuchet24", scrW / 2, scrH - 100, Color(255, 50, 50), TEXT_ALIGN_CENTER)
        end
    end
end

-- ========================================================
-- PVS FIX: Keeps map props fully rendered while looking 
-- through the turret view from behind solid geometry.
-- ========================================================
if SERVER then
    hook.Add("SetupPlayerVisibility", "RebelTurretVisibility", function(ply, viewEntity)
        if not IsValid(ply) then return end
        
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep:GetClass() == "weapon_rebel_turret" and wep.GetIsControlling and wep:GetIsControlling() then
            local turret = wep:GetActiveTurret()
            if IsValid(turret) then
                AddOriginToPVS(turret:GetPos())
            end
        end
    end)
end