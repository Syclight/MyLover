local GameClock = {}

local MINUTES_PER_DAY = 24 * 60
local WAKE_MINUTE = 6 * 60
local WEEKDAYS = { "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六" }

local function isLeapYear(year)
    return year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)
end

local function daysInMonth(year, month)
    local days = { 31, isLeapYear(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    return days[month]
end

local function weekdayIndex(year, month, day)
    local offsets = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if month < 3 then year = year - 1 end
    return (year + math.floor(year / 4) - math.floor(year / 100)
        + math.floor(year / 400) + offsets[month] + day) % 7 + 1
end

function GameClock.new(config)
    config = config or {}
    return {
        absoluteMinutes = config.startMinutes or WAKE_MINUTE,
        minutesPerSecond = config.minutesPerSecond or 1,
        startDate = config.startDate or { year = 1984, month = 6, day = 12 },
    }
end

function GameClock.update(state, dt)
    state.absoluteMinutes = state.absoluteMinutes + dt * state.minutesPerSecond
end

function GameClock.day(state)
    return math.floor(state.absoluteMinutes / MINUTES_PER_DAY) + 1
end

function GameClock.minuteOfDay(state)
    return state.absoluteMinutes % MINUTES_PER_DAY
end

function GameClock.format(state)
    local minute = math.floor(GameClock.minuteOfDay(state))
    return string.format("%02d:%02d", math.floor(minute / 60), minute % 60)
end

function GameClock.date(state)
    local date = {
        year = state.startDate.year,
        month = state.startDate.month,
        day = state.startDate.day,
    }
    local remaining = math.floor(state.absoluteMinutes / MINUTES_PER_DAY)
    while remaining > 0 do
        local available = daysInMonth(date.year, date.month) - date.day
        if remaining <= available then
            date.day = date.day + remaining
            remaining = 0
        else
            remaining = remaining - available - 1
            date.day = 1
            date.month = date.month + 1
            if date.month > 12 then
                date.month = 1
                date.year = date.year + 1
            end
        end
    end
    date.weekday = weekdayIndex(date.year, date.month, date.day)
    date.weekdayName = WEEKDAYS[date.weekday]
    return date
end

function GameClock.formatDate(state)
    local date = GameClock.date(state)
    return string.format("%04d年%02d月%02d日  %s", date.year, date.month, date.day, date.weekdayName)
end

-- 表盘平面方向：x 向右、y 向上，12 点方向为 {0, 1}。
function GameClock.handDirections(state)
    -- 与 HUD 的整分钟显示完全同步，也避免低分辨率光投下每帧微移造成 TAA 闪烁。
    local minutes = math.floor(GameClock.minuteOfDay(state))
    local minuteAngle = (minutes % 60) / 60 * math.pi * 2
    local hourAngle = (minutes % (12 * 60)) / (12 * 60) * math.pi * 2
    return {
        minute = { math.sin(minuteAngle), math.cos(minuteAngle) },
        hour = { math.sin(hourAngle), math.cos(hourAngle) },
    }
end

function GameClock.isAfterMidnightBeforeWake(state)
    return GameClock.minuteOfDay(state) < WAKE_MINUTE
end

function GameClock.restHours(state, hours)
    state.absoluteMinutes = state.absoluteMinutes + math.max(1, hours or 1) * 60
    if GameClock.isAfterMidnightBeforeWake(state) then
        local dayIndex = math.floor(state.absoluteMinutes / MINUTES_PER_DAY)
        state.absoluteMinutes = dayIndex * MINUTES_PER_DAY + WAKE_MINUTE
    end
end

function GameClock.sleepToNextMorning(state)
    local dayIndex = math.floor(state.absoluteMinutes / MINUTES_PER_DAY)
    state.absoluteMinutes = (dayIndex + 1) * MINUTES_PER_DAY + WAKE_MINUTE
end

function GameClock.forceWakeThisMorning(state)
    local dayIndex = math.floor(state.absoluteMinutes / MINUTES_PER_DAY)
    state.absoluteMinutes = dayIndex * MINUTES_PER_DAY + WAKE_MINUTE
end

return GameClock
