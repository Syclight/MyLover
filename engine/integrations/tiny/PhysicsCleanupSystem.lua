local tiny = require("libs.tiny")

-- 组件约定可配置，默认处理 { toDestroy=true, body=<Box2D Body> }。
return function(config)
    config = config or {}
    local destroyFlag = config.destroyFlag or "toDestroy"
    local bodyKey = config.bodyKey or "body"
    local system = tiny.processingSystem()
    system.filter = tiny.requireAll(destroyFlag, bodyKey)

    function system:process(entity)
        local body = entity[bodyKey]
        if body and not body:isDestroyed() then body:destroy() end
        self.world:removeEntity(entity)
    end

    return system
end
