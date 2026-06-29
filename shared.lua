if SERVER then
    AddCSLuaFile( "shared.lua" )
    util.AddNetworkString("FlareGun_RedFirework")

    SWEP.Weight             = 5
    SWEP.AutoSwitchTo       = false
    SWEP.AutoSwitchFrom     = false
end

if CLIENT then
    language.Add("weapon_flaregun_beta", "Flare Gun")

    SWEP.PrintName = "Flare Gun"
    SWEP.Slot = 1
    SWEP.SlotPos = 5
    SWEP.DrawAmmo = false 
    SWEP.DrawCrosshair = true
    SWEP.ViewModelFOV = 54
    SWEP.AutoIconAngle = Angle(0,0,90)
    SWEP.ViewModelFlip = false
    SWEP.WepSelectIcon = surface.GetTextureID("HUD/swepicons/weapon_flaregun_beta") 
    SWEP.DrawWeaponInfoBox  = true
    SWEP.Purpose = "Hey, here's a thought. I've got a cigarette lighter. You've got a gun. Maybe you should go first. -Odell"
    SWEP.Instructions = "LMB: Fire | RMB: Toggle Mode"
    SWEP.BounceWeaponIcon = false 
    SWEP.UseHands = true

    -- Creates a saved client console variable for the skin preference (0 = Normal, 1 = Red, 2 = Black)
    local cl_skin = CreateClientConVar("cl_flaregun_skin", "0", true, false)

    local function GetSkinColor()
        if not cl_skin then return Color(255, 255, 255, 255) end
        local val = cl_skin:GetInt()
        if val == 1 then
            return Color(255, 0, 0, 255)    -- Red Finish
        elseif val == 2 then
            return Color(0, 0, 0, 255)      -- Fully Black Finish
        end
        return Color(255, 255, 255, 255)    -- Factory Normal
    end

    -- Registers the options menu interface under Options -> Weapons -> Olin Flare skin
    hook.Add("PopulateToolMenu", "OlinFlareSkinMenu", function()
        spawnmenu.AddToolMenuOption("Options", "Weapons", "OlinFlareSkin", "Olin Flare skin", "", "", function(panel)
            panel:ClearControls()
            panel:Help("Select a custom finish for your Olin Rocket Flare Gun:")
            
            panel:AddControl("ComboBox", {
                Label = "Skin Finish",
                MenuButton = 0,
                Folder = "",
                Options = {
                    ["Normal Skin"]       = { cl_flaregun_skin = "0" },
                    ["Red Skin"]          = { cl_flaregun_skin = "1" },
                    ["Fully Black Skin"]  = { cl_flaregun_skin = "2" }
                }
            })
        end)
    end)

    -- Dynamic viewmodel rendering adjustments
    function SWEP:PreDrawViewModel(vm, weapon, ply)
        if IsValid(vm) then vm:SetColor(GetSkinColor()) end
    end

    function SWEP:PostDrawViewModel(vm, weapon, ply)
        if IsValid(vm) then vm:SetColor(Color(255, 255, 255, 255)) end -- Reset container so hands aren't tainted
    end

    -- Dynamic worldmodel rendering adjustments
    function SWEP:DrawWorldModel()
        self:SetColor(GetSkinColor())
        self:DrawModel()
    end
end

local FlareFire = Sound( "Weapon_Flaregun.Single" )
local FlareEmpty = Sound( "Weapon_Pistol.Empty" )
local FlareReload = Sound( "Weapon_Flaregun.Reload" )

sound.Add( { name = "Weapon_Flaregun.Single", channel = CHAN_WEAPON, volume = 100, level = SNDLVL_GUNFIRE, pitch = "PITCH_NORM", sound = "weapons/flaregun/fire.wav" } )
sound.Add( { name = "Weapon_Flaregun.Reload", channel = CHAN_ITEM, volume = 100, level = SNDLVL_NORM, pitch = "PITCH_NORM", sound = "weapons/flaregun/reload.wav" } )

SWEP.Base       = "weapon_base"
SWEP.Category   = "Half-Life 2"
SWEP.HoldType   = "pistol"
SWEP.Spawnable = true
SWEP.AdminSpawnable = false
SWEP.ViewModel = "models/weapons/c_flaregun_beta.mdl"
SWEP.WorldModel = "models/weapons/w_flaregun_beta.mdl"

