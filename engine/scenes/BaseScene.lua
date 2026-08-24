local SceneManager = require("engine.managers.SceneManager")
local EventBus = require("engine.utils.EventBus")
local Object = require("engine.utils.Object")

local BaseScene = Object:extend()

function BaseScene:new(o)
    o = Object.new(self, o)
    o.__isSceneInstance = true
    o.layers = o.layers or {}
    o.__subscriptions = o.__subscriptions or {}
    return o
end

-- ==========================================
-- Layer 栈管理（可选使用）
-- ==========================================
-- 场景可以把内容拆成若干 layer（游戏层 / HUD 层 / GUI 层...），用下面的辅助方法
-- 统一管理：update/draw 自底向上，输入分发自顶向下且支持"消费即截断"。
-- 默认生命周期方法已接好转发，简单场景只需 addLayer 而无需覆写 update/draw/输入。

function BaseScene:addLayer(layer)
    self.layers = self.layers or {}
    table.insert(self.layers, layer)
    if layer.enter then layer:enter() end
    return layer
end

function BaseScene:updateLayers(dt)
    for _, layer in ipairs(self.layers or {}) do
        if layer.update then layer:update(dt) end
    end
end

function BaseScene:drawLayers(alpha)
    for _, layer in ipairs(self.layers or {}) do
        if layer.draw then layer:draw(alpha) end
    end
end

-- 自顶向下分发输入；layer 处理器返回 true 表示消费，停止向下传递。
function BaseScene:dispatchToLayers(method, ...)
    local layers = self.layers or {}
    for i = #layers, 1, -1 do
        local layer = layers[i]
        local handler = layer[method]
        if handler and handler(layer, ...) == true then
            return true
        end
    end
    return false
end

-- 逆序退出所有 layer 并清理它们的 EventBus 订阅。
function BaseScene:exitLayers()
    local layers = self.layers or {}
    for i = #layers, 1, -1 do
        local layer = layers[i]
        if layer.exit then layer:exit() end
        if layer.cancelSubscriptions then layer:cancelSubscriptions() end
    end
    self.layers = {}
end

-- ==========================================
-- 作用域化的 EventBus 订阅
-- ==========================================
-- 用 self:on() 代替 EventBus.on()：订阅与场景生命周期绑定，
-- SceneManager 在场景退出时会自动调用 cancelSubscriptions()，杜绝跨场景泄漏。
function BaseScene:on(event, fn)
    local unsubscribe = EventBus.on(event, fn)
    self.__subscriptions = self.__subscriptions or {}
    table.insert(self.__subscriptions, unsubscribe)
    return unsubscribe
end

function BaseScene:cancelSubscriptions()
    local subs = self.__subscriptions or {}
    for i = #subs, 1, -1 do
        subs[i]()
        subs[i] = nil
    end
end

-- ==========================================
-- 默认生命周期（自动转发给 layers；覆写即完全接管）
-- ==========================================
function BaseScene:enter(...) end
function BaseScene:exit() self:exitLayers() end
function BaseScene:update(dt) self:updateLayers(dt) end
-- alpha 是固定步长模拟的渲染插值因子 [0,1)，见 engine/utils/Timestep.lua
function BaseScene:draw(alpha) self:drawLayers(alpha) end
function BaseScene:pause() self:dispatchToLayers("pause") end
function BaseScene:resume() self:dispatchToLayers("resume") end

function BaseScene:mousemoved(...) return self:dispatchToLayers("mousemoved", ...) end
function BaseScene:mousepressed(...) return self:dispatchToLayers("mousepressed", ...) end
function BaseScene:mousereleased(...) return self:dispatchToLayers("mousereleased", ...) end
function BaseScene:keyreleased(...) return self:dispatchToLayers("keyreleased", ...) end
function BaseScene:textinput(...) return self:dispatchToLayers("textinput", ...) end
function BaseScene:textedited(...) return self:dispatchToLayers("textedited", ...) end
function BaseScene:wheelmoved(...) return self:dispatchToLayers("wheelmoved", ...) end
function BaseScene:resize(...) self:dispatchToLayers("resize", ...) end
function BaseScene:focus(...) end
function BaseScene:visible(...) end
function BaseScene:gamepadpressed(...) return self:dispatchToLayers("gamepadpressed", ...) end
function BaseScene:gamepadreleased(...) return self:dispatchToLayers("gamepadreleased", ...) end
function BaseScene:joystickpressed(...) return self:dispatchToLayers("joystickpressed", ...) end
function BaseScene:joystickreleased(...) return self:dispatchToLayers("joystickreleased", ...) end
function BaseScene:touchpressed(...) return self:dispatchToLayers("touchpressed", ...) end
function BaseScene:touchreleased(...) return self:dispatchToLayers("touchreleased", ...) end
function BaseScene:touchmoved(...) return self:dispatchToLayers("touchmoved", ...) end
function BaseScene:allowsGlobalShortcuts() return true end

-- 【通用逻辑】：所有继承这个父类的场景，都自带 Esc 呼出菜单功能！
-- 注意：本方法只负责 Esc，不分发给 layers（很多场景覆写后手动循环 layers，
-- 若这里也分发会造成双重派发）。覆写时请遵守消费约定：
--   if BaseScene.keypressed(self, key, ...) then return true end  -- Esc 被消费就此打住
--   return self:dispatchToLayers("keypressed", key, ...)          -- 再交给 layers
function BaseScene:keypressed(key, scancode, isrepeat)
    if key == "escape" then
        local GlobalPauseScene = require("engine.scenes.GlobalPauseScene")
        SceneManager.push(GlobalPauseScene:new())
        return true
    end
    return false
end

return BaseScene
