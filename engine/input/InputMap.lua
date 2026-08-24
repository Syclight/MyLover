local InputMap = {}
InputMap.__index = InputMap

local function normalizeBinding(binding)
    if type(binding) == "string" then return { device = "key", key = binding } end
    assert(type(binding) == "table", "input binding must be a string or table")
    local copy = {}
    for key, value in pairs(binding) do copy[key] = value end
    copy.device = copy.device or copy.type or "key"
    return copy
end

-- 把一条绑定展开成 0~2 个索引键（key 绑定可同时按 key 和 scancode 命中）
local function indexKeysForBinding(binding)
    local keys = {}
    if binding.device == "key" then
        if binding.key then keys[#keys + 1] = "key:" .. tostring(binding.key) end
        if binding.scancode then keys[#keys + 1] = "scan:" .. tostring(binding.scancode) end
    elseif binding.device == "mouse" then
        keys[#keys + 1] = "mouse:" .. tostring(binding.button)
    elseif binding.device == "gamepad" then
        keys[#keys + 1] = "gamepad:" .. tostring(binding.button)
    end
    return keys
end

function InputMap.new(bindings)
    local self = setmetatable({
        bindings = {},
        index = {},  -- 索引键 -> { action = true } 预建查找表，事件到来时 O(1) 命中
        down = {},
        pressed = {},
        released = {},
    }, InputMap)
    for action, actionBindings in pairs(bindings or {}) do
        self:bind(action, actionBindings)
    end
    return self
end

-- bind 是低频操作（初始化 / 改键），在这里重建索引，
-- 让高频的 actionsForEvent 免于全量遍历所有绑定。
function InputMap:_rebuildIndex()
    self.index = {}
    for action, bindings in pairs(self.bindings) do
        for _, binding in ipairs(bindings) do
            for _, indexKey in ipairs(indexKeysForBinding(binding)) do
                local set = self.index[indexKey]
                if not set then
                    set = {}
                    self.index[indexKey] = set
                end
                set[action] = true
            end
        end
    end
end

function InputMap:bind(action, bindings)
    assert(type(action) == "string" and action ~= "", "input action name is required")
    if bindings[1] == nil and (bindings.device or bindings.type or type(bindings) == "string") then
        bindings = { bindings }
    end
    self.bindings[action] = {}
    for _, binding in ipairs(bindings) do
        self.bindings[action][#self.bindings[action] + 1] = normalizeBinding(binding)
    end
    self:_rebuildIndex()
    return self
end

function InputMap:actionsForEvent(event)
    local actions, seen = {}, {}
    local function collect(indexKey)
        local set = indexKey and self.index[indexKey]
        if not set then return end
        for action in pairs(set) do
            if not seen[action] then
                seen[action] = true
                actions[#actions + 1] = action
            end
        end
    end
    if event.device == "key" then
        if event.key then collect("key:" .. tostring(event.key)) end
        if event.scancode then collect("scan:" .. tostring(event.scancode)) end
    elseif event.device == "mouse" then
        collect("mouse:" .. tostring(event.button))
    elseif event.device == "gamepad" then
        collect("gamepad:" .. tostring(event.button))
    end
    table.sort(actions) -- 保持确定性顺序（命中通常只有 0~2 个，开销可忽略）
    return actions
end

function InputMap:_apply(event, isDown)
    local actions = self:actionsForEvent(event)
    for _, action in ipairs(actions) do
        if isDown then
            if not self.down[action] then self.pressed[action] = true end
            self.down[action] = true
        else
            if self.down[action] then self.released[action] = true end
            self.down[action] = nil
        end
    end
    return #actions > 0, actions
end

function InputMap:keypressed(key, scancode, isrepeat)
    if isrepeat then return false, {} end
    return self:_apply({ device = "key", key = key, scancode = scancode }, true)
end

function InputMap:keyreleased(key, scancode)
    return self:_apply({ device = "key", key = key, scancode = scancode }, false)
end

function InputMap:mousepressed(_x, _y, button)
    return self:_apply({ device = "mouse", button = button }, true)
end

function InputMap:mousereleased(_x, _y, button)
    return self:_apply({ device = "mouse", button = button }, false)
end

function InputMap:gamepadpressed(_joystick, button)
    return self:_apply({ device = "gamepad", button = button }, true)
end

function InputMap:gamepadreleased(_joystick, button)
    return self:_apply({ device = "gamepad", button = button }, false)
end

function InputMap:isDown(action)
    return self.down[action] == true
end

function InputMap:wasPressed(action)
    return self.pressed[action] == true
end

function InputMap:wasReleased(action)
    return self.released[action] == true
end

function InputMap:consumePressed(action)
    local value = self.pressed[action] == true
    self.pressed[action] = nil
    return value
end

function InputMap:resetFrame()
    self.pressed = {}
    self.released = {}
end

function InputMap:reset()
    self.down = {}
    self:resetFrame()
end

return InputMap
