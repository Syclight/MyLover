-- 私人通讯并不是全天持续发生。每条线路定义双方较可能联络的时段，
-- 以及日常闲谈与剧情线索的话题池。时间以当天分钟数表示。
return {
    {
        id = "ch1", freq = "118.4", a = "doctor", b = "teacher",
        windows = {
            { start = 6 * 60 + 35, finish = 7 * 60 + 25, activity = "上班和早自习前的短暂联络" },
            { start = 19 * 60 + 30, finish = 21 * 60 + 20, activity = "下班后的私人通话" },
        },
        mundaneTopics = { "早餐和胃药", "今天的天气", "学校值班安排", "医院食堂", "楼道里的噪声" },
        clueTopics = { "医院药品账目出现的缺口", "学生作文里反复出现的失踪者", "昨夜没有登记的急诊病人" },
    },
    {
        id = "ch2", freq = "127.2", a = "driver", b = "reporter",
        windows = {
            { start = 17 * 60 + 30, finish = 19 * 60, activity = "晚班交接时的路况联络" },
            { start = 22 * 60, finish = 23 * 60 + 45, activity = "末班车结束后的低声通话" },
        },
        mundaneTopics = { "堵车和绕行", "车上的失物", "晚饭吃什么", "汽油配给", "收音机信号" },
        clueTopics = { "一辆没有牌照的黑色轿车", "封锁路段里运出的箱子", "记者被人跟踪的迹象" },
    },
    {
        id = "ch3", freq = "134.5", a = "worker", b = "grocer",
        windows = {
            { start = 6 * 60, finish = 7 * 60 + 5, activity = "开工和开店前确认物资" },
            { start = 18 * 60, finish = 20 * 60 + 30, activity = "收工后的采购联络" },
        },
        mundaneTopics = { "面包和肥皂的价格", "工厂换班", "赊账", "坏掉的水管", "邻居家的猫" },
        clueTopics = { "仓库里来源不明的额外配给", "工厂夜班封闭的旧车间", "被撕掉编号的货运单" },
    },
    {
        id = "ch4", freq = "121.7", a = "teacher", b = "grocer",
        windows = {
            { start = 12 * 60, finish = 13 * 60 + 20, activity = "午休时询问生活用品" },
            { start = 17 * 60 + 20, finish = 19 * 60, activity = "放学后的采购通话" },
        },
        mundaneTopics = { "粉笔和练习本", "蔬菜是否新鲜", "学生午餐", "零钱", "周末营业时间" },
        clueTopics = { "被学校收走的一批旧课本", "有学生突然从名册消失", "商店后门收到的匿名纸条" },
    },
    {
        id = "ch5", freq = "139.9", a = "reporter", b = "doctor",
        windows = {
            { start = 8 * 60, finish = 9 * 60, activity = "上班前确认采访与门诊安排" },
            { start = 20 * 60 + 30, finish = 22 * 60, activity = "夜间交换近况" },
        },
        mundaneTopics = { "预约时间", "咖啡", "报社加班", "感冒症状", "一篇无聊的社区稿" },
        clueTopics = { "伤者身上相同的无名针孔", "被禁止刊登的死亡数字", "医院地下层的夜间车辆" },
    },
}
