-- Precache all bullet models
util.PrecacheModel("models/weapons/w_bullet.mdl")
util.PrecacheModel("models/bullets/w_pbullet1.mdl")
util.PrecacheModel("models/bullets/w_pbullet2.mdl") -- Squished bullet model

local IGNORE_BULLETS = false
local ProcessBulletImpact -- Forward declaration for recursion

-- Helper function to determine the correct exit decal based on material
local function GetExitDecal(mat)
    if mat == MAT_WOOD then return "Impact.Wood"
    elseif mat == MAT_METAL or mat == MAT_VENT or mat == MAT_GRATE then return "Impact.Metal"
    elseif mat == MAT_GLASS then return "Impact.Glass"
    elseif mat == MAT_SAND or mat == MAT_DIRT then return "Impact.Sand"
    else return "Impact.Concrete" end
end

local function GetMaterialResistance(mat)
    if mat == MAT_CONCRETE then return 4
    elseif mat == MAT_METAL or mat == MAT_VENT or mat == MAT_GRATE then return 5
    elseif mat == MAT_WOOD then return 1
    elseif mat == MAT_GLASS then return 0.5 end
    return 2
end

local NEAR_MISS_RADIUS = 12

local function ProcessNearMiss(attacker, data, processed_props)
    if not SERVER then return end

    local start_pos = data.Src
    local bullet_dir = data.Dir
    if IsValid(attacker) then
        if not start_pos and isfunction(attacker.GetShootPos) then
            start_pos = attacker:GetShootPos()
        end
        if not bullet_dir and isfunction(attacker.GetAimVector) then
            bullet_dir = attacker:GetAimVector()
        end
    end
    if not start_pos or not bullet_dir or bullet_dir:LengthSqr() == 0 then return end

    local distance = data.Distance and data.Distance > 0 and data.Distance or 56756
    bullet_dir = bullet_dir:GetNormalized()
    local end_pos = start_pos + bullet_dir * distance
    local direct_hit = util.TraceLine({
        start = start_pos,
        endpos = end_pos,
        filter = attacker,
        mask = MASK_SHOT
    }).Entity
    local scan_distance = math.min(distance, 4096)
    local section_length = scan_distance
    local touched_props = processed_props or {}

    -- Sweep short hull sections so a scratch follows surfaces instead of being a single point.
    for traveled = 0, scan_distance - 1, section_length do
        local section_end = start_pos + bullet_dir * math.min(traveled + section_length, scan_distance)
        local surface = util.TraceHull({
            start = start_pos + bullet_dir * traveled,
            endpos = section_end,
            mins = Vector(-NEAR_MISS_RADIUS, -NEAR_MISS_RADIUS, -NEAR_MISS_RADIUS),
            maxs = Vector(NEAR_MISS_RADIUS, NEAR_MISS_RADIUS, NEAR_MISS_RADIUS),
            filter = attacker,
            mask = MASK_SHOT
        })
        local surface_ent = surface.Entity
        local is_prop = IsValid(surface_ent) and string.StartWith(surface_ent:GetClass(), "prop_")
        local is_world = surface.HitWorld or surface_ent == game.GetWorld()
        local is_direct_prop_hit = is_prop and surface_ent == direct_hit

        if surface.Hit and not is_direct_prop_hit and (is_world or is_prop) then
            local scratch_normal = surface.HitNormal
            if scratch_normal:LengthSqr() == 0 then
                scratch_normal = -bullet_dir
            end
            local decal_start = surface.HitPos + scratch_normal * 4
            local decal_end = surface.HitPos - scratch_normal * 4
            if is_prop then
                util.Decal("ManhackCut", decal_start, decal_end, surface_ent)
            else
                util.Decal("ManhackCut", decal_start, decal_end)
            end

            if is_prop and not touched_props[surface_ent] then
                local max_health = surface_ent:GetMaxHealth()
                local health = surface_ent:Health()
                if max_health > 0 or health > 0 then
                    local damage = DamageInfo()
                    damage:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
                    damage:SetInflictor(IsValid(attacker) and attacker or game.GetWorld())
                    damage:SetDamage(1)
                    damage:SetDamageType(DMG_BULLET)
                    surface_ent:TakeDamageInfo(damage)
                end
                touched_props[surface_ent] = true
            end
        end
    end
end

