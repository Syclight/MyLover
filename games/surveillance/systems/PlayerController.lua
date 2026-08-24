local PlayerController = {}
PlayerController.__index = PlayerController

function PlayerController.new(config)
    return setmetatable({
        mouseSensitivity = assert(config.mouseSensitivity),
        maxPitch = assert(config.maxPitch),
        bobSpeed = config.bobSpeed or 8.0,
        bobAmount = config.bobAmount or 0.015,
    }, PlayerController)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

function PlayerController:update(world, dt)
    local player = world.player
    if world.playerSitting then
        player.height = player.baseHeight
        return
    end

    local forwardX, forwardY = math.cos(player.dir), math.sin(player.dir)
    local rightX, rightY = -forwardY, forwardX
    local moveX, moveY = 0, 0
    if love.keyboard.isDown("up") or love.keyboard.isScancodeDown("w") then
        moveX, moveY = moveX + forwardX * world.moveSpeed * dt, moveY + forwardY * world.moveSpeed * dt
    end
    if love.keyboard.isDown("down") or love.keyboard.isScancodeDown("s") then
        moveX, moveY = moveX - forwardX * world.moveSpeed * dt, moveY - forwardY * world.moveSpeed * dt
    end
    if love.keyboard.isDown("left") or love.keyboard.isScancodeDown("a") then
        moveX, moveY = moveX - rightX * world.strafeSpeed * dt, moveY - rightY * world.strafeSpeed * dt
    end
    if love.keyboard.isDown("right") or love.keyboard.isScancodeDown("d") then
        moveX, moveY = moveX + rightX * world.strafeSpeed * dt, moveY + rightY * world.strafeSpeed * dt
    end

    local nextX, nextY = player.x + moveX, player.y + moveY
    if world:_canOccupy(nextX, player.y) then player.x = nextX end
    if world:_canOccupy(player.x, nextY) then player.y = nextY end

    local moving = math.abs(moveX) > 0.0001 or math.abs(moveY) > 0.0001
    player.height = moving
        and player.baseHeight + math.sin(world.time * self.bobSpeed) * self.bobAmount
        or player.baseHeight
end

function PlayerController:mousemoved(world, dx, dy)
    if not world.mouseLookEnabled or not world.player then return end
    world.player.dir = world.player.dir + dx * self.mouseSensitivity
    world.player.pitch = clamp(world.player.pitch - dy * self.mouseSensitivity, -self.maxPitch, self.maxPitch)
end

return PlayerController
