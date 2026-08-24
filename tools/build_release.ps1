[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target,
    [string]$Name,
    [string]$Version = "1.0.0",
    [string]$OutputDirectory = "dist",
    [string]$LovePath,
    [string]$Icon,
    [switch]$List,
    [switch]$SkipArchive,
    [switch]$KeepLove,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Get-ReleaseTargets {
    $result = @()
    foreach ($kind in @("games", "samples")) {
        $kindRoot = Join-Path $projectRoot $kind
        if (-not (Test-Path -LiteralPath $kindRoot -PathType Container)) { continue }
        foreach ($folder in Get-ChildItem -LiteralPath $kindRoot -Directory) {
            if (Test-Path -LiteralPath (Join-Path $folder.FullName "Game.lua") -PathType Leaf) {
                $result += [PSCustomObject]@{
                    Id = "$kind/$($folder.Name)"
                    Module = "$kind.$($folder.Name).Game"
                    Kind = $kind
                    Folder = $folder.Name
                    Path = $folder.FullName
                }
            }
        }
    }
    return @($result | Sort-Object Id)
}

function Resolve-ReleaseTarget([string]$value, [object[]]$targets) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "请使用 -Target 指定游戏，例如：games/nagashino。用 -List 查看全部目标。"
    }
    $normalized = $value.Replace("\", "/").Trim("/")
    $moduleValue = $normalized.Replace("/", ".")
    $matches = @($targets | Where-Object {
        $_.Id -ieq $normalized -or $_.Module -ieq $moduleValue -or
        "$($_.Kind).$($_.Folder)" -ieq $moduleValue -or $_.Folder -ieq $normalized
    })
    if ($matches.Count -eq 0) { throw "未知目标 '$value'。用 -List 查看可用目标。" }
    if ($matches.Count -gt 1) {
        throw "目标 '$value' 不唯一：$($matches.Id -join ', ')。请指定完整目标。"
    }
    return $matches[0]
}

