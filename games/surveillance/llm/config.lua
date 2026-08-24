-- games/surveillance/llm/config.lua
-- LLM 管线默认配置 —— 集中一处，方便整体替换后端/模型。
--
-- 模型名是占位默认值：请改成你本地 `ollama pull <model>` 实际拉取的模型名。
-- 游戏只提供运行配置；线程、流式传输与后端契约由 Engine LLMService 管理。
return {
    host = "http://localhost:11434", -- Ollama 默认监听地址
    model = "qwen3.5:2b",            -- TODO: 占位，替换为你本地已有的模型名
    backendModule = "engine.services.llm.backends.OllamaBackend",
    think = false,                   -- 关闭推理模型的思考过程（NPC 直接作答，更快、内容不为空）
    options = {
        temperature = 0.8,
        num_predict = 256,           -- 单次回复最大 token，控制延迟
    },
}
