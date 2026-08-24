local Inventory = {}

local function notify(state, text, options)
    if state.messages then
        local HUDMessages = require("games.surveillance.gameplay.HUDMessages")
        HUDMessages.toast(state.messages, text, options)
    else
        state.notice = text
        state.noticeTime = 2.2
    end
end

function Inventory.new(capacity, messages)
    return {
        capacity = capacity or 5,
        slots = {},
        selectedSlot = nil,
        notice = nil,
        noticeTime = 0,
        messages = messages,
    }
end

function Inventory.find(state, itemId)
    for index = 1, state.capacity do
        local item = state.slots[index]
        if item and item.id == itemId then return index, item end
    end
    return nil
end

function Inventory.has(state, itemId)
    return Inventory.find(state, itemId) ~= nil
end

function Inventory.add(state, item)
    if Inventory.has(state, item.id) then return true end
    for index = 1, state.capacity do
        if state.slots[index] == nil then
            state.slots[index] = item
            notify(state, item.name or item.id, {
                title = "获得物品",
                body = item.description,
                duration = 3.0,
            })
            return true, index
        end
    end
    notify(state, "物品栏已满", { title = "无法拾取", duration = 2.2 })
    return false
end

function Inventory.remove(state, itemId)
    local index, item = Inventory.find(state, itemId)
    if not index then return nil end
    state.slots[index] = nil
    if state.selectedSlot == index then state.selectedSlot = nil end
    return item
end

function Inventory.select(state, index)
    if index == nil or state.slots[index] == nil then
        state.selectedSlot = nil
        return nil
    end
    state.selectedSlot = index
    return state.slots[index]
end

function Inventory.deselect(state)
    state.selectedSlot = nil
end

function Inventory.cycle(state, direction)
    direction = direction and direction < 0 and -1 or 1
    local start = state.selectedSlot or (direction > 0 and 0 or state.capacity + 1)
    local index = ((start - 1 + direction) % state.capacity) + 1
    state.selectedSlot = index
    return state.slots[index], index
end

function Inventory.selected(state)
    return state.selectedSlot and state.slots[state.selectedSlot] or nil
end

function Inventory.isSelected(state, itemId)
    local item = Inventory.selected(state)
    return item ~= nil and item.id == itemId
end

function Inventory.update(state, dt)
    if state.noticeTime > 0 then
        state.noticeTime = math.max(0, state.noticeTime - dt)
        if state.noticeTime == 0 then state.notice = nil end
    end
end

return Inventory
