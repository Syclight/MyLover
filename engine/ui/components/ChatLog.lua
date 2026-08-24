-- 截获/对话日志：滚动显示条目，支持未完成条目逐字增长（流式）。
-- 支持滚动：scrollFromBottom = 从底部向上滚动的像素（0 = 贴底显示最新）。
-- 绘制滚动条，并返回 { contentH, innerH, maxScroll } 供调用方管理滚动状态。
local ChatLog = {}

local COLORS = {
    npc = { 0.85, 0.95, 1.0 },
    operator = { 1.0, 0.85, 0.4 },
    system = { 0.6, 0.9, 0.7 },
}

local SCROLLBAR_W = 8

function ChatLog.draw(font, transcript, x, y, w, h, scrollFromBottom)
    scrollFromBottom = scrollFromBottom or 0

    -- 背景与边框
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", x, y, w, h, 6)
    love.graphics.setColor(0.4, 0.6, 0.5, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 6)
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setFont(font)
    local pad = 12
    local innerW = w - pad * 2 - SCROLLBAR_W - 4
    local lineH = font:getHeight() + 2

    -- 预计算各条目布局与总高
    local blocks = {}
    local totalH = 0
    for _, e in ipairs(transcript) do
        local header
        if e.kind == "operator" then
            header = "◀ 监听员 注入"
        elseif e.kind == "system" then
            header = e.speaker or "系统"
        else
            header = (e.speaker or "?") .. " [" .. (e.profession or "") .. "]"
        end

        local body = e.text or ""
        if not e.done and e.kind ~= "operator" and e.kind ~= "system" then
            body = body .. " ▋"
        end

        local _, wrapped = font:getWrap(body, innerW)
        local nLines = math.max(#wrapped, 1)
        blocks[#blocks + 1] = { e = e, header = header, body = body, lines = nLines }
        totalH = totalH + lineH + nLines * lineH + 8
    end

    local innerH = h - pad * 2
    local maxScroll = math.max(0, totalH - innerH)
    scrollFromBottom = math.max(0, math.min(scrollFromBottom, maxScroll))

    local startY
    if totalH <= innerH then
        startY = y + pad
    else
        startY = (y + h - pad) - totalH + scrollFromBottom
    end

    love.graphics.setScissor(x, y, w, h)
    local cy = startY
    for _, b in ipairs(blocks) do
        local col = COLORS[b.e.kind] or COLORS.npc
        love.graphics.setColor(col[1], col[2], col[3], 0.65)
        love.graphics.print(b.header, x + pad, cy)
        cy = cy + lineH
        love.graphics.setColor(col[1], col[2], col[3], 1)
        love.graphics.printf(b.body, x + pad, cy, innerW, "left")
        cy = cy + b.lines * lineH + 8
    end
    love.graphics.setScissor()

    -- 滚动条
    if maxScroll > 0 then
        local trackX = x + w - pad - SCROLLBAR_W + 2
        local trackY = y + pad
        local trackH = innerH
        love.graphics.setColor(1, 1, 1, 0.08)
        love.graphics.rectangle("fill", trackX, trackY, SCROLLBAR_W, trackH, 3)
        local thumbH = math.max(24, trackH * (innerH / totalH))
        local frac = scrollFromBottom / maxScroll -- 0=底部, 1=顶部
        local thumbY = trackY + (1.0 - frac) * (trackH - thumbH)
        love.graphics.setColor(0.5, 0.9, 0.7, 0.6)
        love.graphics.rectangle("fill", trackX, thumbY, SCROLLBAR_W, thumbH, 3)
        love.graphics.setColor(1, 1, 1, 1)
    end

    return { contentH = totalH, innerH = innerH, maxScroll = maxScroll }
end

return ChatLog
