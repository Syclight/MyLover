local PostProcess = {}
PostProcess.__index = PostProcess

function PostProcess.new(canvas, shader)
    local instance = setmetatable({}, PostProcess)
    assert(canvas and shader, "PostProcess requires manifest canvas and shader")
    instance.canvas = canvas
    instance.shader = shader
    
    -- 3. 效果参数
    instance.distortion = 0
    instance.redStrength = 0
    instance.time = 0
    
    return instance
end


function PostProcess:setCanvas(canvas)
    self.canvas = canvas
end

-- 在每一帧开始时调用：把绘图目标指向画布
function PostProcess:start()
    -- 清空上一帧的画布
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear() 
end

-- 在每一帧结束时调用：把画布画到屏幕上，并应用 Shader
function PostProcess:stop()
    love.graphics.setCanvas() -- 切回主屏幕
    
    love.graphics.setColor(1, 1, 1) -- 重置颜色
    
    -- 应用 Shader
    love.graphics.setShader(self.shader)
    
    -- 传递参数给 GLSL
    if self.shader:hasUniform("time") then
        self.shader:send("time", self.time)
    end
    if self.shader:hasUniform("distortion") then
        self.shader:send("distortion", self.distortion)
    end
    if self.shader:hasUniform("red_strength") then
        self.shader:send("red_strength", self.redStrength)
    end
    
    -- 画出画布
    -- 此时，所有的游戏内容都在这张 canvas 图片上
    love.graphics.draw(self.canvas, 0, 0)
    
    -- 关闭 Shader (以免影响后续 UI 绘制)
    love.graphics.setShader()
end

function PostProcess:update(dt)
    self.time = self.time + dt
    
    -- 这里可以加一些简单的衰减逻辑 (比如受击后红色慢慢褪去)
    if self.redStrength > 0 then
        self.redStrength = math.max(0, self.redStrength - dt * 2) -- 0.5秒褪色
    end
    
    if self.distortion > 0 then
        self.distortion = math.max(0, self.distortion - dt * 1) -- 1秒恢复
    end
end

-- 触发受击效果 (外部调用)
function PostProcess:triggerDamage()
    self.redStrength = 1.0   -- 瞬间变红
    self.distortion = 5.0    -- 瞬间扭曲
end

return PostProcess
