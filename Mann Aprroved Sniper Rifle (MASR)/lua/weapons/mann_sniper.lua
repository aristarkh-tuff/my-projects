if SERVER then
    AddCSLuaFile()
    util.AddNetworkString("MASR_ToggleLaser")
    util.AddNetworkString("MASR_SetSkin")
end

-- ==========================================
-- ADDON METADATA & DESCRIPTION
-- ==========================================
SWEP.PrintName    = "Mann Approved Sniper Rifle"
SWEP.Author       = "Collaborator"
SWEP.Category     = "Mann Co. Tactical"
SWEP.Spawnable    = true
SWEP.AdminOnly    = false
SWEP.CanDrop      = true 

SWEP.Purpose      = "A 100% pin-point accurate sniper rifle equipped with a chargeable prototype laser system."
SWEP.Instructions = "Open console and type: bind KEY masr_toggle_laser\nActive laser dynamically ramps base damage from 100 up to 250 over 3 seconds."

SWEP.IsMASR = true 

-- Models
SWEP.ViewModel  = "models/weapons/w_models/w_sniperrifle.mdl"
SWEP.WorldModel = "models/weapons/w_models/w_sniperrifle.mdl"
SWEP.UseHands   = false 
SWEP.HoldType   = "ar2" 

-- Weapon Statistics
SWEP.Primary.ClipSize     = 1
SWEP.Primary.DefaultClip = 10
SWEP.Primary.Ammo        = "357"
SWEP.Primary.Automatic   = false

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Ammo        = "none"
SWEP.Secondary.Automatic   = false

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    self:SetClip1(self.Primary.ClipSize)
end

-- FIXED: Moved skin loading to Deploy so it has a valid owner
function SWEP:Deploy()
    self:SetHoldType(self.HoldType)
    
    if SERVER then
        local owner = self:GetOwner()
        if IsValid(owner) then
            local skin = owner:GetPData("MASR_Skin", 0)
            self:SetSkin(tonumber(skin))
        end
    end
    return true
end

-- ==========================================
-- CONSOLE COMMAND & NETWORKING (Bindable Laser)
-- ==========================================
if CLIENT then
    concommand.Add("masr_toggle_laser", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        
        if IsValid(wep) and wep.IsMASR then
            net.Start("MASR_ToggleLaser")
            net.SendToServer()
        end
    end)
end

if SERVER then
    net.Receive("MASR_ToggleLaser", function(len, ply)
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep.IsMASR then
            local currentState = wep:GetNWBool("MASR_Laser", false)
            wep:SetNWBool("MASR_Laser", not currentState)
            
            if not currentState then
                wep:SetNWFloat("MASR_LaserStartTime", CurTime())
                wep:SetNWFloat("MASR_CalcFinishTime", CurTime() + math.Rand(1, 3))
            else
                wep:SetNWFloat("MASR_LaserStartTime", 0)
                wep:SetNWFloat("MASR_CalcFinishTime", 0)
            end
            
            wep:EmitSound("buttons/lightswitch2.wav", 60, 110)
        end
    end)

    -- Handle skin saving
    net.Receive("MASR_SetSkin", function(len, ply)
        local skinID = net.ReadInt(16)
        ply:SetPData("MASR_Skin", skinID)
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep.IsMASR then
            wep:SetSkin(skinID)
        end
    end)
end

