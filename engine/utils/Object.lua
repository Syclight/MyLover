-- 极简类继承基础。BaseScene / BaseLayer 共用，避免各自复制 new/extend。
--
-- 用法：
--   local Object = require("engine.utils.Object")
--   local Animal = Object:extend()
--   local Dog = Animal:extend()
--   local dog = Dog:new({ name = "wang" })
--
-- 语义与原 BaseScene:extend 完全一致：
--   * extend(): 派生子类，子类实例查找链为 instance -> class -> 父类 -> ... -> Object
--   * new(o):   以 o（可选）为实例表挂上类元表
local Object = {}
Object.__index = Object

function Object:new(o)
    o = o or {}
    setmetatable(o, self)
    return o
end

function Object:extend()
    local cls = {}
    cls.__index = cls
    setmetatable(cls, self)
    return cls
end

return Object