game.AddAmmoType( { name = "FlareRound", dmgtype = DMG_BURN, tracer = TRACER_LINE, plydmg = 30, npcdmg = 40, maxcarry = 20, force = 600 } )
game.AddAmmoType( { name = "Buckshot", dmgtype = DMG_BULLET, tracer = TRACER_LINE, plydmg = 20, npcdmg = 20, maxcarry = 40, force = 5 } )
if ( CLIENT ) then 
    language.Add( "FlareRound_ammo", "Flares" ) 
    language.Add( "Buckshot_ammo", "12 Gauge" )
end

SWEP.Primary.Recoil        = 2
SWEP.Primary.Sound         = Sound( "weapons/flaregun/fire.wav" )
SWEP.Primary.ClipSize      = 1
SWEP.Primary.DefaultClip   = 5
SWEP.Primary.Automatic     = false
SWEP.Primary.Delay         = 1
SWEP.Primary.Ammo          = "FlareRound"

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

function SWEP:Initialize()
    self:SetWeaponHoldType(self.HoldType)
    self:SetNWInt("FireMode", 0) 
end

function SWEP:Deploy()
    self.Weapon:SendWeaponAnim(ACT_VM_DRAW)
    self:SetNextPrimaryFire( CurTime() + self:SequenceDuration() )
    self:Idle()
    return true
end

function SWEP:Holster( weapon )
    if ( CLIENT ) then return end
    self:StopIdle()
    return true
end

function SWEP:PrimaryAttack()
    if self:Clip1() <= 0 then
        self:SendWeaponAnim(ACT_VM_DRYFIRE)
        self.Weapon:SetNextPrimaryFire( CurTime() + 1 )
        self.Weapon:SetNextSecondaryFire( CurTime() + 1 )
        self.Weapon:EmitSound( FlareEmpty )
        self:Reload()
        return
    end

    self.Weapon:SetNextPrimaryFire( CurTime() + 1 )
    self.Weapon:SetNextSecondaryFire( CurTime() + 1 )
    self.Weapon:TakePrimaryAmmo( 1 )
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    self.Owner:SetAnimation( PLAYER_ATTACK1 )

    local mode = self:GetNWInt("FireMode", 0)

    if mode == 1 then 
        self.Weapon:EmitSound( "Weapon_Shotgun.Single" )
        local bullet = {}
        bullet.Num = 12
        bullet.Src = self.Owner:GetShootPos()
        bullet.Dir = self.Owner:GetAimVector()
        bullet.Spread = Vector(0.15, 0.15, 0)
        bullet.Tracer = 1
        bullet.Force = 5
        bullet.Damage = 20 
        bullet.AmmoType = "Buckshot"
        self.Owner:FireBullets(bullet)
        self.Owner:ViewPunch( Angle( -10, math.Rand(-2,2), 0 ) )

    elseif mode == 2 then 
        self.Weapon:EmitSound( "Weapon_357.Single" )
        
        -- Recursive function to handle bullet bounces while keeping zero force setup
        local function FireSlug(src, dir, bounces)
            if bounces > 4 then return end -- Crash guard to prevent endless bouncing loops
            
            local bullet = {}
            bullet.Num = 1 
            bullet.Src = src
            bullet.Dir = dir
            bullet.Spread = Vector(0, 0, 0) 
            bullet.Tracer = 1
            bullet.Force = 0 -- Keep physics pushback disabled
            bullet.Damage = 40 -- Updated damage to 40
            bullet.AmmoType = "357"
            
            bullet.Callback = function(attacker, tr, dmginfo)
                -- 90% chance to ricochet off of metallic textures/materials
                if tr.MatType == MAT_METAL and math.random(1, 100) <= 90 then
                    -- Calculate dynamic angle of reflection
                    local dot = tr.Normal:Dot(tr.HitNormal)
                    local reflectDir = tr.Normal - 2 * dot * tr.HitNormal
                    
                    -- Spawn physical spark effects and sound at impact zone
                    local effect = EffectData()
                    effect:SetOrigin(tr.HitPos)
                    effect:SetNormal(tr.HitNormal)
                    util.Effect("MetalSpark", effect)
                    
                    sound.Play("weapons/fx/rics/ric" .. math.random(1, 5) .. ".wav", tr.HitPos, 80, math.random(90, 110))
                    
                    -- Re-fire the reflected slug slightly forward off the wall
                    FireSlug(tr.HitPos + reflectDir * 2, reflectDir, bounces + 1)
                end
            end
            
            self.Owner:FireBullets(bullet)
        end
        
        FireSlug(self.Owner:GetShootPos(), self.Owner:GetAimVector(), 0)
        self.Owner:ViewPunch( Angle( -14, math.Rand(-1,1), 0 ) ) 

    else 
        self.Weapon:EmitSound( FlareFire )
        self:LaunchFlare(3000)
        self.Owner:ViewPunch( Angle( -3, 0, 0 ) )
    end
