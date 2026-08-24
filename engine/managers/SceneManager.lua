local ResourceManager = require("engine.managers.ResourceManager")
local Timestep = require("engine.utils.Timestep")
local SceneManager = {}

-- 使用数组作为场景栈，取代之前的单一 currentScene
local stack = {}

local function currentEntry()
    return stack[#stack]
end

local function current()
    local entry = currentEntry()
    return entry and entry.scene or nil
end

local function activate(entry)
    ResourceManager:activateSceneScope(entry and entry.resources or nil)
end

local function makeEntry(scene)
    assert(type(scene) == "table" and scene.__isSceneInstance == true,
        "SceneManager requires SceneClass:new(), not the scene class table")
    return {
        scene = scene,
        resources = ResourceManager:createSceneScope(tostring(scene)),
    }
end

local function exitEntry(entry)
    if not entry then return end
    activate(entry)
    -- exit 用保护调用：即使场景（尤其是 enter 半途失败的场景）exit 抛错，
    -- 资源作用域和订阅仍然必须被释放，否则一处异常引发全局泄漏。
    if entry.scene.exit then
        local ok, err = xpcall(entry.scene.exit, debug.traceback, entry.scene)
        if not ok then print("SceneManager: scene exit failed:\n" .. tostring(err)) end
    end
    -- 自动清理场景通过 BaseScene:on() 注册的 EventBus 订阅（引擎兜底，
    -- 即使场景覆写 exit 时忘了调用也不会泄漏）。
    if type(entry.scene.cancelSubscriptions) == "function" then
        pcall(entry.scene.cancelSubscriptions, entry.scene)
    end
    -- 释放资源作用域前先通知 AudioManager：BGM 等引用可能指向即将被 release 的
    -- Source，若不解除引用，之后任何 setVolume/stop 都会 use-after-release 崩溃。
    -- （延迟 require 避免 SceneManager <-> AudioManager 的加载期循环依赖）
    local AudioManager = require("engine.managers.AudioManager")
    AudioManager:onResourcesReleasing(entry.resources and entry.resources.resources)
    ResourceManager:releaseSceneScope(entry.resources)
end

-- ==========================================
-- 1. 彻底切换场景 (洗牌重来)
-- 完全兼容你现在的代码，用于切换完全不同的大关卡
-- ==========================================
-- enter 的保护调用：失败返回 false + traceback，交由调用方决定善后。
-- 若不保护，switch 已清空场景栈，enter 抛错 = 永久黑屏且无任何提示。
local function safeEnter(scene, ...)
    if not scene.enter then return true end
    return xpcall(scene.enter, debug.traceback, scene, ...)
end

-- enter 失败时展示的兜底错误场景（纯表构造，避免 require BaseScene 造成循环依赖）
local function makeErrorScene(message)
    local scene = { __isSceneInstance = true }
    function scene:draw()
        local w = love.graphics.getWidth()
        love.graphics.setColor(0.9, 0.3, 0.3, 1)
        love.graphics.printf("Scene enter failed:\n\n" .. tostring(message), 40, 40, w - 80)
        love.graphics.setColor(1, 1, 1, 1)
    end
    function scene:keypressed(key)
        if key == "escape" then love.event.quit() end
        return true
    end
    function scene:allowsGlobalShortcuts() return false end
    return scene
end

function SceneManager.switch(nextScene, ...)
    -- 1. 退出并清理栈内所有场景
    while #stack > 0 do
        exitEntry(table.remove(stack))
    end

    -- 2. 将新场景压入栈顶
    local entry = makeEntry(nextScene)
    table.insert(stack, entry)
    activate(entry)

    -- 3. 执行新场景的 enter 逻辑（保护调用，失败进入错误场景而非黑屏）
    local ok, err = safeEnter(nextScene, ...)
    if not ok then
        print("SceneManager.switch: enter failed:\n" .. tostring(err))
        exitEntry(table.remove(stack))
        local errorEntry = makeEntry(makeErrorScene(err))
        table.insert(stack, errorEntry)
        activate(errorEntry)
    end
end

-- ==========================================
-- 2. 压入新场景 (叠加菜单)
-- 适用于：呼出暂停菜单、打开背包、弹出对话框
-- ==========================================
function SceneManager.push(nextScene, ...)
    local curr = current()

    -- 如果底层场景有 pause 方法，则暂停它（停止它的音效或计时器）
    if curr and curr.pause then
        curr:pause()
    end

    local entry = makeEntry(nextScene)
    table.insert(stack, entry)
    activate(entry)

    -- 保护调用：push 失败就撤掉坏场景、唤醒底下的场景，游戏继续跑
    local ok, err = safeEnter(nextScene, ...)
    if not ok then
        print("SceneManager.push: enter failed, reverting:\n" .. tostring(err))
        exitEntry(table.remove(stack))
        local prevEntry = currentEntry()
        activate(prevEntry)
        local prev = prevEntry and prevEntry.scene or nil
        if prev and prev.resume then prev:resume() end
    end
end

-- ==========================================
-- 3. 弹出顶层场景 (关闭菜单)
-- 适用于：关闭暂停菜单，回到游戏
-- ==========================================
function SceneManager.pop()
    if #stack == 0 then return end

    -- 移除并退出最顶层的场景（比如关掉菜单）
    exitEntry(table.remove(stack))

    -- 唤醒露出来的下层场景
    local prevEntry = currentEntry()
    activate(prevEntry)
    local prev = prevEntry and prevEntry.scene or nil
    if prev and prev.resume then
        prev:resume()
    end
end

-- ==========================================
-- 生命周期与事件转发
-- ==========================================

function SceneManager.update(dt)
    -- Update 只更新最顶层的场景！
    -- 这样底下的游戏画面就会自动“冻结”时间，实现真正的暂停
    local entry = currentEntry()
    activate(entry)
    local curr = entry and entry.scene or nil
    if curr and curr.update then
        curr:update(dt)
    end
end

function SceneManager.draw()
    -- Draw 会从栈底到栈顶依次绘制！
    -- 这样顶层的菜单就可以覆盖在底层游戏画面之上，甚至可以做半透明背景
    --
    -- alpha 是固定步长模拟的渲染插值因子 [0,1)（见 Timestep）：
    -- 场景可用 draw(alpha) 在上一模拟态与当前模拟态之间插值，消除高刷新率下的抖动。
    local alpha = Timestep.alpha
    for i = 1, #stack do
        local entry = stack[i]
        activate(entry)
        local scene = entry.scene
        if scene.draw then
            scene:draw(alpha)
        end
    end
    activate(currentEntry())
end

-- 变长参数全量转发：保留 scancode/isrepeat/istouch/presses 等尾部参数。
function SceneManager.keypressed(...)
    return SceneManager.dispatchInput("keypressed", ...)
end

function SceneManager.mousepressed(...)
    return SceneManager.dispatchInput("mousepressed", ...)
end

function SceneManager.textinput(text)
    return SceneManager.dispatchInput("textinput", text)
end

function SceneManager.textedited(text, start, length)
    return SceneManager.dispatchInput("textedited", text, start, length)
end

function SceneManager.mousemoved(...)
    return SceneManager.dispatchInput("mousemoved", ...)
end

function SceneManager.wheelmoved(x, y)
    return SceneManager.dispatchInput("wheelmoved", x, y)
end

function SceneManager.current()
    return current()
end

function SceneManager.quit()
    -- 游戏退出时，确保所有层级的场景都执行了资源清理
    while #stack > 0 do
        print("SceneManager: Triggering exit for scene on quit...")
        exitEntry(table.remove(stack))
    end
    ResourceManager:activateSceneScope(nil)
end

local function restoreCurrent()
    activate(currentEntry())
end

local function allowsBubble(scene)
    if scene and scene.allowsGlobalShortcuts then
        return scene:allowsGlobalShortcuts() ~= false
    end
    return true
end

function SceneManager.dispatchInput(method, ...)
    for i = #stack, 1, -1 do
        local entry = stack[i]
        activate(entry)
        local scene = entry.scene
        if scene and scene[method] then
            local consumed = scene[method](scene, ...)
            if consumed == true then
                restoreCurrent()
                return true
            end
        end
        if not allowsBubble(scene) then
            restoreCurrent()
            return false
        end
    end
    restoreCurrent()
    return false
end

local function dispatchAll(method, ...)
    for i = 1, #stack do
        local entry = stack[i]
        activate(entry)
        local scene = entry.scene
        if scene and scene[method] then scene[method](scene, ...) end
    end
    restoreCurrent()
end

function SceneManager.keyreleased(...) return SceneManager.dispatchInput("keyreleased", ...) end
function SceneManager.mousereleased(...) return SceneManager.dispatchInput("mousereleased", ...) end
function SceneManager.resize(...) return dispatchAll("resize", ...) end
function SceneManager.focus(...) return dispatchAll("focus", ...) end
function SceneManager.visible(...) return dispatchAll("visible", ...) end
function SceneManager.gamepadpressed(...) return SceneManager.dispatchInput("gamepadpressed", ...) end
function SceneManager.gamepadreleased(...) return SceneManager.dispatchInput("gamepadreleased", ...) end
function SceneManager.joystickpressed(...) return SceneManager.dispatchInput("joystickpressed", ...) end
function SceneManager.joystickreleased(...) return SceneManager.dispatchInput("joystickreleased", ...) end
function SceneManager.touchpressed(...) return SceneManager.dispatchInput("touchpressed", ...) end
function SceneManager.touchreleased(...) return SceneManager.dispatchInput("touchreleased", ...) end
function SceneManager.touchmoved(...) return SceneManager.dispatchInput("touchmoved", ...) end

return SceneManager
