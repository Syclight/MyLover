local SpriteSheet = require("engine.rendering.SpriteSheet")
local ResourceManager = require("engine.managers.ResourceManager")

local FRAME_W      = 40
local FRAME_H      = 40
local IMAGE_PATH   = "samples/musou/assets/images/musou_sprites.png"

local MusouSprites = {}
MusouSprites.FRAME_W      = FRAME_W
MusouSprites.FRAME_H      = FRAME_H
MusouSprites.SCALE_FACTOR = 2.2

function MusouSprites.createSheet()
    local key   = "musou_sprite_sheet"
    local image = ResourceManager:get(key, "scene")
    if not image then
        image = ResourceManager:loadImage(IMAGE_PATH, "scene", key)
    end
    return SpriteSheet.new(image, FRAME_W, FRAME_H)
end

return MusouSprites
