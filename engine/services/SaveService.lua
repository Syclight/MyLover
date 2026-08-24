local json = require("engine.utils.json")

local SaveService = {}
SaveService.__index = SaveService

local function defaultStorage()
    return love.filesystem
end

local function sanitizeSlot(slot)
    slot = tostring(slot or "")
    assert(slot:match("^[%w%._%-]+$"), "save slot may only contain letters, numbers, dot, underscore, or dash")
    return slot
end

local function joinPath(root, name)
    if root == "" then return name end
    return root .. "/" .. name
end

function SaveService.new(options)
    options = options or {}
    return setmetatable({
        root = options.root or "saves",
        version = options.version or 1,
        storage = options.storage or defaultStorage(),
    }, SaveService)
end

function SaveService:pathFor(slot)
    return joinPath(self.root, sanitizeSlot(slot) .. ".json")
end

function SaveService:save(slot, payload, metadata)
    assert(type(payload) == "table", "save payload must be a table")
    local storage = self.storage
    if self.root ~= "" and storage.createDirectory then storage.createDirectory(self.root) end
    local envelope = {
        version = self.version,
        savedAt = os.time(),
        metadata = metadata or {},
        payload = payload,
    }
    local content = json.encode(envelope)
    local ok, err = storage.write(self:pathFor(slot), content)
    if not ok then error("SaveService failed to write slot '" .. tostring(slot) .. "': " .. tostring(err), 2) end
    return envelope
end

function SaveService:load(slot)
    local path = self:pathFor(slot)
    local content = self.storage.read(path)
    if not content then return nil end
    local envelope = json.decode(content)
    if type(envelope) ~= "table" or type(envelope.payload) ~= "table" then
        error("SaveService invalid save file: " .. path, 2)
    end
    return envelope.payload, envelope
end

function SaveService:exists(slot)
    local info = self.storage.getInfo and self.storage.getInfo(self:pathFor(slot))
    return info ~= nil
end

function SaveService:delete(slot)
    if self.storage.remove then return self.storage.remove(self:pathFor(slot)) end
    return false
end

function SaveService:list()
    local items = {}
    if not self.storage.getDirectoryItems then return items end
    local names = self.storage.getDirectoryItems(self.root) or {}
    table.sort(names)
    for _, name in ipairs(names) do
        local slot = name:match("^(.*)%.json$")
        if slot then items[#items + 1] = slot end
    end
    return items
end

return SaveService
