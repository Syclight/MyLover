local Button = require("engine.ui.components.Button")
local Slot = require("samples.breakout.ui.components.InventorySlot")

local InventoryView = {}

-- 模拟一些背包数据
local items = {"Sword", "Potion", "Map", "Key"}

function InventoryView.draw(layer)
    local w, h = love.graphics.getDimensions()
    
    -- 1. 画背景面板
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
    love.graphics.rectangle("fill", 100, 100, w-200, h-200, 10)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("INVENTORY", 120, 120)
    
    -- 2. 画格子 (4x4 矩阵)
    local startX, startY = 150, 180
    local size = 60
    local padding = 10
    
    for i = 0, 15 do
        local row = math.floor(i / 4)
        local col = i % 4
        local x = startX + col * (size + padding)
        local y = startY + row * (size + padding)
        local id = "slot_" .. i
        
        -- 获取当前格子的物品
        local item = items[i+1] 
        
        if Slot.new(id, x, y, size, item) then
            print("Clicked item: " .. (item or "Empty"))
        end
    end
    
    -- 3. 关闭按钮
    if Button.new("close_inv", "CLOSE", w-250, h-160, 100, 40, "danger") then
        layer.state = "MENU"
    end
end

return InventoryView
