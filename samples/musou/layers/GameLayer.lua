local BaseLayer = require("engine.layers.BaseLayer")
local MusouSprites = require("samples.musou.layers.MusouSprites")
local GameLayer    = BaseLayer:extend()

-- ── Constants ──────────────────────────────────────────────────────────────
local BASE_RADIUS     = 40
local BASE_HP         = 2000
local FORTRESS_RADIUS = 70
local FORTRESS_HP     = 5000
local SPAWN_INTERVAL  = 3.5
local WAVE_COUNT      = 14
local SIEGE_INTERVAL  = 10.0
local SIEGE_DAMAGE    = 100
local MORTAR_GRAVITY  = 310   -- px/s², used for mortar arc

-- ── Ally Unit Types ────────────────────────────────────────────────────────
local UNIT_TYPES = {
    { id="warrior",   name="战士", hp=65,  speed=80,  damage=18, attackRange=36,  attackCooldown=0.80, radius=5, color={0.28,0.58,1.0} },
    { id="spearman",  name="枪兵", hp=45,  speed=105, damage=13, attackRange=56,  attackCooldown=0.60, radius=4, color={0.65,0.90,0.35} },
    { id="knight",    name="骑士", hp=120, speed=118, damage=34, attackRange=40,  attackCooldown=1.20, radius=7, color={0.85,0.62,0.28}, aoeRadius=42 },
    { id="dualblade", name="双刃", hp=36,  speed=132, damage=10, attackRange=30,  attackCooldown=0.38, radius=4, color={0.45,0.92,0.68} },
    { id="mage",      name="法师", hp=30,  speed=68,  damage=26, attackRange=175, attackCooldown=1.30, radius=5, color={0.80,0.28,1.0},  projectileSpeed=500, aoeRadius=34, isRanged=true },
    { id="archer",    name="弓手", hp=38,  speed=85,  damage=19, attackRange=215, attackCooldown=0.90, radius=4, color={0.55,0.90,0.28}, projectileSpeed=860, piercing=true, isRanged=true },
}

-- ── Turret Types ───────────────────────────────────────────────────────────
local TURRET_TYPES = {
    { id="gatling", name="机枪台", hp=200, damage=16, range=210, cooldown=0.35, radius=11, color={0.55,0.72,0.30}, projSpeed=920 },
    { id="cannon",  name="炮  台", hp=350, damage=48, range=300, cooldown=1.80, radius=14, color={0.85,0.50,0.20}, projSpeed=640, aoeRadius=28 },
    { id="mortar",  name="迫击炮", hp=280, damage=72, range=420, cooldown=3.20, radius=13, color={0.72,0.28,0.85}, projSpeed=360, aoeRadius=54 },
    { id="sniper",  name="狙击炮", hp=150, damage=95, range=480, cooldown=3.80, radius=10, color={0.28,0.82,0.75}, projSpeed=1100, piercing=true },
}
local TURRET_SCORE = { gatling=30, cannon=50, mortar=60, sniper=70 }

-- ── Garrison Defender Types ────────────────────────────────────────────────
local GARRISON_TYPES = {
    { id="garcher", name="守卫弓手", hp=55,  damage=22, range=265, cooldown=1.10, radius=5, color={0.92,0.35,0.18}, projSpeed=800 },
    { id="gmage",   name="守卫法师", hp=40,  damage=40, range=200, cooldown=2.10, radius=5, color={0.78,0.18,0.88}, projSpeed=390, aoeRadius=44 },
}
local GARRISON_SCORE = { garcher=20, gmage=35 }

local FORMATIONS = {
    { name="直线", id="line" },
    { name="楔形", id="wedge" },
    { name="双翼", id="wings" },
    { name="散兵", id="scatter" },
}

-- ── Utility ────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function distSq(x1,y1,x2,y2) return (x1-x2)^2+(y1-y2)^2 end
local function norm(dx, dy)
    local d = math.sqrt(dx*dx+dy*dy)
    if d < 0.0001 then return 0,0,0 end
    return dx/d, dy/d, d
end

-- Predict where a moving ally unit will be after the projectile travels to it.
-- lead: 0=no prediction, 1=full lead. Returns predicted (tx, ty).
local function predictTarget(target, srcX, srcY, speed, lead)
    lead = lead or 0.70
    local ddx, ddy = target.x - srcX, target.y - srcY
    local dist = math.sqrt(ddx*ddx + ddy*ddy)
    if dist < 1 or speed < 1 then return target.x, target.y end
    local travelTime = dist / speed
    local ut  = UNIT_TYPES[target.typeIdx]
    local spd = ut and ut.speed or 0
    local fx  = target.facingX or 0
    local fy  = target.facingY or 0
    return target.x + fx * spd * travelTime * lead,
           target.y + fy * spd * travelTime * lead
end

local function spawnOffset(formId, index, total, marchDirX)
    local gap = 11
    if formId == "line" then
        local mid = (total+1)*0.5
        return 0, (index-mid)*gap
    elseif formId == "wedge" then
        local row  = math.ceil(index/2)
        local side = (index%2==0) and 1 or -1
        return marchDirX*(total-row)*gap*0.5, (total-row)*gap*0.4*side
    elseif formId == "wings" then
        local half = math.ceil(total*0.5)
        local side = (index<=half) and -1 or 1
        local i    = (index<=half) and index or (index-half)
        return marchDirX*(i-1)*gap*0.3, side*i*gap*0.8
    else
        return (math.random()-0.5)*80, (math.random()-0.5)*80
    end
end

-- ── Obstacle collision push-out ────────────────────────────────────────────
local function resolveObstacle(unit, obs)
    if obs.shape == "circle" then
        local dx, dy, dist = norm(unit.x - obs.x, unit.y - obs.y)
        local minD = unit.radius + obs.radius
        if dist > 0 and dist < minD then
            unit.x = obs.x + dx * minD
            unit.y = obs.y + dy * minD
        end
    elseif obs.shape == "rect" then
        local cx = clamp(unit.x, obs.x, obs.x + obs.w)
        local cy = clamp(unit.y, obs.y, obs.y + obs.h)
        local dx, dy, dist = norm(unit.x - cx, unit.y - cy)
        if dist < unit.radius then
            if dist < 0.001 then unit.x = unit.x + unit.radius + 2
            else unit.x = cx + dx * unit.radius; unit.y = cy + dy * unit.radius end
        end
    end
end

-- ── HP color ───────────────────────────────────────────────────────────────
local function hpColor(pct)
    if pct > 0.6 then return 0.25, 0.85, 0.30
    elseif pct > 0.3 then return 0.90, 0.75, 0.15
    else return 0.95, 0.25, 0.20 end
end

-- ── GameLayer ──────────────────────────────────────────────────────────────
function GameLayer:new()
    local instance = BaseLayer.new(self)
    instance.unitTypes        = UNIT_TYPES
    instance.formations       = FORMATIONS
    instance.currentUnitType  = 1
    instance.currentFormation = 1
    instance.spawnInterval    = SPAWN_INTERVAL
    return instance
end

function GameLayer:enter() self:reset() end

