local GameClock = require("games.surveillance.gameplay.GameClock")

local EvidenceLog = {}

local MAX_ENTRIES = 80

function EvidenceLog.new()
    return {
        entries = {},
        selected = 1,
        nextId = 1,
    }
end

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clampSelection(state)
    if #state.entries == 0 then
        state.selected = 1
    else
        state.selected = math.max(1, math.min(state.selected or 1, #state.entries))
    end
end

function EvidenceLog.add(state, clock, data)
    if not state or not data then return nil end
    local quote = trim(data.quote)
    if quote == "" then return nil end

    local entry = {
        id = state.nextId,
        time = GameClock.format(clock),
        date = GameClock.formatDate(clock),
        absoluteMinutes = clock and clock.absoluteMinutes or 0,
        channelId = data.channelId,
        frequency = data.frequency or "",
        speaker = data.speaker or "未知对象",
        profession = data.profession or "",
        counterpart = data.counterpart or "",
        activity = data.activity or "",
        topic = data.topic or "",
        quote = quote,
        reviewed = false,
    }
    state.nextId = state.nextId + 1
    table.insert(state.entries, 1, entry)
    while #state.entries > MAX_ENTRIES do
        table.remove(state.entries)
    end
    state.selected = 1
    return entry
end

function EvidenceLog.count(state)
    return #(state and state.entries or {})
end

function EvidenceLog.selected(state)
    if not state or #state.entries == 0 then return nil end
    clampSelection(state)
    return state.entries[state.selected]
end

function EvidenceLog.moveSelection(state, delta)
    if not state then return nil end
    if #state.entries == 0 then
        state.selected = 1
        return nil
    end
    state.selected = ((state.selected - 1 + delta) % #state.entries) + 1
    return EvidenceLog.selected(state)
end

function EvidenceLog.markReviewed(state, entry)
    entry = entry or EvidenceLog.selected(state)
    if entry then entry.reviewed = true end
    return entry
end

function EvidenceLog.unreviewedCount(state)
    local total = 0
    for _, entry in ipairs(state and state.entries or {}) do
        if not entry.reviewed then total = total + 1 end
    end
    return total
end

return EvidenceLog
