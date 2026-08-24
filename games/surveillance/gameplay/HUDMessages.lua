local HUDMessages = {}

local LIMITS = { toast = 4, monologue = 3, system = 3 }

function HUDMessages.new()
    return {
        queues = { toast = {}, monologue = {}, system = {} },
        current = { toast = nil, monologue = nil, system = nil },
    }
end

local function beginNext(state, channel)
    if state.current[channel] or #state.queues[channel] == 0 then return end
    state.current[channel] = table.remove(state.queues[channel], 1)
    state.current[channel].elapsed = 0
end

function HUDMessages.push(state, channel, text, options)
    if not state or type(text) ~= "string" or text == "" then return false end
    options = options or {}
    channel = channel or "toast"
    state.queues[channel] = state.queues[channel] or {}
    state.current[channel] = state.current[channel]
    local queue = state.queues[channel]
    local limit = LIMITS[channel] or 3
    if #queue >= limit then table.remove(queue, 1) end
    queue[#queue + 1] = {
        text = text,
        title = options.title,
        body = options.body,
        channel = channel,
        duration = options.duration or (channel == "monologue" and 4.2 or 2.4),
        fadeIn = options.fadeIn or 0.18,
        fadeOut = options.fadeOut or 0.45,
        tone = options.tone or channel,
    }
    beginNext(state, channel)
    return true
end

function HUDMessages.toast(state, text, options)
    return HUDMessages.push(state, "toast", text, options)
end

function HUDMessages.monologue(state, text, options)
    return HUDMessages.push(state, "monologue", text, options)
end

function HUDMessages.system(state, text, options)
    return HUDMessages.push(state, "system", text, options)
end

function HUDMessages.update(state, dt)
    if not state then return end
    for channel, current in pairs(state.current) do
        if current then
            current.elapsed = current.elapsed + dt
            if current.elapsed >= current.duration then
                state.current[channel] = nil
                beginNext(state, channel)
            end
        else
            beginNext(state, channel)
        end
    end
end

function HUDMessages.visible(state, channel)
    local line = state and state.current and state.current[channel]
    if not line then return nil, 0 end
    local alpha = 1
    if line.elapsed < line.fadeIn then
        alpha = line.elapsed / line.fadeIn
    elseif line.elapsed > line.duration - line.fadeOut then
        alpha = (line.duration - line.elapsed) / line.fadeOut
    end
    return line, math.max(0, math.min(1, alpha))
end

return HUDMessages