-- ==========================================
-- SHOOTING & ACCURACY & DAMAGE CHARGING
-- ==========================================
function SWEP:PrimaryAttack()
    if self:Clip1() <= 0 then 
        self:Reload()
        return 
    end
    
    self:SetNextPrimaryFire(CurTime() + 2.5)
    
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local filterList = {owner}
    if CLIENT and IsValid(self.ClientVM) then table.insert(filterList, self.ClientVM) end
    
    local eyeTrace = util.TraceLine({
        start = owner:GetShootPos(),
        endpos = owner:GetShootPos() + owner:GetAimVector() * 15000,
        filter = filterList
    })
    
    local baseDamage = 100
    if self:GetNWBool("MASR_Laser", false) then
        local startTime = self:GetNWFloat("MASR_LaserStartTime", CurTime())
        local elapsed = CurTime() - startTime
        local chargePercent = math.Clamp(elapsed / 3, 0, 1) 
        baseDamage = Lerp(chargePercent, 100, 250)
    end
    
    local finalDamage = (eyeTrace.HitGroup == HITGROUP_HEAD) and (baseDamage * 2) or baseDamage

    local bullet = {
        Num = 1,
        Src = owner:GetShootPos(),
        Dir = owner:GetAimVector(),
        Spread = Vector(0, 0, 0), 
        Tracer = 1,
        Damage = finalDamage,
        Force = 15
    }
    
    owner:FireBullets(bullet)
    self:SetClip1(0) 
    
    if SERVER then
        owner:ViewPunch(Angle(-4, util.SharedRandom("MASR", -1, 1), 0))
    end
    
    self:EmitSound("weapons/sniper_shoot.wav", 85, 100)
    owner:SetAnimation(PLAYER_ATTACK1)

    if self:GetNWBool("MASR_Laser", false) then
        self:SetNWFloat("MASR_LaserStartTime", CurTime())
        self:SetNWFloat("MASR_CalcFinishTime", CurTime() + math.Rand(1, 3))
    end

    timer.Simple(1.0, function()
        if IsValid(self) and IsValid(owner) and self:Clip1() <= 0 then
            self:Reload(true)
        end
    end)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    local isZoomed = not self:GetNWBool("MASR_Zoom", false)
    self:SetNWBool("MASR_Zoom", isZoomed)
    
    if SERVER then 
        self:GetOwner():SetFOV(isZoomed and 20 or 0, 0.15)
    end
end

function SWEP:Reload(isAuto)
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    if not isAuto and self:GetNextPrimaryFire() > CurTime() then return end
    if self:Clip1() >= self.Primary.ClipSize then return end
    if owner:GetAmmoCount(self.Primary.Ammo) <= 0 then return end

    self:SetClip1(1)
    owner:RemoveAmmo(1, self.Primary.Ammo)
end

function SWEP:Holster()
    if SERVER and IsValid(self:GetOwner()) then 
        self:GetOwner():SetFOV(0, 0) 
    end
    self:SetNWBool("MASR_Zoom", false)
    if CLIENT and IsValid(self.ClientVM) then
        self.ClientVM:Remove()
    end
    return true
end

function SWEP:OnRemove()
    if CLIENT and IsValid(self.ClientVM) then
        self.ClientVM:Remove()
    end
end

