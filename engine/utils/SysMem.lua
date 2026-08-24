-- 通过 LuaJIT FFI 读取 Windows 的"系统内存压力 / 本进程内存 / 缺页计数"。
-- 这是判断"卡顿是不是内存不够导致换页"的关键数据——LÖVE 自身只暴露 Lua 堆
-- (collectgarbage)和 GPU 贴图显存(love.graphics.getStats),拿不到操作系统层面的
-- 物理内存占用与缺页(page fault),所以这里直接调 kernel32。
--
-- 设计:全程 pcall 包裹 + 懒加载;非 Windows 或调用失败时返回 { ok = false },
-- 调用方据此降级显示(不崩溃、不打断游戏)。不缓存数值由调用方按采样间隔自行控制。
local SysMem = {}

local ok_ffi, ffi = pcall(require, "ffi")

local kernel32 = nil
local memStatus = nil   -- 复用的 MEMORYSTATUSEX 结构体,避免每次分配
local procCounters = nil -- 复用的 PROCESS_MEMORY_COUNTERS 结构体
local initialized = false
local available = false

local BYTES_PER_MB = 1024 * 1024

local function tryInit()
    if initialized then return end
    initialized = true
    if not ok_ffi or ffi.os ~= "Windows" then
        available = false
        return
    end

    local ok = pcall(function()
        ffi.cdef([[
            typedef struct {
                uint32_t dwLength;
                uint32_t dwMemoryLoad;
                uint64_t ullTotalPhys;
                uint64_t ullAvailPhys;
                uint64_t ullTotalPageFile;
                uint64_t ullAvailPageFile;
                uint64_t ullTotalVirtual;
                uint64_t ullAvailVirtual;
                uint64_t ullAvailExtendedVirtual;
            } MEMORYSTATUSEX;

            typedef struct {
                uint32_t cb;
                uint32_t PageFaultCount;
                size_t   PeakWorkingSetSize;
                size_t   WorkingSetSize;
                size_t   QuotaPeakPagedPoolUsage;
                size_t   QuotaPagedPoolUsage;
                size_t   QuotaPeakNonPagedPoolUsage;
                size_t   QuotaNonPagedPoolUsage;
                size_t   PagefileUsage;
                size_t   PeakPagefileUsage;
            } PROCESS_MEMORY_COUNTERS;

            int  GlobalMemoryStatusEx(MEMORYSTATUSEX* lpBuffer);
            void* GetCurrentProcess(void);
            int  K32GetProcessMemoryInfo(void* Process, PROCESS_MEMORY_COUNTERS* ppsmemCounters, uint32_t cb);
        ]])
        kernel32 = ffi.load("kernel32")
        memStatus = ffi.new("MEMORYSTATUSEX")
        procCounters = ffi.new("PROCESS_MEMORY_COUNTERS")
    end)
    available = ok and kernel32 ~= nil
end

-- 返回一份快照(单位均为 MB,缺页为累计计数):
--   { ok=true, loadPct, totalMB, availMB, usedMB, processMB, pageFaults }
-- 失败 / 非 Windows:{ ok=false }
function SysMem.query()
    tryInit()
    if not available then return { ok = false } end

    local result = { ok = true }
    local ok = pcall(function()
        memStatus.dwLength = ffi.sizeof("MEMORYSTATUSEX")
        if kernel32.GlobalMemoryStatusEx(memStatus) ~= 0 then
            local total = tonumber(memStatus.ullTotalPhys)
            local avail = tonumber(memStatus.ullAvailPhys)
            result.loadPct = tonumber(memStatus.dwMemoryLoad)
            result.totalMB = total / BYTES_PER_MB
            result.availMB = avail / BYTES_PER_MB
            result.usedMB = (total - avail) / BYTES_PER_MB
        end

        procCounters.cb = ffi.sizeof("PROCESS_MEMORY_COUNTERS")
        local handle = kernel32.GetCurrentProcess()
        if kernel32.K32GetProcessMemoryInfo(handle, procCounters, procCounters.cb) ~= 0 then
            -- 工作集:本进程当前占用的物理内存(可能含与其它程序共享的 DLL 等页)。
            result.processMB = tonumber(procCounters.WorkingSetSize) / BYTES_PER_MB
            -- 私有提交:仅属本进程、不与他人共享的已提交内存(≈任务管理器"提交大小")。
            -- 这是"纯本项目"最准的单一指标。
            result.privateMB = tonumber(procCounters.PagefileUsage) / BYTES_PER_MB
            result.pageFaults = tonumber(procCounters.PageFaultCount)
        end
    end)

    if not ok then return { ok = false } end
    return result
end

function SysMem.isAvailable()
    tryInit()
    return available
end

return SysMem