end

function SWEP:SecondaryAttack()
    if not IsFirstTimePredicted() then return end
    
    local currentMode = self:GetNWInt("FireMode", 0)
    
    if self:Clip1() > 0 then
        local returnAmmo = "FlareRound"
        if currentMode == 1 then
            returnAmmo = "Buckshot"
        elseif currentMode == 2 then
            returnAmmo = "357"
        end
        self.Owner:GiveAmmo(1, returnAmmo)
        self:SetClip1(0)
    end
    
    local newMode = (currentMode + 1) % 3
    self:SetNWInt("FireMode", newMode)
    
    if newMode == 0 then
        self.Primary.Ammo = "FlareRound"
    elseif newMode == 1 then
        self.Primary.Ammo = "Buckshot"
    elseif newMode == 2 then
        self.Primary.Ammo = "357"
    end
    
    self.Weapon:EmitSound("weapons/smg1/switch_single.wav")
    self.Weapon:SetNextPrimaryFire( CurTime() + 0.5 )
    self.Weapon:SetNextSecondaryFire( CurTime() + 0.5 )
end

if CLIENT then
    hook.Add("HUDShouldDraw", "HideFlareGunAmmo", function(name)
        if IsValid(LocalPlayer():GetActiveWeapon()) and LocalPlayer():GetActiveWeapon():GetClass() == "weapon_flaregun_beta" then
            if (name == "CHudAmmo" or name == "CHudSecondaryAmmo") then return false end
        end
    end)

    hook.Add("HUDPaint", "DrawCustomFlareGunAmmo", function()
        local wep = LocalPlayer():GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() != "weapon_flaregun_beta" then return end
        
        local x, y = ScrW() - 220, ScrH() - 100
        
        local mode = wep:GetNWInt("FireMode", 0)
        local modeText = "MODE: FLARES"
        local ammoType = "FlareRound"
        
        if mode == 1 then
            modeText = "MODE: 12 GAUGE"
            ammoType = "Buckshot"
        elseif mode == 2 then
            modeText = "MODE: SLUG"
            ammoType = "357" 
        end
        
        local reserve = LocalPlayer():GetAmmoCount(ammoType)
        local ammoCount = wep:Clip1()

        draw.RoundedBox(4, x, y, 200, 60, Color(0, 0, 0, 200))
        draw.SimpleText(modeText, "DermaDefaultBold", x + 10, y + 10, Color(255, 255, 255))
        draw.SimpleText("IN CLIP: " .. ammoCount .. " | RESERVE: " .. reserve, "DermaDefault", x + 10, y + 30, Color(255, 200, 0))
    end)
end

local function DetonateFlare(flare, attacker, inflictor, explicitPos, isMidAir)
    if not IsValid(flare) or flare.HasDetonated then return end
    flare.HasDetonated = true
    
    local pos = explicitPos or flare:GetPos()
    
    local radius = isMidAir and 180 or 100
    local damage = isMidAir and 35 or 20
    util.BlastDamage(inflictor, attacker, pos, radius, damage)
    
    net.Start("FlareGun_RedFirework")
        net.WriteVector(pos)
        net.WriteBool(isMidAir) 
    net.Broadcast()
    
    flare:Remove()
end