-- Helper function to fire our simulated continuation bullets
local function FireContinuationBullet(attacker, pos, dir, damage, bounces, is_shotgun, skip_bullet_model)
    -- Stop if the bullet runs out of energy or bounces too many times
    if damage <= 1 or bounces >= 3 then return end

    local bullet = {}
    bullet.Num = 1
    bullet.Src = pos
    bullet.Dir = dir
    bullet.Spread = Vector(0, 0, 0)
    bullet.Tracer = 1
    bullet.TracerName = "Tracer"
    bullet.Force = damage * 0.2
    bullet.Damage = damage
    bullet.DamageType = DMG_BULLET
    
    -- Chain the logic back into our main impact function
    bullet.Callback = function(att, tr, dmginfo)
        dmginfo:SetDamageType(DMG_BULLET)
        ProcessBulletImpact(att, tr, dmginfo, bounces, is_shotgun, skip_bullet_model, dir)
    end

    -- Temporarily disable the hook to prevent infinite stack overflows
    IGNORE_BULLETS = true
    attacker:FireBullets(bullet)
    IGNORE_BULLETS = false
end

-- The main physics and calculation logic
ProcessBulletImpact = function(attacker, tr, dmginfo, bounces, is_shotgun, skip_bullet_model, bullet_dir)
    -- Don't calculate for the skybox or misses
    if not tr.Hit or tr.HitSky then return false end

    -- Failsafe: Completely ignore any damage flagged as sharp (slash) or blunt melee
    if dmginfo:IsDamageType(DMG_SLASH) or dmginfo:IsDamageType(DMG_CLUB) then return false end

    local pos = tr.HitPos
    local normal = tr.HitNormal
    local dir = bullet_dir or tr.Normal
    local mat = tr.MatType
    local dmg = dmginfo:GetDamage()
    local hit_ent = tr.Entity
    
    local penetrated = false
    local ricocheted = false
    local cancel_default_decal = false -- Used to override default decals

    -- ==========================================
    -- 1. RICOCHET LOGIC
    -- ==========================================
    local dot = -dir:Dot(normal)
    local attempt_ricochet = false
    
    -- Evaluate ricochet probabilities on shallow angles
    if dot < 0.55 then
        local ricochet_chance = 0
        
        -- Non-ricochet materials (Flesh, Wood, Plastic, Dirt, Sand, etc.)
        if mat == MAT_FLESH or mat == MAT_ALIENFLESH or mat == MAT_WOOD or mat == MAT_PLASTIC or mat == MAT_SAND or mat == MAT_DIRT or mat == MAT_FOLIAGE or mat == MAT_ANTLION or mat == MAT_BLOODYFLESH or mat == MAT_SNOW or mat == MAT_SLOSH then
            ricochet_chance = 0
        -- Glass (Very small chance)
        elseif mat == MAT_GLASS then
            ricochet_chance = 5
        -- Metal (Realistic high chance on shallow angle)
        elseif mat == MAT_METAL or mat == MAT_VENT or mat == MAT_GRATE then
            ricochet_chance = 75
        -- Every other material (Concrete, Tile, etc. - Small chance)
        else
            ricochet_chance = 20
        end

        -- Roll the dice to see if it actually ricochets based on the assigned chance
        if ricochet_chance > 0 and math.random(1, 100) <= ricochet_chance then
            attempt_ricochet = true
        end
    end

    if attempt_ricochet then 
        ricocheted = true
        cancel_default_decal = true -- Tells the hook to cancel the default bullet hole

        -- If hitting a destructible prop/entity, take away 70% of the damage (deals 30%)
        if IsValid(hit_ent) and (hit_ent:GetMaxHealth() > 0 or hit_ent:Health() > 0) then
            dmginfo:ScaleDamage(0.3)
        end

        -- Leave the Manhack Scratch decal ONLY if the material is not glass
        if mat ~= MAT_GLASS then
            util.Decal("ManhackCut", pos + normal * 2, pos - normal * 2)
        end

        -- Calculate vector reflection math
        local reflect = dir - 2 * (dir:Dot(normal)) * normal
        reflect:Normalize()
        reflect = reflect + VectorRand() * 0.05 -- Add slight spread to ricochet
        reflect:Normalize()

        -- Play a satisfying HL2/CS ricochet sound
        sound.Play("weapons/fx/ric" .. math.random(1, 5) .. ".wav", pos, 75, math.random(90, 110), 1)

        -- 20% Chance for a Failed Ricochet
        local is_failed_ricochet = (math.random(1, 100) <= 20)

        if is_failed_ricochet then
            -- Spawn a physical physics bullet model that tumbles along the trajectory
            if SERVER then
                local phys_bullet = ents.Create("prop_physics")
                if IsValid(phys_bullet) then
                    phys_bullet:SetModel("models/bullets/w_pbullet1.mdl")
                    phys_bullet:SetPos(pos + normal * 2)
                    phys_bullet:SetAngles(reflect:Angle())
                    phys_bullet:Spawn()
                        
                    local phys = phys_bullet:GetPhysicsObject()
                    if IsValid(phys) then
                        -- Launch with reduced velocity and randomized spin
                        phys:SetVelocity(reflect * math.Clamp(dmg * 20, 150, 600))
                        phys:AddAngleVelocity(VectorRand() * 400)
                    end

                    SafeRemoveEntityDelayed(phys_bullet, 10)
                end
            end

            -- Heavily weakened continuation bullet for the failed ricochet
            FireContinuationBullet(attacker, pos + normal * 2, reflect, dmg * 0.2, bounces + 1, is_shotgun, skip_bullet_model)
        else
            -- Normal Successful Ricochet (60% remaining damage)
            FireContinuationBullet(attacker, pos + normal * 2, reflect, dmg * 0.6, bounces + 1, is_shotgun, skip_bullet_model)
        end
    end

    -- ==========================================
    -- 2. CS:S WALLBANG / PENETRATION LOGIC
    -- ==========================================
    if not ricocheted and not is_shotgun then
        -- Set max physical penetration depth based on material density
        local max_pen = 16
        if mat == MAT_WOOD then max_pen = 36
        elseif mat == MAT_PLASTIC then max_pen = 24
        elseif mat == MAT_CONCRETE then max_pen = 12
        elseif mat == MAT_METAL then max_pen = 8
        elseif mat == MAT_GLASS then max_pen = 48 end

        -- Trace backwards from max depth to find the backside of the wall
        local exit_tr = util.TraceLine({
            start = pos + dir * max_pen,
            endpos = pos,
            filter = attacker,
            mask = MASK_SHOT
        })

        -- If it didn't start solid, it means the wall was thin enough to puncture
        if exit_tr.Hit and not exit_tr.StartSolid then
            local exit_pos = exit_tr.HitPos
            local thickness = exit_pos:Distance(pos)

            if thickness > 0 and thickness < max_pen then
                penetrated = true

                -- Place the exit decal on the backface
                util.Decal(GetExitDecal(mat), exit_pos + dir * 5, exit_pos - dir * 5)

                -- CS:S Style Damage Nerf Multipliers
                local pen_resistance = GetMaterialResistance(mat)
                local dmg_loss = thickness * pen_resistance
                local new_dmg = dmg - dmg_loss

                -- Only exit the wall if there's remaining damage
                if new_dmg > 2 then
                    FireContinuationBullet(attacker, exit_pos + dir * 2, dir, new_dmg, bounces, is_shotgun, skip_bullet_model)
                else
                    penetrated = false -- Ran out of energy while inside the wall
                end
            end
        end
    end

    -- ==========================================
    -- 3. BULLET LODGING LOGIC
    -- ==========================================
    local can_lodge = true

    if IsValid(hit_ent) then
        if hit_ent:IsNPC() or hit_ent:IsPlayer() or hit_ent:IsRagdoll() or hit_ent:GetClass() == "prop_ragdoll" then
            can_lodge = false
        end
    end

    -- Lodges bullet prop ONLY into walls or props
    if not penetrated and not ricocheted and not skip_bullet_model and can_lodge and SERVER then
        
        -- Calculate exact impact angle (0 = dead on, 90 = parallel)
        local safe_dot = math.Clamp(dot, 0, 1)
        local hit_angle = math.deg(math.acos(safe_dot))

        -- Failsafe for extreme grazing angles on ANY material
        if hit_angle > 80 then
            -- Spawn a physics bullet that simply drops out of the surface
            local phys_bullet = ents.Create("prop_physics")
            if IsValid(phys_bullet) then
                phys_bullet:SetModel("models/bullets/w_pbullet1.mdl")
                
                -- Spawn slightly away from the wall to prevent getting stuck in geometry
                phys_bullet:SetPos(pos + normal * 2) 
                phys_bullet:SetAngles(dir:Angle())
                phys_bullet:Spawn()
                
                local phys = phys_bullet:GetPhysicsObject()
                if IsValid(phys) then
                    -- Gentle velocity pushing outward and downward
                    phys:SetVelocity(normal * 15 - Vector(0, 0, 40))
                    phys:AddAngleVelocity(VectorRand() * 50) -- Slight tumble
                end
                
                SafeRemoveEntityDelayed(phys_bullet, 10)
            end
        else
            -- Normal embedding logic
            local material_resistance = GetMaterialResistance(mat)
            local embed_depth = math.Clamp(dmg * 0.1 * (2 / material_resistance), 0.5, 10)
            local embed_pos = pos + dir * embed_depth
            
            -- Determine base squish chance based on surface material
            local squish_chance = 20
            if mat == MAT_METAL or mat == MAT_VENT or mat == MAT_GRATE then
                squish_chance = 40
            elseif mat == MAT_GLASS then 
                squish_chance = 5
            end
            
            -- Light damage multiplier: Scales chance up to 2.0x for weapons dealing 10 or less damage
            local dmg_multiplier = math.Clamp(1 + (30 - dmg) / 20, 1, 2)
            local final_squish_chance = squish_chance * dmg_multiplier

            local is_squished = (math.random(1, 100) <= final_squish_chance)
            local chosen_model = is_squished and "models/bullets/w_pbullet2.mdl" or "models/weapons/w_bullet.mdl"

            local bullet_prop = ents.Create("prop_dynamic")
            if IsValid(bullet_prop) then
                bullet_prop:SetModel(chosen_model)
                bullet_prop:SetPos(embed_pos)

                -- Align the bullet nose with the trajectory direction
                local ang = dir:Angle()
                bullet_prop:SetAngles(ang)

                -- Disable physical collisions so it doesn't cause physics freakouts
                bullet_prop:SetSolid(SOLID_NONE)

                -- Parent to physics props so lodged bullets move when props are moved
                if IsValid(hit_ent) and not hit_ent:IsWorld() then
                    bullet_prop:SetParent(hit_ent)
                end

                bullet_prop:Spawn()
                bullet_prop:DrawShadow(false)

                -- Despawn after 15 seconds to prevent entity limits
                SafeRemoveEntityDelayed(bullet_prop, 15)
            end
        end
    end
    
    return cancel_default_decal
