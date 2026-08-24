-- Procedural sprite-sheet generator for Musou unit types.
-- Generates a Canvas atlas with 8 animation frames per unit type:
--   cols 0-3 : walk cycle  (walkPhase = col * π/2)
--   cols 4-7 : attack cycle (attackPhase = (col-4)/3  → sin peak at col 5-6)
-- All unit sprites face RIGHT (+x). Rotation is applied at draw time.
--
-- Usage: require("samples.musou.utils.MusouSpriteGen").generate()
-- Output: samples/musou/assets/images/musou_sprites.png

local FRAME_W  = 40
local FRAME_H  = 40
local NUM_COLS = 8
local NUM_ROWS = 6  -- one row per unit type

local MusouSpriteGen = {}
MusouSpriteGen.FRAME_W = FRAME_W
MusouSpriteGen.FRAME_H = FRAME_H

-- ── Color palette (matches UNIT_TYPES order) ──────────────────────────────
local C = {
    { 0.28, 0.58, 1.00 },  -- 1 warrior
    { 0.65, 0.90, 0.35 },  -- 2 spearman
    { 0.85, 0.62, 0.28 },  -- 3 knight
    { 0.45, 0.92, 0.68 },  -- 4 dualblade
    { 0.80, 0.28, 1.00 },  -- 5 mage
    { 0.55, 0.90, 0.28 },  -- 6 archer
}
local SKIN = { 0.92, 0.80, 0.67 }

-- ── Drawing helpers ────────────────────────────────────────────────────────
local function sc(c, factor, alpha)
    factor = factor or 1.0
    love.graphics.setColor(c[1] * factor, c[2] * factor, c[3] * factor, alpha or 1.0)
end

local function lw(w) love.graphics.setLineWidth(w or 1) end

local function helmet(cx, cy, r, c, alpha)
    sc(c, 0.72, alpha or 0.92)
    love.graphics.arc("fill", cx, cy, r, math.pi, math.pi * 2)
end

local function specular(cx, cy, r)
    love.graphics.setColor(1, 1, 1, 0.28)
    love.graphics.circle("fill", cx - r * 0.40, cy - r * 0.40, r * 0.32)
end

local function shadow(rx, ry)
    love.graphics.setColor(0, 0, 0, 0.28)
    love.graphics.ellipse("fill", 1.5, 3, rx, ry)
end

-- ── Per-unit draw functions ────────────────────────────────────────────────
-- Coordinates relative to frame center (0,0), unit always facing RIGHT.
-- walkPhase  : 0..2π
-- attackPhase: 0..1  (sin-bell: 0 → ramp up → peak 0.5 → ramp down → 1)
-- isAttack   : bool

-- 1 ── Warrior (blue): round shield + sword ──────────────────────────────
local function drawWarrior(walkPhase, attackPhase, isAttack)
    local c       = C[1]
    local bob     = isAttack and 0 or (math.sin(walkPhase) * 1.5)
    local legBob  = isAttack and 0 or (math.sin(walkPhase) * 3.2)
    local swordExt = isAttack and (math.sin(attackPhase * math.pi) * 9) or 0

    shadow(9, 4.5)

    sc(c, 0.38)
    love.graphics.ellipse("fill", -2,  bob + 7 + legBob, 3,   4)
    love.graphics.ellipse("fill",  3,  bob + 7 - legBob, 3,   4)

    sc(c, 0.52)
    love.graphics.ellipse("fill", -9, bob, 3.5, 6.5)
    sc(c, 0.85); lw(0.8)
    love.graphics.ellipse("line", -9, bob, 3.5, 6.5)
    lw(1)
    love.graphics.setColor(1, 1, 1, 0.55)
    lw(0.8)
    love.graphics.line(-9, bob - 3,  -9, bob + 3)
    love.graphics.line(-12, bob,     -6, bob)
    lw(1)

    love.graphics.setColor(0.86, 0.86, 0.94, 1)
    lw(2.5)
    love.graphics.line(5, bob, 5 + 9 + swordExt, bob)
    lw(1)
    love.graphics.setColor(0.72, 0.62, 0.28, 1)
    lw(2)
    love.graphics.line(5, bob - 2.5, 5, bob + 2.5)
    lw(1)

    sc(c, 0.42)
    love.graphics.circle("fill", 0, bob, 8.5)
    sc(c, 1.0)
    love.graphics.circle("fill", 0, bob, 7.5)
    specular(0, bob, 7.5)
    sc(c, 0.75, 0.7)
    lw(0.7)
    love.graphics.line(-3, bob - 5, 1, bob + 6)
    lw(1)

    love.graphics.setColor(SKIN[1], SKIN[2], SKIN[3], 1)
    love.graphics.circle("fill", 2, bob - 6, 4)
    helmet(2, bob - 6, 4, c)
    love.graphics.setColor(0, 0, 0, 0.62)
    lw(0.9)
    love.graphics.line(-1.2, bob - 6.8, 5.2, bob - 6.8)
    lw(1)