function GameLayer:reset()
    local w, h = love.graphics.getDimensions()
    local cy   = h * 0.5

    self.elapsed    = 0
    self.kills      = 0
    self.score      = 0
    self.gameOver   = false
    self.winner     = nil
    self.siegeTimer = 15.0
    self.shakeAmt   = 0

    self.allyBase = {
        x=88, y=cy, radius=BASE_RADIUS,
        hp=BASE_HP, maxHp=BASE_HP, color={0.22,0.50,1.0}
    }
    self.fortress = {
        x=w-100, y=cy, radius=FORTRESS_RADIUS,
        hp=FORTRESS_HP, maxHp=FORTRESS_HP, color={0.78,0.20,0.15}
    }

    local bx = self.allyBase.x + BASE_RADIUS + 10
    self.allyBarracks = {
        { x=bx, y=cy-28, timer=SPAWN_INTERVAL,       color={0.22,0.50,1.0} },
        { x=bx, y=cy+28, timer=SPAWN_INTERVAL * 0.5, color={0.22,0.50,1.0} },
    }

    self:initTurrets(w, h)
    self:initGarrison(w, h)
    self:initObstacles(w, h)

    self.allies      = {}
    self.projectiles = {}
    self.effects     = {}
    self.spriteSheet = MusouSprites.createSheet()
end

-- ── Turret placement ───────────────────────────────────────────────────────
function GameLayer:initTurrets(w, h)
    local placements = {
        {1, 0.44, 0.22}, {1, 0.44, 0.78},
        {2, 0.54, 0.30}, {2, 0.54, 0.70},
        {3, 0.60, 0.50},
        {4, 0.67, 0.17}, {4, 0.67, 0.83},
        {2, 0.73, 0.37}, {2, 0.73, 0.63},
        {1, 0.81, 0.50},
    }
    self.turrets = {}
    for _, p in ipairs(placements) do
        local tt = TURRET_TYPES[p[1]]
        table.insert(self.turrets, {
            typeIdx=p[1], x=w*p[2], y=h*p[3],
            hp=tt.hp, maxHp=tt.hp, radius=tt.radius, color=tt.color,
            angle=math.pi, attackTimer=math.random()*tt.cooldown, scored=false,
        })
    end
end

-- ── Garrison placement ─────────────────────────────────────────────────────
function GameLayer:initGarrison(w, h)
    -- typeIdx, relX, relY
    local placements = {
        {1, 0.70, 0.14}, {1, 0.70, 0.86},   -- far archers top/bot
        {1, 0.74, 0.26}, {1, 0.74, 0.74},   -- mid archers
        {2, 0.72, 0.40}, {2, 0.72, 0.60},   -- front mages
        {1, 0.78, 0.33}, {1, 0.78, 0.67},   -- inner archers
        {2, 0.80, 0.45}, {2, 0.80, 0.55},   -- gate mages
        {1, 0.84, 0.28}, {1, 0.84, 0.72},   -- fortress flank archers
    }
    self.garrison = {}
    for _, p in ipairs(placements) do
        local gt = GARRISON_TYPES[p[1]]
        table.insert(self.garrison, {
            typeIdx=p[1], x=w*p[2], y=h*p[3],
            hp=gt.hp, maxHp=gt.hp, radius=gt.radius, color=gt.color,
            angle=math.pi,  -- face left toward attackers
            attackTimer=math.random()*gt.cooldown, scored=false,
        })
    end
end

-- ── Obstacle placement ─────────────────────────────────────────────────────
function GameLayer:initObstacles(w, h)
    self.obstacles = {
        { shape="circle", x=w*0.30, y=h*0.28, radius=20, color={0.45,0.40,0.35} },
        { shape="circle", x=w*0.30, y=h*0.72, radius=22, color={0.45,0.40,0.35} },
        { shape="circle", x=w*0.40, y=h*0.50, radius=26, color={0.40,0.38,0.32} },
        { shape="circle", x=w*0.49, y=h*0.34, radius=17, color={0.45,0.40,0.35} },
        { shape="circle", x=w*0.49, y=h*0.66, radius=17, color={0.45,0.40,0.35} },
        { shape="circle", x=w*0.61, y=h*0.27, radius=16, color={0.45,0.40,0.35} },
        { shape="circle", x=w*0.61, y=h*0.73, radius=16, color={0.45,0.40,0.35} },
        { shape="rect", x=w*0.36-7, y=h*0.16, w=14, h=h*0.11, color={0.50,0.44,0.36} },
        { shape="rect", x=w*0.36-7, y=h*0.73, w=14, h=h*0.11, color={0.50,0.44,0.36} },
        { shape="rect", x=w*0.53-h*0.06, y=h*0.17-7, w=h*0.12, h=14, color={0.50,0.44,0.36} },
        { shape="rect", x=w*0.53-h*0.06, y=h*0.83,   w=h*0.12, h=14, color={0.50,0.44,0.36} },
        { shape="rect", x=w*0.81-7, y=h*0.27, w=14, h=h*0.16, color={0.55,0.22,0.16} },
        { shape="rect", x=w*0.81-7, y=h*0.57, w=14, h=h*0.16, color={0.55,0.22,0.16} },
    }
end

-- ── Barracks ───────────────────────────────────────────────────────────────
function GameLayer:updateBarracks(dt)
    for _, bar in ipairs(self.allyBarracks) do
        bar.timer = bar.timer - dt
        if bar.timer <= 0 then
            bar.timer = SPAWN_INTERVAL
            self:spawnWave(bar.x, bar.y, self.currentUnitType, self.currentFormation)
        end
    end
end

function GameLayer:spawnWave(bx, by, utIdx, formIdx)
    local h      = love.graphics.getHeight()
    local ut     = UNIT_TYPES[utIdx]
    local formId = FORMATIONS[formIdx].id
    for i = 1, WAVE_COUNT do
        local ox, oy = spawnOffset(formId, i, WAVE_COUNT, 1)
        table.insert(self.allies, {
            x=bx+ox, y=clamp(by+oy, 20, h-20),
            hp=ut.hp, maxHp=ut.hp, typeIdx=utIdx,
            radius=ut.radius, color=ut.color,
            attackTimer=math.random()*ut.attackCooldown,
            facingX=1, facingY=0,
            animTime=math.random() * math.pi * 2,
            attackAnimTime=0,
            isAttacking=false,
        })
    end
end

-- ── VFX helpers ────────────────────────────────────────────────────────────
function GameLayer:addShake(amt)
    self.shakeAmt = math.max(self.shakeAmt, amt)
end

function GameLayer:spawnRing(x, y, maxR, color, life)
    table.insert(self.effects, {
        type="ring", x=x, y=y, maxR=maxR,
        color=color or {1,0.7,0.2},
        life=life or 0.42, maxLife=life or 0.42,
    })
end

function GameLayer:spawnBurst(x, y, color)
    local pts, n = {}, math.random(5,8)
    for i = 1, n do
        local ang = (i/n)*2*math.pi + math.random()*0.8
        local spd = math.random(40,110)
        table.insert(pts, {x=x, y=y, vx=math.cos(ang)*spd, vy=math.sin(ang)*spd})
    end
    table.insert(self.effects, {
        type="burst", pts=pts, color=color or {1,1,1},
        life=0.50, maxLife=0.50,
    })
end