-- ==========================================
-- ENGINE RENDERING OVERRIDES (Client Only)
-- ==========================================
if CLIENT then

    function SWEP:CreateCSModel()
        if not IsValid(self.ClientVM) then
            self.ClientVM = ClientsideModel(self.WorldModel, RENDERGROUP_VIEWMODEL)
            if IsValid(self.ClientVM) then
                self.ClientVM:SetNoDraw(true)
                local skin = LocalPlayer():GetPData("MASR_Skin", 0)
                self.ClientVM:SetSkin(tonumber(skin))
            end
        end
    end

    function SWEP:PreDrawViewModel(vm)
        self:CreateCSModel()
        local ply = self:GetOwner()
        if not IsValid(ply) then return true end

        if IsValid(self.ClientVM) then
            local eyePos = ply:EyePos()
            local eyeAng = ply:EyeAngles()
            local forward = eyeAng:Forward() * 18  
            local right   = eyeAng:Right() * 5.5    
            local up      = eyeAng:Up() * -5.5       
            local renderPos = eyePos + forward + right + up
            local renderAng = Angle(eyeAng.p, eyeAng.y, eyeAng.r)
            renderAng:RotateAroundAxis(renderAng:Up(), 0)
            renderAng:RotateAroundAxis(renderAng:Right(), -2)

            self.ClientVM:SetRenderOrigin(renderPos)
            self.ClientVM:SetRenderAngles(renderAng)
            self.ClientVM:SetupBones()
            self.ClientVM:DrawModel()

            if self:GetNWBool("MASR_Laser", false) then
                local trace = util.TraceLine({
                    start = ply:GetShootPos(),
                    endpos = ply:GetShootPos() + ply:GetAimVector() * 15000,
                    filter = {ply, self.ClientVM, vm}
                })
                
                local laserStart = renderPos + eyeAng:Forward() * 25 + eyeAng:Right() * -0.5 + eyeAng:Up() * 3.2
                local activeFOV = ply:GetFOV()
                local isFullyZoomed = (activeFOV > 0 and activeFOV < 35)
                local currentBeamWidth = isFullyZoomed and 0.8 or 1.2
                local currentDotSize   = isFullyZoomed and 0.6 or 2.0

                render.SetColorMaterial()
                render.DrawBeam(laserStart, trace.HitPos, currentBeamWidth, 0, 1, Color(255, 0, 0, 60))
                render.DrawSphere(trace.HitPos, currentDotSize, 8, 8, Color(255, 0, 0, 160))
            end
        end
        return true 
    end

    function SWEP:DrawWorldModel()
        local owner = self:GetOwner()
        if IsValid(owner) then
            local boneId = owner:LookupBone("ValveBiped.Bip01_R_Hand")
            if boneId then
                local matrix = owner:GetBoneMatrix(boneId)
                if matrix then
                    local pos = matrix:GetTranslation()
                    local ang = matrix:GetAngles()
                    ang:RotateAroundAxis(ang:Forward(), 180)
                    ang:RotateAroundAxis(ang:Right(), 10)
                    pos = pos + ang:Forward() * 5 + ang:Right() * 2 + ang:Up() * -2
                    self:SetRenderOrigin(pos)
                    self:SetRenderAngles(ang)
                end
            end
        end
        self:DrawModel()
    end

    hook.Add("PopulateToolMenu", "MASR_Menu", function()
        spawnmenu.AddToolMenuOption("Options", "MASR", "MASR_Settings", "Sniper Settings", "", "", function(panel)
            panel:Help("Configure your personal weapon skin.")
            local slider = panel:NumSlider("Skin ID", "masr_skin_id", 0, 10, 0)
            local button = panel:Button("Save Favorite Skin")
            button.DoClick = function()
                local val = math.floor(GetConVar("masr_skin_id"):GetInt())
                net.Start("MASR_SetSkin")
                net.WriteInt(val, 16)
                net.SendToServer()
                chat.AddText(Color(255, 215, 0), "MASR: Skin preference saved!")
            end
        end)
    end)
    CreateClientConVar("masr_skin_id", 0, true, false)

    hook.Add("PostDrawTranslucentRenderables", "MASR_GlobalLaserSystem", function()
        for _, ply in ipairs(player.GetAll()) do
            if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then continue end
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) and wep.IsMASR and wep:GetNWBool("MASR_Laser", false) and IsValid(wep:GetOwner()) then
                local trace = util.TraceLine({
                    start = ply:GetShootPos(),
                    endpos = ply:GetShootPos() + ply:GetAimVector() * 15000,
                    filter = ply
                })
                local startPos = ply:GetShootPos() + ply:GetAimVector() * 25
                local boneId = ply:LookupBone("ValveBiped.Bip01_R_Hand")
                if boneId then
                    ply:SetupBones()
                    local matrix = ply:GetBoneMatrix(boneId)
                    if matrix then
                        local pos = matrix:GetTranslation()
                        local ang = matrix:GetAngles()
                        ang:RotateAroundAxis(ang:Forward(), 180)
                        ang:RotateAroundAxis(ang:Right(), 10)
                        local wepPos = pos + ang:Forward() * 5 + ang:Right() * 2 + ang:Up() * -2
                        startPos = wepPos + ang:Forward() * 35 + ang:Up() * 5.5 + ang:Right() * 0.1
                    end
                end
                render.SetColorMaterial()
                render.DrawBeam(startPos, trace.HitPos, 1.2, 0, 1, Color(255, 0, 0, 60))
                render.DrawSphere(trace.HitPos, 2.5, 8, 8, Color(255, 0, 0, 160))
            end
        end
    end)

    hook.Add("HUDPaint", "MASR_HUDDisplay", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or not wep.IsMASR then return end
        
        local isCycling = wep:GetNextPrimaryFire() > CurTime()
        local status = "ROUND LOADED"
        local statusColor = Color(0, 255, 100)
        
        if isCycling then
            status = "CYCLING BOLT..."
            statusColor = Color(255, 200, 0)
        elseif wep:Clip1() <= 0 then
            status = "CHAMBER EMPTY"
            statusColor = Color(255, 50, 50)
        end
        
        local reserve = ply:GetAmmoCount("357")
        local chargeText = "LASER OFFLINE"
        local chargeColor = Color(150, 150, 150)
        local rangeText = "RANGEFINDER: OFFLINE"
        local rangeColor = Color(150, 150, 150)
        
        local pct = 0
        if wep:GetNWBool("MASR_Laser", false) then
            local startTime = wep:GetNWFloat("MASR_LaserStartTime", CurTime())
            local elapsed = CurTime() - startTime
            pct = math.Min(math.Round((elapsed / 3) * 100), 100)
            chargeText = "LASER CHARGE: " .. pct .. "%"
            chargeColor = Color(255, 50, 50)
            
            local finishTime = wep:GetNWFloat("MASR_CalcFinishTime", 0)
            if CurTime() < finishTime then
                rangeText = "CALCULATING..."
                rangeColor = Color(255, 255, 0)
            else
                local trace = util.TraceLine({
                    start = ply:GetShootPos(),
                    endpos = ply:GetShootPos() + ply:GetAimVector() * 15000,
                    filter = ply
                })
                local distMeters = math.Round(trace.Fraction * 15000 * 0.01905, 1)
                rangeText = "DISTANCE: " .. distMeters .. "m"
                rangeColor = Color(0, 200, 255)
            end
        end

        local boxWidth, boxHeight = 240, 110
        local posX = ScrW() - boxWidth - 40
        local posY = ScrH() - boxHeight - 40

        draw.RoundedBox(6, posX, posY, boxWidth, boxHeight, Color(0, 0, 0, 180))
        draw.RoundedBox(0, posX, posY, 4, boxHeight, Color(255, 215, 0))

        draw.SimpleText("MASR .357 Tactical", "BudgetLabel", posX + 15, posY + 10, Color(255, 215, 0))
        draw.SimpleText(status, "BudgetLabel", posX + 15, posY + 25, statusColor)
        draw.SimpleText("Reserve Rounds: " .. reserve, "BudgetLabel", posX + 15, posY + 40, Color(255, 255, 255))
        draw.SimpleText(chargeText, "BudgetLabel", posX + 15, posY + 55, chargeColor)
        
        if wep:GetNWBool("MASR_Laser", false) then
            draw.RoundedBox(0, posX + 15, posY + 70, 210, 4, Color(50, 50, 50, 255))
            draw.RoundedBox(0, posX + 15, posY + 70, 210 * (pct/100), 4, Color(255, 50, 50, 255))
        end

        draw.SimpleText(rangeText, "BudgetLabel", posX + 15, posY + 85, rangeColor)
    end)

    hook.Add("HUDShouldDraw", "MASR_HideAmmo", function(name)
        if name == "CHudAmmo" then
            local ply = LocalPlayer()
            if IsValid(ply) and IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon().IsMASR then 
                return false 
            end
        end
    end)
end