-- assets/data/tasks.lua
-- 国家安全部派遣的审查任务。targetCitizenId 对应 assets/data/residents.lua 中的市民 id。
-- 玩家通过终端审讯目标，再用 F1(忠诚)/F2(嫌疑) 提交裁决。
return {
    {
        id = "task_doctor",
        title = "忠诚度复核 · 第 114 号",
        targetCitizenId = "doctor",
        briefing = "目标：人民医院 林大夫。近期有匿名举报称其私下议论物资调配。请接入通讯，评估其忠诚度。",
    },
    {
        id = "task_teacher",
        title = "言论审查 · 第 209 号",
        targetCitizenId = "teacher",
        briefing = "目标：中学教师 周老师。课堂用语疑似含隐喻。请审讯并判断是否需要立案。",
    },
    {
        id = "task_driver",
        title = "情报来源排查 · 第 077 号",
        targetCitizenId = "driver",
        briefing = "目标：出租车司机 老赵。掌握大量街头消息。确认其消息来源是否可靠、是否散布谣言。",
    },
    {
        id = "task_reporter",
        title = "内部倾向评估 · 第 301 号",
        targetCitizenId = "reporter",
        briefing = "目标：报社记者 小江。审查其对官方口径的真实态度。",
    },
}
