local Inventory = require("games.surveillance.gameplay.Inventory")
local PlayerMonologue = require("games.surveillance.gameplay.PlayerMonologue")
local Books = require("games.surveillance.data.books")

local ItemWorldSystem = {}
ItemWorldSystem.__index = ItemWorldSystem

function ItemWorldSystem.new(config)
    return setmetatable({
        maxPlacedBooks = assert(config.maxPlacedBooks),
        placementReach = assert(config.placementReach),
    }, ItemWorldSystem)
end

local function removeInteractable(world, target)
    for index = #world.interactables, 1, -1 do
        if world.interactables[index] == target then
            table.remove(world.interactables, index)
            return
        end
    end
end

local function slotIsEmpty(mask, slotIndex)
    local bit = 2 ^ (slotIndex - 1)
    return math.floor(mask / bit) % 2 == 0
end

local function setPackedBookStyle(packed, slotIndex, bookIndex)
    local weight = 8 ^ (slotIndex - 1)
    local current = math.floor(packed / weight) % 8
    return packed + ((bookIndex or slotIndex) - current) * weight
end

function ItemWorldSystem:pickUpHovered(world)
    local target = world.sceneState.apartment.pickupTarget
    if not target then return end
    if target == world.remoteInteractable then return self:pickUpRemote(world) end
    if target.interaction ~= "pickup_book" then return end

    local added, slot = Inventory.add(world.sceneState.inventory, {
        id = target.itemId, name = target.desc, icon = "book",
        bookIndex = target.bookIndex,
        shelfKey = target.shelfKey,
        originalSlotIndex = target.slotIndex,
        description = "从公寓书架上取下的一本书。",
    })
    if not added then return end
    Inventory.select(world.sceneState.inventory, slot)
    if target.shelfKey then
        local bit = 2 ^ ((target.slotIndex or target.bookIndex) - 1)
        world.bookshelfMasks[target.shelfKey] = world.bookshelfMasks[target.shelfKey] - bit
    elseif target.placedEntry then
        for index = #world.placedBooks, 1, -1 do
            if world.placedBooks[index] == target.placedEntry then
                table.remove(world.placedBooks, index)
                break
            end
        end
    end
    removeInteractable(world, target)
    world.sceneState.apartment.pickupTarget = nil
    PlayerMonologue.say(world.sceneState.monologue, Books.thought(target.bookIndex), {
        key = "pickup_book:" .. tostring(target.itemId),
    })
end

function ItemWorldSystem:placeBook(world)
    local inventory = world.sceneState.inventory
    local item = Inventory.selected(inventory)
    if not item or item.icon ~= "book" then return end
    local shelf = world.sceneState.apartment.bookShelfTarget
    if shelf then
        local shelfKey = shelf.shelfKey
        local preferred = item.shelfKey == shelfKey and item.originalSlotIndex or nil
        local order = {}
        if preferred and slotIsEmpty(world.bookshelfMasks[shelfKey], preferred) then
            order[#order + 1] = preferred
        end
        for slotIndex = 1, 6 do
            if slotIndex ~= preferred then order[#order + 1] = slotIndex end
        end
        for _, slotIndex in ipairs(order) do
            local bit = 2 ^ (slotIndex - 1)
            if slotIsEmpty(world.bookshelfMasks[shelfKey], slotIndex) then
                local target = world.bookSlots[shelfKey][slotIndex]
                target.desc, target.itemId, target.bookIndex = item.name, item.id, item.bookIndex
                world.bookshelfMasks[shelfKey] = world.bookshelfMasks[shelfKey] + bit
                world.bookshelfBookStyles[shelfKey] = setPackedBookStyle(
                    world.bookshelfBookStyles[shelfKey], slotIndex, item.bookIndex)
                world.interactables[#world.interactables + 1] = target
                Inventory.remove(inventory, item.id)
                return
            end
        end
        inventory.notice, inventory.noticeTime = "这个书架已经放满了", 2.2
        return
    end

    local spot = world.bookPlacement
    if not spot or #world.placedBooks >= self.maxPlacedBooks then return end
    local entry = { item = item, x = spot.x, y = spot.y, z = spot.z }
    local target = {
        id = "placed_" .. item.id, type = "book", interaction = "pickup_book",
        x = spot.x, y = spot.y, desc = item.name, itemId = item.id,
        bookIndex = item.bookIndex, priority = 7,
        bottomHeight = spot.z, targetHeight = spot.z + 0.08,
        widthMeters = 0.18, depthMeters = 0.26, reachMeters = self.placementReach,
        placedEntry = entry,
    }
    entry.interactable = target
    world.placedBooks[#world.placedBooks + 1] = entry
    world.interactables[#world.interactables + 1] = target
    Inventory.remove(inventory, item.id)
    world.bookPlacement = nil
end

function ItemWorldSystem:pickUpRemote(world)
    local inventory = world.sceneState.inventory
    if Inventory.has(inventory, "ac_remote") or not world.remoteInteractable then return end
    local added, slot = Inventory.add(inventory, {
        id = "ac_remote", name = "空调遥控器", icon = "remote",
        description = "政府公寓配发的空调遥控器。",
    })
    if not added then return end
    Inventory.select(inventory, slot)
    removeInteractable(world, world.remoteInteractable)
end

function ItemWorldSystem:commitRemote(world, x, y, z)
    Inventory.remove(world.sceneState.inventory, "ac_remote")
    world.remoteRest = { x = x, y = y, z = z }
    world.remotePlacement = nil
    local target = world.remoteInteractable
    if not target then return end
    target.x, target.y = x, y
    target.bottomHeight, target.targetHeight = z, z + 0.12
    for _, interactable in ipairs(world.interactables) do
        if interactable == target then return end
    end
    world.interactables[#world.interactables + 1] = target
end

function ItemWorldSystem:placeRemote(world)
    if not Inventory.isSelected(world.sceneState.inventory, "ac_remote") then return end
    local placement = world.remotePlacement
    if placement then self:commitRemote(world, placement.x, placement.y, placement.z) end
end

return ItemWorldSystem