function GameLayer:spawnFlash(x, y, color, size)
    table.insert(self.effects, {
        type="flash", x=x, y=y, size=size or 1,
        color=color or {1,0.8,0.3},
        life=0.12, maxLife=0.12,
    })
end

-- Smoke puff for mortar trail
function GameLayer:spawnSmoke(x, y)
    table.insert(self.effects, {
        type="smoke", x=x, y=y,
        r = math.random(3,7),
        life=0.55, maxLife=0.55,
    })
end

-- ── Turret AI ──────────────────────────────────────────────────────────────
function GameLayer:updateTurrets(dt)
    for _, t in ipairs(self.turrets) do
        if t.hp > 0 then
            local tt = TURRET_TYPES[t.typeIdx]
            t.attackTimer = t.attackTimer - dt

            local nearAlly, nearD2 = nil, math.huge
            for _, u in ipairs(self.allies) do
                if u.hp > 0 then
                    local d2 = distSq(t.x,t.y,u.x,u.y)
                    local ar = tt.range + u.radius
                    if d2 <= ar*ar and d2 < nearD2 then nearAlly=u; nearD2=d2 end
                end
            end

            if nearAlly then
                local targetAngle = math.atan2(nearAlly.y-t.y, nearAlly.x-t.x)
                local da = targetAngle - t.angle
                while da >  math.pi do da = da - 2*math.pi end
                while da < -math.pi do da = da + 2*math.pi end
                local maxRot = math.pi * 1.8 * dt
                t.angle = t.angle + clamp(da, -maxRot, maxRot)
                if t.attackTimer <= 0 and math.abs(da) < 0.22 then
                    t.attackTimer = tt.cooldown
                    self:spawnTurretProjectile(t, nearAlly, tt)
                end
            end
        end
    end
end

function GameLayer:spawnTurretProjectile(turret, target, tt)
    local bx = turret.x + math.cos(turret.angle)*(turret.radius+5)
    local by = turret.y + math.sin(turret.angle)*(turret.radius+5)
    self:spawnFlash(bx, by, turret.color, 1.2)

    local tx, ty, trailMax, pRadius

    if tt.id == "mortar" then
        -- predict target position + area scatter
        local px, py = predictTarget(target, bx, by, tt.projSpeed, 0.55)
        local scatter = 26
        tx = px + (math.random()-0.5)*scatter*2
        ty = py + (math.random()-0.5)*scatter*2
        trailMax = 14; pRadius = 7
    elseif tt.id == "cannon" then
        -- predict + slight scatter
        local px, py = predictTarget(target, bx, by, tt.projSpeed, 0.62)
        local scatter = 12
        tx = px + (math.random()-0.5)*scatter*2
        ty = py + (math.random()-0.5)*scatter*2
        trailMax = 9; pRadius = 6
    elseif tt.id == "sniper" then
        -- high-precision prediction
        tx, ty = predictTarget(target, bx, by, tt.projSpeed, 0.82)
        trailMax = 16; pRadius = 2
    else  -- gatling
        tx, ty = predictTarget(target, bx, by, tt.projSpeed, 0.72)
        trailMax = 6; pRadius = 2
    end

    local ddx, ddy = norm(tx-bx, ty-by)
    table.insert(self.projectiles, {
        x=bx, y=by, vx=ddx*tt.projSpeed, vy=ddy*tt.projSpeed,
        targetX=tx, targetY=ty,
        damage=tt.damage, radius=pRadius,
        isEnemy=true, piercing=tt.piercing or false,
        aoeRadius=tt.aoeRadius or 0,
        lifetime=5.0, projType=tt.id,
        trail={}, trailMax=trailMax, smokeTimer=0,
    })
end

-- ── Garrison AI ───────────────────────────────────────────────────────────
function GameLayer:updateGarrison(dt)
    for _, g in ipairs(self.garrison) do
        if g.hp > 0 then
            local gt = GARRISON_TYPES[g.typeIdx]
            g.attackTimer = g.attackTimer - dt

            local nearAlly, nearD2 = nil, math.huge
            for _, u in ipairs(self.allies) do
                if u.hp > 0 then
                    local d2 = distSq(g.x,g.y,u.x,u.y)
                    local ar = gt.range + u.radius
                    if d2 <= ar*ar and d2 < nearD2 then nearAlly=u; nearD2=d2 end
                end
            end

            if nearAlly then
                -- rotate to face target
                local ta = math.atan2(nearAlly.y-g.y, nearAlly.x-g.x)
                local da = ta - g.angle
                while da >  math.pi do da = da - 2*math.pi end
                while da < -math.pi do da = da + 2*math.pi end
                local maxRot = math.pi * 2.2 * dt
                g.angle = g.angle + clamp(da, -maxRot, maxRot)

                if g.attackTimer <= 0 and math.abs(da) < 0.30 then
                    g.attackTimer = gt.cooldown
                    self:spawnGarrisonProjectile(g, nearAlly, gt)
                end
            end
        end
    end
end

function GameLayer:spawnGarrisonProjectile(guard, target, gt)
    local bx = guard.x + math.cos(guard.angle)*(guard.radius+4)
    local by = guard.y + math.sin(guard.angle)*(guard.radius+4)
    self:spawnFlash(bx, by, guard.color, 0.7)

    -- predict where ally will be when projectile arrives
    local tx, ty = predictTarget(target, bx, by, gt.projSpeed, 0.70)
    local ddx, ddy = norm(tx-bx, ty-by)
    local pType = (gt.id == "garcher") and "arrow" or "mbolt"
    table.insert(self.projectiles, {
        x=bx, y=by,
        vx=ddx*gt.projSpeed, vy=ddy*gt.projSpeed,
        targetX=tx, targetY=ty,
        damage=gt.damage, radius=(gt.id=="garcher") and 3 or 5,
        isEnemy=true, piercing=false,
        aoeRadius=gt.aoeRadius or 0,
        lifetime=4.0, projType=pType,
        trail={}, trailMax=(gt.id=="garcher") and 5 or 7,
    })
end

-- ── Fortress siege ─────────────────────────────────────────────────────────
function GameLayer:updateFortress(dt)
    local f = self.fortress
    if f.hp <= 0 then return end
    self.siegeTimer = self.siegeTimer - dt
    if self.siegeTimer <= 0 then
        self.siegeTimer = SIEGE_INTERVAL
        self:spawnSiegeShot()
    end
end

function GameLayer:spawnSiegeShot()
    local f = self.fortress
    local b = self.allyBase
    -- scatter landing point around ally base
    local scatter = 70
    local tx = b.x + (math.random() - 0.5) * scatter * 2
    local ty = b.y + (math.random() - 0.5) * scatter * 2
    local dx, dy = norm(tx - f.x, ty - f.y)
    local speed  = 280
    table.insert(self.projectiles, {
        x=f.x, y=f.y,
        vx=dx*speed, vy=dy*speed,
        targetX=tx, targetY=ty,
        damage=SIEGE_DAMAGE, radius=11,
        isEnemy=true, piercing=false,
        aoeRadius=65, lifetime=12.0,
        projType="siege",
        trail={}, trailMax=18, smokeTimer=0,
        targetsBase=true,
    })
end

