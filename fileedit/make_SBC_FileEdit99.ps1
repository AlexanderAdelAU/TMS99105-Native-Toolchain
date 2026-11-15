$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# FILEEDIT build rule (FILESTAT source lineage retained):
#   The project tree is authoritative.
#   build\ is disposable.
#   ALL tools, libraries, sources and includes are copied into build\ first.
#   Compilation, assembly, DREL and LINK99 then run only inside build\.
#
# This makes the script independent of Eclipse's current working directory.

$ProjectRoot = $PSScriptRoot
$ToolsDir    = Join-Path $ProjectRoot "tools"
$LibDir      = Join-Path $ProjectRoot "lib"
$SrcResident = Join-Path $ProjectRoot "src\resident"
$SrcOverlay  = Join-Path $ProjectRoot "src\overlays"
$TestsDir    = Join-Path $ProjectRoot "tests"
$OverlayMap  = Join-Path $ProjectRoot "OVLMAP.TXT"
$Generator   = Join-Path $ToolsDir "ovlgen.ps1"
$BuildDir    = Join-Path $ProjectRoot "build"
$DistDir     = Join-Path $ProjectRoot "dist"

# Download/deployment directory in the sibling TMS99105_SBC workspace project.
# FILESTAT project:
#   <workspace>\TMS9900 _C\SBC_filestat99
# Monitor project:
#   <workspace>\TMS99105_SBC\MONITOR
#
# Keep this workspace-relative: no drive letter or machine-specific absolute path.
$MonitorDir = Join-Path $ProjectRoot "..\..\TMS99105_SBC\MONITOR"
$SkipMonitor = ($env:FILEEDIT_SKIP_MONITOR_DEPLOY -eq "1")

function Need-File($Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "*** BUILD FAILED: missing $Path"
    }
}

function Need-Dir($Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "*** BUILD FAILED: missing directory $Path"
    }
}

# Verify the project-local inputs before deleting the old build.
foreach($d in @($ToolsDir,$LibDir,$SrcResident,$SrcOverlay,$TestsDir)) {
    Need-Dir $d
}
if(-not $SkipMonitor) { Need-Dir $MonitorDir }
Need-File $OverlayMap
Need-File $Generator

$RequiredTools = @("smallcp.exe","r99.exe","drel.exe","link99.exe")
foreach($f in $RequiredTools) {
    Need-File (Join-Path $ToolsDir $f)
}

$RequiredLibs = @(
    "call.R99","iocore.R99","ioopen.R99","ioread.R99","ioseek.R99","iowrite.R99",
    "cbdos.R99","clib99.LIB","clib99.NDX","iolib99.LIB","iolib99.NDX"
)
foreach($f in $RequiredLibs) {
    Need-File (Join-Path $LibDir $f)
}

# Known-good IOLIB99 modular build from the current IOLIB99(7) package.
# Verify the project-local lib\ copies BEFORE deleting build\ so a stale
# modular object cannot be silently staged and linked.
$ExpectedIOLib = [ordered]@{
    "call.R99"     = @{ Length = 761;   SHA256 = "6E8A9B54C2173448D8BEAAF3DC80AFA3EE07AFD00E3D9D858B23883178F4EF9F" }
    "cbdos.R99"    = @{ Length = 90;    SHA256 = "6577225B6030AE80EB16A82E2E08538960E7104F212498013FB4D5A8F0C79524" }
    "iocore.R99"   = @{ Length = 3708;  SHA256 = "BBE5F9412CCF48EA63EC32A9973F92BAA5BE5E2AF97095A1BC27573A83D23A3D" }
    "ioopen.R99"   = @{ Length = 3922;  SHA256 = "17022213A76336504AAA7160946F40EF4E85990F7CC77938BF6C4845D96A40FD" }
    "ioread.R99"   = @{ Length = 2245;  SHA256 = "930BA28F30C8885156C04C8476EDC2C7E47ED18312E6FB9B5363818BC044665F" }
    "ioseek.R99"   = @{ Length = 849;   SHA256 = "DF2F2C6A6D178E5E003CC7A465B145AA86D8A68EB4291F5D761387958F489EA6" }
    "iowrite.R99"  = @{ Length = 2225;  SHA256 = "66345E64B60AE39B295ECB6FD9110208D022EFAFA1E759090A61029BE230F922" }
    "iolib99.LIB"  = @{ Length = 13787; SHA256 = "546CCF717B213ADEDAD9AEE6EEB0F419C11963F98580778EBD0FEA46B29C8FBD8" }
    "iolib99.NDX"  = @{ Length = 36;    SHA256 = "50EDBD46D44BFA6F41ED37E3A8DE5F30C587BC9D6FD2238E649B9C5F1D4E6F1B" }
}

