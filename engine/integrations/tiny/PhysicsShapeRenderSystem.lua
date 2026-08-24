local tiny = require("libs.tiny")

-- 面向简单原型的 Box2D shape 渲染器；正式游戏可替换为自己的表现层。
return function(camera, config)
    config = config or {}
    local bodyKey, shapeKey = config.bodyKey or "body", config.shapeKey or "shape"
    local colorKey = config.colorKey or "color"
    local system = tiny.processingSystem()
    system.filter = tiny.requireAll(bodyKey, shapeKey, colorKey)
    system.camera = camera
    system.isRenderSystem = true

    function system:preProcess()
        if self.camera then self.camera:attach() end
    end

    function system:postProcess()
        if self.camera then self.camera:detach() end
    end

    function system:process(entity)
        local body, shape = entity[bodyKey], entity[shapeKey]
        if body:isDestroyed() then return end
        love.graphics.setColor(entity[colorKey] or { 1, 1, 1 })
        local shapeType = shape:getType()
        if shapeType == "polygon" then
            love.graphics.polygon("fill", body:getWorldPoints(shape:getPoints()))
        elseif shapeType == "circle" then
            local x, y = body:getPosition()
            love.graphics.circle("fill", x, y, shape:getRadius())
        end
    end

    return system
end
