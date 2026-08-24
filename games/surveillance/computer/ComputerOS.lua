local ComputerOS = {}

ComputerOS.apps = {
    { id = "surveillance", label = "监听终端", subtitle = "审讯与频道监听" },
    { id = "archives", label = "公民档案", subtitle = "居民身份数据库" },
    { id = "evidence", label = "证据档案", subtitle = "异常截获片段" },
    { id = "notes", label = "记事本", subtitle = "本地文本记录" },
    { id = "system", label = "系统信息", subtitle = "终端运行状态" },
}

function ComputerOS.new()
    return {
        activeApp = "desktop",
        selected = 1,
        booted = false,
        bootTimer = 0,
    }
end

function ComputerOS.beginSession(state)
    state.activeApp = "desktop"
    if not state.booted then
        state.booted = true
        state.bootTimer = 1.6
    end
end

function ComputerOS.update(state, dt)
    state.bootTimer = math.max(0, state.bootTimer - dt)
end

function ComputerOS.open(state, appId)
    for _, app in ipairs(ComputerOS.apps) do
        if app.id == appId then
            state.activeApp = appId
            return true
        end
    end
    return false
end

function ComputerOS.openSelected(state)
    return ComputerOS.open(state, ComputerOS.apps[state.selected].id)
end

function ComputerOS.moveSelection(state, delta)
    state.selected = ((state.selected - 1 + delta) % #ComputerOS.apps) + 1
    return state.selected
end

function ComputerOS.backToDesktop(state)
    if state.activeApp == "desktop" then return false end
    state.activeApp = "desktop"
    return true
end

function ComputerOS.keypressedDesktop(state, key)
    if key == "left" or key == "up" then
        ComputerOS.moveSelection(state, -1)
    elseif key == "right" or key == "down" or key == "tab" then
        ComputerOS.moveSelection(state, 1)
    elseif key == "return" or key == "kpenter" then
        ComputerOS.openSelected(state)
    else
        local number = tonumber(key)
        if number and ComputerOS.apps[number] then
            state.selected = number
            ComputerOS.openSelected(state)
        end
    end
end

return ComputerOS
