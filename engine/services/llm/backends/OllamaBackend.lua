local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("engine.utils.json")

local OllamaBackend = {}

function OllamaBackend.run(job, emit)
    local payload = {
        model = job.model,
        messages = job.messages,
        stream = true,
        options = job.options,
    }
    if job.think ~= nil then payload.think = job.think end
    local body = json.encode(payload)
    local buffer, apiError = "", nil
    local previousTimeout = http.TIMEOUT
    if job.timeout then http.TIMEOUT = job.timeout end

    local function processLine(line)
        if not line or line == "" then return end
        local ok, object = pcall(json.decode, line)
        if not ok or type(object) ~= "table" then return end
        if object.error then apiError = tostring(object.error) end
        if object.message and object.message.content and object.message.content ~= "" then
            emit(object.message.content)
        end
    end

    local function sink(chunk, err)
        if job.isCanceled and job.isCanceled() then return nil, "request canceled" end
        if err then return nil, err end
        if chunk == nil then return 1 end
        buffer = buffer .. chunk
        while true do
            local newline = buffer:find("\n", 1, true)
            if not newline then break end
            processLine(buffer:sub(1, newline - 1))
            buffer = buffer:sub(newline + 1)
        end
        return 1
    end

    local requestOk, ok, statusCode = pcall(http.request, {
        url = (job.host or "http://localhost:11434") .. "/api/chat",
        method = "POST",
        headers = { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body) },
        source = ltn12.source.string(body),
        sink = sink,
    })
    if job.timeout then http.TIMEOUT = previousTimeout end
    if not requestOk then error(tostring(ok)) end
    if buffer ~= "" then processLine(buffer) end
    if ok == nil then error("cannot connect to LLM backend: " .. tostring(statusCode)) end
    if apiError then error("Ollama error: " .. apiError) end
    if type(statusCode) == "number" and statusCode >= 400 then
        error("Ollama returned HTTP " .. tostring(statusCode))
    end
end

return OllamaBackend
