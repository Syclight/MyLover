local json = require("engine.utils.json")

local LLMService = {}
LLMService.__index = LLMService

local nextGeneration = 0

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

function LLMService.new(config)
    config = copyTable(config)
    assert(type(config.backendModule) == "string" and config.backendModule ~= "",
        "LLMService requires config.backendModule")
    return setmetatable({
        config = config,
        started = false,
        pending = {},
        nextId = 1,
        workerError = nil,
    }, LLMService)
end

function LLMService:start()
    if self.started then return end
    nextGeneration = nextGeneration + 1
    self.generation = nextGeneration
    local suffix = tostring(self.generation)
    local requestName = "llm_requests_" .. suffix
    local eventName = "llm_events_" .. suffix
    local cancelName = "llm_cancels_" .. suffix
    self.requestChannel = love.thread.getChannel(requestName)
    self.eventChannel = love.thread.getChannel(eventName)
    self.cancelChannel = love.thread.getChannel(cancelName)
    self.requestChannel:clear()
    self.eventChannel:clear()
    self.cancelChannel:clear()
    self.pending = {}
    self.workerError = nil
    self.thread = love.thread.newThread("engine/services/llm/worker.lua")
    self.thread:start(requestName, eventName, cancelName, self.generation)
    self.started = true
end

function LLMService:chat(options, handlers)
    assert(self.started, "LLMService must be started before chat()")
    options = options or {}
    local id = self.nextId
    self.nextId = self.nextId + 1
    local job = {
        id = id,
        backendModule = options.backendModule or self.config.backendModule,
        host = options.host or self.config.host,
        model = options.model or self.config.model,
        messages = assert(options.messages, "LLM chat messages are required"),
        options = options.options or self.config.options,
        think = options.think,
        timeout = options.timeout or self.config.timeout,
    }
    if job.think == nil then job.think = self.config.think end
    self.pending[id] = { handlers = handlers or {}, buffer = {} }
    self.requestChannel:push(json.encode(job))
    return id
end

function LLMService:cancel(id)
    if self.cancelChannel and id ~= nil then self.cancelChannel:push(tostring(id)) end
    self.pending[id] = nil
end

local function failPending(self, message)
    for id, entry in pairs(self.pending) do
        self.pending[id] = nil
        if entry.handlers.onError then entry.handlers.onError(message) end
    end
end

function LLMService:update()
    if not self.started then return end
    if not self.workerError then
        local err = self.thread:getError()
        if err then
            self.workerError = tostring(err)
            failPending(self, self.workerError)
        end
    end
    while true do
        local raw = self.eventChannel:pop()
        if not raw then break end
        local ok, event = pcall(json.decode, raw)
        if ok and type(event) == "table" and event.generation == self.generation then
            local entry = self.pending[event.id]
            if entry then
                local handlers = entry.handlers
                if event.type == "chunk" then
                    entry.buffer[#entry.buffer + 1] = event.data or ""
                    if handlers.onChunk then handlers.onChunk(event.data or "") end
                elseif event.type == "done" then
                    self.pending[event.id] = nil
                    if handlers.onDone then handlers.onDone(table.concat(entry.buffer)) end
                elseif event.type == "error" then
                    self.pending[event.id] = nil
                    if handlers.onError then handlers.onError(event.data) end
                end
            end
        end
    end
end

function LLMService:debugStats()
    local count = 0
    for _ in pairs(self.pending) do count = count + 1 end
    return { started = self.started, pending = count, error = self.workerError }
end

local function waitForThread(thread, timeout)
    if not thread then return true end
    local deadline = love.timer.getTime() + (timeout or 0)
    while thread:isRunning() and love.timer.getTime() < deadline do
        love.timer.sleep(0.005)
    end
    if not thread:isRunning() then
        thread:wait()
        return true
    end
    return false
end

function LLMService:stop()
    if not self.started then return end
    if self.cancelChannel then self.cancelChannel:push("*") end
    self.requestChannel:push(json.encode({ cmd = "shutdown" }))
    failPending(self, "LLM service stopped")
    local threadStopped = waitForThread(self.thread, self.config.stopTimeout or 0.2)
    if not threadStopped then
        self.workerError = "LLM worker did not stop before timeout"
    end
    self.started = false
    self.thread = nil
    self.requestChannel = nil
    self.eventChannel = nil
    self.cancelChannel = nil
end

return LLMService
