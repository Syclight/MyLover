-- 长筱战役的轻量战斗循环：单位是战场表现与胜负统计的共同来源。
local BattleSimulation = {}
BattleSimulation.__index = BattleSimulation

local DEATH_FALL_DURATION = 0.62

local function addFormation(units, faction, rows, columns, originX, originZ, spacingX, spacingZ, facing, roleForRow)
    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local id = #units + 1
            units[id] = {
                id = id,
                faction = faction,
                startX = originX + row * spacingX,
                startZ = originZ + (column - (columns - 1) * 0.5) * spacingZ,
                x = originX + row * spacingX,
                z = originZ + (column - (columns - 1) * 0.5) * spacingZ,
                facing = facing,
                role = roleForRow(row, column),
                rank = row,
                column = column,
                volleyRank = row % 3,
                alive = true,
                seed = (id * 0.61803398875) % 1,
                gait = 0,
                speed = 0,
            }
        end
    end
end

function BattleSimulation.new()
    local self = setmetatable({}, BattleSimulation)
    self:reset()
    return self
end

function BattleSimulation:reset()
    self.time = 0
    self.phase = "deployment"
    self.paused = false
    self.result = nil
    self.units = {}
    -- 三段火枪队、长枪足轻与赤备骑兵：共 238 名表现单位。
    addFormation(self.units, "oda", 7, 11, 10.0, 0, 1.15, 1.35, -1,
        function(row) return row < 3 and "teppo" or "ashigaru" end)
    addFormation(self.units, "tokugawa", 5, 9, 18.5, 0, 1.1, 1.5, -1,
        function(row) return row < 2 and "teppo" or "ashigaru" end)
    addFormation(self.units, "takeda", 8, 14, -31.0, 0, 1.25, 1.15, 1,
        function() return "cavalry" end)
    self.initial = { oda = 77, tokugawa = 45, takeda = 112 }
    self.losses = { oda = 0, tokugawa = 0, takeda = 0 }
    self.events = {}
    self.lastVolleyCycle = -1
end

function BattleSimulation:aliveCount(faction)
    return self.initial[faction] - self.losses[faction]
end

function BattleSimulation:statusText()
    if self.result == "alliance" then return "织田・德川联军守住马防柵" end
    if self.result == "takeda" then return "武田军突破火枪阵" end
    if self.phase == "deployment" then return "部署中：武田骑马队正在集结" end
    if self.phase == "volley" then return "三段击开始：火枪齐射压制冲锋" end
    return "武田军冲锋：守住马防柵" 
end

function BattleSimulation:kill(unit)
    if not unit.alive then return end
    unit.alive = false
    unit.dying = true
    unit.deathTime = 0
    unit.fallProgress = 0
    unit.deathStartX, unit.deathStartZ = unit.x, unit.z
    self.losses[unit.faction] = self.losses[unit.faction] + 1
end

function BattleSimulation:emit(type, x, z, seed, facing, role, faction)
    self.events[#self.events + 1] = {
        type = type,
        x = x,
        z = z,
        seed = seed or 0,
        facing = facing or 0,
        role = role,
        faction = faction,
    }
end

function BattleSimulation:drainEvents()
    local events = self.events
    self.events = {}
    return events
end

function BattleSimulation:emitVolleyEffects()
    local cycle = math.floor(self.time * 2)
    if cycle == self.lastVolleyCycle then return end
    self.lastVolleyCycle = cycle
    local activeRank = cycle % 3
    for _, unit in ipairs(self.units) do
        if unit.alive and unit.role == "teppo" and unit.volleyRank == activeRank then
            self:emit("muzzle", unit.x, unit.z, unit.seed, unit.facing)
            -- 每列散布部分落点，避免整齐的火力网与粒子数量暴涨。
            if (unit.id + cycle) % 2 == 0 then
                local spread = (unit.seed - 0.5) * 7.5
                self:emit("impact", unit.x - 17.0 - unit.seed * 9.0, unit.z + spread, unit.seed, unit.facing)
            end
        end
    end
end

function BattleSimulation:update(dt)
    if self.paused or self.result then return end
    self.time = self.time + dt
    if self.time > 2.4 and self.phase == "deployment" then self.phase = "volley" end
    if self.time > 5.0 then self.phase = "charge" end
    if self.phase ~= "deployment" then self:emitVolleyEffects() end

    for _, unit in ipairs(self.units) do
        if unit.dying then
            unit.deathTime = unit.deathTime + dt
            unit.speed = 0
            local t = math.min(1, unit.deathTime / DEATH_FALL_DURATION)
            unit.fallProgress = t * t * (3 - 2 * t)
            if unit.deathTime >= DEATH_FALL_DURATION then
                unit.dying = false
                self:emit("blood", unit.x, unit.z, unit.seed)
                self:emit("casualty", unit.x, unit.z, unit.seed, unit.facing, unit.role, unit.faction)
                self:emit("weapon", unit.x, unit.z, unit.seed, unit.facing, unit.role, unit.faction)
            end
        end
        if unit.alive then
            local oldX, oldZ = unit.x, unit.z
            if unit.faction == "takeda" and self.phase == "charge" then
                local chargeTime = self.time - 5.0
                unit.x = math.min(unit.startX + chargeTime * (3.8 + unit.seed * 0.7), 6.2)
                unit.z = unit.startZ + math.sin(self.time * 2.3 + unit.id) * 0.10
                unit.gait = self.time * 9.5 + unit.seed * 12
                -- 三段击会随冲锋距离渐进造成伤亡，阵列自然出现缺口。
                if unit.x > -13 and math.floor(chargeTime * 1.7 + unit.id * 0.31) % 13 == 0 then
                    self:kill(unit)
                end
            else
                unit.gait = self.time * 2.2 + unit.seed * 9
            end
            local inverseDt = 1 / math.max(dt, 0.0001)
            local dx, dz = unit.x - oldX, unit.z - oldZ
            unit.speed = math.sqrt(dx * dx + dz * dz) * inverseDt
        end
    end

    if self.losses.takeda >= 72 then
        self.result = "alliance"
    elseif self.time > 22 and self.aliveCount("takeda") > 58 then
        self.result = "takeda"
    end
end

return BattleSimulation
