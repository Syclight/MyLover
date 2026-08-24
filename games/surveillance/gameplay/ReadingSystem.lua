local Books = require("games.surveillance.data.books")

local ReadingSystem = {}

function ReadingSystem.new()
    return { open = false, bookIndex = nil, page = 1 }
end

function ReadingSystem.openBook(state, item)
    if not item or item.icon ~= "book" then return false end
    state.open = true
    state.bookIndex = item.bookIndex or 1
    state.page = 1
    return true
end

function ReadingSystem.close(state)
    state.open = false
end

function ReadingSystem.pageCount(state)
    return #(Books.get(state.bookIndex).pages or {})
end

function ReadingSystem.turn(state, direction)
    if not state.open then return false end
    local count = math.max(1, ReadingSystem.pageCount(state))
    state.page = math.max(1, math.min(count, state.page + direction))
    return true
end

function ReadingSystem.keypressed(state, key)
    if not state.open then return false end
    if key == "escape" or key == "r" then
        ReadingSystem.close(state)
    elseif key == "left" or key == "a" or key == "pageup" then
        ReadingSystem.turn(state, -1)
    elseif key == "right" or key == "d" or key == "pagedown" or key == "space" then
        ReadingSystem.turn(state, 1)
    end
    return true
end

function ReadingSystem.wheelmoved(state, dy)
    if not state.open or dy == 0 then return false end
    return ReadingSystem.turn(state, dy < 0 and 1 or -1)
end

return ReadingSystem