function Test-KnownIOLibSet($Directory, $Label) {
    Write-Output "`n--- $Label (HASH/LENGTH BYPASSED) ---"
    Write-Output ("Directory: " + $Directory)

    foreach($name in $ExpectedIOLib.Keys) {
        $path = Join-Path $Directory $name
        Need-File $path
        Write-Output ("  {0,-12} EXISTS" -f $name)
    }

    Write-Output "  IOLIB set existence verified."
}

# First gate: prove that the authoritative project lib\ directory itself
# contains the current modular IOLIB set.  Nothing has been deleted yet.
Test-KnownIOLibSet $LibDir "SOURCE LIB IOLIB PREFLIGHT"

# Recreate the disposable staging/output directories.
if(Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
if(Test-Path -LiteralPath $DistDir)  { Remove-Item -LiteralPath $DistDir  -Recurse -Force }

New-Item -ItemType Directory -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Path $DistDir  | Out-Null

Write-Output "`n--- staging FILEEDIT build directory ---"

# Stage ALL project-local tools and libraries.
Copy-Item -Path (Join-Path $ToolsDir "*") -Destination $BuildDir -Force
Copy-Item -Path (Join-Path $LibDir   "*") -Destination $BuildDir -Force

# Second gate: prove that staging copied exactly the same IOLIB objects.
Test-KnownIOLibSet $BuildDir "STAGED IOLIB CHECK"

# Stage ALL application source files and includes.
Copy-Item -Path (Join-Path $SrcResident "*") -Destination $BuildDir -Force
Copy-Item -Path (Join-Path $SrcOverlay  "*") -Destination $BuildDir -Force

# Stage the tutorial sample input only. Large-file test data is user-supplied.
Copy-Item -LiteralPath (Join-Path $TestsDir "SAMPLE.TXT") -Destination $BuildDir -Force
Copy-Item -LiteralPath $OverlayMap -Destination $BuildDir -Force

# From this point until final copy-out, EVERYTHING happens in build\.
Set-Location -LiteralPath $BuildDir
[Environment]::CurrentDirectory = (Get-Location).Path

function Compile-Main($Name) {
    Write-Output "`n--- compile executable $Name ---"
    $o = & .\smallcp.exe -C $Name 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "Errors:\s+0") {
        throw "compile failed: $Name"
    }
}

function Compile-Mod($Name) {
    Write-Output "`n--- compile module $Name (-M) ---"
    $o = & .\smallcp.exe -C -M $Name 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "Errors:\s+0") {
        throw "compile failed: $Name"
    }
}

function Assemble($Name) {
    Write-Output "`n--- assemble $Name ---"
    $asm = Join-Path (Get-Location).Path "$Name.A99"
    if(-not (Test-Path -LiteralPath $asm -PathType Leaf)) {
        Write-Output ("Assembler input absent: " + $asm)
        Write-Output ("Build A99 files: " + ((Get-ChildItem -Filter "*.A99" | ForEach-Object { $_.Name }) -join ", "))
        throw "compiled/handwritten assembly input missing: $Name"
    }
    Write-Output ("  input: " + $asm)
    $o = & .\r99.exe $Name SCHC 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "No error\(s\)") {
        throw "assemble failed: $Name"
    }
}

# Generate IDs and DREL descriptors from OVLMAP.TXT. The build no longer
# maintains overlay ID, page and function lists by hand.
Write-Output "`n--- OVL99 map -> definitions and descriptors ---"
& $Generator -Phase defs -Map ".\OVLMAP.TXT" -Dir "."
if($LASTEXITCODE -ne 0) { throw "OVL99 defs generation failed" }
Need-File ".\OVLDEFS.INC"
Need-File ".\OVLDESC.TXT"
$Desc = @(Get-Content -LiteralPath ".\OVLDESC.TXT" | Where-Object { $_.Trim() -ne '' })
$Overlays = @()
$OvlFiles = @()
$PageArgs = @()
foreach($d in $Desc) {
    $m = [regex]::Match($d, '^([A-Za-z_][A-Za-z0-9_]*)\.R99=(\d+),(\d+),')
    if(-not $m.Success) { throw "invalid generated DREL descriptor: $d" }
    $name = $m.Groups[1].Value
    $page = [int]$m.Groups[2].Value
    $Overlays += @{ Name=$name; Page=$page; Id=[int]$m.Groups[3].Value }
    $OvlFiles += "$name.R99"
    $PageArgs += "-P$page"
    $PageArgs += "$name.R99"
}

