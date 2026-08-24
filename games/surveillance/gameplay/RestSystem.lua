local GameClock = require("games.surveillance.gameplay.GameClock")

local RestSystem = {}

function RestSystem.new()
    return {
        bedElapsed = 0,
        menuOpen = false,
        customMode = false,
        customHours = 3,
        dismissed = false,
        sleepOverlay = 0,
        sleepMessage = nil,
        drowsiness = 0,
    }
end

local function beginSleep(state, message)
    state.menuOpen = false
    state.customMode = false
    state.dismissed = true
    state.sleepOverlay = 1.5
    state.sleepMessage = message
end

function RestSystem.update(state, clock, postureKind, dt)
    if state.sleepOverlay > 0 then
        state.sleepOverlay = math.max(0, state.sleepOverlay - dt)
    end

    if GameClock.isAfterMidnightBeforeWake(clock) then
        GameClock.forceWakeThisMorning(clock)
        beginSleep(state, "午夜之后，你再也支撑不住。醒来时已经是早上六点。")
        return "forced_sleep"
    end

    if postureKind == "lie" then
        state.bedElapsed = state.bedElapsed + dt
        state.drowsiness = state.dismissed and 0 or math.min(1, state.bedElapsed / 5)
        if state.bedElapsed >= 5 and not state.dismissed and not state.menuOpen then
            state.menuOpen = true
        end
    else
        state.bedElapsed = 0
        state.drowsiness = 0
        state.menuOpen = false
        state.customMode = false
        state.dismissed = false
    end
end

local function restFor(state, clock, hours)
    GameClock.restHours(clock, hours)
    beginSleep(state, "你睡了 " .. tostring(hours) .. " 小时。")
end

function RestSystem.keypressed(state, clock, key)
    if not state.menuOpen then return false end
    if state.customMode then
        if key == "left" or key == "down" then
            state.customHours = math.max(1, state.customHours - 1)
        elseif key == "right" or key == "up" then
            state.customHours = math.min(12, state.customHours + 1)
        elseif key == "return" or key == "kpenter" then
            restFor(state, clock, state.customHours)
        elseif key == "escape" or key == "backspace" then
            state.customMode = false
        end
        return true
    end

    if key == "1" or key == "kp1" then
        restFor(state, clock, 1)
    elseif key == "2" or key == "kp2" then
        restFor(state, clock, 2)
    elseif key == "3" or key == "kp3" then
        state.customMode = true
    elseif key == "4" or key == "kp4" then
        GameClock.sleepToNextMorning(clock)
        beginSleep(state, "你一直睡到第二天早上六点。")
    elseif key == "escape" then
        state.menuOpen = false
        state.dismissed = true
        state.drowsiness = 0
    else
        return false
    end
    return true
end

return RestSystem
