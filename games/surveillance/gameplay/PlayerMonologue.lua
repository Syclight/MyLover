local PlayerMonologue = {}

function PlayerMonologue.new(messages)
    return { current = nil, queue = {}, seen = {}, messages = messages }
end

local function beginNext(state)
    if state.current or #state.queue == 0 then return end
    state.current = table.remove(state.queue, 1)
    state.current.elapsed = 0
end

function PlayerMonologue.say(state, text, options)
    if not state or type(text) ~= "string" or text == "" then return false end
    options = options or {}
    if options.key and state.seen[options.key] and not options.force then return false end
    if options.key then state.seen[options.key] = true end
    if state.messages then
        local HUDMessages = require("games.surveillance.gameplay.HUDMessages")
        return HUDMessages.monologue(state.messages, text, options)
    end
    if #state.queue >= 3 then table.remove(state.queue, 1) end
    state.queue[#state.queue + 1] = {
        text = text,
        duration = options.duration or 4.2,
        fadeIn = options.fadeIn or 0.25,
        fadeOut = options.fadeOut or 0.65,
    }
    beginNext(state)
    return true
end

function PlayerMonologue.update(state, dt)
    if not state or not state.current then
        if state then beginNext(state) end
        return
    end
    state.current.elapsed = state.current.elapsed + dt
    if state.current.elapsed >= state.current.duration then
        state.current = nil
        beginNext(state)
    end
end

function PlayerMonologue.visible(state)
    local line = state and state.current
    if not line then return nil, 0 end
    local alpha = 1
    if line.elapsed < line.fadeIn then
        alpha = line.elapsed / line.fadeIn
    elseif line.elapsed > line.duration - line.fadeOut then
        alpha = (line.duration - line.elapsed) / line.fadeOut
    end
    return line.text, math.max(0, math.min(1, alpha))
end

return PlayerMonologue