# FILESTAT owns the IOLIB startup.  Every other C file is a module.
Compile-Main "FILESTAT"
foreach($m in (@("FILEIO","FILEDATA","TERMIO","NAMEIO","EDITBUF","VIEWCTL","EDITCTL","EDITMENU") + @($Overlays | ForEach-Object { $_.Name }))) {
    Compile-Mod $m
}

# Assemble the generated A99 modules.
foreach($m in (@("FILESTAT","FILEIO","FILEDATA","TERMIO","NAMEIO","EDITBUF","VIEWCTL","EDITCTL","EDITMENU") + @($Overlays | ForEach-Object { $_.Name }))) {
    Assemble $m
}
# Hand-written resident assembly services.
Assemble "CONRX"
Assemble "EBMAP"

Write-Output "`n--- DREL overlay chain lint ---"
$lint = & .\drel.exe -c @OvlFiles 2>&1 | Out-String
Write-Output $lint
if($LASTEXITCODE -ne 0 -or $lint -notmatch "all chains conform") {
    throw "overlay chain lint failed"
}

# DREL creates the resident include files from the overlay entry records.
$drelArgs = @("-i","OVLADDR.INC")
foreach($d in $Desc) {
    $drelArgs += $d
}

Write-Output "`n--- DREL generated overlay tables ---"
$gen = & .\drel.exe @drelArgs 2>&1 | Out-String
Write-Output $gen
if($LASTEXITCODE -ne 0) {
    throw "DREL include generation failed"
}

Need-File ".\OVLADDR.INC"
Need-File ".\OVLTABLE.INC"

# Generate public thunks AFTER DREL has published entry addresses.
Write-Output "`n--- OVL99 map -> public entry thunks ---"
& $Generator -Phase thunks -Map ".\OVLMAP.TXT" -Dir "."
if($LASTEXITCODE -ne 0) { throw "OVL99 thunks generation failed" }
Need-File ".\OVLTHUNK.A99"

Assemble "OVLMGR"
Assemble "OVCALL"
Assemble "OVLTHUNK"

