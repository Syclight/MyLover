-- 无状态单行输入框：缓冲(value)由调用方持有（这里是 sceneState.radio.input），
-- 字符录入/退格由 RadioLayer 在 textinput/keypressed 中处理，本组件只负责绘制。
local TextInput = {}

-- composition: 输入法合成串（拼字尚未上屏），以高亮+下划线显示，可省略
function TextInput.draw(font, label, value, x, y, w, composition)
    local h = font:getHeight() + 16
    local fh = font:getHeight()

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x, y, w, h, 5)
    love.graphics.setColor(0.4, 0.8, 0.6, 0.8)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 5)

    love.graphics.setFont(font)

    -- 提示标签
    love.graphics.setColor(0.6, 0.9, 0.7, 0.9)
    love.graphics.print(label, x + 10, y + 8)
    local labelW = font:getWidth(label)

    local textX = x + 10 + labelW + 4
    local textY = y + 8

    -- 已上屏内容
    local valueStr = value or ""
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(valueStr, textX, textY)
    local cursorX = textX + font:getWidth(valueStr)

    -- 输入法合成串：背景高亮 + 文字 + 下划线，提示"正在拼字、尚未确认"
    local comp = composition or ""
    if comp ~= "" then
        local compW = font:getWidth(comp)
        love.graphics.setColor(0.5, 0.9, 0.7, 0.22)
        love.graphics.rectangle("fill", cursorX, textY, compW, fh)
        love.graphics.setColor(0.75, 1, 0.88, 1)
        love.graphics.print(comp, cursorX, textY)
        love.graphics.setColor(0.5, 0.9, 0.7, 0.9)
        love.graphics.line(cursorX, textY + fh, cursorX + compW, textY + fh)
        cursorX = cursorX + compW
    end

    -- 闪烁光标
    local caret = (math.floor(love.timer.getTime() * 2) % 2 == 0) and "▋" or ""
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(caret, cursorX, textY)

    love.graphics.setColor(1, 1, 1, 1)
end

return TextInput