function Resolve-LoveExecutable([string]$value) {
    $candidates = @()
    if ($value) {
        $expanded = [IO.Path]::GetFullPath($value)
        if (Test-Path -LiteralPath $expanded -PathType Container) {
            $candidates += (Join-Path $expanded "love.exe")
        } else {
            $candidates += $expanded
        }
    }
    $command = Get-Command love.exe -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $candidates += @(
        "D:\Softwares\LOVE\love.exe",
        "$env:ProgramFiles\LOVE\love.exe",
        "${env:ProgramFiles(x86)}\LOVE\love.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw "找不到 love.exe。请安装 LÖVE，或通过 -LovePath 指定 love.exe/安装目录。"
}

function Test-ReleaseFile([string]$relativePath, [string]$sourcePath) {
    $path = $relativePath.Replace("\", "/")
    $segments = $path.Split("/")
    foreach ($segment in $segments) {
        if ($segment -in @(".git", ".github", ".vscode", ".claude", ".agents", ".codex", "tests", "test", "tools", "source", "docs", "editor", "__pycache__")) {
            return $false
        }
    }
    if ($path -in @("engine/layers/DebugLayer.lua", "engine/utils/SysMem.lua")) { return $false }
    if ($path -match "(^|/)(test-report|smoke-report)\.tmp$") { return $false }
    if ($path -match "\.(blend|blend1|psd|kra|xcf|py|js|map|pdb)$") { return $false }
    # Compiled .mesh files are the release representation; retain OBJ/MTL only
    # when no compiled sibling exists and runtime fallback is actually needed.
    if ($sourcePath -and $path -match "\.(obj|mtl)$") {
        $compiled = [IO.Path]::ChangeExtension($sourcePath, ".mesh")
        if (Test-Path -LiteralPath $compiled -PathType Leaf) { return $false }
    }
    return $true
}

function Copy-ReleaseTree([string]$sourceRoot, [string]$relativeRoot, [string]$stageRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File) {
        $inside = $file.FullName.Substring($sourceRoot.Length).TrimStart("\", "/")
        $relative = if ($relativeRoot) { "$relativeRoot/$($inside.Replace('\', '/'))" } else { $inside.Replace("\", "/") }
        if (-not (Test-ReleaseFile $relative $file.FullName)) { continue }
        $destination = Join-Path $stageRoot $relative
        $parent = Split-Path -Parent $destination
        [IO.Directory]::CreateDirectory($parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}

function Get-PackageDependencies([object]$selected) {
    $dependencies = @{$selected.Id = $selected}
    $pending = [Collections.Generic.Queue[object]]::new()
    $pending.Enqueue($selected)
    $allTargets = Get-ReleaseTargets
    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        foreach ($file in Get-ChildItem -LiteralPath $current.Path -Recurse -File -Include *.lua,*.glsl) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($candidate in $allTargets) {
                if ($dependencies.ContainsKey($candidate.Id)) { continue }
                $moduleToken = "$($candidate.Kind).$($candidate.Folder)."
                # Cross-package code/shader modules are real runtime dependencies.
                # Asset path strings are intentionally ignored: every package owns
                # its release assets, and transformed source paths can otherwise
                # pull large prototype folders into the build by mistake.
                if ($content.Contains($moduleToken)) {
                    $dependencies[$candidate.Id] = $candidate
                    $pending.Enqueue($candidate)
                }
            }
        }
    }
    return @($dependencies.Values | Sort-Object Id)
}

function ConvertTo-LuaString([string]$value) {
    return '"' + $value.Replace("\", "\\").Replace('"', '\"').Replace("`r", "\r").Replace("`n", "\n") + '"'
}

function New-ZipFromDirectory([string]$source, [string]$destination) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
    $fileStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
            $relative = $file.FullName.Substring($source.Length).TrimStart("\", "/").Replace("\", "/")
            $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            $input = [IO.File]::OpenRead($file.FullName)
            try { $input.CopyTo($entryStream) } finally {
                $input.Dispose()
                $entryStream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
        $fileStream.Dispose()
    }
}

function Join-BinaryFiles([string]$first, [string]$second, [string]$destination) {
    $output = [IO.File]::Create($destination)
    try {
        foreach ($inputPath in @($first, $second)) {
            $input = [IO.File]::OpenRead($inputPath)
            try { $input.CopyTo($output) } finally { $input.Dispose() }
        }
    } finally { $output.Dispose() }
}

function Set-ExecutableIcon([string]$executablePath, [string]$iconPath) {
    if (-not ("ReleaseIconNative" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ReleaseIconNative
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr BeginUpdateResource(string fileName, bool deleteExistingResources);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UpdateResource(
        IntPtr update, IntPtr type, IntPtr name, ushort language,
        byte[] data, uint dataSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EndUpdateResource(IntPtr update, bool discard);
}
'@
    }

    # ICO: ICONDIR followed by ICONDIRENTRY records and raw image payloads.
    $stream = [IO.File]::OpenRead($iconPath)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        $reserved = $reader.ReadUInt16()
        $type = $reader.ReadUInt16()
        $count = $reader.ReadUInt16()
        if ($reserved -ne 0 -or $type -ne 1 -or $count -lt 1) {
            throw "不是有效的 Windows ICO 文件：$iconPath"
        }

        $entries = @()
        for ($index = 0; $index -lt $count; $index++) {
            $entries += [PSCustomObject]@{
                Width = $reader.ReadByte()
                Height = $reader.ReadByte()
                ColorCount = $reader.ReadByte()
                Reserved = $reader.ReadByte()
                Planes = $reader.ReadUInt16()
                BitCount = $reader.ReadUInt16()
                Size = $reader.ReadUInt32()
                Offset = $reader.ReadUInt32()
                ResourceId = [UInt16]($index + 1)
            }
        }

        foreach ($entry in $entries) {
            if ([UInt64]$entry.Offset + [UInt64]$entry.Size -gt [UInt64]$stream.Length) {
                throw "ICO 图像数据越界：$iconPath"
            }
            $stream.Position = $entry.Offset
            $entry | Add-Member -NotePropertyName Data -NotePropertyValue $reader.ReadBytes([int]$entry.Size)
        }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }

    # GRPICONDIR has the ICO directory layout, but replaces each image offset
    # with the RT_ICON resource id stored in the executable.
    $groupStream = [IO.MemoryStream]::new()
    $groupWriter = [IO.BinaryWriter]::new($groupStream)
    try {
        $groupWriter.Write([UInt16]0)
        $groupWriter.Write([UInt16]1)
        $groupWriter.Write([UInt16]$entries.Count)
        foreach ($entry in $entries) {
            $groupWriter.Write([Byte]$entry.Width)
            $groupWriter.Write([Byte]$entry.Height)
            $groupWriter.Write([Byte]$entry.ColorCount)
            $groupWriter.Write([Byte]$entry.Reserved)
            $groupWriter.Write([UInt16]$entry.Planes)
            $groupWriter.Write([UInt16]$entry.BitCount)
            $groupWriter.Write([UInt32]$entry.Size)
            $groupWriter.Write([UInt16]$entry.ResourceId)
        }
        $groupWriter.Flush()
        $groupData = $groupStream.ToArray()
    } finally {
        $groupWriter.Dispose()
        $groupStream.Dispose()
    }

    $handle = [ReleaseIconNative]::BeginUpdateResource($executablePath, $false)
    if ($handle -eq [IntPtr]::Zero) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }

    $committed = $false
    try {
        foreach ($entry in $entries) {
            $ok = [ReleaseIconNative]::UpdateResource(
                $handle, [IntPtr]3, [IntPtr]$entry.ResourceId, 0,
                $entry.Data, [UInt32]$entry.Data.Length)
            if (-not $ok) {
                throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }
        }
        $ok = [ReleaseIconNative]::UpdateResource(
            $handle, [IntPtr]14, [IntPtr]1, 0, $groupData, [UInt32]$groupData.Length)
        if (-not $ok) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        if (-not [ReleaseIconNative]::EndUpdateResource($handle, $false)) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        $committed = $true
    } finally {
        if (-not $committed) { [void][ReleaseIconNative]::EndUpdateResource($handle, $true) }
    }
}

$targets = Get-ReleaseTargets
if ($List) {
    $targets | Format-Table @{Label="目标"; Expression={$_.Id}}, @{Label="Lua 模块"; Expression={$_.Module}} -AutoSize
    exit 0
}

$selected = Resolve-ReleaseTarget $Target $targets
$loveExe = Resolve-LoveExecutable $LovePath
$loveDir = Split-Path -Parent $loveExe
if (-not $Name) { $Name = $selected.Folder }
if ($Name -notmatch '^[^\\/:*?"<>|]+$') { throw "-Name 含有 Windows 文件名不允许的字符。" }
$iconPath = $null
if ($Icon) {
    $iconPath = [IO.Path]::GetFullPath($Icon)
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { throw "图标不存在：$iconPath" }
    if ([IO.Path]::GetExtension($iconPath) -ine ".ico") { throw "-Icon 仅支持 Windows .ico 文件。" }
}

$outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    [IO.Path]::GetFullPath($OutputDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
}
$packageDir = Join-Path $outputRoot $Name
$stageDir = Join-Path $outputRoot ".$Name-stage"
$iconBaseExe = Join-Path $outputRoot ".$Name-icon-base.exe"
$loveArchive = Join-Path $outputRoot "$Name.love"
$zipArchive = Join-Path $outputRoot "$Name-$Version-windows-x64.zip"

if ((Test-Path -LiteralPath $packageDir) -and -not $Force) {
    throw "输出目录已存在：$packageDir。确认覆盖时添加 -Force。"
}
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
foreach ($old in @($stageDir, $packageDir, $iconBaseExe)) {
    if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
}
[IO.Directory]::CreateDirectory($stageDir) | Out-Null
[IO.Directory]::CreateDirectory($packageDir) | Out-Null

try {
    Copy-ReleaseTree (Join-Path $projectRoot "engine") "engine" $stageDir
    if (Test-Path -LiteralPath (Join-Path $projectRoot "libs")) {
        Copy-ReleaseTree (Join-Path $projectRoot "libs") "libs" $stageDir
    }
    $dependencies = Get-PackageDependencies $selected
    foreach ($dependency in $dependencies) {
        Copy-ReleaseTree $dependency.Path $dependency.Id $stageDir
    }
    foreach ($rootFile in @("conf.lua", "copyright.txt")) {
        $source = Join-Path $projectRoot $rootFile
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $stageDir $rootFile) -Force
        }
    }

    $builtAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $projectLua = @"
return {
    name = $(ConvertTo-LuaString $Name),
    game = $(ConvertTo-LuaString $selected.Module),
    globalManifest = "engine/assets/manifest/global.lua",
    debugOverlay = false,
    release = true,
    version = $(ConvertTo-LuaString $Version),
}
"@
    $mainLua = 'require("engine.Engine").install(require("project"))' + "`n"
    $releaseLua = @"
return {
    target = $(ConvertTo-LuaString $selected.Id),
    version = $(ConvertTo-LuaString $Version),
    builtAt = $(ConvertTo-LuaString $builtAt),
}
"@
    [IO.File]::WriteAllText((Join-Path $stageDir "project.lua"), $projectLua, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stageDir "main.lua"), $mainLua, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stageDir "release.lua"), $releaseLua, [Text.UTF8Encoding]::new($false))

    New-ZipFromDirectory $stageDir $loveArchive
    $exePath = Join-Path $packageDir "$Name.exe"
    $fusionBaseExe = $loveExe
    if ($iconPath) {
        # UpdateResource rewrites the PE and discards appended overlay data, so
        # customize a temporary base executable before fusing the .love archive.
        Copy-Item -LiteralPath $loveExe -Destination $iconBaseExe -Force
        Set-ExecutableIcon $iconBaseExe $iconPath
        $fusionBaseExe = $iconBaseExe
        Write-Host "  图标: $iconPath"
    }
    Join-BinaryFiles $fusionBaseExe $loveArchive $exePath

    $runtimePatterns = @("*.dll", "license.txt")
    foreach ($pattern in $runtimePatterns) {
        foreach ($file in Get-ChildItem -LiteralPath $loveDir -Filter $pattern -File) {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $packageDir $file.Name) -Force
        }
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot "copyright.txt") -Destination (Join-Path $packageDir "copyright.txt") -Force -ErrorAction SilentlyContinue

    if (-not $SkipArchive) { New-ZipFromDirectory $packageDir $zipArchive }
    if (-not $KeepLove) { Remove-Item -LiteralPath $loveArchive -Force }

    $sizeMb = [math]::Round((Get-Item -LiteralPath $exePath).Length / 1MB, 2)
    Write-Host "发行版构建完成" -ForegroundColor Green
    Write-Host "  目标: $($selected.Id) -> $($selected.Module)"
    Write-Host "  EXE : $exePath ($sizeMb MB)"
    if (-not $SkipArchive) { Write-Host "  ZIP : $zipArchive" }
    Write-Host "  依赖: $($dependencies.Id -join ', ')"
} finally {
    if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
    if (Test-Path -LiteralPath $iconBaseExe) { Remove-Item -LiteralPath $iconBaseExe -Force }
}
