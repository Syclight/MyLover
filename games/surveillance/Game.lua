local SurveillanceScene = require("games.surveillance.scenes.SurveillanceScene")
local LLMService = require("engine.services.llm.LLMService")
local llmConfig = require("games.surveillance.llm.config")

local Game = {
    id = "surveillance",
    name = "Surveillance",
}

function Game:createInitialScene(context)
    local llm = context.services and context.services:get("llm") or nil
    return SurveillanceScene:new({ llm = llm })
end

function Game:start(context)
    local llm = context.services:register("llm", LLMService.new(llmConfig))
    context.diagnostics.register("llm", function() return llm:debugStats() end)
end

function Game:stop(context)
    context.diagnostics.unregister("llm")
end

return Game
