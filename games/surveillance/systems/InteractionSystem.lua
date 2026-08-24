local Inventory = require("games.surveillance.gameplay.Inventory")

local InteractionSystem = {}
InteractionSystem.__index = InteractionSystem

function InteractionSystem.new()
    return setmetatable({}, InteractionSystem)
end

-- 交互优先级代表明确的选择层级，而不是微小的距离偏移。
-- 这样放在床/沙发表面的薄物品可以优先于家具的大型交互盒。
function InteractionSystem.isBetterHit(candidate, incumbent)
    if not incumbent then return true end
    local candidatePriority = candidate.target.priority or 0
    local incumbentPriority = incumbent.target.priority or 0
    if candidatePriority ~= incumbentPriority then
        return candidatePriority > incumbentPriority
    end
    return candidate.distance < incumbent.distance
end

function InteractionSystem:update(world, hovered)
    local apt = world.sceneState.apartment
    apt.canUseComputer = false
    apt.canMoveChair = false
    apt.canSitChair = false
    apt.canPickRemote = false
    apt.isSitting = world.playerSitting
    apt.canPickItem = false
    apt.canRest = false
    apt.postureKind = world.postureKind
    apt.pickupTarget = nil
    apt.restTarget = nil
    apt.bookShelfTarget = nil
    apt.canReturnBook = false
    apt.canPlaceBook = false
    apt.hoverComputer = nil
    apt.hoverDesc = nil
    apt.hoverDetail = nil

    local inventory = world.sceneState.inventory
    local remoteSelected = Inventory.isSelected(inventory, "ac_remote")
    local heldItem = Inventory.selected(inventory)
    local bookSelected = heldItem and heldItem.icon == "book"

    if not remoteSelected then
        local kind = hovered and hovered.interaction or nil
        if kind == "terminal" then
            apt.canUseComputer, apt.hoverComputer, apt.hoverDesc = true, hovered, hovered.desc
            apt.hoverDetail = hovered.detail ~= "" and hovered.detail or "终端屏幕泛着冷光。"
        elseif kind == "pickup" and not world.playerSitting then
            apt.canPickRemote, apt.canPickItem = true, true
            apt.pickupTarget, apt.hoverDesc = hovered, hovered.desc
            apt.hoverDetail = hovered.detail ~= "" and hovered.detail or "它被放在手边。"
        elseif kind == "pickup_book" and not world.playerSitting then
            apt.canPickItem, apt.pickupTarget, apt.hoverDesc = true, hovered, hovered.desc
            apt.hoverDetail = hovered.detail ~= "" and hovered.detail or "这本书似乎被翻过很多次。"
        elseif kind == "rest" and not world.playerSitting then
            apt.canRest, apt.restTarget, apt.hoverDesc = true, hovered, hovered.desc
            apt.hoverDetail = hovered.detail ~= "" and hovered.detail
                or (hovered.props.pose == "lie" and "床铺看起来有些疲惫。" or "沙发安静地陷在角落里。")
        elseif kind == "sit" and not world.playerSitting then
            if world.chairSeated then apt.canSitChair = true else apt.canMoveChair = true end
            apt.hoverDesc = hovered.desc or "椅子"
            apt.hoverDetail = world.chairSeated and "坐下后可以更专注地使用终端。" or "椅子离终端还有一点距离。"
        end
    end

    apt.canPlaceRemote = false
    if remoteSelected then
        world.remotePlacement = world:_computePlacement()
        apt.canPlaceRemote = world.remotePlacement ~= nil
    else
        world.remotePlacement = nil
    end

    world.bookPlacement = nil
    if bookSelected then
        if hovered and hovered.shelfKey then
            apt.bookShelfTarget, apt.canReturnBook = hovered, true
        else
            world.bookPlacement = world:_computePlacement()
            apt.canPlaceBook = world.bookPlacement ~= nil
        end
    end
end

return InteractionSystem