-- ── Ally unit AI ──────────────────────────────────────────────────────────
function GameLayer:updateAllyUnit(unit, dt)
    local ut = UNIT_TYPES[unit.typeIdx]
    unit.attackTimer = unit.attackTimer - dt

    -- Animation timers (always updated, regardless of early returns below)
    unit.animTime = unit.animTime + dt
    if unit.isAttacking then
        unit.attackAnimTime = unit.attackAnimTime + dt
        if unit.attackAnimTime >= 0.45 then
            unit.isAttacking    = false
            unit.attackAnimTime = 0
        end
    end

    for _, obs in ipairs(self.obstacles) do resolveObstacle(unit, obs) end

    -- nearest live garrison unit
    local nearGarr, nearGarrD2 = nil, math.huge
    for _, g in ipairs(self.garrison) do
        if g.hp > 0 then
            local d2 = distSq(unit.x,unit.y,g.x,g.y)
            if d2 < nearGarrD2 then nearGarr=g; nearGarrD2=d2 end
        end
    end

    -- nearest live turret
    local nearTurret, nearTurretD2 = nil, math.huge
    for _, t in ipairs(self.turrets) do
        if t.hp > 0 then
            local d2 = distSq(unit.x,unit.y,t.x,t.y)
            if d2 < nearTurretD2 then nearTurret=t; nearTurretD2=d2 end
        end
    end

    -- primary target: closest of garrison / turret / fortress
    local fortressD2 = distSq(unit.x,unit.y,self.fortress.x,self.fortress.y)
    local primaryTarget
    local bestD2 = fortressD2
    primaryTarget = self.fortress
    if nearTurret and nearTurretD2 < bestD2 then bestD2=nearTurretD2; primaryTarget=nearTurret end
    if nearGarr   and nearGarrD2   < bestD2 then bestD2=nearGarrD2;   primaryTarget=nearGarr   end

    -- ranged units: fire at anything in range, priority: garrison > turret > fortress
    if ut.isRanged then
        local fireTarget, fireD2 = nil, math.huge
        local function tryFireAt(obj)
            if not obj or not (obj.hp > 0) then return end
            local d2 = distSq(unit.x,unit.y,obj.x,obj.y)
            if d2 <= (ut.attackRange+obj.radius)^2 and d2 < fireD2 then
                fireTarget=obj; fireD2=d2
            end
        end
        for _, g in ipairs(self.garrison) do tryFireAt(g) end
        for _, t in ipairs(self.turrets)  do tryFireAt(t) end
        tryFireAt(self.fortress)

        if fireTarget then
            local dx, dy = norm(fireTarget.x-unit.x, fireTarget.y-unit.y)
            unit.facingX, unit.facingY = dx, dy
            if unit.attackTimer <= 0 then
                unit.attackTimer    = ut.attackCooldown
                unit.isAttacking    = true
                unit.attackAnimTime = 0
                self:spawnAllyProjectile(unit, fireTarget, ut)
            end
            return
        end
    end

    -- melee range attack
    local targetD2 = distSq(unit.x,unit.y,primaryTarget.x,primaryTarget.y)
    local ar = ut.attackRange + primaryTarget.radius
    if targetD2 <= ar*ar then
        local dx, dy = norm(primaryTarget.x-unit.x, primaryTarget.y-unit.y)
        unit.facingX, unit.facingY = dx, dy
        if unit.attackTimer <= 0 then
            unit.attackTimer    = ut.attackCooldown
            unit.isAttacking    = true
            unit.attackAnimTime = 0
            if ut.isRanged then
                self:spawnAllyProjectile(unit, primaryTarget, ut)
            elseif (ut.aoeRadius or 0) > 0 then
                local function aoeHit(obj)
                    if obj and obj.hp > 0 and distSq(unit.x,unit.y,obj.x,obj.y) <= (ut.aoeRadius+obj.radius)^2 then
                        obj.hp = obj.hp - ut.damage*0.55
                        self:floatText(obj.x, obj.y, string.format("%.0f",ut.damage*0.55), {1,0.6,0.2})
                    end
                end
                for _, g in ipairs(self.garrison) do aoeHit(g) end
                for _, t in ipairs(self.turrets)  do aoeHit(t) end
                aoeHit(self.fortress)
            else
                primaryTarget.hp = primaryTarget.hp - ut.damage
                self:floatText(primaryTarget.x, primaryTarget.y, string.format("%.0f",ut.damage), {1,0.85,0.3})
            end
        end
        return
    end

    -- march
    local dx, dy = norm(primaryTarget.x-unit.x, primaryTarget.y-unit.y)
    unit.x = unit.x + dx*ut.speed*dt
    unit.y = unit.y + dy*ut.speed*dt
    unit.facingX, unit.facingY = dx, dy
end

-- ── Separation ─────────────────────────────────────────────────────────────
function GameLayer:separateUnits(units)
    for i = 1, #units do
        local a = units[i]
        if a.hp > 0 then
            for j = i+1, #units do
                local b = units[j]
                if b.hp > 0 then
                    local dx, dy, dist = norm(a.x-b.x, a.y-b.y)
                    local minD = a.radius+b.radius+1
                    if dist > 0 and dist < minD then
                        local push = (minD-dist)*0.5
                        a.x=a.x+dx*push; a.y=a.y+dy*push
                        b.x=b.x-dx*push; b.y=b.y-dy*push
                    end
                end
            end
        end
    end
end

-- ── Projectile spawning ────────────────────────────────────────────────────
function GameLayer:spawnAllyProjectile(unit, target, ut)
    local dx, dy = norm(target.x-unit.x, target.y-unit.y)
    local pType = (ut.id=="archer") and "arrow" or
                  (ut.id=="mage")   and "mbolt" or "shell"
    -- targets (garrison/turret/fortress) are static: aim directly at their position
    table.insert(self.projectiles, {
        x=unit.x, y=unit.y,
        vx=dx*ut.projectileSpeed, vy=dy*ut.projectileSpeed,
        targetX=target.x, targetY=target.y,
        damage=ut.damage, radius=4,
        isEnemy=false, piercing=ut.piercing or false,
        aoeRadius=ut.aoeRadius or 0,
        lifetime=3.0, projType=pType,
        trail={}, trailMax=(ut.id=="archer") and 5 or 8,
    })
end

function GameLayer:floatText(x, y, text, color)
    table.insert(self.effects, {
        type="floatText", x=x, y=y, text=text,
        color=color or {1,1,1}, life=0.9, maxLife=0.9, vy=-42,
    })
end

