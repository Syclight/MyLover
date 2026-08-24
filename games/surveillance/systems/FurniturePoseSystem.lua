local FurniturePoseSystem = {}
FurniturePoseSystem.__index = FurniturePoseSystem

function FurniturePoseSystem.new(config)
    return setmetatable({
        chairSeatOffset = assert(config.chairSeatOffset),
        chairSmoothing = assert(config.chairSmoothing),
        seatedEyeHeight = assert(config.seatedEyeHeight),
        maxPitch = assert(config.maxPitch),
    }, FurniturePoseSystem)
end

local function rememberPose(world)
    world.preSit = {
        x = world.player.x, y = world.player.y,
        dir = world.player.dir, pitch = world.player.pitch,
        baseHeight = world.player.baseHeight,
    }
end

function FurniturePoseSystem:setupChair(world)
    world.chairSeated, world.playerSitting, world.preSit = false, false, nil
    world.chairHome, world.chairSeatTarget, world.chairTarget = nil, nil, nil
    if not world.chairPos then return end
    world.chairHome = { x = world.chairPos.x, y = world.chairPos.y }
    world.chairTarget = { x = world.chairPos.x, y = world.chairPos.y }
    if world.computerPos then
        world.chairSeatTarget = {
            x = world.computerPos.x,
            y = world.computerPos.y + self.chairSeatOffset / world.tileSizeMeters,
        }
    end
end

function FurniturePoseSystem:moveChairToComputer(world)
    if not world.chairPos or not world.chairSeatTarget then return end
    world.chairSeated = true
    world.chairTarget = { x = world.chairSeatTarget.x, y = world.chairSeatTarget.y }
end

function FurniturePoseSystem:returnChairHome(world)
    if not world.chairPos or world.playerSitting then return end
    world.chairSeated = false
    world.chairTarget = { x = world.chairHome.x, y = world.chairHome.y }
end

function FurniturePoseSystem:sitDown(world)
    if world.playerSitting or not world.chairSeated or not world.chairSeatTarget then return end
    world.playerSitting = true
    rememberPose(world)
    world.player.x, world.player.y = world.chairSeatTarget.x, world.chairSeatTarget.y
    world.player.dir, world.player.pitch = -math.pi * 0.5, -0.06
    world.player.baseHeight, world.player.height = self.seatedEyeHeight, self.seatedEyeHeight
end

function FurniturePoseSystem:standUp(world)
    if not world.playerSitting then return end
    world.playerSitting, world.postureKind = false, nil
    if not world.preSit then return end
    local pose = world.preSit
    world.player.x, world.player.y = pose.x, pose.y
    world.player.dir, world.player.pitch = pose.dir, pose.pitch
    world.player.baseHeight, world.player.height = pose.baseHeight, pose.baseHeight
    world.preSit = nil
end

function FurniturePoseSystem:useRest(world)
    local target = world.sceneState.apartment.restTarget
    if not target or world.playerSitting then return end
    world.playerSitting = true
    world.postureKind = target.props.pose or "sofa"
    rememberPose(world)
    local yaw = math.rad(tonumber(target.props.yaw) or 0)
    local offsetY = world.postureKind == "lie" and 0.42 or 0.04
    world.player.x = target.x - math.sin(yaw) * offsetY / world.tileSizeMeters
    world.player.y = target.y + math.cos(yaw) * offsetY / world.tileSizeMeters
    if world.postureKind == "lie" then
        world.player.dir, world.player.pitch, world.player.baseHeight = yaw - math.pi * 0.5, 0.30, 0.72
    else
        world.player.dir, world.player.pitch, world.player.baseHeight = yaw + math.pi * 0.5, -0.04, 1.02
    end
    world.player.height = world.player.baseHeight
end

function FurniturePoseSystem:updateChair(world, dt)
    if not world.chairPos or not world.chairTarget then return end
    local amount = 1.0 - math.exp(-self.chairSmoothing * dt)
    world.chairPos.x = world.chairPos.x + (world.chairTarget.x - world.chairPos.x) * amount
    world.chairPos.y = world.chairPos.y + (world.chairTarget.y - world.chairPos.y) * amount
    if world.chairInteractable then
        world.chairInteractable.x, world.chairInteractable.y = world.chairPos.x, world.chairPos.y
    end
end

return FurniturePoseSystem
