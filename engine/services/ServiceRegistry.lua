local ServiceRegistry = {}
ServiceRegistry.__index = ServiceRegistry

function ServiceRegistry.new()
    return setmetatable({
        services = {},
        order = {},
        started = false,
        context = nil,
    }, ServiceRegistry)
end

function ServiceRegistry:register(name, service)
    assert(type(name) == "string" and name ~= "", "service name is required")
    assert(type(service) == "table", "service must be a table")
    assert(self.services[name] == nil, "service already registered: " .. name)
    self.services[name] = service
    self.order[#self.order + 1] = name
    if self.started and service.start then service:start(self.context) end
    return service
end

function ServiceRegistry:get(name)
    return self.services[name]
end

function ServiceRegistry:require(name)
    return assert(self.services[name], "service is not registered: " .. tostring(name))
end

function ServiceRegistry:unregister(name)
    local service = self.services[name]
    if not service then return nil end
    if self.started and service.stop then service:stop(self.context) end
    self.services[name] = nil
    for index, registeredName in ipairs(self.order) do
        if registeredName == name then
            table.remove(self.order, index)
            break
        end
    end
    return service
end

function ServiceRegistry:startAll(context)
    if self.started then return end
    self.started = true
    self.context = context
    for _, name in ipairs(self.order) do
        local service = self.services[name]
        if service.start then service:start(context) end
    end
end

function ServiceRegistry:update(dt)
    if not self.started then return end
    for _, name in ipairs(self.order) do
        local service = self.services[name]
        if service and service.update then service:update(dt) end
    end
end

function ServiceRegistry:stopAll()
    if not self.started then return end
    for index = #self.order, 1, -1 do
        local service = self.services[self.order[index]]
        if service and service.stop then service:stop(self.context) end
    end
    self.started = false
    self.context = nil
end

return ServiceRegistry
