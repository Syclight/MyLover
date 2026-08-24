local CharacterProfilePrompt = {}

local function join(value)
    if type(value) == "table" then return table.concat(value, "；") end
    return tostring(value or "未记录")
end

local function append(lines, label, value)
    if value and value ~= "" and (type(value) ~= "table" or #value > 0) then
        lines[#lines + 1] = label .. "：" .. join(value)
    end
end

function CharacterProfilePrompt.build(profile)
    assert(type(profile) == "table" and profile.id, "character profile requires id")
    local identity = profile.identity or {}
    local lines = {
        "【角色档案】",
        "姓名：" .. tostring(identity.fullName or profile.name),
        "年龄与身份：" .. tostring(identity.age or "未知") .. "岁，" .. tostring(identity.occupation or "未知职业"),
    }
    append(lines, "出生与户籍", identity.origin)
    append(lines, "家庭状况", identity.household)
    append(lines, "外貌与习惯", profile.appearance)
    append(lines, "生平", profile.biography)
    append(lines, "核心性格", profile.personality)
    append(lines, "价值观", profile.values)
    append(lines, "日常规律", profile.dailyRoutine)
    append(lines, "重要关系", profile.relationships)
    append(lines, "当前压力", profile.currentPressures)
    append(lines, "短期目标", profile.goals)
    append(lines, "恐惧与软肋", profile.fears)
    append(lines, "对国家与监听的态度", profile.attitude)
    append(lines, "掌握的信息", profile.knowledge and profile.knowledge.knows)
    append(lines, "知识边界", profile.knowledge and profile.knowledge.unknown)
    append(lines, "隐私与秘密", profile.secrets)
    append(lines, "容易展开的话题", profile.conversationHooks)
    local speech = profile.speech or {}
    append(lines, "说话语气", speech.tone)
    append(lines, "语言习惯", speech.habits)
    append(lines, "刻意回避", speech.avoids)
    lines[#lines + 1] = "【对话约束】不得主动背诵档案；只在问题、情绪和关系自然触发时透露信息。秘密应分层泄露，受到压力时可以含糊、转移、沉默或说谎，但前后逻辑必须符合角色经历。"
    if profile.dialogueExamples then
        lines[#lines + 1] = "【语气示例】"
        for _, example in ipairs(profile.dialogueExamples) do
            lines[#lines + 1] = "对方：" .. example[1] .. "\n角色：" .. example[2]
        end
    end
    return table.concat(lines, "\n")
end

return CharacterProfilePrompt
