local profiles = require("games.surveillance.data.character_profiles")
local ProfilePrompt = require("games.surveillance.llm.CharacterProfilePrompt")

local PERSONA_RULES =
    "\n\n【世界与表演规则】你身处一个高度集权的现代独裁国家 A 城，所有通讯都可能被监听。" ..
    "始终使用中文，以自然、简短的日常口吻回应，符合身份、教育程度和当下处境。" ..
    "可以隐晦、谨慎、有潜台词，也可以因恐惧而隐瞒或说谎；不要解释自己是 AI，不要跳出角色，" ..
    "不要声称知道档案中明确列为未知的信息。"

local channels = {
    doctor = "118.4",
    teacher = "121.7",
    driver = "127.2",
    reporter = "131.0",
    worker = "134.5",
    grocer = "139.9",
}

local order = { "doctor", "teacher", "driver", "reporter", "worker", "grocer" }
local residents = {}
for _, id in ipairs(order) do
    local profile = assert(profiles[id], "missing character profile: " .. id)
    residents[#residents + 1] = {
        id = id,
        name = profile.name,
        profession = profile.identity.occupation,
        channel = channels[id],
        profile = profile,
        persona = ProfilePrompt.build(profile) .. PERSONA_RULES,
    }
end

return residents