function SWEP:LaunchFlare(force)
    if CLIENT then return end
    local ply = self.Owner
    local ply_Ang = ply:GetAimVector():Angle()
    
    local flare = ents.Create("prop_physics")
    if not IsValid(flare) then return end
    
    flare:SetModel("models/items/ar2_grenade.mdl")
    flare:SetPos( ply:GetShootPos() + ply_Ang:Forward() * 18 + ply_Ang:Right() * 8 + ply_Ang:Up() * -2 )
    flare:SetAngles(ply_Ang)
    flare:SetOwner(ply)
    
    flare:Spawn()
    flare:SetMoveType(MOVETYPE_VPHYSICS)
    flare:SetSolid(SOLID_VPHYSICS)
    
    flare:SetColor(Color(255, 120, 60, 255))
    flare:SetRenderMode(RENDERMODE_TRANSCOLOR)
    
    local phys = flare:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(ply:GetAimVector() * force)
        phys:SetMass(1)
        phys:EnableGravity(true)
        phys:Wake()
    end
    
    util.SpriteTrail(flare, 0, Color(255, 40, 15), false, 14, 2, 0.75, 0.05, "effects/beam_generic01.vmt")
    
    flare.SpawnTime = CurTime()
    flare.Shooter = ply
    flare.Wep = self
    
    flare:AddCallback("PhysicsCollide", function(ent, data)
        timer.Simple(0, function()
            if IsValid(ent) then 
                DetonateFlare(ent, ent.Shooter, ent.Wep, data.HitPos, false) 
            end
        end)
    end)
    
    local fIdx = flare:EntIndex()
    timer.Create("FlareTracker_" .. fIdx, 0.05, 0, function()
        if not IsValid(flare) then timer.Remove("FlareTracker_" .. fIdx) return end
        
        if CurTime() - flare.SpawnTime > 4.9 then
            DetonateFlare(flare, flare.Shooter, flare.Wep, flare:GetPos(), true)
            timer.Remove("FlareTracker_" .. fIdx)
            return
        end

        if flare:WaterLevel() > 0 then
            sound.Play("ambient/levels/canals/toxic_slime_sizzle2.wav", flare:GetPos(), 75, math.random(95, 105))
            flare:Remove()
            timer.Remove("FlareTracker_" .. fIdx)
            return
        end
        
        for _, v in ipairs(ents.FindInSphere(flare:GetPos(), 32)) do
            if IsValid(v) and (v:IsPlayer() or v:IsNPC()) and v != flare.Shooter and v:Health() > 0 then
                v:Ignite(15, 1)
                DetonateFlare(flare, flare.Shooter, flare.Wep, flare:GetPos(), false)
                timer.Remove("FlareTracker_" .. fIdx)
                break
            end
        end
    end)
end

function SWEP:Reload()
    local mode = self:GetNWInt("FireMode", 0)
    local ammoType = "FlareRound"
    
    if mode == 1 then
        ammoType = "Buckshot"
    elseif mode == 2 then
        ammoType = "357"
    end
    self.Primary.Ammo = ammoType
    
    if ( self:Clip1() < self.Primary.ClipSize && self.Owner:GetAmmoCount( ammoType ) > 0 ) then
        if self:DefaultReload( ACT_VM_RELOAD ) then 
            self.Weapon:EmitSound( FlareReload )
            self:SetNextPrimaryFire( CurTime() + 1 )
            self:SetNextSecondaryFire( CurTime() + 1 )
            self:Idle()
        end
    end
end

function SWEP:DoIdleAnimation() self:SendWeaponAnim( ACT_VM_IDLE ) end
function SWEP:DoIdle()
    self:DoIdleAnimation()
    timer.Adjust( "weapon_idle" .. self:EntIndex(), self:SequenceDuration(), 0, function()
        if ( !IsValid( self ) ) then timer.Destroy( "weapon_idle" .. self:EntIndex() ) return end
        self:DoIdleAnimation()
    end )
end
function SWEP:StopIdle() timer.Destroy( "weapon_idle" .. self:EntIndex() ) end
function SWEP:Idle()
    if ( CLIENT || !IsValid( self.Owner ) ) then return end
    timer.Create( "weapon_idle" .. self:EntIndex(), self:SequenceDuration() - 0.2, 1, function()
        if ( !IsValid( self ) ) then return end
        self:DoIdle()
    end )
end

