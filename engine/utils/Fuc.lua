local function safeSend(shader, name, value, ...)
    if shader:hasUniform(name) then
        shader:send(name, value, ...)
    end
end

return {
    safeSend = safeSend
}