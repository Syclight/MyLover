local tiny = require("libs.tiny")

return function(config)
    config = config or {}
    local speed = config.speed or 600
    local paddleWidth = config.paddleWidth or 100
    local system = tiny.processingSystem()
    system.filter = tiny.requireAll("isPlayer", "body")

    function system:process(entity)
        local velocity = 0
        if love.keyboard.isDown("left") then velocity = -speed
        elseif love.keyboard.isDown("right") then velocity = speed end
        entity.body:setLinearVelocity(velocity, 0)

        local x, y = entity.body:getPosition()
        local halfWidth = paddleWidth * 0.5
        local screenWidth = love.graphics.getWidth()
        if x < halfWidth then entity.body:setPosition(halfWidth, y)
        elseif x > screenWidth - halfWidth then entity.body:setPosition(screenWidth - halfWidth, y) end
    end

    return system
end