if CLIENT then
    net.Receive("FlareGun_RedFirework", function()
        local pos = net.ReadVector()
        local isMidAir = net.ReadBool() 
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        
        local emitter = ParticleEmitter(pos)
        if not IsValid(emitter) then return end

        if isMidAir then
            local distance = ply:GetPos():Distance(pos)
            
            sound.Play("ambient/explosions/explode_9.wav", pos, 140, math.random(110, 125))
            sound.Play("weapons/mortar/mortar_explode2.wav", pos, 120, math.random(90, 105))
            sound.Play("ambient/fire/gas_explosion_1.wav", pos, 125, math.random(135, 150))
            
            if distance > 1000 then
                local waveDelay = distance / 13500 
                timer.Simple(waveDelay, function()
                    if not IsValid(ply) then return end
                    surface.PlaySound("ambient/atmosphere/thunder1.wav")
                    ply:EmitSound("ambient/explosions/explode_4_far.wav", 75, math.random(85, 95), 1, CHAN_AUTO)
                end)
            end
            
            for i = 1, 4 do
                local glare = emitter:Add("sprites/light_glow02_add", pos)
                if glare then
                    glare:SetVelocity(Vector(0, 0, 0))
                    glare:SetDieTime(math.Rand(5.5, 7.0)) 
                    glare:SetStartAlpha(255)
                    glare:SetEndAlpha(0)
                    glare:SetStartSize(1500) 
                    glare:SetEndSize(100)
                    glare:SetColor(255, 70, 20)
                end
            end
            
            for i = 1, 70 do
                local part = emitter:Add("effects/fire_cloud1", pos)
                if part then
                    part:SetVelocity(VectorRand() * math.random(150, 450))
                    part:SetDieTime(math.Rand(1.2, 2.4)) 
                    part:SetStartAlpha(255)
                    part:SetEndAlpha(0)
                    part:SetStartSize(math.random(35, 60))
                    part:SetEndSize(math.random(110, 160))
                    part:SetColor(255, 55, 15)
                    part:SetAirResistance(120)
                end
            end
            
            for i = 1, 250 do
                local part = emitter:Add("effects/spark", pos)
                if part then
                    local heading = VectorRand()
                    heading:Normalize()
                    part:SetVelocity(heading * math.random(550, 1400))
                    part:SetDieTime(math.Rand(3.0, 5.2)) 
                    part:SetStartAlpha(255)
                    part:SetEndAlpha(0)
                    part:SetStartSize(math.random(6, 14))
                    part:SetEndSize(0)
                    part:SetColor(255, 140, 40)
                    part:SetGravity(Vector(0, 0, -160)) 
                    part:SetAirResistance(50)
                end
            end
            
            for i = 1, 90 do
                local part = emitter:Add("effects/yellowflare", pos)
                if part then
                    part:SetVelocity(VectorRand() * math.random(100, 450))
                    part:SetDieTime(math.Rand(2.5, 4.8)) 
                    part:SetStartAlpha(255)
                    part:SetEndAlpha(0)
                    part:SetStartSize(30)
                    part:SetEndSize(4)
                    part:SetColor(255, 30, 5)
                    part:SetGravity(Vector(0, 0, -45))
                    part:SetAirResistance(35)
                end
            end
            
            local dlight = DynamicLight(math.random(10000, 99999))
            if dlight then
                dlight.pos = pos
                dlight.r = 255; dlight.g = 45; dlight.b = 10
                dlight.brightness = 15      
                dlight.Decay = 45           
                dlight.Size = 10240         
                dlight.DieTime = CurTime() + 7.5 
            end
        else
            sound.Play("ambient/explosions/explode_9.wav", pos, 95, math.random(120, 135))
            
            for i = 1, 20 do
                local part = emitter:Add("effects/fire_cloud1", pos)
                if part then
                    part:SetVelocity(VectorRand() * math.random(60, 160))
                    part:SetDieTime(math.Rand(0.3, 0.5)) 
                    part:SetStartAlpha(230)
                    part:SetEndAlpha(0)
                    part:SetStartSize(math.random(15, 25))
                    part:SetEndSize(math.random(35, 55))
                    part:SetColor(255, 65, 20)
                    part:SetAirResistance(180)
                end
            end
            
            for i = 1, 25 do
                local part = emitter:Add("effects/spark", pos)
                if part then
                    part:SetVelocity(VectorRand() * math.random(200, 400))
                    part:SetDieTime(math.Rand(0.4, 0.8))
                    part:SetStartAlpha(255)
                    part:SetEndAlpha(0)
                    part:SetStartSize(math.random(4, 8))
                    part:SetEndSize(0)
                    part:SetColor(255, 100, 30)
                    part:SetGravity(Vector(0, 0, -300))
                end
            end
            
            local dlight = DynamicLight(math.random(10000, 99999))
            if dlight then
                dlight.pos = pos
                dlight.r = 255; dlight.g = 60; dlight.b = 20
                dlight.brightness = 5
                dlight.Decay = 1200
                dlight.Size = 400
                dlight.DieTime = CurTime() + 0.4
            end
        end
        
        emitter:Finish()
    end)
end