end

-- 2 ── Spearman (green): long spear + light armour ───────────────────────
local function drawSpearman(walkPhase, attackPhase, isAttack)
    local c      = C[2]
    local lunge  = isAttack and (math.sin(attackPhase * math.pi) * 3) or 0
    local bob    = isAttack and 0 or (math.sin(walkPhase) * 1.5)
    local legBob = isAttack and 0 or (math.sin(walkPhase) * 3.0)

    shadow(7, 3.5)

    love.graphics.setColor(0.56, 0.42, 0.18, 1)
    lw(1.8)
    love.graphics.line(lunge - 14, bob + 1, lunge + 15, bob + 1)
    lw(1)
    love.graphics.setColor(0.82, 0.84, 0.92, 1)
    love.graphics.polygon("fill",
        lunge + 15, bob + 1,
        lunge + 12, bob - 1.5,
        lunge + 19, bob + 1,
        lunge + 12, bob + 3.5)
    love.graphics.setColor(0.36, 0.26, 0.10, 1)
    lw(2)
    love.graphics.line(lunge - 14, bob + 1, lunge - 16, bob + 1)
    lw(1)

    sc(c, 0.40)
    love.graphics.ellipse("fill", lunge - 1.5, bob + 6.5 + legBob, 2.5, 3.5)
    love.graphics.ellipse("fill", lunge + 2,   bob + 6.5 - legBob, 2.5, 3.5)

    sc(c, 0.44)
    love.graphics.circle("fill", lunge, bob, 7)
    sc(c, 1.0)
    love.graphics.circle("fill", lunge, bob, 6)
    specular(lunge, bob, 6)

    love.graphics.setColor(SKIN[1], SKIN[2], SKIN[3], 1)
    love.graphics.circle("fill", lunge + 1.5, bob - 4.5, 3.5)
    helmet(lunge + 1.5, bob - 4.5, 3.5, c)
end

-- 3 ── Knight (orange): on horseback + lance ─────────────────────────────
local function drawKnight(walkPhase, attackPhase, isAttack)
    local c       = C[3]
    local hop     = isAttack and 0 or (math.sin(walkPhase) * 2.5)
    local hoofBob = isAttack and 0 or (math.sin(walkPhase) * 4)
    local lanceExt = isAttack and (math.sin(attackPhase * math.pi) * 3) or 0

    love.graphics.setColor(0, 0, 0, 0.30)
    love.graphics.ellipse("fill", 2, hop + 6, 14, 5.5)

    sc(c, 0.33)
    love.graphics.ellipse("fill", -8, hop + 7 + hoofBob, 3,   2.5)
    love.graphics.ellipse("fill",  7, hop + 7 - hoofBob, 3,   2.5)
    love.graphics.ellipse("fill", -4, hop + 9 - hoofBob, 3,   2.5)
    love.graphics.ellipse("fill",  4, hop + 9 + hoofBob, 3,   2.5)

    sc(c, 0.46)
    love.graphics.ellipse("fill", 0, hop + 2, 14, 9)
    sc(c, 1.0)
    love.graphics.ellipse("fill", 0, hop + 2, 13, 8)
    specular(0, hop + 2, 9)
    sc(c, 0.68)
    lw(2)
    love.graphics.line(5, hop - 2, 9, hop + 2)
    lw(1)

    love.graphics.setColor(0.55, 0.42, 0.18, 1)
    lw(2)
    love.graphics.line(lanceExt - 4, hop - 2, lanceExt + 15, hop - 10)
    lw(1)
    love.graphics.setColor(0.82, 0.84, 0.92, 1)
    love.graphics.polygon("fill",
        lanceExt + 15, hop - 10,
        lanceExt + 12, hop - 11.5,
        lanceExt + 19, hop - 10,
        lanceExt + 12, hop - 8.5)

    sc(c, 0.44)
    love.graphics.circle("fill", 0, hop - 4, 5.5)
    sc(c, 1.0)
    love.graphics.circle("fill", 0, hop - 4, 5)
    specular(0, hop - 4, 5)

    love.graphics.setColor(SKIN[1], SKIN[2], SKIN[3], 1)
    love.graphics.circle("fill", 1, hop - 9.5, 3.5)
    helmet(1, hop - 9.5, 3.5, c)
