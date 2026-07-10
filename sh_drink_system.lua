-- Single-file Food & Drink Props System (Jug, Uncapped Vodka, Milk Detox, Bottle Shatter & Melon Gib Update)
-- Save this file in: garrysmod/lua/autorun/sh_drink_system.lua

local cv_tf2 = CreateConVar("gmod_food_tf2_mode", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Enable TF2 Content Mode (Adds Heavy's Sandvich)")
local cv_fat = CreateConVar("gmod_food_enable_fat", "1", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Toggle the weight gain and bone inflation system completely")
local cv_ragmod = CreateConVar("gmod_food_enable_ragmod_trip", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Allow highly drunk players to randomly pass out into a Ragmod state")

local SWEP_BASE_DATA = {}
SWEP_BASE_DATA.Base = "weapon_base"

-- Initialize sub-tables
SWEP_BASE_DATA.Primary = {}
SWEP_BASE_DATA.Primary.ClipSize = -1
SWEP_BASE_DATA.Primary.DefaultClip = -1
SWEP_BASE_DATA.Primary.Automatic = true 

SWEP_BASE_DATA.Secondary = {}
SWEP_BASE_DATA.Secondary.ClipSize = -1
SWEP_BASE_DATA.Secondary.DefaultClip = -1
SWEP_BASE_DATA.Secondary.Automatic = false

SWEP_BASE_DATA.UseHands = false 
SWEP_BASE_DATA.HoldType = "slam" 
SWEP_BASE_DATA.Category = "Food n Drink Props"
SWEP_BASE_DATA.Spawnable = true
SWEP_BASE_DATA.ViewModel = "models/weapons/v_hands.mdl"

SWEP_BASE_DATA.DrawAmmo = false
SWEP_BASE_DATA.DrawCrosshair = false

function SWEP_BASE_DATA:SetupDataTables()
    self:NetworkVar("Int", 0, "MaxAmmo")
end

function SWEP_BASE_DATA:Initialize()
    self:SetHoldType(self.HoldType)
    if SERVER then
        local maxHP = isfunction(self.MaxHealthCapacity) and self.MaxHealthCapacity() or self.MaxHealthCapacity
        self:SetMaxAmmo(maxHP)
        
        local startHP = self.SpawnHealthCapacity or maxHP
        if isfunction(startHP) then startHP = startHP() end
        self:SetClip1(startHP)
    end
end

function SWEP_BASE_DATA:PrimaryAttack()
    if self:Clip1() <= 0 then return end
    
    local owner = self:GetOwner()
    local fireDelay = self.CustomDelay or 0.15 

    if IsValid(owner) then
        if not self.CustomDelay then
            local lookUpFactor = math.max(0, owner:GetAimVector().z) 
            fireDelay = Lerp(lookUpFactor, 0.15, 0.04)
        end
        
        -- Alcohol Fire-rate Acceleration (Scales up to 250 for Vodka)
        local drunk = owner:GetNWFloat("BeerDrunk", 0)
        if drunk > 20 then
            local speedFactor = math.Remap(math.min(drunk, 250), 20, 100, 1.0, 0.5)
            fireDelay = fireDelay * speedFactor
        end
    end
    
    self:SetNextPrimaryFire(CurTime() + fireDelay) 

    if SERVER then
        if IsValid(owner) and owner:Alive() then
            self:SetClip1(self:Clip1() - 1) 
            
            local currentHP = owner:Health()
            local maxOverheal = 150 

            if currentHP < maxOverheal then
                local healAmt = self.HealAmount or 1
                owner.FoodFractionalHP = (owner.FoodFractionalHP or 0) + healAmt
                
                if owner.FoodFractionalHP >= 1 then
                    local toHeal = math.floor(owner.FoodFractionalHP)
                    owner.FoodFractionalHP = owner.FoodFractionalHP - toHeal
                    owner:SetHealth(math.min(maxOverheal, currentHP + toHeal)) 
                end
            end

            local soundEffect = self.CustomSound or ("ambient/water/drip" .. math.random(1, 4) .. ".wav")
            owner:EmitSound(soundEffect, 60, 100, 0.6)
            
            if self.IsBeer then
                local currentDrunk = owner:GetNWFloat("BeerDrunk", 0)
                local drinkPotency = self.DrunkPotency or 5
                
                -- Uncaps Vodka to 250, while keeping standard beers locked to 100
                local maxDrunkCap = (self:GetClass() == "weapon_drink_vodka") and 250 or 100
                owner:SetNWFloat("BeerDrunk", math.min(maxDrunkCap, currentDrunk + drinkPotency))
            end

            -- Milk Sobber-up Mechanic
            if self:GetClass() == "weapon_drink_milk" then
                owner:SetNWFloat("BeerDrunk", 0)
            end

            -- Caloric Weight System Integration (If enabled globally)
            if cv_fat:GetBool() then
                local currentFat = owner:GetNWFloat("PlayerFatness", 0)
                local fatGain = 0
                
                if not self.IsLiquid then
                    fatGain = (self.HealAmount or 1.0) * 1.6 
                else
                    local class = self:GetClass()
                    if class == "weapon_drink_milk" then fatGain = 0.5
                    elseif string.find(class, "popcan") then fatGain = 0.2 end 
                end

                if fatGain > 0 then
                    owner:SetNWFloat("PlayerFatness", math.min(100, currentFat + fatGain))
                end
            end

            if self:Clip1() <= 0 then
                -- Isolated Watermelon Gib Bursts
                if self.IsWatermelon then
                    local pos = owner:GetShootPos() + owner:GetAimVector() * 16
                    local gibModels = {
                        "models/props_junk/Watermelon01_chunk01a.mdl",
                        "models/props_junk/Watermelon01_chunk01b.mdl",
                        "models/props_junk/Watermelon01_chunk01c.mdl"
                    }
                    
                    owner:EmitSound("physics/flesh/flesh_squishy_impact_hard4.wav", 75, 90)
                    
                    for i = 1, math.random(5, 8) do
                        local chunk = ents.Create("prop_physics")
                        if IsValid(chunk) then
                            chunk:SetModel(gibModels[math.random(1, #gibModels)])
                            chunk:SetPos(pos + VectorRand() * 6)
                            chunk:SetAngles(AngleRand())
                            chunk:Spawn()
                            
                            local phys = chunk:GetPhysicsObject()
                            if IsValid(phys) then
                                phys:SetVelocity(owner:GetAimVector() * 220 + VectorRand() * 130)
                                phys:AddAngleVelocity(VectorRand() * 400)
                            end
                            
                            -- Prevent eternal map clutter
                            timer.Simple(12, function() if IsValid(chunk) then chunk:Remove() end end)
                        end
                    end
                end

                if not self.KeepWhenEmpty then
                    owner:StripWeapon(self:GetClass())
                end
            end
        end
    end
end

function SWEP_BASE_DATA:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1.0)

    if SERVER then
        local owner = self:GetOwner()
        if IsValid(owner) and owner:Alive() then
            local currentAmmo = self:Clip1()
            local wepClass = self:GetClass()
            local wepSkin = self.Skin

            local ent = ents.Create("prop_physics")
            if IsValid(ent) then
                ent:SetModel(self.WorldModel)
                if wepSkin then ent:SetSkin(wepSkin) end
                if self.PaintYellow then ent:SetColor(Color(255, 255, 0)) end
                
                local aimVec = owner:GetAimVector()
                ent:SetPos(owner:GetShootPos() + aimVec * 16)
                ent:SetAngles(owner:EyeAngles())
                ent:Spawn()
                
                ent:SetPhysicsAttacker(owner)
                
                if currentAmmo > 0 then
                    ent.DrinkAmmo = currentAmmo
                    ent.DrinkClass = wepClass
                end

                -- Track and setup Break / Collision Decal Callbacks strictly for Beer Bottles
                if wepClass == "weapon_drink_glassbottle001" or wepClass == "weapon_drink_glassbottle003" then
                    ent.IsBeerBottleProp = true
                    ent:AddCallback("PhysicsCollide", function(entity, data)
                        entity.LastCollisionPos = data.HitPos
                        entity.LastCollisionNormal = data.HitNormal
                        entity.HadPhysicsCollision = true
                    end)
                end

                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(aimVec * 1400 + owner:GetVelocity())
                    phys:AddAngleVelocity(Vector(math.random(-400, 400), math.random(-400, 400), math.random(-400, 400)))
                end
                
                owner:StripWeapon(wepClass)
            end
        end
    end
end

function SWEP_BASE_DATA:Think()
    if SERVER and self.RegenRate and self:Clip1() < self:GetMaxAmmo() then
        self.NextRegen = self.NextRegen or 0
        if CurTime() >= self.NextRegen then
            self:SetClip1(self:Clip1() + 1)
            self.NextRegen = CurTime() + self.RegenRate
        end
    end
end

if CLIENT then
    SWEP_BASE_DATA.TiltAmt = 0

    function SWEP_BASE_DATA:GetCSModel()
        if not IsValid(self.CSModel) then
            self.CSModel = ClientsideModel(self.WorldModel, RENDERGROUP_VIEWMODEL_TRANSLUCENT)
            if IsValid(self.CSModel) then self.CSModel:SetNoDraw(true) end
        end
        return self.CSModel
    end

    function SWEP_BASE_DATA:PreDrawViewModel(vm, weapon, ply)
        local cs = self:GetCSModel()
        if IsValid(cs) then
            local pos = vm:GetPos()
            local ang = vm:GetAngles()

            local target = (ply:KeyDown(IN_ATTACK) and self:Clip1() > 0) and 1 or 0
            self.TiltAmt = Lerp(FrameTime() * 8, self.TiltAmt, target)

            local forward = ang:Forward()
            local right = ang:Right()
            local up = ang:Up()

            local fwdOffset = self.OffsetForward or 14
            local rgtOffset = self.OffsetRight or 6
            local upOffset  = self.OffsetUp or 8

            pos = pos + (forward * fwdOffset) + (right * rgtOffset) - (up * upOffset)
            ang:RotateAroundAxis(up, -90)
            ang:RotateAroundAxis(forward, -10)

            if self.TiltAmt > 0 then
                pos = pos - forward * (self.TiltAmt * 3) - right * (self.TiltAmt * 2) + up * (self.TiltAmt * 1)
                ang:RotateAroundAxis(right, self.TiltAmt * 40) 
            end

            cs:SetPos(pos)
            cs:SetAngles(ang)
            if self.Skin then cs:SetSkin(self.Skin) end
            if self.PaintYellow then cs:SetColor(Color(255, 255, 0)) else cs:SetColor(Color(255, 255, 255)) end

            cs:SetupBones()
            cs:DrawModel()
        end
        return true 
    end

    function SWEP_BASE_DATA:OnRemove()
        if IsValid(self.CSModel) then self.CSModel:Remove() end
    end

    function SWEP_BASE_DATA:Holster()
        if IsValid(self.CSModel) then self.CSModel:Remove() end
        return true
    end

    function SWEP_BASE_DATA:DrawWorldModel()
        local owner = self:GetOwner()
        if IsValid(owner) then
            local boneIndex = owner:LookupBone("ValveBiped.Bip01_R_Hand")
            if boneIndex then
                local matrix = owner:GetBoneMatrix(boneIndex)
                if matrix then
                    local pos, ang = matrix:GetTranslation(), matrix:GetAngles()
                    pos = pos + ang:Forward() * 3.5 + ang:Right() * 2.5 + ang:Up() * -1.5
                    ang:RotateAroundAxis(ang:Forward(), 90)
                    ang:RotateAroundAxis(ang:Right(), 90)
                    
                    self:SetRenderOrigin(pos)
                    self:SetRenderAngles(ang)
                    if self.Skin then self:SetSkin(self.Skin) end
                    if self.PaintYellow then self:SetColor(Color(255, 255, 0)) else self:SetColor(Color(255, 255, 255)) end

                    self:DrawModel()
                    return
                end
            end
        end
        self:DrawModel()
    end

    function SWEP_BASE_DATA:DrawHUD()
        local owner = self:GetOwner()
        if not IsValid(owner) then return end

        local currentAmmo = self:Clip1()
        local maxAmmo = self:GetMaxAmmo()
        if maxAmmo <= 0 then maxAmmo = 10 end 

        local progress = math.Clamp(currentAmmo / maxAmmo, 0, 1)
        local barWidth, barHeight, padding = 26, 180, 4
        local xPos = ScrW() - barWidth - 60
        local yPos = ScrH() - barHeight - 80

        surface.SetDrawColor(0, 0, 0, 160)
        surface.DrawRect(xPos, yPos, barWidth, barHeight)
        surface.SetDrawColor(80, 80, 80, 220)
        surface.DrawOutlinedRect(xPos, yPos, barWidth, barHeight, 2)

        local contentWidth = barWidth - (padding * 2)
        local maxContentHeight = barHeight - (padding * 2)
        local currentFillHeight = maxContentHeight * progress
        local currentFillY = yPos + padding + (maxContentHeight - currentFillHeight)

        local liquidColor = self.HUDColor or Color(0, 135, 255)

        if currentAmmo > 0 then
            surface.SetDrawColor(liquidColor.r, liquidColor.g, liquidColor.b, 210)
            surface.DrawRect(xPos + padding, currentFillY, contentWidth, currentFillHeight)
            surface.SetDrawColor(255, 255, 255, 40)
            surface.DrawRect(xPos + padding, currentFillY, 3, currentFillHeight)
        end

        draw.SimpleText("RESERVE", "DermaDefaultBold", xPos + (barWidth / 2), yPos - 18, Color(255, 255, 255, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(currentAmmo .. "/" .. maxAmmo, "DermaDefaultBold", xPos + (barWidth / 2), yPos + barHeight + 6, Color(liquidColor.r, liquidColor.g, liquidColor.b, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end

    hook.Add("CalcView", "DrinkSystemDrunkWobble", function(ply, pos, angles, fov)
        if not IsValid(ply) then return end
        local drunk = ply:GetNWFloat("BeerDrunk", 0)
        if drunk > 15 then
            local intensity = math.Remap(math.min(drunk, 250), 15, 100, 0, 1)
            angles.pitch = angles.pitch + math.sin(CurTime() * 1.4) * 3.5 * intensity
            angles.yaw = angles.yaw + math.cos(CurTime() * 1.1) * 3.0 * intensity
            angles.roll = angles.roll + math.sin(CurTime() * 0.7) * 4.5 * intensity
            
            return { origin = pos, angles = angles, fov = fov }
        end
    end)

    -- Dynamic Bone Scale Renderer (Stomach & Chest Inflation Loop)
    hook.Add("Think", "DrinkSystemClientBoneScale", function()
        local fatEnabled = cv_fat:GetBool()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) then
                local fatness = fatEnabled and ply:GetNWFloat("PlayerFatness", 0) or 0
                
                -- Stomach Area
                local spineBone = ply:LookupBone("ValveBiped.Bip01_Spine")
                if spineBone then
                    if fatness > 0 then
                        local scaleX = 1 + (fatness * 0.004)
                        local scaleY = 1 + (fatness * 0.004)
                        local scaleZ = 1 + (fatness * 0.001)
                        ply:ManipulateBoneScale(spineBone, Vector(scaleX, scaleY, scaleZ))
                    else
                        ply:ManipulateBoneScale(spineBone, Vector(1, 1, 1))
                    end
                end
                
                -- Chest Area
                local chestBone = ply:LookupBone("ValveBiped.Bip01_Spine2")
                if chestBone then
                    if fatness > 0 then
                        local scaleX = 1 + (fatness * 0.002)
                        local scaleY = 1 + (fatness * 0.002)
                        local scaleZ = 1 + (fatness * 0.001)
                        ply:ManipulateBoneScale(chestBone, Vector(scaleX, scaleY, scaleZ))
                    else
                        ply:ManipulateBoneScale(chestBone, Vector(1, 1, 1))
                    end
                end
            end
        end
    end)

    -- Add Option Panel checkboxes into spawnmenu utilities list
    hook.Add("PopulateToolMenu", "DrinkSystemMenuOptionsPopulate", function()
        spawnmenu.AddToolMenuOption("Options", "Player", "DrinkSystemMenuPanel", "Food & Drink Props", "", "", function(panel)
            panel:ClearControls()
            panel:CheckBox("Enable Weight & Body Inflation", "gmod_food_enable_fat")
            panel:ControlHelp("When turned off, servers can eat/roleplay without triggering visual bone inflation changes.")
            
            panel:CheckBox("Enable Ragmod Drunk Tripping", "gmod_food_enable_ragmod_trip")
            panel:ControlHelp("When turned on, extreme intoxication has a running chance to force a standard Ragmod collapse.")
        end)
    end)
end

-- Define food & drink configurations
local drinkConfigs = {
    {
        class = "weapon_drink_popcan_opened",
        printName = "Opened Pop Can",
        model = "models/props_junk/PopCan01a.mdl",
        skin = 0,
        maxHP = function() return math.random(5, 9) end,
        hudColor = Color(0, 135, 255),
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_popcan_blue", 
        printName = "Breen's Private Reserve (Blue)",
        model = "models/props_junk/PopCan01a.mdl",
        skin = 0,
        maxHP = 10,
        regen = 8.0,
        hudColor = Color(0, 135, 255),
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_popcan_red", 
        printName = "Breen's Private Reserve (Red)",
        model = "models/props_junk/PopCan01a.mdl",
        skin = 1,
        maxHP = 10,
        regen = 8.0,
        hudColor = Color(0, 135, 255),
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_popcan_yellow", 
        printName = "Breen's Private Reserve (Yellow)",
        model = "models/props_junk/PopCan01a.mdl",
        skin = 2,
        maxHP = 10,
        regen = 8.0,
        hudColor = Color(0, 135, 255),
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_popcan_lemonade", 
        printName = "Dr. Breen's Lemonade",
        model = "models/props_junk/PopCan01a.mdl",
        skin = 2, 
        maxHP = 12,
        regen = 6.0,
        hudColor = Color(255, 235, 0), 
        paintYellow = true,
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_glassbottle001",
        printName = "Closed Beer Bottle", 
        model = "models/props_junk/garbage_glassbottle001a.mdl",
        skin = 0,
        maxHP = 40,
        hudColor = Color(200, 130, 45),
        isBeer = true,
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_glassjug",
        printName = "Reusable Glass Jug",
        model = "models/props_junk/glassjug01.mdl",
        skin = 0,
        maxHP = 60,   
        hudColor = Color(0, 180, 255),
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_glassbottle003",
        printName = "Traditional Beer Bottle",
        model = "models/props_junk/garbage_glassbottle003a.mdl",
        skin = 0,
        maxHP = 21,
        hudColor = Color(200, 130, 45),
        isBeer = true,
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_milk",
        printName = "Milk Carton",
        model = "models/props_junk/garbage_milkcarton002a.mdl",
        skin = 0,
        maxHP = 35,
        hudColor = Color(240, 240, 235),
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_sprite",
        printName = "Bottle of Sprite",
        model = "models/props_junk/GlassBottle01a.mdl",
        skin = 0,
        maxHP = 20,
        hudColor = Color(0, 225, 90),
        isLiquid = true,
        keepWhenEmpty = true
    },
    {
        class = "weapon_drink_vodka",
        printName = "Russian Standard Vodka",
        model = "models/props_junk/garbage_glassbottle003a.mdl",
        skin = 0,
        maxHP = 12,
        hudColor = Color(220, 240, 255),
        isBeer = true,
        isLiquid = true,
        drunkPotency = 32, 
        customSound = "ambient/water/gurgle.wav",
        keepWhenEmpty = false,
        offsetUp = 9
    },
    {
        class = "weapon_food_nutripaste",
        printName = "Standard Issue Nutritious Paste",
        model = "models/weapons/w_package.mdl",
        skin = 0,
        maxHP = 80,
        healAmount = 5.0,
        hudColor = Color(110, 175, 125),
        customSound = "ambient/water/gurgle.wav",
        isLiquid = false,
        keepWhenEmpty = true,
        offsetUp = 10,
        offsetForward = 14
    },
    {
        class = "weapon_food_watermelon",
        printName = "Fresh Watermelon",
        model = "models/props_junk/watermelon01.mdl",
        skin = 0,
        maxHP = 20,
        healAmount = 3.0,
        hudColor = Color(235, 75, 95),
        customSound = "npc/barnacle/barnacle_crunch3.wav",
        isLiquid = false,
        keepWhenEmpty = false,
        isWatermelon = true,
        offsetUp = 18,
        offsetForward = 22,
        offsetRight = 2
    },
    {
        class = "weapon_food_noodles",
        printName = "Takeout Noodles",
        model = "models/props_junk/garbage_takeoutcarton001a.mdl",
        skin = 0,
        maxHP = 15,
        healAmount = 1.5, 
        hudColor = Color(230, 205, 160),
        customSound = "physics/flesh/flesh_squishy_impact_hard2.wav",
        isLiquid = false,
        keepWhenEmpty = true
    },
    {
        class = "weapon_food_beans",
        printName = "Canned Beans",
        model = "models/props_junk/garbage_metalcan001a.mdl",
        skin = 0,
        maxHP = 15,
        healAmount = 2.0, 
        hudColor = Color(140, 75, 45),
        customSound = "physics/flesh/flesh_squishy_impact_hard1.wav",
        isLiquid = false,
        keepWhenEmpty = true
    },
    {
        class = "weapon_food_burger",
        printName = "Juicy Burger",
        model = "models/food/burger.mdl",
        skin = 0,
        maxHP = 5,           
        healAmount = 5.0,    
        customDelay = 1.0,   
        hudColor = Color(165, 115, 60), 
        customSound = "npc/barnacle/barnacle_crunch2.wav",
        isLiquid = false,
        keepWhenEmpty = false, 
        offsetUp = 13,       
        offsetForward = 15   
    },
    {
        class = "weapon_food_hotdog",
        printName = "Tasty Hotdog",
        model = "models/food/hotdog.mdl",
        skin = 0,
        maxHP = 3,           
        healAmount = 10.0,   
        customDelay = 0.8,   
        hudColor = Color(185, 75, 45), 
        customSound = "npc/barnacle/barnacle_crunch2.wav",
        isLiquid = false,
        keepWhenEmpty = false, 
        offsetUp = 11,       
        offsetForward = 15
    },
    {
        class = "weapon_food_sandvich",
        printName = "Heavy's Sandvich",
        model = "models/weapons/c_models/c_sandwich/c_sandwich.mdl",
        skin = 0,
        maxHP = 10,          
        healAmount = 5.0,    
        customDelay = 1.0,   
        hudColor = Color(180, 30, 30), 
        customSound = "npc/barnacle/barnacle_crunch2.wav",
        isLiquid = false,
        keepWhenEmpty = false, 
        offsetUp = 10,       
        offsetForward = 14,
        isTF2Item = true     
    }
}

-- Registry loop
for _, config in ipairs(drinkConfigs) do
    local swepTable = table.Copy(SWEP_BASE_DATA)
    swepTable.PrintName = config.printName
    swepTable.WorldModel = config.model
    swepTable.MaxHealthCapacity = config.maxHP
    swepTable.SpawnHealthCapacity = config.spawnHP or nil
    swepTable.RegenRate = config.regen
    swepTable.Skin = config.skin
    swepTable.HUDColor = config.hudColor
    swepTable.PaintYellow = config.paintYellow or false
    swepTable.IsBeer = config.isBeer or false
    swepTable.DrunkPotency = config.drunkPotency or nil
    swepTable.HealAmount = config.healAmount or 1
    swepTable.CustomDelay = config.customDelay or nil
    swepTable.CustomSound = config.customSound or nil
    swepTable.IsLiquid = config.isLiquid or false
    swepTable.KeepWhenEmpty = config.keepWhenEmpty or false
    swepTable.IsWatermelon = config.isWatermelon or false
    
    swepTable.OffsetForward = config.offsetForward or nil
    swepTable.OffsetRight = config.offsetRight or nil
    swepTable.OffsetUp = config.offsetUp or nil
    
    weapons.Register(swepTable, config.class)
end

-- =========================================================================
-- SERVER-SIDE REPLACEMENT, CONTROL LOOPS & COMBAT INTERRUPTS
-- =========================================================================
if SERVER then
    local propReplacements = {
        ["models/props_junk/PopCan01a.mdl"] = function()
            local roll = math.random(1, 100)
            if roll <= 45 then return "weapon_drink_popcan_opened" end       
            if roll <= 65 then 
                local flavor = math.random(1, 3)
                if flavor == 1 then return "weapon_drink_popcan_blue" end   
                if flavor == 2 then return "weapon_drink_popcan_red" end    
                return "weapon_drink_popcan_yellow"
            end     
            if roll <= 80 then return "weapon_drink_popcan_lemonade" end 
            return nil                                                                       
        end,
        ["models/props_junk/garbage_glassbottle001a.mdl"] = function()
            local roll = math.random(1, 100)
            if roll <= 8 then return "weapon_drink_vodka" end 
            return (roll <= 50) and "weapon_drink_glassbottle001" or nil 
        end,
        ["models/props_junk/glassjug01.mdl"] = function()
            return (math.random(1, 100) <= 50) and "weapon_drink_glassjug" or nil        
        end,
        ["models/props_junk/garbage_glassbottle003a.mdl"] = function()
            local roll = math.random(1, 100)
            if roll <= 12 then return "weapon_drink_vodka" end 
            return (roll <= 60) and "weapon_drink_glassbottle003" or nil 
        end,
        ["models/props_junk/garbage_milkcarton002a.mdl"] = function()
            return (math.random(1, 100) <= 60) and "weapon_drink_milk" or nil
        end,
        ["models/props_junk/GlassBottle01a.mdl"] = function()
            local roll = math.random(1, 100)
            if roll <= 10 then return "weapon_drink_vodka" end
            return (roll <= 60) and "weapon_drink_sprite" or nil
        end,
        ["models/props_junk/watermelon01.mdl"] = function()
            return "weapon_food_watermelon"
        end,
        ["models/weapons/w_package.mdl"] = function()
            return "weapon_food_nutripaste"
        end,
        ["models/props_junk/garbage_takeoutcarton001a.mdl"] = function()
            return (math.random(1, 100) <= 60) and "weapon_food_noodles" or nil
        end,
        ["models/props_junk/garbage_metalcan001a.mdl"] = function()
            return (math.random(1, 100) <= 60) and "weapon_food_beans" or nil
        end,
        ["models/food/burger.mdl"] = function() return "weapon_food_burger" end,
        ["models/food/hotdog.mdl"] = function() return "weapon_food_hotdog" end,
        ["models/weapons/c_models/c_sandwich/c_sandwich.mdl"] = function()
            return cv_tf2:GetBool() and "weapon_food_sandvich" or nil
        end
    }

    hook.Add("PlayerSpawnSWEP", "DrinkSystemEnforceTF2ModeSpawn", function(ply, class, wep)
        if class == "weapon_food_sandvich" and not cv_tf2:GetBool() then return false end
    end)
    
    hook.Add("PlayerGiveSWEP", "DrinkSystemEnforceTF2ModeGive", function(ply, class, wep)
        if class == "weapon_food_sandvich" and not cv_tf2:GetBool() then return false end
    end)

    local function TryReplaceProp(ent)
        if not IsValid(ent) then return end
        local model = ent:GetModel()
        
        if model and propReplacements[model] then
            local swepClass = propReplacements[model]()
            if swepClass then
                local pos = ent:GetPos()
                local ang = ent:GetAngles()
                
                local weaponItem = ents.Create(swepClass)
                if IsValid(weaponItem) then
                    weaponItem:SetPos(pos)
                    weaponItem:SetAngles(ang)
                    weaponItem:Spawn()
                    
                    local phys = weaponItem:GetPhysicsObject()
                    if IsValid(phys) then phys:Wake() end
                    
                    ent:Remove() 
                    return true
                end
            end
        end
        return false
    end

    local function ReplaceMapProps()
        timer.Simple(1, function()
            for _, ent in ipairs(ents.FindByClass("prop_physics")) do
                TryReplaceProp(ent)
            end
        end)
    end
    hook.Add("InitPostEntity", "DrinkSystemReplaceProps", ReplaceMapProps)
    hook.Add("PostCleanupMap", "DrinkSystemCleanupProps", ReplaceMapProps)

    hook.Add("PlayerSpawnedProp", "DrinkSystemPlayerSpawnedProp", function(ply, model, ent)
        TryReplaceProp(ent)
    end)

    -- RESET ON DEATH HOOK
    hook.Add("PlayerDeath", "DrinkSystemResetOnDeath", function(ply)
        ply:SetNWFloat("BeerDrunk", 0)
        ply:SetNWFloat("PlayerFatness", 0)
    end)

    -- BEER BOTTLE SHATTER DECAL HOOK
    hook.Add("EntityRemoved", "DrinkSystemBeerBottleShatterDecal", function(ent)
        if ent.IsBeerBottleProp and ent.HadPhysicsCollision and not ent.PickedUpByPlayer then
            if ent.DrinkAmmo and ent.DrinkAmmo > 1 then
                local splatPos = ent.LastCollisionPos or ent:GetPos()
                local splatNormal = ent.LastCollisionNormal or Vector(0, 0, 1)
                
                util.Decal("BeerSplat", splatPos + splatNormal, splatPos - splatNormal)
            end
        end
    end)

    -- MIXING MECHANIC 1: Intercepts walking over weapons
    hook.Add("PlayerCanPickupWeapon", "DrinkSystemJugMixingWalkover", function(ply, wep)
        if not IsValid(ply) or not IsValid(wep) then return end
        if wep:GetClass() == "weapon_food_sandvich" and not cv_tf2:GetBool() then return false end

        if wep.Base == "weapon_base" and wep.IsLiquid then
            local incomingClass = wep:GetClass()
            
            if incomingClass ~= "weapon_drink_glassjug" and ply:HasWeapon("weapon_drink_glassjug") then
                local jug = ply:GetWeapon("weapon_drink_glassjug")
                if IsValid(jug) then
                    local currentJugClip = jug:Clip1()
                    if currentJugClip < 60 then
                        local incomingFluid = wep:Clip1()
                        if incomingFluid <= 0 then return false end 
                        
                        local availableSpace = 60 - currentJugClip
                        local transferAmount = math.min(incomingFluid, availableSpace)
                        
                        jug:SetClip1(currentJugClip + transferAmount)
                        wep:SetClip1(incomingFluid - transferAmount)
                        
                        ply:EmitSound("physics/fluid/splash_slosh1.wav", 65, 125, 0.7)
                        if wep:Clip1() <= 0 then
                            wep.PickedUpByPlayer = true
                            wep:Remove()
                            return false 
                        end
                    end
                end
            end
        end
    end)

    -- MIXING MECHANIC 2: Intercepts hitting 'E'
    hook.Add("PlayerUse", "DrinkSystemPickupProp", function(ply, ent)
        if IsValid(ent) and ent.DrinkAmmo and ent.DrinkClass then
            if IsValid(ply) and ply:Alive() then
                if ent.DrinkClass == "weapon_food_sandvich" and not cv_tf2:GetBool() then return false end

                local itemData = weapons.Get(ent.DrinkClass)
                local isLiquid = itemData and itemData.IsLiquid
                
                if isLiquid and ent.DrinkClass ~= "weapon_drink_glassjug" and ply:HasWeapon("weapon_drink_glassjug") then
                    local jug = ply:GetWeapon("weapon_drink_glassjug")
                    if IsValid(jug) then
                        local currentJugClip = jug:Clip1()
                        if currentJugClip < 60 then
                            local availableSpace = 60 - currentJugClip
                            local transferAmount = math.min(ent.DrinkAmmo, availableSpace)
                            
                            jug:SetClip1(currentJugClip + transferAmount)
                            ent.DrinkAmmo = ent.DrinkAmmo - transferAmount
                            
                            ply:EmitSound("physics/fluid/splash_slosh1.wav", 65, 125, 0.7)
                            if ent.DrinkAmmo <= 0 then 
                                ent.PickedUpByPlayer = true
                                ent:Remove() 
                            end
                            return true
                        end
                    end
                end

                local existingWep = ply:GetWeapon(ent.DrinkClass)
                if IsValid(existingWep) then
                    local currentAmmo = existingWep:Clip1()
                    local maxAmmo = existingWep:GetMaxAmmo()
                    
                    if currentAmmo < maxAmmo then
                        local pool = currentAmmo + ent.DrinkAmmo
                        existingWep:SetClip1(math.min(maxAmmo, pool))
                        
                        local leftover = pool - maxAmmo
                        if leftover > 0 then 
                            ent.DrinkAmmo = leftover 
                        else 
                            ent.PickedUpByPlayer = true
                            ent:Remove() 
                        end
                        ply:EmitSound("items/item_pickup.wav", 65, 100)
                        return true
                    end
                else
                    ply:Give(ent.DrinkClass)
                    local wep = ply:GetWeapon(ent.DrinkClass)
                    if IsValid(wep) then wep:SetClip1(ent.DrinkAmmo) end
                    ent.PickedUpByPlayer = true
                    ent:Remove()
                    ply:EmitSound("items/item_pickup.wav", 65, 100)
                    return true
                end
            end
        end
    end)

    -- FISTS COMBAT DAMAGE MODIFIER
    hook.Add("EntityTakeDamage", "DrinkSystemBrawlerFistsBuff", function(target, dmginfo)
        local attacker = dmginfo:GetAttacker()
        if IsValid(attacker) and attacker:IsPlayer() then
            local drunk = attacker:GetNWFloat("BeerDrunk", 0)
            if drunk > 20 then
                local currentWep = attacker:GetActiveWeapon()
                if IsValid(currentWep) and currentWep:GetClass() == "weapon_fists" then
                    if dmginfo:GetDamage() <= 12 then 
                        dmginfo:SetDamage(25)
                    end
                end
            end
        end
    end)

    -- DRUNK DRIVING CONTROLLER
    hook.Add("StartCommand", "DrinkSystemDrunkDrivingSwerve", function(ply, cmd)
        if not ply:Alive() or not ply:InVehicle() then return end
        
        local drunk = ply:GetNWFloat("BeerDrunk", 0)
        if drunk > 25 then
            local seedTime = CurTime()
            local driftFactor = math.sin(seedTime * 1.8) * math.cos(seedTime * 0.6)
            local scaleMultiplier = math.Remap(math.min(drunk, 250), 25, 100, 0.15, 0.85)
            
            if math.random(1, 100) < 35 then
                local sideCorrection = driftFactor * 380 * scaleMultiplier
                cmd:SetSideMove(cmd:GetSideMove() + sideCorrection)
            end
        end
    end)

    -- SERVER SYSTEM CYCLE
    local nextCycleTime = 0
    hook.Add("Think", "DrinkSystemSystemCoreCycle", function()
        if CurTime() < nextCycleTime then return end
        nextCycleTime = CurTime() + 0.4 

        local fatEnabled = cv_fat:GetBool()
        local ragmodEnabled = cv_ragmod:GetBool()

        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                -- 1. Overheal Decay
                local currentHP = ply:Health()
                local baseMaxHP = math.max(100, ply:GetMaxHealth()) 
                if currentHP > baseMaxHP then ply:SetHealth(currentHP - 1) end
                
                -- 2. Alcohol Dissipation
                local drunk = ply:GetNWFloat("BeerDrunk", 0)
                if drunk > 0 then
                    local decayedDrunk = math.max(0, drunk - 0.4) 
                    ply:SetNWFloat("BeerDrunk", decayedDrunk)
                    drunk = decayedDrunk
                end

                -- 3. Weight Metabolism Check
                local fatness = fatEnabled and ply:GetNWFloat("PlayerFatness", 0) or 0
                if fatEnabled and fatness > 0 then
                    local metabolicRate = 0.05 
                    local isRunning = ply:KeyDown(IN_SPEED) and ply:GetVelocity():Length2D() > ply:GetWalkSpeed()
                    if isRunning then metabolicRate = 0.40 end
                    
                    ply:SetNWFloat("PlayerFatness", math.max(0, fatness - metabolicRate))
                    fatness = ply:GetNWFloat("PlayerFatness", 0)
                end
                
                -- 4. Speed Management Core
                if not ply.DrinkSysOrigWalk then ply.DrinkSysOrigWalk = ply:GetWalkSpeed() end
                if not ply.DrinkSysOrigRun then ply.DrinkSysOrigRun = ply:GetRunSpeed() end
                
                local speedMult = 1.0
                
                if drunk > 20 then
                    speedMult = speedMult + math.Remap(math.min(drunk, 250), 20, 100, 0.0, 0.35)
                    
                    local activeWep = ply:GetActiveWeapon()
                    if IsValid(activeWep) and activeWep:GetClass() == "weapon_fists" then
                        speedMult = speedMult - 0.25 
                    end
                end
                
                if fatEnabled and fatness > 15 then
                    speedMult = speedMult - math.Remap(math.min(fatness, 100), 15, 100, 0.0, 0.35)
                end
                
                ply:SetWalkSpeed(ply.DrinkSysOrigWalk * speedMult)
                ply:SetRunSpeed(ply.DrinkSysOrigRun * speedMult)

                -- 5. Ragmod Falling Interaction Loop
                if ragmodEnabled and drunk > 40 and not ply:InVehicle() then
                    local curVelocity = ply:GetVelocity():Length2D()
                    if curVelocity > (ply.DrinkSysOrigWalk or 200) then
                        local randomChance = math.random(1, 100)
                        if randomChance <= math.floor(drunk * 0.06) then
                            ply:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav", 65, 85)
                            ply:ConCommand("ragmod_toggle") 
                        end
                    end
                end
            end
        end
    end)

    -- NPC RAMMING HITBOXES
    hook.Add("PlayerTick", "DrinkSystemFatNPCCollisionRam", function(ply)
        if not cv_fat:GetBool() or not ply:Alive() then return end
        
        local fatness = ply:GetNWFloat("PlayerFatness", 0)
        if fatness < 30 then return end 
        
        if ply:KeyDown(IN_SPEED) and ply:GetVelocity():Length2D() > (ply.DrinkSysOrigWalk or 200) then
            local scanRadius = 46
            local entitiesFound = ents.FindInSphere(ply:GetPos(), scanRadius)
            
            for _, ent in ipairs(entitiesFound) do
                if (ent:IsNPC() or ent:IsNextBot()) and ent ~= ply then
                    local nextRam = ent.NextFatRamTime or 0
                    if CurTime() >= nextRam then
                        ent.NextFatRamTime = CurTime() + 1.5 
                        
                        local damageImpact = math.floor(math.Remap(fatness, 30, 100, 25, 75))
                        
                        local dmgInfo = DamageInfo()
                        dmgInfo:SetDamage(damageImpact)
                        dmgInfo:SetAttacker(ply)
                        dmgInfo:SetInflictor(ply)
                        dmgInfo:SetDamageType(DMG_CRUSH)
                        
                        local pushDir = ply:GetAimVector()
                        pushDir.z = 0
                        pushDir:Normalize()
                        
                        ent:TakeDamageInfo(dmgInfo)
                        ent:SetVelocity(pushDir * (fatness * 6.5) + Vector(0, 0, 160))
                        
                        if ent:IsNPC() and ent.SetSchedule then
                            ent:ClearSchedule()
                            ent:SetSchedule(SCHED_BIG_FLINCH)
                        end
                        
                        ply:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 75, math.random(85, 95))
                        ent:EmitSound("physics/flesh/flesh_bloody_break.wav", 70, 95)
                        util.ScreenShake(ply:GetPos(), 6, 5, 0.45, 120)
                    end
                end
            end
        end
    end)
end