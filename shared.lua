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

game.AddAmmoType( { name = "FlareRound", dmgtype = DMG_BURN, tracer = TRACER_LINE, plydmg = 20, npcdmg = 20, maxcarry = 20, force = 600 } )
game.AddAmmoType( { name = "Buckshot", dmgtype = DMG_BULLET, tracer = TRACER_LINE, plydmg = 8, npcdmg = 8, maxcarry = 20, force = 5 } )
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
    self:SetNWBool("ShotgunMode", false)
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

    if self:GetNWBool("ShotgunMode") then
        self.Weapon:EmitSound( "Weapon_Shotgun.Single" )
        local bullet = {}
        bullet.Num = 12
        bullet.Src = self.Owner:GetShootPos()
        bullet.Dir = self.Owner:GetAimVector()
        bullet.Spread = Vector(0.15, 0.15, 0)
        bullet.Tracer = 1
        bullet.Force = 5
        bullet.Damage = 8
        bullet.AmmoType = "Buckshot"
        self.Owner:FireBullets(bullet)
        self.Owner:ViewPunch( Angle( -10, math.Rand(-2,2), 0 ) )
    else
        self.Weapon:EmitSound( FlareFire )
        self:LaunchFlare(3200)
        self.Owner:ViewPunch( Angle( -3, 0, 0 ) )
    end
end

function SWEP:SecondaryAttack()
    if not IsFirstTimePredicted() then return end
    
    -- Return ammo if one is chambered
    if self:Clip1() > 0 then
        local returnAmmo = self:GetNWBool("ShotgunMode") and "Buckshot" or "FlareRound"
        self.Owner:GiveAmmo(1, returnAmmo)
        self:SetClip1(0)
    end
    
    -- Toggle mode
    local newMode = not self:GetNWBool("ShotgunMode")
    self:SetNWBool("ShotgunMode", newMode)
    
    -- Force set primary ammo so DefaultReload knows which one to use
    self.Primary.Ammo = newMode and "Buckshot" or "FlareRound"
    
    self.Weapon:EmitSound("weapons/smg1/switch_single.wav")
    self.Weapon:SetNextPrimaryFire( CurTime() + 0.5 )
    self.Weapon:SetNextSecondaryFire( CurTime() + 0.5 )
end

-- CUSTOM HUD CODE
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
        
        -- FIX: Determine type based on mode, not the SWEP table variable
        local isShotgun = wep:GetNWBool("ShotgunMode")
        local modeText = isShotgun and "MODE: 12 GAUGE" or "MODE: FLARES"
        local ammoType = isShotgun and "Buckshot" or "FlareRound"
        local reserve = LocalPlayer():GetAmmoCount(ammoType)
        
        local ammoCount = wep:Clip1()

        draw.RoundedBox(4, x, y, 200, 60, Color(0, 0, 0, 200))
        draw.SimpleText(modeText, "DermaDefaultBold", x + 10, y + 10, Color(255, 255, 255))
        draw.SimpleText("IN CLIP: " .. ammoCount .. " | RESERVE: " .. reserve, "DermaDefault", x + 10, y + 30, Color(255, 200, 0))
    end)
end

-- Detonation Logic
local function DetonateFlare(flare, attacker, inflictor)
    if not IsValid(flare) or flare.HasDetonated then return end
    flare.HasDetonated = true
    local pos = flare:GetPos()
    util.BlastDamage(inflictor, attacker, pos, 130, 20)
    net.Start("FlareGun_RedFirework")
        net.WriteVector(pos)
    net.Broadcast()
    flare:Remove()
end

function SWEP:LaunchFlare(force)
    if CLIENT then return end
    local ply = self.Owner
    local ply_Ang = ply:GetAimVector():Angle()
    local flare = ents.Create("env_flare")
    if not IsValid(flare) then return end
    flare:SetPos( ply:GetShootPos() + ply_Ang:Forward() * 18 + ply_Ang:Right() * 8 + ply_Ang:Up() * -2 )
    flare:SetAngles(ply_Ang)
    flare:Spawn()
    flare:Activate()
    flare:Fire( "Launch", tostring(force), 0 )
    util.SpriteTrail(flare, 0, Color(255, 50, 30), false, 8, 1, 0.45, 0.125, "effects/beam_generic01.vmt")
    flare.SpawnTime = CurTime()
    flare.Shooter = ply
    flare.Wep = self
    flare:AddCallback("PhysicsCollide", function(ent, data)
        if CurTime() - ent.SpawnTime > 0.05 then DetonateFlare(ent, ent.Shooter, ent.Wep) end
    end)
    local fIdx = flare:EntIndex()
    timer.Create("FlareTracker_" .. fIdx, 0.03, 0, function()
        if not IsValid(flare) then timer.Remove("FlareTracker_" .. fIdx) return end
        if flare:WaterLevel() > 0 then
            sound.Play("ambient/levels/canals/toxic_slime_sizzle2.wav", flare:GetPos(), 75, math.random(95, 105))
            flare:Remove()
            timer.Remove("FlareTracker_" .. fIdx)
            return
        end
        for _, v in ipairs(ents.FindInSphere(flare:GetPos(), 32)) do
            if IsValid(v) and (v:IsPlayer() or v:IsNPC()) and v != ply and v:Health() > 0 then
                v:Ignite(30, 1)
                DetonateFlare(flare, ply, self)
                timer.Remove("FlareTracker_" .. fIdx)
                break
            end
        end
    end)
end

function SWEP:Reload()
    -- Sync ammo type before calling DefaultReload
    local ammoType = self:GetNWBool("ShotgunMode") and "Buckshot" or "FlareRound"
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

-- Animation helpers
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
        sound.Play("ambient/explosions/explode_9.wav", pos, 100, math.random(130, 145))
        local emitter = ParticleEmitter(pos)
        if not IsValid(emitter) then return end
        for i = 1, 30 do
            local part = emitter:Add("effects/fire_cloud1", pos)
            if part then
                part:SetVelocity(VectorRand() * math.random(40, 200))
                part:SetDieTime(math.Rand(0.25, 0.5))
                part:SetStartAlpha(255)
                part:SetEndAlpha(0)
                part:SetStartSize(math.random(15, 25))
                part:SetEndSize(math.random(45, 65))
                part:SetColor(255, 35, 15)
                part:SetAirResistance(160)
            end
        end
        for i = 1, 45 do
            local part = emitter:Add("effects/spark", pos)
            if part then
                part:SetVelocity(VectorRand() * math.random(150, 550))
                part:SetDieTime(math.Rand(0.4, 0.85))
                part:SetStartAlpha(255)
                part:SetEndAlpha(0)
                part:SetStartSize(math.random(4, 8))
                part:SetEndSize(0)
                part:SetColor(255, 75, 50)
                part:SetGravity(Vector(0, 0, -250))
                part:SetAirResistance(40)
            end
        end
        emitter:Finish()
        local dlight = DynamicLight(math.random(1, 9999))
        if dlight then
            dlight.pos = pos
            dlight.r = 255
            dlight.g = 45
            dlight.b = 20
            dlight.brightness = 5
            dlight.Decay = 1000
            dlight.Size = 256
            dlight.DieTime = CurTime() + 0.15
        end
    end)
end
