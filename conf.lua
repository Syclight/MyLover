-- conf.lua

-- 让"系统输入法候选词窗口"在游戏内显示。
-- 背景：LÖVE 底层是 SDL2，SDL2 在 Windows 上默认隐藏原生输入法 UI（只发合成串事件），
-- 于是能看到拼音、却看不到候选字。设置 SDL_IME_SHOW_UI=1 可让 SDL 显示原生候选窗。
-- 关键：该提示在"窗口/IME 初始化"时读取，必须早于窗口创建——所以放在 conf.lua 顶层
-- （早于 love.load）。这里用 LuaJIT FFI 直接调用已加载的 SDL2，等效于启动前设环境变量，
-- 但不改动本地计算机。全程 pcall，失败则静默降级（仍保留自绘拼音串）。
pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, [[
        int SDL_SetHintWithPriority(const char *name, const char *value, int priority);
    ]])
    local sdl = ffi.load("SDL2") -- Windows 上即已加载的 SDL2.dll
    -- priority 2 = SDL_HINT_OVERRIDE，确保覆盖默认值
    sdl.SDL_SetHintWithPriority("SDL_IME_SHOW_UI", "1", 2)
end)

-- 全屏测试开关。注意:history/present 等 canvas 在场景加载时按"当时的屏幕分辨率"
-- 创建,全屏后分辨率变大,TAAU resolve/FXAA 的逐像素成本会随之上升,对比帧率时需留意。
-- fullscreentype 两种取值:
--   "desktop"   无边框窗口化全屏,走 DWM 合成,分辨率跟随桌面(width/height 被忽略)
--   "exclusive" 独占全屏,可绕过合成器直接翻转(测混合显卡呈现链路用这个),
--               分辨率取最接近 width/height 的显示模式
local FULLSCREEN = false
local FULLSCREEN_TYPE = "desktop"

-- 开发/发布开关：发布构建改为 false（或设环境变量 LOVE_RELEASE=1）。
--   DEV = true  → 开控制台、关 vsync（测最大帧率，代价是空转烧 CPU/GPU）
--   DEV = false → 关控制台、开 vsync（省电、无画面撕裂，交付给玩家用这个）
-- 发行打包器会在 .love 内写入 release.lua，因此融合后的 exe 无需依赖玩家机器上的环境变量。
local IS_PACKAGED_RELEASE = love.filesystem and love.filesystem.getInfo("release.lua") ~= nil
local DEV = not IS_PACKAGED_RELEASE and os.getenv("LOVE_RELEASE") ~= "1"

function love.conf(t)
    t.window.title = "长筱之战：设乐原"
    t.window.width = 1280
    t.window.height = 720
    -- t.window.width = 1920
    -- t.window.height = 1080
    t.window.fullscreen = FULLSCREEN
    t.window.fullscreentype = FULLSCREEN_TYPE
    t.console = DEV
    -- vsync=0 只用于测性能：开启 vsync 后帧率被显示器刷新率锁定，无法反映性能差异
    t.window.vsync = DEV and 0 or 1
end
