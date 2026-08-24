local Camera = {}
Camera.__index = Camera

function Camera.new(x, y, zoom)
    local instance = setmetatable({}, Camera)
    instance.x = x or 0
    instance.y = y or 0
    instance.scaleX = zoom or 1
    instance.scaleY = zoom or 1
    instance.rotation = 0
    
    -- 震动相关的变量
    instance.shakeDuration = 0
    instance.shakeMagnitude = 0
    instance.shakeOffsetX = 0
    instance.shakeOffsetY = 0
    
    return instance
end

-- 设置跟随目标
function Camera:lookAt(x, y)
    local w, h = love.graphics.getDimensions()
    -- 让 (x,y) 居中
    self.x = x - w / (2 * self.scaleX)
    self.y = y - h / (2 * self.scaleY)
end

-- 触发震动 (关键功能！)
function Camera:shake(magnitude, duration)
    self.shakeMagnitude = magnitude
    self.shakeDuration = duration
end

function Camera:update(dt)
    -- 处理震动计时
    if self.shakeDuration > 0 then
        self.shakeDuration = self.shakeDuration - dt
        if self.shakeDuration <= 0 then
            self.shakeOffsetX = 0
            self.shakeOffsetY = 0
        else
            -- 随机生成偏移量
            self.shakeOffsetX = love.math.random(-1, 1) * self.shakeMagnitude
            self.shakeOffsetY = love.math.random(-1, 1) * self.shakeMagnitude
        end
    end
end

-- 应用变换 (在绘制前调用)
function Camera:attach()
    love.graphics.push()
    -- 1. 移动到屏幕中心
    local w, h = love.graphics.getDimensions()
    love.graphics.translate(w/2, h/2)
    -- 2. 缩放
    love.graphics.scale(self.scaleX, self.scaleY)
    -- 3. 旋转
    love.graphics.rotate(self.rotation)
    -- 4. 移回原点 + 摄像机位移 + 震动偏移
    love.graphics.translate(-w/2 - self.x + self.shakeOffsetX, -h/2 - self.y + self.shakeOffsetY)
end

-- 解除变换 (在绘制后调用)
function Camera:detach()
    love.graphics.pop()
end

-- 【优化】判断物体是否在视野内 (剔除)
function Camera:isVisible(x, y, w, h)
    -- 简单的 AABB 碰撞检测，判断物体矩形是否和屏幕矩形相交
    -- 这里暂时略写，如果地图很大才需要这个
    return true 
end

return Camera
