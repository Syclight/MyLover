local InputRecorder = {}
InputRecorder.__index = InputRecorder
local unpack = table.unpack or unpack

local function copyArgs(...)
    local args = { ... }
    args.n = select("#", ...)
    return args
end

local function unpackArgs(args)
    return unpack(args, 1, args.n or #args)
end

function InputRecorder.new()
    return setmetatable({
        mode = "idle",
        time = 0,
        events = {},
        cursor = 1,
        sink = nil,
    }, InputRecorder)
end

function InputRecorder:startRecording()
    self.mode = "record"
    self.time = 0
    self.events = {}
    self.cursor = 1
end

function InputRecorder:record(method, ...)
    if self.mode ~= "record" then return false end
    self.events[#self.events + 1] = {
        t = self.time,
        method = method,
        args = copyArgs(...),
    }
    return true
end

function InputRecorder:stopRecording()
    local events = self.events
    self.mode = "idle"
    return events
end

function InputRecorder:startPlayback(events, sink)
    assert(type(events) == "table", "playback events must be a table")
    assert(type(sink) == "table" or type(sink) == "function", "playback sink is required")
    self.mode = "playback"
    self.time = 0
    self.events = events
    self.cursor = 1
    self.sink = sink
end

function InputRecorder:isPlaying()
    return self.mode == "playback"
end

function InputRecorder:isRecording()
    return self.mode == "record"
end

function InputRecorder:update(dt)
    self.time = self.time + (dt or 0)
    if self.mode ~= "playback" then return end
    while self.cursor <= #self.events and (self.events[self.cursor].t or 0) <= self.time do
        local event = self.events[self.cursor]
        if type(self.sink) == "function" then
            self.sink(event.method, unpackArgs(event.args or {}))
        elseif self.sink[event.method] then
            self.sink[event.method](self.sink, unpackArgs(event.args or {}))
        end
        self.cursor = self.cursor + 1
    end
    if self.cursor > #self.events then self.mode = "idle" end
end

function InputRecorder:stop()
    self.mode = "idle"
    self.sink = nil
end

return InputRecorder