end

-- 4 ── Dualblade (cyan): two crossed daggers ─────────────────────────────
local function drawDualblade(walkPhase, attackPhase, isAttack)
    local c      = C[4]
    local bob    = isAttack and 0 or (math.sin(walkPhase) * 1.5)
    local legBob = isAttack and 0 or (math.sin(walkPhase) * 3.2)
    local spread = isAttack and (math.sin(attackPhase * math.pi) * 5) or 0

    shadow(6.5, 3)

    sc(c, 0.40)
    love.graphics.ellipse("fill", -1.5, bob + 6  + legBob, 2.5, 3.5)
    love.graphics.ellipse("fill",  2,   bob + 6  - legBob, 2.5, 3.5)

    love.graphics.setColor(0.86, 0.93, 0.99, 1)
    lw(2.2)
    love.graphics.line(-4, bob - 2 - spread, 10 + spread, bob + 4 + spread)
    lw(1)
    sc(c, 0.72)
    lw(1.8)
    love.graphics.line(-4, bob - 5, 0, bob - 1)
    lw(1)

    love.graphics.setColor(0.86, 0.93, 0.99, 1)
    lw(2.2)
    love.graphics.line(-4, bob + 2 + spread, 10 + spread, bob - 4 - spread)
    lw(1)
    sc(c, 0.72)
    lw(1.8)
    love.graphics.line(-4, bob + 5, 0, bob + 1)
    lw(1)

    sc(c, 0.44)
    love.graphics.circle("fill", 0, bob, 6.5)
    sc(c, 1.0)
    love.graphics.circle("fill", 0, bob, 5.5)
    specular(0, bob, 5.5)

    love.graphics.setColor(SKIN[1], SKIN[2], SKIN[3], 1)
    love.graphics.circle("fill", 1.5, bob - 4.5, 3.5)
    helmet(1.5, bob - 4.5, 3.5, c)
end

-- 5 ── Mage (purple): staff + glowing orb ────────────────────────────────
local function drawMage(walkPhase, attackPhase, isAttack)
    local c        = C[5]
    local hover    = isAttack and 0 or (math.sin(walkPhase) * 1.2)
    local orbR     = 2.5 + (isAttack and (math.sin(attackPhase * math.pi) * 4) or 0)
    local orbGlow  = isAttack and math.sin(attackPhase * math.pi) or 0

    shadow(7, 3.5)

    sc(c, 0.38)
    love.graphics.polygon("fill",
        -4, hover,
         4, hover,
         6, hover + 10,
        -6, hover + 10)
    sc(c, 0.62)
    love.graphics.polygon("fill",
        -3, hover,
         3, hover,
         4.5, hover + 9,
        -4.5, hover + 9)
    love.graphics.setColor(1, 1, 1, 0.12)
    lw(0.8)
    love.graphics.line(-0.5, hover + 0.5, 0.5, hover + 8)
    lw(1)

    love.graphics.setColor(0.60, 0.46, 0.20, 1)
    lw(2)
    love.graphics.line(-1, hover - 5, 11, hover - 14)
    lw(1)

    if orbGlow > 0.04 then
        sc(c, 1.1, orbGlow * 0.38)
        love.graphics.circle("fill", 11, hover - 14, orbR + 4)
    end
    sc(c, 0.42)
    love.graphics.circle("fill", 11, hover - 14, orbR + 1.5)
    sc(c, 1.2)
    love.graphics.circle("fill", 11, hover - 14, orbR)
    love.graphics.setColor(1, 1, 1, 0.60)
    love.graphics.circle("fill", 9.5, hover - 15.5, orbR * 0.38)

    sc(c, 0.40)
    love.graphics.circle("fill", 0, hover, 7)
    sc(c, 0.88)
    love.graphics.circle("fill", 0, hover, 6)
    specular(0, hover, 6)

    love.graphics.setColor(SKIN[1], SKIN[2], SKIN[3], 1)
    love.graphics.circle("fill", 1, hover - 5, 3.8)
    sc(c, 0.52, 0.88)
    love.graphics.arc("fill", 1, hover - 5, 3.8, math.pi * 0.85, math.pi * 2.15)
end