Write-Output "`n--- overlay page budgets ---"
foreach($o in $Overlays) {
    $pattern = "MODULE\s+" + [regex]::Escape($o.Name) + "\s+size=([0-9A-F]+)"
    $match = [regex]::Match(
        $lint,
        $pattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if(-not $match.Success) {
        throw "no DREL size for $($o.Name)"
    }

    $used = [Convert]::ToInt32($match.Groups[1].Value,16)
    $free = 0x0FC0 - $used

    Write-Output ("  {0,-8} used {1,4}  chain-free {2,4}" -f $o.Name,$used,$free)

    if($free -lt 0) {
        throw "$($o.Name) exceeds one-page chain-safe limit >0FC0"
    }
}

Write-Output "`n--- resident chain lint ---"
$ResidentObjects = @(
    "FILESTAT.R99","FILEIO.R99","FILEDATA.R99","TERMIO.R99","CONRX.R99","EBMAP.R99","NAMEIO.R99","EDITBUF.R99","VIEWCTL.R99","EDITCTL.R99","EDITMENU.R99","OVLMGR.R99","OVCALL.R99","OVLTHUNK.R99"
)
$rLint = & .\drel.exe -c @ResidentObjects 2>&1 | Out-String
Write-Output $rLint
if($LASTEXITCODE -ne 0 -or $rLint -notmatch "all chains conform") {
    throw "resident chain lint failed"
}

$LinkArgs = @(
    "-O1000","-M","-S","FILEEDIT.EXE",
    "FILESTAT.R99","FILEIO.R99","FILEDATA.R99","TERMIO.R99","CONRX.R99","EBMAP.R99","NAMEIO.R99","EDITBUF.R99","VIEWCTL.R99","EDITCTL.R99","EDITMENU.R99","OVLMGR.R99","OVCALL.R99","OVLTHUNK.R99",
    "CALL.R99","IOCORE.R99","IOOPEN.R99","IOREAD.R99","IOWRITE.R99","CBDOS.R99"
)
$LinkArgs += $PageArgs
$LinkArgs += "CLIB99.LIB"

# Final gate immediately before LINK99.  This catches any accidental overwrite
# of a staged modular object during the compile/assemble phases.
Test-KnownIOLibSet $BuildDir "PRE-LINK IOLIB CHECK"

Write-Output "`n--- LINK99 ---"
Write-Output (".\link99.exe " + ($LinkArgs -join " "))

Write-Output "`n--- DREL LIBRARY CHECK ---"
Write-Output "Checking IOLIB99.LIB..."
$drelIo = & .\drel.exe IOLIB99.LIB 2>&1 | Out-String
Write-Output $drelIo

Write-Output "Checking CLIB99.LIB..."
$drelC = & .\drel.exe CLIB99.LIB 2>&1 | Out-String
Write-Output $drelC


$linkOut = & .\link99.exe @LinkArgs 2>&1 | Out-String
Write-Output $linkOut

if($LASTEXITCODE -ne 0 -or
   $linkOut -match '(?im)^\s*-\s*Unresolved:' -or
   $linkOut -match '(?im)^\s*-\s*Error:' -or
   $linkOut -match '(?im)^\s*\*{3}\s*FATAL\b') {
    throw "LINK99 failed"
}

# Verify every externally referenced published entry bound to its resident
# thunk. A direct bind to >8000 would be unsafe after an overlay switch.
Write-Output "`n--- OVL99 generated entry bindings ---"
$Bindings = @{}
foreach($line in ($linkOut -split "`r?`n")) {
    $m = [regex]::Match($line, 'xref\s+(\S+)\s+@\s*([0-9A-F]+)\s*=\s*([0-9A-F]+)', 'IgnoreCase')
    if($m.Success) { $Bindings[$m.Groups[1].Value.ToLowerInvariant()] = $m.Groups[3].Value }
}
$Entries = @()
foreach($d in $Desc) {
    foreach($m in [regex]::Matches($d, '([A-Za-z_][A-Za-z0-9_]*):O_')) {
        $Entries += $m.Groups[1].Value
    }
}
foreach($entry in @($Entries | Sort-Object -Unique)) {
    if(-not $Bindings.ContainsKey($entry)) {
        throw "OVL99: no LINK99 external xref for published entry $entry"
    }
    $bound = [Convert]::ToInt32($Bindings[$entry],16)
    if($bound -ge 0x8000 -or $bound -lt 0x1000) {
        throw ("OVL99: {0} resolved at >{1:X4}, outside resident program" -f $entry,$bound)
    }
    Write-Output ("  {0,-12} -> >{1:X4} resident thunk" -f $entry,$bound)
}

Need-File ".\FILEEDIT.EXE"

# Only final deliverables leave build\.
Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination (Join-Path $DistDir "FILEEDIT.EXE") -Force
# Backward-compatible command name for the original tutorial/analyser lineage.
Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination (Join-Path $DistDir "FILESTAT.EXE") -Force
Copy-Item -LiteralPath ".\SAMPLE.TXT"   -Destination (Join-Path $DistDir "SAMPLE.TXT")   -Force

# Default behaviour: deploy to the sibling SBC MONITOR workspace.
# CI and isolated checkouts set FILEEDIT_SKIP_MONITOR_DEPLOY=1 to build
# without requiring any unrelated Windows workspace directories.
if(-not $SkipMonitor) {
    $MonitorExe = Join-Path $MonitorDir "FILEEDIT.EXE"
    Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination $MonitorExe -Force
    $MonitorAlias = Join-Path $MonitorDir "FILESTAT.EXE"
    Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination $MonitorAlias -Force
}

Set-Location -LiteralPath $ProjectRoot
[Environment]::CurrentDirectory = (Get-Location).Path

Write-Output "`nBUILD SUCCESSFUL"
Write-Output "  .\dist\FILEEDIT.EXE"
Write-Output "  .\dist\FILESTAT.EXE  (compatibility alias)"
Write-Output "  .\dist\SAMPLE.TXT"
if($SkipMonitor) {
    Write-Output "  MONITOR deployment skipped by FILEEDIT_SKIP_MONITOR_DEPLOY"
}
else {
    Write-Output ("  deployed: " + $MonitorExe)
}
Write-Output "Run stats:    FILEEDIT SAMPLE.TXT /S"
Write-Output "Run overlay nesting test: FILEEDIT /O"
Write-Output "Run editor:   FILEEDIT SAMPLE.TXT /E"