-- ── Projectile detonation ─────────────────────────────────────────────────
-- Called when a projectile reaches its target point.
-- Applies area / direct damage and spawns VFX.
function GameLayer:detonateProjectile(p)
    local aoeR  = p.aoeRadius or 0
    local hitR  = aoeR > 0 and aoeR or 18   -- blast radius (non-AOE uses small impact zone)
    local isAOE = aoeR > 0

    if p.isEnemy then
        -- ── damage ally units in blast radius ────────────────────────────
        for _, u in ipairs(self.allies) do
            if u.hp > 0 and distSq(p.x,p.y,u.x,u.y) <= (hitR+u.radius)^2 then
                u.hp = u.hp - p.damage
                self:floatText(u.x, u.y, string.format("%.0f", p.damage), {1,0.4,0.2})
                if not isAOE and not p.piercing then break end
            end
        end
        -- ── siege: also damage ally base ─────────────────────────────────
        if p.targetsBase then
            local blastR = aoeR > 0 and aoeR or 55
            if distSq(p.x,p.y,self.allyBase.x,self.allyBase.y) <= (blastR+self.allyBase.radius)^2 then
                self.allyBase.hp = self.allyBase.hp - p.damage
                self:floatText(self.allyBase.x, self.allyBase.y-14,
                    "轰炸! -"..math.floor(p.damage), {1,0.18,0.08})
            end
        end
    else
        -- ── damage garrison in blast radius ──────────────────────────────
        for _, g in ipairs(self.garrison) do
            if g.hp > 0 and distSq(p.x,p.y,g.x,g.y) <= (hitR+g.radius)^2 then
                g.hp = g.hp - p.damage
                self:floatText(g.x, g.y, string.format("%.0f", p.damage), {1,0.85,0.3})
                if not isAOE and not p.piercing then break end
            end
        end
        -- ── damage turrets in blast radius ───────────────────────────────
        for _, t in ipairs(self.turrets) do
            if t.hp > 0 and distSq(p.x,p.y,t.x,t.y) <= (hitR+t.radius)^2 then
                t.hp = t.hp - p.damage
                self:floatText(t.x, t.y, string.format("%.0f", p.damage), {1,0.85,0.3})
                if not isAOE and not p.piercing then break end
            end
        end
        -- ── damage fortress ──────────────────────────────────────────────
        if self.fortress.hp > 0 and
           distSq(p.x,p.y,self.fortress.x,self.fortress.y) <= (hitR+self.fortress.radius)^2 then
            self.fortress.hp = self.fortress.hp - p.damage
            self:floatText(self.fortress.x, self.fortress.y,
                string.format("%.0f", p.damage), {1,0.85,0.3})
        end
    end

    -- ── Visual effects ────────────────────────────────────────────────────
    if isAOE then
        local bigHit    = p.targetsBase
        local ringColor = p.isEnemy and {1, bigHit and 0.38 or 0.55, 0.15} or {0.55,0.85,1.0}
        local shake     = bigHit and 22 or (p.isEnemy and 10 or 6)
        local ringLife  = bigHit and 0.65 or 0.45
        self:spawnRing(p.x, p.y, aoeR, ringColor, ringLife)
        self:spawnBurst(p.x, p.y, p.isEnemy and {1,0.55,0.2} or {0.6,0.85,1.0})
        self:addShake(shake)
    else
        self:spawnFlash(p.x, p.y, p.isEnemy and {1,0.8,0.3} or {0.8,1.0,0.5}, 0.8)
        self:addShake(p.isEnemy and 3 or 2)
    end
end

-- ── Projectiles update ─────────────────────────────────────────────────────
-- Projectiles fly to their pre-computed target point and detonate on arrival.
-- No per-frame collision detection — aim is locked at fire time.
function GameLayer:updateProjectiles(dt)
    local w, h = love.graphics.getDimensions()
    local dead = {}

    for idx, p in ipairs(self.projectiles) do
        local px0, py0 = p.x, p.y          -- position before this frame's move

        p.x = p.x + p.vx*dt
        p.y = p.y + p.vy*dt
        p.lifetime = p.lifetime - dt

        -- trail
        if p.trailMax and p.trailMax > 0 then
            table.insert(p.trail, 1, {x=p.x, y=p.y})
            while #p.trail > p.trailMax do table.remove(p.trail) end
        end

        -- mortar/siege smoke puffs
        if p.projType == "mortar" or p.projType == "siege" then
            p.smokeTimer = (p.smokeTimer or 0) + dt
            if p.smokeTimer >= 0.06 then
                p.smokeTimer = 0
                self:spawnSmoke(p.x, p.y)
            end
        end

        -- ── Arrival detection ─────────────────────────────────────────────
        local kill = false
        if p.targetX then
            local d2now  = distSq(p.x,  p.y,  p.targetX, p.targetY)
            local d2prev = distSq(px0, py0, p.targetX, p.targetY)
            -- Detonate when: within 8 px of target, OR we've overshot (distance growing)
            if d2now <= 64 or d2now > d2prev then
                p.x, p.y = p.targetX, p.targetY    -- snap to exact impact point
                self:detonateProjectile(p)
                kill = true
            end
        end

        if kill or p.lifetime <= 0
            or p.x < -60 or p.x > w+60
            or p.y < -60 or p.y > h+60 then
            table.insert(dead, idx)
        end
    end
    for i = #dead, 1, -1 do table.remove(self.projectiles, dead[i]) end
end

-- ── Effects ────────────────────────────────────────────────────────────────
function GameLayer:updateEffects(dt)
    for i = #self.effects, 1, -1 do
        local e = self.effects[i]
        e.life = e.life - dt
        if e.type == "floatText" then
            e.y = e.y + e.vy*dt
        elseif e.type == "burst" then
            for _, p in ipairs(e.pts) do
                p.x=p.x+p.vx*dt; p.y=p.y+p.vy*dt
                p.vx=p.vx*0.88;  p.vy=p.vy*0.88
            end
        end
        if e.life <= 0 then table.remove(self.effects, i) end
    end
end

-- ── Cleanup / Scoring ──────────────────────────────────────────────────────
function GameLayer:cleanupDead()
    for i = #self.allies, 1, -1 do
        local u = self.allies[i]
        if u.hp <= 0 then
            self:spawnBurst(u.x, u.y, u.color)
            table.remove(self.allies, i)
        end
    end
    for _, t in ipairs(self.turrets) do
        if t.hp<=0 and not t.scored then
            t.scored=true; self.kills=self.kills+1
            local tt=TURRET_TYPES[t.typeIdx]
            self.score=self.score+(TURRET_SCORE[tt.id] or 40)
            self:spawnRing(t.x,t.y, 40, {1,0.65,0.2}, 0.60)
            self:addShake(12)
        end
    end
    for _, g in ipairs(self.garrison) do
        if g.hp<=0 and not g.scored then
            g.scored=true; self.kills=self.kills+1
            local gt=GARRISON_TYPES[g.typeIdx]
            self.score=self.score+(GARRISON_SCORE[gt.id] or 20)
            self:spawnBurst(g.x, g.y, g.color)
        end
    end
end

-- ── Main update ────────────────────────────────────────────────────────────
function GameLayer:update(dt)
    if self.gameOver then return end
    self.elapsed  = self.elapsed + dt
    self.shakeAmt = self.shakeAmt * math.max(0, 1 - dt*14)

    self:updateBarracks(dt)
    self:updateTurrets(dt)
    self:updateGarrison(dt)
    self:updateFortress(dt)

    for _, u in ipairs(self.allies) do
        if u.hp > 0 then self:updateAllyUnit(u, dt) end
    end

    self:separateUnits(self.allies)
    self:updateProjectiles(dt)
    self:updateEffects(dt)
    self:cleanupDead()

    local w, h = love.graphics.getDimensions()
    for _, u in ipairs(self.allies) do
        u.x=clamp(u.x, u.radius, w-u.radius)
        u.y=clamp(u.y, u.radius, h-u.radius)
    end

    if self.fortress.hp <= 0 then
        self.fortress.hp=0; self.score=self.score+500
        self.gameOver=true; self.winner="ally"
    end
    if self.allyBase.hp <= 0 then
        self.allyBase.hp=0; self.gameOver=true; self.winner="enemy"
    end