end

-- Hook into every bullet fired by weapons, NPCs, or players
hook.Add("EntityFireBullets", "CSS_Realistic_Bullets", function(attacker, data)
    if IGNORE_BULLETS then return end

    -- Detect melee weapons using simulated short-range bullet traces
    if data.Distance and data.Distance < 300 then
        return -- Exit completely, ignoring our custom ricochet/squish logic
    end

    -- Detect Ammo Name
    local ammo_name = ""
    if data.AmmoType then
        if isstring(data.AmmoType) then
            ammo_name = string.lower(data.AmmoType)
        else
            ammo_name = string.lower(game.GetAmmoName(data.AmmoType) or "")
        end
    end
    
    local is_shotgun = (data.Num > 1 or string.find(ammo_name, "buckshot") ~= nil)

    -- Check if energy weapons (AR2/Pulse) or Combine Turrets fired this bullet
    local skip_bullet_model = false

    if ammo_name == "ar2" or ammo_name == "combinecannon" then
        skip_bullet_model = true
    end

    if IsValid(attacker) then
        local att_class = string.lower(attacker:GetClass() or "")
        
        -- Check for any type of Combine turret
        if string.find(att_class, "turret") then
            skip_bullet_model = true
        end

        -- Check for Pulse Rifle or AR2 active weapon
        if isfunction(attacker.GetActiveWeapon) then
            local active_wep = attacker:GetActiveWeapon()
            if IsValid(active_wep) then
                local wep_class = string.lower(active_wep:GetClass() or "")
                if string.find(wep_class, "ar2") or string.find(wep_class, "pulse") then
                    skip_bullet_model = true
                end
            end
        end
    end

    ProcessNearMiss(attacker, data)

    -- Hijack the bullet callback cleanly
    local old_cb = data.Callback
    data.Callback = function(att, tr, dmginfo)
        local old_ret = nil
        -- Call original weapon's callback first if it exists
        if old_cb then 
            old_ret = old_cb(att, tr, dmginfo) 
        end 

        -- Run our physics, returning true if we need to replace the standard decal
        local cancel_decal = ProcessBulletImpact(att, tr, dmginfo, 0, is_shotgun, skip_bullet_model, data.Dir)
        
        -- Returning false to Garry's Mod engine prevents the default bullet hole decal
        if cancel_decal then
            return false
        end
        
        return old_ret
    end

    return true
end)