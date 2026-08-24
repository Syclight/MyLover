local tiny = require("libs.tiny")

-- Tiny ECS 对 LÖVE Box2D World 的可选适配器。
-- 世界由游戏创建和销毁；本系统只在固定更新中推进它。
return function(physicsWorld)
    assert(type(physicsWorld) == "userdata" or type(physicsWorld) == "table",
        "PhysicsStepSystem requires a LÖVE Physics World-like object")
    assert(type(physicsWorld.update) == "function", "physics world must provide update(dt)")

    local system = tiny.system()
    system.physicsWorld = physicsWorld
    system.isPhysicsStepSystem = true
    system.enabled = true

    function system:setPhysicsWorld(nextWorld)
        assert(nextWorld and type(nextWorld.update) == "function", "physics world must provide update(dt)")
        self.physicsWorld = nextWorld
    end

    function system:update(dt)
        if self.enabled and self.physicsWorld then self.physicsWorld:update(dt) end
    end

    return system
end
