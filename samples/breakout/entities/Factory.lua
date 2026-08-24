local Factory = {}

function Factory.createWall(world, x, y, w, h)
    local body = love.physics.newBody(world, x + w/2, y + h/2, "static")
    local shape = love.physics.newRectangleShape(w, h)
    local fixture = love.physics.newFixture(body, shape)
    fixture:setUserData({tag = "Wall"})
    
    return {
        body = body,
        shape = shape,
        fixture = fixture,
        color = {0.5, 0.5, 0.5},
        name = "Wall"
    }
end

function Factory.createBrick(world, x, y, w, h, color)
    local body = love.physics.newBody(world, x + w/2, y + h/2, "static")
    local shape = love.physics.newRectangleShape(w, h)
    local fixture = love.physics.newFixture(body, shape)
    
    local entity = {
        body = body,
        shape = shape,
        fixture = fixture,
        color = color,
        isBrick = true
    }
    fixture:setUserData(entity) -- 关键绑定
    return entity
end

function Factory.createPaddle(world, x, y, w, h)
    local body = love.physics.newBody(world, x, y, "kinematic")
    local shape = love.physics.newRectangleShape(w, h)
    local fixture = love.physics.newFixture(body, shape)
    fixture:setUserData({tag = "Paddle"})
    
    return {
        body = body,
        shape = shape,
        fixture = fixture,
        color = {0.2, 0.6, 1},
        isPlayer = true
    }
end

function Factory.createBall(world, x, y, r)
    local body = love.physics.newBody(world, x, y, "dynamic")
    local shape = love.physics.newCircleShape(r)
    local fixture = love.physics.newFixture(body, shape, 1)
    
    fixture:setRestitution(1)
    fixture:setFriction(0)
    fixture:setUserData({tag = "Ball"})
    body:setLinearVelocity(300, -400)
    
    return {
        body = body,
        shape = shape,
        fixture = fixture,
        color = {1, 0.3, 0.3},
        isBall = true
    }
end

return Factory
