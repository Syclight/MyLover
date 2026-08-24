local EventBus = require("engine.utils.EventBus")
local Object = require("engine.utils.Object")

local BaseLayer = Object:extend()

function BaseLayer:new(o)
    o = Object.new(self, o)
    o.__subscriptions = o.__subscriptions or {}
    return o
end

-- 作用域化的 EventBus 订阅：用 self:on() 订阅，layer 退出时由
-- BaseScene:exitLayers() 自动调用 cancelSubscriptions() 清理。
function BaseLayer:on(event, fn)
    local unsubscribe = EventBus.on(event, fn)
    self.__subscriptions = self.__subscriptions or {}
    table.insert(self.__subscriptions, unsubscribe)
    return unsubscribe
end

function BaseLayer:cancelSubscriptions()
    local subs = self.__subscriptions or {}
    for i = #subs, 1, -1 do
        subs[i]()
        subs[i] = nil
    end
end

function BaseLayer:enter() end
function BaseLayer:exit() end
function BaseLayer:update(dt) end
function BaseLayer:draw(alpha) end
function BaseLayer:keypressed(key, scancode, isrepeat) end
function BaseLayer:mousemoved(x, y, dx, dy) end
function BaseLayer:mousepressed(x, y, button) end
function BaseLayer:textinput(text) end
function BaseLayer:resize(width, height) end
function BaseLayer:pause() end
function BaseLayer:resume() end

return BaseLayer
