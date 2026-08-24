require("love.thread")

local json = require("engine.utils.json")
local requestChannelName, eventChannelName, cancelChannelName, generation = ...
local requests = love.thread.getChannel(requestChannelName)
local events = love.thread.getChannel(eventChannelName)
local cancels = love.thread.getChannel(cancelChannelName)
local canceled = {}
local shuttingDown = false

local function emit(event)
    event.generation = generation
    events:push(json.encode(event))
end

local function pollCancels()
    while true do
        local value = cancels:pop()
        if value == nil then break end
        if value == "*" then
            shuttingDown = true
        else
            canceled[tonumber(value) or value] = true
        end
    end
end

local function isCanceled(id)
    pollCancels()
    return shuttingDown or canceled[id] == true
end

while true do
    local raw = requests:demand()
    pollCancels()
    local ok, job = pcall(json.decode, raw)
    if ok and type(job) == "table" then
        if job.cmd == "shutdown" then break end
        if isCanceled(job.id) then
            emit({ type = "error", id = job.id, data = "request canceled" })
        else
            local function emitChunk(chunk)
                emit({ type = "chunk", id = job.id, data = chunk })
            end
            job.isCanceled = function() return isCanceled(job.id) end
            local backendOk, err = pcall(function()
                local backend = require(job.backendModule)
                assert(type(backend.run) == "function", "LLM backend must provide run(job, emit)")
                backend.run(job, emitChunk)
            end)
            emit({
                type = backendOk and "done" or "error",
                id = job.id,
                data = backendOk and nil or tostring(err),
            })
        end
        if shuttingDown then break end
    end
end