-- 6 ── Archer (yellow-green): bow + arrow ────────────────────────────────
local function drawArcher(walkPhase, attackPhase, isAttack)
    local c           = C[6]
    local bob         = isAttack and 0 or (math.sin(walkPhase) * 1.5)
    local legBob      = isAttack and 0 or (math.sin(walkPhase) * 3.0)
    local arrowAlpha  = isAttack and math.min(attackPhase * 2.5, 1.0) or 0

    shadow(7, 3.5)

    sc(c, 0.40)
    love.graphics.ellipse("fill", -1.5, bob + 6.5 + legBob, 2.5, 3.5)
    love.graphics.ellipse("fill",  2,   bob + 6.5 - legBob, 2.5, 3.5)

    love.graphics.setColor(0.50, 0.35, 0.12, 1)
    love.graphics.rectangle("fill", 4, bob - 5.5, 4, 9, 1, 1)
    love.graphics.setColor(0.72, 0.55, 0.22, 0.85)
    lw(0.8)
    love.graphics.line(5.5, bob - 5.5, 5.5, bob)
    love.graphics.line(6.5, bob - 6.5, 6.5, bob)
    lw(1)

    sc(c, 0.58)
    lw(1.8)
    love.graphics.line(9, bob - 7, 4, bob)
    love.graphics.line(4, bob,     9, bob + 7)
    lw(1)
    love.graphics.setColor(0.90, 0.88, 0.78, 0.80)
    lw(0.8)
    love.graphics.line(9, bob - 7, 9, bob + 7)
    lw(1)

    if arrowAlpha > 0 then
        love.graphics.setColor(0.72, 0.55, 0.22, arrowAlpha)
        lw(1.2)
        love.graphics.line(9, bob, 18, bob)
        lw(1)
        love.graphics.setColor(0.88, 0.88, 0.82, arrowAlpha)
        love.graphics.polygon("fill", 18, bob, 15.5, bob - 1.5, 15.5, bob + 1.5)
    end

    sc(c, 0.44)
    love.graphics.circle("fill", -1, bob, 7)
    sc(c, 1.0)
    love.graphics.circle("fill", -1, bob, 6)
    specular(-1, bob, 6)

    love.graphics.setColor(SKIN[1], SKIN[2], SKIN[3], 1)
    love.graphics.circle("fill", 1, bob - 5, 3.5)
    helmet(1, bob - 5, 3.5, c)
end

-- ── Ordered draw-function table (matches UNIT_TYPES indices) ──────────────
local unitDrawers = {
    drawWarrior,
    drawSpearman,
    drawKnight,
    drawDualblade,
    drawMage,
    drawArcher,
}

-- ── Save canvas as PNG to this sample's asset directory ──────────────────
local function saveSheetPNG(canvas)
    local imgData = canvas:newImageData()
    local fd      = imgData:encode("png")
    imgData:release()

    local srcDir = love.filesystem.getSource()
    if srcDir == "" then srcDir = "." end
    srcDir = srcDir:gsub("\\", "/")
    local outPath = srcDir .. "/samples/musou/assets/images/musou_sprites.png"

    local f = io.open(outPath, "wb")
    if f then
        f:write(fd:getString())
        f:close()
        print("[MusouSpriteGen] sprite sheet saved → " .. outPath)
    else
        print("[MusouSpriteGen] WARNING: cannot write to " .. outPath)
    end
end

-- ── Public API ─────────────────────────────────────────────────────────────

-- Render all frames onto a canvas, save to the Musou sample asset directory,
-- and return the canvas. Call this once during development or asset build.
function MusouSpriteGen.generate()
    local sheetW = NUM_COLS * FRAME_W
    local sheetH = NUM_ROWS * FRAME_H
    local canvas = love.graphics.newCanvas(sheetW, sheetH)
    canvas:setFilter("linear", "linear")

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    for typeIdx = 1, NUM_ROWS do
        for col = 0, NUM_COLS - 1 do
            local cx = col * FRAME_W + FRAME_W * 0.5
            local cy = (typeIdx - 1) * FRAME_H + FRAME_H * 0.5

            local isAttack = col >= 4
            local walkPhase, attackPhase
            if isAttack then
                walkPhase   = 0
                attackPhase = (col - 4) / 3.0
            else
                walkPhase   = col * math.pi * 0.5
                attackPhase = 0
            end

            love.graphics.push("all")
            love.graphics.translate(cx, cy)
            unitDrawers[typeIdx](walkPhase, attackPhase, isAttack)
            love.graphics.pop()
        end
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)

    saveSheetPNG(canvas)
    canvas:release()
end

return MusouSpriteGen
