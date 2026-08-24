local Diagnostics = { providers = {} }

function Diagnostics.register(name, provider)
    assert(type(name) == "string" and name ~= "", "diagnostic provider name is required")
    assert(type(provider) == "function", "diagnostic provider must be a function")
    Diagnostics.providers[name] = provider
end

function Diagnostics.unregister(name)
    Diagnostics.providers[name] = nil
end

function Diagnostics.read(name)
    local provider = Diagnostics.providers[name]
    if not provider then return nil end
    local ok, value = pcall(provider)
    return ok and value or nil
end

function Diagnostics.clear()
    Diagnostics.providers = {}
end

return Diagnostics
