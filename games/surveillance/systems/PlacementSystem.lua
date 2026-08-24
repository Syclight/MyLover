local PlacementSystem = {}
PlacementSystem.__index = PlacementSystem

function PlacementSystem.new(config)
    return setmetatable({ reach = assert(config.reach) }, PlacementSystem)
end

function PlacementSystem:compute(world)
    local player = world.player
    local cosPitch = math.cos(player.pitch or 0.0)
    local rdX = math.cos(player.dir) * cosPitch
    local rdY = math.sin(player.dir) * cosPitch
    local rdZ = math.sin(player.pitch or 0.0)
    local roX = player.x * world.tileSizeMeters
    local roY = player.y * world.tileSizeMeters
    local roZ = player.height
    local tileSize = world.tileSizeMeters
    local best

    local function consider(z, centerX, centerY, halfWidth, halfDepth, floor)
        if math.abs(rdZ) < 1.0e-5 then return end
        local distance = (z - roZ) / rdZ
        if distance <= 0.02 or distance > self.reach then return end
        local hitX = (roX + rdX * distance) / tileSize
        local hitY = (roY + rdY * distance) / tileSize
        if floor then
            if world:_isBlockedAt(hitX, hitY) then return end
        elseif math.abs(hitX - centerX) > halfWidth or math.abs(hitY - centerY) > halfDepth then
            return
        end
        if not best or distance < best.distance then
            best = { x = hitX, y = hitY, z = z, distance = distance }
        end
    end

    for _, surface in ipairs(world.placeSurfaces or {}) do
        consider(surface.z, surface.x, surface.y, surface.w * 0.5, surface.d * 0.5, false)
    end
    consider(0.0, 0, 0, 0, 0, true)
    return best and { x = best.x, y = best.y, z = best.z } or nil
end

return PlacementSystem
