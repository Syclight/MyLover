-- samples/raycast/LightingSystem.lua

local LightingSystem = {
    enabled = true,        -- 【核心功能】是否开启光照
    ambientLight = 0.05,   -- 全局环境光亮度
    playerLanternRadius = 3, -- 玩家手里的提灯半径
    lights = {}            -- 存放地图上的所有点光源
}

-- 1. 添加光源的接口
function LightingSystem:addLight(x, y, r, g, b, radius)
    table.insert(self.lights, {x = x, y = y, r = r, g = g, b = b, radius = radius})
end

-- 2. 清空光源 (切换场景时使用)
function LightingSystem:clearLights()
    self.lights = {}
end

-- 3. 一键开关光照
function LightingSystem:toggle()
    self.enabled = not self.enabled
    print("Lighting System Enabled: " .. tostring(self.enabled))
end

-- 4. 内部工具函数：阴影检测 (从场景中抽离)
local function checkLineOfSight(x1, y1, x2, y2, map)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    
    local steps = math.floor(dist * 5) 
    if steps <= 1 then return true end
    
    local stepX = dx / steps
    local stepY = dy / steps
    local cx, cy = x1, y1
    
    for i = 1, steps - 1 do
        cx = cx + stepX
        cy = cy + stepY
        local mapX = math.floor(cx) + 1
        local mapY = math.floor(cy) + 1
        if map[mapY] and map[mapY][mapX] and map[mapY][mapX] > 0 then
            return false -- 被墙挡住
        end
    end
    return true -- 视线畅通
end

-- =========================================================
-- 提供给渲染器的核心 API
-- =========================================================

-- 获取墙壁的受光颜色
function LightingSystem:getWallColor(hitX, hitY, normX, normY, distance, map)
    -- 如果关闭了光照系统，直接返回纯白 (贴图原色)
    if not self.enabled then return 1, 1, 1 end

    local finalR, finalG, finalB = self.ambientLight, self.ambientLight, self.ambientLight
    
    -- 玩家提灯
    if distance < self.playerLanternRadius then
        local falloff = 1 - (distance / self.playerLanternRadius)
        finalR = finalR + 0.8 * falloff
        finalG = finalG + 0.8 * falloff
        finalB = finalB + 0.8 * falloff
    end

    -- 遍历光源
    for _, light in ipairs(self.lights) do
        local lx = light.x - hitX
        local ly = light.y - hitY
        local distToLight = math.sqrt(lx*lx + ly*ly)
        
        if distToLight < light.radius then
            local lDirX = lx / distToLight
            local lDirY = ly / distToLight
            local dotProduct = normX * lDirX + normY * lDirY
            
            if dotProduct > 0 then
                -- 阴影偏移 (解决自阴影)
                local bias = 0.05
                local shadowStartX = hitX + normX * bias
                local shadowStartY = hitY + normY * bias
                
                if checkLineOfSight(shadowStartX, shadowStartY, light.x, light.y, map) then
                    local attenuation = math.max(0, 1.0 - (distToLight / light.radius))
                    local falloff = attenuation * attenuation 
                    local intensity = dotProduct * falloff
                    
                    finalR = finalR + light.r * intensity
                    finalG = finalG + light.g * intensity
                    finalB = finalB + light.b * intensity
                end
            end
        end
    end
    
    return math.min(1, finalR), math.min(1, finalG), math.min(1, finalB)
end

-- 获取地板的受光颜色 (简化版，无阴影检测)
function LightingSystem:getFloorColor(floorX, floorY, distance)
    if not self.enabled then return 1, 1, 1 end

    local currentR, currentG, currentB = self.ambientLight, self.ambientLight, self.ambientLight
    
    if distance < self.playerLanternRadius then
         local falloff = 1 - (distance / self.playerLanternRadius)
         local intensity = falloff * falloff
         currentR = currentR + 0.8 * intensity
         currentG = currentG + 0.8 * intensity
         currentB = currentB + 0.8 * intensity
    end

    for _, light in ipairs(self.lights) do
        local dx = floorX - light.x
        local dy = floorY - light.y
        local distSq = dx * dx + dy * dy
        local radiusSq = light.radius * light.radius
        
        if distSq < radiusSq then
            local dist = math.sqrt(distSq)
            local falloff = 1.0 - (dist / light.radius)
            falloff = falloff * falloff 
            
            currentR = currentR + light.r * falloff
            currentG = currentG + light.g * falloff
            currentB = currentB + light.b * falloff
        end
    end

    return math.min(1, currentR), math.min(1, currentG), math.min(1, currentB)
end

-- 获取精灵的受光颜色
function LightingSystem:getSpriteColor(distance)
     if not self.enabled then return 1, 1, 1 end
     
     local spriteLight = self.ambientLight
     if distance < self.playerLanternRadius then
         spriteLight = spriteLight + 0.8 * (1 - distance / self.playerLanternRadius)
     end
     spriteLight = math.min(1, spriteLight)
     return spriteLight, spriteLight, spriteLight
end

return LightingSystem
