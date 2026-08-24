-- 简易 GLSL #include 预处理器。LÖVE 的 GLSL 没有 include，公共函数只能
-- 复制粘贴——这里在 newShader 之前做一次纯文本展开，让 shader 源码可以写：
--
--   #include "engine/assets/shaders/include/lighting.glsl"
--
-- 规则（刻意保持简单，不做完整 C 预处理器）：
--  * 只识别独占一行的 #include "路径"（双引号，行内注释都不允许）。
--  * 路径两级解析：先相对"包含方所在目录"，再相对工程根（love.filesystem）。
--  * 同一文件在一次展开中只包含一次（#pragma once 语义）——公共库互相引用
--    不会展开出重复定义。
--  * 包含环直接报错（附带完整包含链，便于定位）。
--  * 展开处插入 begin/end 注释标记：GLSL 编译错误的行号会落在展开后的源码上，
--    标记让你能对回原始文件。
--
-- 入口：process(source, baseDir)。无 #include 的源码原样返回（零成本透传），
-- 所以 ResourceManager 对所有 shader 统一走这里是安全的。
local ShaderPreprocessor = {}

local INCLUDE_PATTERN = '^%s*#include%s+"([^"]+)"%s*$'

local function dirname(path)
    return path and path:match("^(.*)/[^/]+$") or nil
end

local function resolvePath(includePath, baseDir)
    if baseDir then
        local relative = baseDir .. "/" .. includePath
        if love.filesystem.getInfo(relative) then return relative end
    end
    if love.filesystem.getInfo(includePath) then return includePath end
    return nil
end

local function describeChain(stack)
    return table.concat(stack, " -> ")
end

-- included：本次展开已包含过的文件集合（once 语义）
-- stack：当前包含链（环检测 + 报错信息）
local function expand(source, baseDir, included, stack, out)
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local includePath = line:match(INCLUDE_PATTERN)
        if not includePath then
            out[#out + 1] = line
        else
            local resolved = resolvePath(includePath, baseDir)
            if not resolved then
                error(('ShaderPreprocessor: cannot resolve #include "%s" (chain: %s)')
                    :format(includePath, describeChain(stack)))
            end
            for _, ancestor in ipairs(stack) do
                if ancestor == resolved then
                    error(('ShaderPreprocessor: circular #include "%s" (chain: %s)')
                        :format(resolved, describeChain(stack)))
                end
            end
            if included[resolved] then
                out[#out + 1] = "// include skipped (already included): " .. resolved
            else
                included[resolved] = true
                local content, err = love.filesystem.read(resolved)
                if not content then
                    error(('ShaderPreprocessor: cannot read "%s": %s'):format(resolved, tostring(err)))
                end
                out[#out + 1] = "// ==== begin include: " .. resolved .. " ===="
                stack[#stack + 1] = resolved
                expand(content, dirname(resolved), included, stack, out)
                stack[#stack] = nil
                out[#out + 1] = "// ==== end include: " .. resolved .. " ===="
            end
        end
    end
end

-- 展开 source 中的 #include。baseDir 是"包含方所在目录"（可 nil，则只按工程根解析），
-- origin 仅用于报错信息（如文件路径或模块名）。
function ShaderPreprocessor.process(source, baseDir, origin)
    assert(type(source) == "string", "ShaderPreprocessor.process expects shader source text")
    if not source:find("#include", 1, true) then return source end
    local out = {}
    expand(source, baseDir, {}, { origin or "<source>" }, out)
    return table.concat(out, "\n")
end

-- 便捷入口：读文件并展开（baseDir 取文件所在目录）
function ShaderPreprocessor.processFile(path)
    local content, err = love.filesystem.read(path)
    if not content then
        error(('ShaderPreprocessor: cannot read "%s": %s'):format(path, tostring(err)))
    end
    return ShaderPreprocessor.process(content, dirname(path), path)
end

-- 模块路径（"a.b.c"）→ 所在目录（"a/b"），供 shader 的 .lua 模块模式解析相对 include
function ShaderPreprocessor.moduleDir(moduleName)
    return dirname((moduleName:gsub("%.", "/")))
end

return ShaderPreprocessor
