local EventBus = {
    listeners = {}
}

function EventBus.on(event, func)
    assert(type(func) == "function", "EventBus.on requires a function listener")
    if not EventBus.listeners[event] then EventBus.listeners[event] = {} end
    local listeners = EventBus.listeners[event]
    local subscription = { callback = func, active = true }
    table.insert(listeners, subscription)

    return function()
        if not subscription.active then return end
        subscription.active = false
        for i = #listeners, 1, -1 do
            if listeners[i] == subscription then
                table.remove(listeners, i)
                break
            end
        end
        if #listeners == 0 then EventBus.listeners[event] = nil end
    end
end

function EventBus.emit(event, ...)
    if EventBus.listeners[event] then
        -- Copy so listeners may safely unsubscribe while an event is being emitted.
        local snapshot = {}
        for i, subscription in ipairs(EventBus.listeners[event]) do snapshot[i] = subscription end
        for _, subscription in ipairs(snapshot) do
            if subscription.active then subscription.callback(...) end
        end
    end
end

function EventBus.clear()
    for _, listeners in pairs(EventBus.listeners) do
        for _, subscription in ipairs(listeners) do subscription.active = false end
    end
    EventBus.listeners = {}
end

return EventBus