end

-- ── Input ──────────────────────────────────────────────────────────────────
function GameLayer:keypressed(key)
    if key=="space" and self.gameOver then self:reset() end
    for i = 1, #UNIT_TYPES do
        if key==tostring(i) then self.currentUnitType=i end
    end
    if key=="q" then
        self.currentFormation=((self.currentFormation-2)%#FORMATIONS)+1
    elseif key=="e" then
        self.currentFormation=(self.currentFormation%#FORMATIONS)+1
    end
end

function GameLayer:wheelmoved(x, y)
    self.currentUnitType=((self.currentUnitType-1-y)%#UNIT_TYPES)+1
end

-- ── Draw helpers ───────────────────────────────────────────────────────────
function GameLayer:drawUnit(u)
    local row   = u.typeIdx - 1
    local col
    if u.isAttacking then
        col = 4 + (math.floor(u.attackAnimTime * 10) % 4)
    else
        col = math.floor(u.animTime * 6) % 4
    end

    local angle = math.atan2(u.facingY, u.facingX)
    local scale = u.radius * MusouSprites.SCALE_FACTOR / MusouSprites.FRAME_W
    love.graphics.setColor(1, 1, 1, 0.95)
    self.spriteSheet:getFrame(row, col):draw(u.x, u.y, angle, scale, scale)

    local pct = clamp(u.hp / u.maxHp, 0, 1)
    if pct < 0.80 then
        local barW = 10
        love.graphics.setColor(0.10, 0.10, 0.10, 0.82)
        love.graphics.rectangle("fill", u.x - barW*0.5, u.y - u.radius - 4, barW, 2)
        love.graphics.setColor(hpColor(pct))
        love.graphics.rectangle("fill", u.x - barW*0.5, u.y - u.radius - 4, barW*pct, 2)
    end
end

local function drawBase(base)
    local r,g,b = base.color[1],base.color[2],base.color[3]
    love.graphics.setColor(r*0.18,g*0.18,b*0.18,0.92)
    love.graphics.circle("fill", base.x,base.y,base.radius)
    love.graphics.setColor(r,g,b,0.85)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", base.x,base.y,base.radius)
    love.graphics.setLineWidth(1)
    local pct=clamp(base.hp/base.maxHp,0,1)
    local bw=base.radius*2.4
    love.graphics.setColor(0.10,0.10,0.10,0.85)
    love.graphics.rectangle("fill", base.x-bw*0.5,base.y-base.radius-12, bw, 7, 2,2)
    love.graphics.setColor(hpColor(pct))
    love.graphics.rectangle("fill", base.x-bw*0.5,base.y-base.radius-12, bw*pct, 7, 2,2)
end

function GameLayer:drawObstacles()
    for _, obs in ipairs(self.obstacles) do
        local r,g,b = obs.color[1],obs.color[2],obs.color[3]
        if obs.shape == "circle" then
            love.graphics.setColor(r*0.55,g*0.55,b*0.55,0.95)
            love.graphics.circle("fill", obs.x,obs.y,obs.radius)
            love.graphics.setColor(r,g,b,0.70)
            love.graphics.setLineWidth(1.5)
            love.graphics.circle("line", obs.x,obs.y,obs.radius)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(r*0.35,g*0.35,b*0.35,0.60)
            love.graphics.line(obs.x-obs.radius*0.3,obs.y-obs.radius*0.4, obs.x+obs.radius*0.1,obs.y+obs.radius*0.3)
        elseif obs.shape == "rect" then
            love.graphics.setColor(r*0.50,g*0.50,b*0.50,0.95)
            love.graphics.rectangle("fill", obs.x,obs.y,obs.w,obs.h, 2,2)
            love.graphics.setColor(r,g,b,0.72)
            love.graphics.setLineWidth(1.5)
            love.graphics.rectangle("line", obs.x,obs.y,obs.w,obs.h, 2,2)
            love.graphics.setLineWidth(1)
        end
    end
end

function GameLayer:drawFortress()
    local f=self.fortress
    local pct=clamp(f.hp/f.maxHp,0,1)
    local r,g,b = f.color[1],f.color[2],f.color[3]

    love.graphics.setColor(r*0.28,g*0.10,b*0.10,0.92)
    love.graphics.circle("fill", f.x,f.y, f.radius+14)
    love.graphics.setColor(r*0.55,g*0.20,b*0.16,0.85)
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", f.x,f.y, f.radius+14)
    love.graphics.setLineWidth(1)
    for i = 1, 8 do
        local ang=(i-0.5)/8*2*math.pi
        love.graphics.setColor(r*0.60,g*0.22,b*0.18,0.90)
        love.graphics.circle("fill", f.x+math.cos(ang)*(f.radius+6), f.y+math.sin(ang)*(f.radius+6), 7)
    end
    love.graphics.setColor(r*0.18,g*0.10,b*0.10,0.95)
    love.graphics.circle("fill", f.x,f.y, f.radius)
    love.graphics.setColor(r,g,b,0.88)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", f.x,f.y, f.radius)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.55,0.55,0.62,0.85)
    love.graphics.setLineWidth(2)
    love.graphics.line(f.x,f.y+10, f.x,f.y-26)
    love.graphics.setColor(1,0.18,0.10,0.92)
    love.graphics.polygon("fill", f.x,f.y-26, f.x+16,f.y-18, f.x,f.y-10)
    love.graphics.setLineWidth(1)
    -- HP bar
    local bw=f.radius*3.0
    love.graphics.setColor(0.10,0.10,0.10,0.88)
    love.graphics.rectangle("fill", f.x-bw*0.5,f.y-f.radius-20, bw,9, 3,3)
    love.graphics.setColor(hpColor(pct))
    love.graphics.rectangle("fill", f.x-bw*0.5,f.y-f.radius-20, bw*pct,9, 3,3)
    -- siege countdown arc
    local sigeMax=(self.elapsed<1) and 15.0 or SIEGE_INTERVAL
    local siegePct=clamp(self.siegeTimer/sigeMax,0,1)
    love.graphics.setColor(1,0.55,0.10,0.45)
    love.graphics.arc("fill", f.x,f.y, f.radius-8, -math.pi*0.5, -math.pi*0.5+(1-siegePct)*2*math.pi)
    love.graphics.setColor(1,0.55,0.10,0.80)
    love.graphics.setLineWidth(2)
    love.graphics.arc("line", f.x,f.y, f.radius-8, -math.pi*0.5, -math.pi*0.5+(1-siegePct)*2*math.pi)
    love.graphics.setLineWidth(1)
end

function GameLayer:drawTurrets()
    for _, t in ipairs(self.turrets) do
        local tt=TURRET_TYPES[t.typeIdx]
        local r,g,b = t.color[1],t.color[2],t.color[3]
        local alive = t.hp > 0
        if alive then
            love.graphics.setColor(r,g,b,0.05)
            love.graphics.circle("fill", t.x,t.y, tt.range)
            love.graphics.setColor(r,g,b,0.12)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", t.x,t.y, tt.range)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.20,0.20,0.23,0.95)
            love.graphics.circle("fill", t.x,t.y, t.radius+5)
            love.graphics.setColor(r*0.28,g*0.28,b*0.28,0.92)
            love.graphics.circle("fill", t.x,t.y, t.radius)
            love.graphics.setColor(r,g,b,0.85)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", t.x,t.y, t.radius)
            love.graphics.setLineWidth(1)
            -- barrel
            local bLen=t.radius+12
            love.graphics.setColor(r*0.8,g*0.8,b*0.8,0.92)
            love.graphics.setLineWidth(3.5)
            love.graphics.line(t.x,t.y, t.x+math.cos(t.angle)*bLen, t.y+math.sin(t.angle)*bLen)
            love.graphics.setLineWidth(1)
            -- HP bar
            local pct=clamp(t.hp/t.maxHp,0,1)
            local bw=t.radius*2+8
            love.graphics.setColor(0.10,0.10,0.10,0.80)
            love.graphics.rectangle("fill", t.x-bw*0.5,t.y-t.radius-8, bw,4, 2,2)
            love.graphics.setColor(hpColor(pct))
            love.graphics.rectangle("fill", t.x-bw*0.5,t.y-t.radius-8, bw*pct,4, 2,2)
        else
            love.graphics.setColor(0.28,0.24,0.20,0.72)
            love.graphics.circle("fill", t.x,t.y, t.radius*0.75)
            love.graphics.setColor(0.45,0.36,0.28,0.45)
            love.graphics.setLineWidth(1.5)
            love.graphics.line(t.x-6,t.y-6, t.x+6,t.y+6)
            love.graphics.line(t.x+6,t.y-6, t.x-6,t.y+6)
            love.graphics.setLineWidth(1)
        end
    end
end

-- ── Garrison draw ──────────────────────────────────────────────────────────
function GameLayer:drawGarrison()
    for _, g in ipairs(self.garrison) do
        local gt=GARRISON_TYPES[g.typeIdx]
        local r,b_c,b2 = g.color[1],g.color[2],g.color[3]
        local alive = g.hp > 0

        if alive then
            -- shadow
            love.graphics.setColor(0.08,0.06,0.06,0.70)
            love.graphics.circle("fill", g.x+1,g.y+2, g.radius+2)
            -- body (diamond shape via rotated rectangle for visual distinction)
            love.graphics.setColor(r*0.22, b_c*0.22, b2*0.22, 0.92)
            love.graphics.circle("fill", g.x,g.y, g.radius)
            love.graphics.setColor(r, b_c, b2, 0.95)
            love.graphics.setLineWidth(1.5)
            love.graphics.circle("line", g.x,g.y, g.radius)
            love.graphics.setLineWidth(1)

            -- weapon direction indicator
            local wLen = g.radius + 8
            local wx = g.x + math.cos(g.angle)*wLen
            local wy = g.y + math.sin(g.angle)*wLen
            if gt.id == "garcher" then
                -- bow: curved arc toward target + arrow line
                love.graphics.setColor(r*0.9, b_c*0.6, b2*0.3, 0.85)
                love.graphics.setLineWidth(1.5)
                love.graphics.line(g.x, g.y, wx, wy)
                -- arrowhead
                local px = wx + math.cos(g.angle)*3
                local py = wy + math.sin(g.angle)*3
                love.graphics.setColor(0.95, 0.88, 0.65, 0.90)
                love.graphics.circle("fill", px, py, 1.5)
                love.graphics.setLineWidth(1)
            else
                -- mage: orbiting magic circle
                love.graphics.setColor(r, b_c, b2, 0.70)
                love.graphics.setLineWidth(1)
                love.graphics.circle("line", g.x,g.y, g.radius+4)
                love.graphics.setColor(1, 0.85, 1, 0.55)
                love.graphics.circle("fill", wx, wy, 2.5)
            end

            -- HP bar
            local pct=clamp(g.hp/g.maxHp,0,1)
            if pct < 0.85 then
                local bw=12
                love.graphics.setColor(0.10,0.10,0.10,0.80)
                love.graphics.rectangle("fill", g.x-bw*0.5,g.y-g.radius-5, bw,2)
                love.graphics.setColor(hpColor(pct))
                love.graphics.rectangle("fill", g.x-bw*0.5,g.y-g.radius-5, bw*pct,2)
            end
        else
            -- dead: small dark remains
            love.graphics.setColor(0.25,0.18,0.14,0.55)
            love.graphics.circle("fill", g.x,g.y, g.radius*0.6)
        end
    end
end

function GameLayer:drawBarracks()
    local bSz=26
    for _, bar in ipairs(self.allyBarracks) do
        local r,g,b = bar.color[1],bar.color[2],bar.color[3]
        love.graphics.setColor(r*0.28,g*0.28,b*0.28,0.9)
        love.graphics.rectangle("fill", bar.x-bSz*0.5,bar.y-bSz*0.5, bSz,bSz, 4,4)
        love.graphics.setColor(r,g,b,0.80)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", bar.x-bSz*0.5,bar.y-bSz*0.5, bSz,bSz, 4,4)
        love.graphics.setLineWidth(1)
        local pct=1-(bar.timer/SPAWN_INTERVAL)
        local pw=bSz+6
        love.graphics.setColor(0.12,0.13,0.16,0.88)
        love.graphics.rectangle("fill", bar.x-pw*0.5,bar.y+bSz*0.5+3, pw,5, 2,2)
        love.graphics.setColor(r,g,b,0.88)
        love.graphics.rectangle("fill", bar.x-pw*0.5,bar.y+bSz*0.5+3, pw*clamp(pct,0,1),5, 2,2)
    end
end

-- ── Projectile draw ────────────────────────────────────────────────────────
function GameLayer:drawProjectiles()
    for _, p in ipairs(self.projectiles) do
        local ptype = p.projType or ""

        -- draw trail first (behind the head)
        if p.trail and #p.trail > 1 then
            local n = #p.trail
            for i, tp in ipairs(p.trail) do
                local ta   = (1 - i/n)          -- 1 at head, 0 at tail
                local tsz  = p.radius * ta * 0.85

                if ptype == "mortar" or ptype == "siege" then
                    -- smoke-grey trail
                    love.graphics.setColor(0.60,0.55,0.50, ta*0.45)
                    love.graphics.circle("fill", tp.x,tp.y, math.max(1, tsz+2))
                elseif ptype == "sniper" then
                    -- bright cyan streak
                    love.graphics.setColor(0.30,1.0,0.90, ta*0.75)
                    love.graphics.circle("fill", tp.x,tp.y, math.max(0.8, tsz))
                elseif ptype == "gatling" then
                    -- yellow-white tracer
                    love.graphics.setColor(1.0,0.95,0.60, ta*0.80)
                    love.graphics.circle("fill", tp.x,tp.y, math.max(0.6, tsz))
                elseif ptype == "cannon" then
                    -- orange-red fire trail
                    love.graphics.setColor(1.0, 0.5-ta*0.3, 0.10, ta*0.55)
                    love.graphics.circle("fill", tp.x,tp.y, math.max(1, tsz*1.2))
                elseif ptype == "arrow" then
                    -- thin orange trace
                    love.graphics.setColor(0.92,0.42,0.15, ta*0.55)
                    love.graphics.circle("fill", tp.x,tp.y, math.max(0.6, tsz*0.7))
                elseif ptype == "mbolt" then
                    -- purple sparkle
                    love.graphics.setColor(0.80,0.20,0.90, ta*0.60)
                    love.graphics.circle("fill", tp.x,tp.y, math.max(0.8, tsz))
                else
                    -- generic blue (ally spells)
                    love.graphics.setColor(0.35,0.82,1.0, ta*0.50)
                    love.graphics.circle("fill", tp.x,tp.y, math.max(0.8, tsz))
                end
            end
        end

        -- draw projectile head
        if ptype == "siege" then
            -- large flaming siege ball
            love.graphics.setColor(1.0, 0.70, 0.10, 0.92)
            love.graphics.circle("fill", p.x,p.y, p.radius)
            love.graphics.setColor(1.0, 0.30, 0.05, 0.55)
            love.graphics.circle("fill", p.x,p.y, p.radius+4)
            love.graphics.setColor(1.0, 1.0, 0.80, 0.40)
            love.graphics.circle("fill", p.x,p.y, p.radius*0.4)

        elseif ptype == "mortar" then
            love.graphics.setColor(0.72,0.22,0.85,0.95)
            love.graphics.circle("fill", p.x,p.y, p.radius)
            love.graphics.setColor(1.0,0.60,1.0,0.45)
            love.graphics.circle("fill", p.x,p.y, p.radius+3)
            love.graphics.setColor(1,1,1,0.25)
            love.graphics.circle("fill", p.x,p.y, p.radius*0.4)

        elseif ptype == "cannon" then
            love.graphics.setColor(1.0,0.50,0.12,0.95)
            love.graphics.circle("fill", p.x,p.y, p.radius)
            love.graphics.setColor(1.0,0.80,0.20,0.35)
            love.graphics.circle("fill", p.x,p.y, p.radius+2)
            love.graphics.setColor(1,1,1,0.30)
            love.graphics.circle("fill", p.x,p.y, p.radius*0.35)

        elseif ptype == "gatling" then
            love.graphics.setColor(1.0,0.98,0.70,0.98)
            love.graphics.circle("fill", p.x,p.y, p.radius)
            love.graphics.setColor(1,1,1,0.85)
            love.graphics.circle("fill", p.x,p.y, p.radius*0.5)

        elseif ptype == "sniper" then
            love.graphics.setColor(0.20,1.0,0.88,0.98)
            love.graphics.circle("fill", p.x,p.y, p.radius)
            love.graphics.setColor(1,1,1,0.90)
            love.graphics.circle("fill", p.x,p.y, p.radius*0.5)

        elseif ptype == "arrow" then
            -- enemy arrow: draw as short line in travel direction
            local spd  = math.sqrt(p.vx*p.vx+p.vy*p.vy)
            local adx  = spd>1 and p.vx/spd or 1
            local ady  = spd>1 and p.vy/spd or 0
            love.graphics.setColor(0.92,0.38,0.15,0.95)
            love.graphics.setLineWidth(2)
            love.graphics.line(p.x-adx*6, p.y-ady*6, p.x+adx*4, p.y+ady*4)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.95,0.85,0.55,0.90)
            love.graphics.circle("fill", p.x+adx*4, p.y+ady*4, 1.5)

        elseif ptype == "mbolt" then
            love.graphics.setColor(0.78,0.18,0.88,0.95)
            love.graphics.circle("fill", p.x,p.y, p.radius)
            love.graphics.setColor(1.0,0.70,1.0,0.40)
            love.graphics.circle("fill", p.x,p.y, p.radius+3)
            love.graphics.setColor(1,1,1,0.35)
            love.graphics.circle("fill", p.x,p.y, p.radius*0.45)

        else
            -- ally generic (spell, etc.)
            local c = (p.aoeRadius>0) and {0.70,0.35,1.0} or {0.35,0.82,1.0}
            love.graphics.setColor(c[1],c[2],c[3],0.92)
            love.graphics.circle("fill", p.x,p.y, p.radius)
            if p.aoeRadius>0 then
                love.graphics.setColor(c[1],c[2],c[3],0.28)
                love.graphics.circle("fill", p.x,p.y, p.radius+4)
            end
        end
    end
end

-- ── Effects draw ───────────────────────────────────────────────────────────
function GameLayer:drawEffects()
    for _, e in ipairs(self.effects) do
        local a = e.life/e.maxLife
        if e.type == "floatText" then
            love.graphics.setColor(e.color[1],e.color[2],e.color[3],a)
            love.graphics.print(e.text, math.floor(e.x-10),math.floor(e.y))

        elseif e.type == "ring" then
            local t   = 1-a
            local rad = e.maxR*(0.15+t*0.85)
            love.graphics.setColor(e.color[1],e.color[2],e.color[3], a*0.80)
            love.graphics.setLineWidth(2.5*a)
            love.graphics.circle("line", e.x,e.y, rad)
            love.graphics.setColor(1,1,1, a*0.35)
            love.graphics.circle("line", e.x,e.y, rad*0.6)
            love.graphics.setLineWidth(1)

        elseif e.type == "burst" then
            local sz = 2.8*math.sqrt(a)
            for _, pt in ipairs(e.pts) do
                love.graphics.setColor(e.color[1],e.color[2],e.color[3], a*0.92)
                love.graphics.circle("fill", pt.x,pt.y, sz)
                love.graphics.setColor(1,1,1, a*0.55)
                love.graphics.circle("fill", pt.x,pt.y, sz*0.45)
            end

        elseif e.type == "flash" then
            local sz = 10*(e.size or 1)*a
            love.graphics.setColor(e.color[1],e.color[2],e.color[3], a*0.85)
            love.graphics.circle("fill", e.x,e.y, sz)
            love.graphics.setColor(1,1,1, a*0.70)
            love.graphics.circle("fill", e.x,e.y, sz*0.45)

        elseif e.type == "smoke" then
            love.graphics.setColor(0.55,0.52,0.48, a*0.28)
            love.graphics.circle("fill", e.x,e.y, e.r*(1+a*0.5))
        end
    end
end

-- ── Main draw ──────────────────────────────────────────────────────────────
function GameLayer:draw()
    love.graphics.push("all")
    local w, h = love.graphics.getDimensions()

    if self.shakeAmt > 0.4 then
        love.graphics.translate(
            (math.random()-0.5)*self.shakeAmt*2,
            (math.random()-0.5)*self.shakeAmt*2)
    end

    love.graphics.setColor(0.07,0.09,0.11)
    love.graphics.rectangle("fill", 0,0,w,h)

    love.graphics.setColor(0.10,0.12,0.14,0.45)
    love.graphics.setLineWidth(0.5)
    for i = 1, 7 do love.graphics.line(0,h*i/8, w,h*i/8) end
    love.graphics.setLineWidth(1)

    self:drawObstacles()
    self:drawFortress()
    self:drawTurrets()
    self:drawGarrison()
    self:drawBarracks()
    drawBase(self.allyBase)

    for _, u in ipairs(self.allies) do
        if u.hp > 0 then self:drawUnit(u) end
    end

    self:drawProjectiles()
    self:drawEffects()
    love.graphics.pop()
end

return GameLayer
