$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# SBC LINK99 build:
#   project tree is authoritative; build\ is disposable;
#   the host link99 (3.10.1 or later) reads OVLMAP.TXT (-Y): it places the
#   overlay and bank modules on their pages and builds OVL_TABLE and the
#   resident runusage thunk.  No DREL step and no generated include file.

$ProjectRoot = $PSScriptRoot
$ToolsDir    = Join-Path $ProjectRoot "tools"
$LibDir      = Join-Path $ProjectRoot "lib"
$SrcResident = Join-Path $ProjectRoot "src\resident"
$SrcOverlay  = Join-Path $ProjectRoot "src\overlays"
$IncludeDir  = Join-Path $ProjectRoot "include"
# Shared REL headers and GETREL.C.  A development tree keeps them in a sibling
# ..\CommonLibrary; this repository ships the same files as .\common.  Use the
# sibling when it exists, otherwise the bundled copy.
$CommonRoot  = Join-Path $ProjectRoot "..\CommonLibrary"
if(-not (Test-Path -LiteralPath $CommonRoot -PathType Container)) {
    $CommonRoot = Join-Path $ProjectRoot "common"
}
$CommonIncDir= Join-Path $CommonRoot "Includes"
$Rel99SrcDir = Join-Path $CommonRoot "rel99"
$BuildDir    = Join-Path $ProjectRoot "build"
$DistDir     = Join-Path $ProjectRoot "dist"
$OverlayMap  = Join-Path $ProjectRoot "OVLMAP.TXT"
# Deploy target: the nearest TMS99105_SBC\MONITOR in a folder above this one
# (works from <workspace>\TMS9900 _C\SBC_Link99 and from a git clone at
# <workspace>\GIT\TMS99105-Native-Toolchain\link99).  SBC_MONITOR_DIR overrides.
$MonitorDir = $env:SBC_MONITOR_DIR
if(-not $MonitorDir) {
    $up = Split-Path -Parent $ProjectRoot
    while($up) {
        $c = Join-Path $up "TMS99105_SBC\MONITOR"
        if(Test-Path -LiteralPath $c -PathType Container) { $MonitorDir = $c; break }
        $next = Split-Path -Parent $up
        if(-not $next -or $next -eq $up) { break }
        $up = $next
    }
}
if(-not $MonitorDir) { $MonitorDir = Join-Path $ProjectRoot "..\..\TMS99105_SBC\MONITOR" }

function Need-File($Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "*** BUILD FAILED: missing file $Path"
    }
}
function Need-Dir($Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "*** BUILD FAILED: missing directory $Path"
    }
}

# The MONITOR folder is only the deploy target, so it is not required here;
# step 9 copies to it when it exists.
foreach($d in @($ToolsDir,$LibDir,$SrcResident,$SrcOverlay,$IncludeDir,$CommonRoot,$CommonIncDir,$Rel99SrcDir)) {
    Need-Dir $d
}
foreach($f in @("smallcp.exe","r99.exe","link99.exe")) {   # drel is not needed to build
    Need-File (Join-Path $ToolsDir $f)
}
foreach($f in @(
    "call.R99","iocore.R99","ioopen.R99","ioread.R99","ioseek.R99","iowrite.R99","cbdos.R99",
    "clib99.LIB","clib99.NDX","strlib99.LIB","strlib99.NDX"
)) {
    Need-File (Join-Path $LibDir $f)
}
Need-File (Join-Path $SrcResident "LINK99.C")
Need-File (Join-Path $SrcResident "OVLMGR.A99")
Need-File (Join-Path $SrcResident "OVLAPI.A99")
Need-File (Join-Path $SrcResident "FINAL.C")
Need-File (Join-Path $SrcOverlay  "OVL_USAGE.C")
foreach($i in 0..9) { Need-File (Join-Path $SrcOverlay ("OVL_CODE{0}.A99" -f $i)) }
foreach($f in @("OVL_S9.A99","OVL_S10.A99","OVL_S11.A99")) { Need-File (Join-Path $SrcOverlay $f) }
Need-File (Join-Path $IncludeDir  "OVLDEFS.INC")
Need-File $OverlayMap
Need-File (Join-Path $Rel99SrcDir "GETREL.C")

Write-Output "`n--- 1. clear build/dist folders ---"
if(Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
if(Test-Path -LiteralPath $DistDir)  { Remove-Item -LiteralPath $DistDir  -Recurse -Force }
New-Item -ItemType Directory -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Path $DistDir  | Out-Null

Write-Output "`n--- 2. stage LINK99 build directory ---"
Copy-Item -Path (Join-Path $ToolsDir "*") -Destination $BuildDir -Force
Copy-Item -Path (Join-Path $LibDir   "*") -Destination $BuildDir -Force
Copy-Item -Path (Join-Path $IncludeDir "*") -Destination $BuildDir -Force
Copy-Item -Path (Join-Path $CommonIncDir "*") -Destination $BuildDir -Force
Copy-Item -Path (Join-Path $SrcResident "*") -Destination $BuildDir -Force
Copy-Item -Path (Join-Path $SrcOverlay  "*") -Destination $BuildDir -Force
# Only GETREL is part of native LINK99; do not stage unrelated PUTREL/SEEREL programs.
Copy-Item -LiteralPath (Join-Path $Rel99SrcDir "GETREL.C") -Destination $BuildDir -Force
Copy-Item -LiteralPath $OverlayMap -Destination $BuildDir -Force

Set-Location -LiteralPath $BuildDir

function Compile-Main($Name) {
    Write-Output "`n--- compile executable $Name ---"
    $o = & .\smallcp.exe -C $Name 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "Errors:\s+0") { throw "compile failed: $Name" }
    Need-File (Join-Path $BuildDir ($Name + ".A99"))
}
function Compile-Mod($Name) {
    Write-Output "`n--- compile module $Name (-M) ---"
    $o = & .\smallcp.exe -C -M $Name 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "Errors:\s+0") { throw "compile failed: $Name" }
    Need-File (Join-Path $BuildDir ($Name + ".A99"))
}
function Assemble($Name) {
    Write-Output "`n--- assemble $Name ---"
    $o = & .\r99.exe $Name SCHCLC 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "No error\(s\)") { throw "assemble failed: $Name" }
    Need-File (Join-Path $BuildDir ($Name + ".R99"))
}

# The overlay and bank modules, in map order.  Pages, IDs and the table
# come from link99 -Y; the build only needs the names.
$OvlFiles = @()
foreach($raw in (Get-Content -LiteralPath $OverlayMap)) {
    $line = ($raw -replace '#.*$','').Trim()
    if($line -eq '') { continue }
    $f = @($line -split '[ \t]+')
    if(@('window','guest') -contains $f[0].ToLowerInvariant()) { continue }
    $OvlFiles += "$($f[0]).R99"
}

Write-Output "`n--- 3. compile resident + overlay C ---"
Compile-Main "LINK99"
Compile-Mod  "GETREL"
Compile-Mod  "FINAL"
Compile-Mod  "OVL_USAGE"

Assemble "LINK99"
Assemble "GETREL"
Assemble "FINAL"
Assemble "OVL_USAGE"
foreach($i in 0..9) { Assemble ("OVL_CODE{0}" -f $i) }
Assemble "OVL_S9"
Assemble "OVL_S10"
Assemble "OVL_S11"

# Startup ownership must be deterministic. The manager owns this state, so its
# initializer itself must clear CUR_WINA_ID before any overlay/data-bank mapping.
$inInit = $false
$sawOwnerClear = $false
foreach($line in (Get-Content -LiteralPath ".\OVLMGR.A99")) {
    if($line -match '^\s*OVLMGR_INIT:\s*$') { $inInit = $true; continue }
    if(-not $inInit) { continue }
    if($line -match '^\s*CLR\s+@CUR_WINA_ID\b') { $sawOwnerClear = $true; continue }
    if($line -match '^\s*RET\s*$') { break }
}
if(-not $inInit -or -not $sawOwnerClear) {
    throw "OVLMGR_INIT must explicitly CLR @CUR_WINA_ID before returning"
}

# Also prove application startup crosses the initialization boundary before
# getmem()/phase1(), either of which can map data banks or executable overlays.
$linkSource = Get-Content ".\LINK99.C" -Raw
$mainPos = $linkSource.IndexOf("main(")
$ovlInitCall = $linkSource.IndexOf("ovlinit();", $mainPos)
$getmemCall = $linkSource.IndexOf("getmem();", $mainPos)
$phase1Call = $linkSource.IndexOf("phase1(", $mainPos)
if($mainPos -lt 0 -or $ovlInitCall -lt 0 -or $getmemCall -lt 0 -or $phase1Call -lt 0 -or
   $ovlInitCall -gt $getmemCall -or $ovlInitCall -gt $phase1Call) {
    throw "LINK99 main() must call ovlinit() before getmem()/phase1()"
}
Write-Output "Overlay startup audit: owner reset is explicit and ovlinit() precedes first mapping."

Write-Output "`n--- 4. assemble resident overlay framework ---"
Assemble "OVLMGR"
Assemble "OVLAPI"

# Match FILEEDIT's proven ordering: application resident objects, explicit
# resident I/O/runtime objects, overlay page objects, then C/string libraries.
# No -P: the pages come from OVLMAP.TXT.
$LinkArgs = @(
    "-O1000","-M","-S","-YOVLMAP.TXT","SBC99.EXE",
    "LINK99.R99","GETREL.R99","FINAL.R99","OVLMGR.R99","OVLAPI.R99",
    "CALL.R99","IOCORE.R99","IOOPEN.R99","IOREAD.R99","IOSEEK.R99","IOWRITE.R99","CBDOS.R99"
)
$LinkArgs += $OvlFiles
$LinkArgs += "CLIB99.LIB"
$LinkArgs += "STRLIB99.LIB"

Write-Output "`n--- 5. LINK99 ---"
Write-Output (".\link99.exe " + ($LinkArgs -join " "))
$linkOut = & .\link99.exe @LinkArgs 2>&1 | Out-String
Write-Output $linkOut
if($LASTEXITCODE -ne 0 -or
   $linkOut -match '(?im)^\s*-\s*Unresolved:' -or
   $linkOut -match '(?im)^\s*-\s*Error:' -or
   $linkOut -match '(?im)^\s*\*{3}\s*FATAL\b') {
    throw "LINK99 failed"
}
Need-File ".\SBC99.EXE"

# ---- 6. the table link99 built, checked against what LINK99 expects ----
# OVLAPI.A99 maps the banks by ID through include\OVLDEFS.INC, so every
# ID there must name the overlay link99 gave that number, with the row
# this linker's memory model depends on:
#   USAGE  8/2              the one callable overlay
#   CODEn  C/(2+n)          the ten target-code banks, n = 0..9 (guests)
#   SYM    9/13 A/14 B/15   the symbol workspace (guest: never segment 8)
Write-Output "`n--- 6. overlay table audit ---"
$rows = @{}
$inMap = $false
foreach($l in ($linkOut -split "\r?\n")) {
    if($l -match '^OVL99 overlay map') { $inMap = $true; continue }
    if(-not $inMap) { continue }
    if($l.Trim() -eq '') { break }
    $m = [regex]::Match($l, '^\s*ID\s*(\d+)\s+(\S+)\s+seg/page((?:\s+[0-9A-F]/\d+)+)')
    if($m.Success) { $rows[$m.Groups[2].Value] = @{ Id=[int]$m.Groups[1].Value; Row=($m.Groups[3].Value.Trim() -replace '\s+',' ') } }
    Write-Output ("  " + $l.Trim())
}
if($rows.Count -eq 0) { throw "link99 printed no overlay table: tools\link99.exe must be 3.10.1 or later (-Y)" }
$expect = [ordered]@{ USAGE = "8/2" }
foreach($i in 0..9) { $expect[("CODE{0}" -f $i)] = ("C/{0}" -f (2 + $i)) }
$expect["SYM"] = "9/13 A/14 B/15"
foreach($k in $expect.Keys) {
    if(-not $rows.ContainsKey($k)) { throw "link99 built no row for $k" }
    if($rows[$k].Row -ne $expect[$k]) { throw ("{0} maps {1}, expected {2}" -f $k,$rows[$k].Row,$expect[$k]) }
}
$defs = @{}
foreach($l in (Get-Content -LiteralPath ".\OVLDEFS.INC")) {
    $m = [regex]::Match($l, '^\s*OVL_(\w+)\s+EQU\s+(\d+)')
    if($m.Success) { $defs[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
}
foreach($k in $expect.Keys) {
    if(-not $defs.ContainsKey($k)) { throw "OVLDEFS.INC has no OVL_$k" }
    if($defs[$k] -ne $rows[$k].Id) { throw ("OVLDEFS.INC says OVL_{0} EQU {1}, but link99 made it ID {2}" -f $k,$defs[$k],$rows[$k].Id) }
}
Write-Output "Overlay table audit: USAGE 8/2, CODE0-9 C/2..C/11, SYM 9/13 A/14 B/15 (guests); OVLDEFS.INC agrees."

# Page budget for the callable overlay, from link99's -M listing.
$m = [regex]::Match($linkOut, '(?im)^\s*([0-9A-F]+) Code Bytes at\s+\S+\s+\S+\s+OVL_USAGE\s*$')
if(-not $m.Success) { throw "link99 listed no size for OVL_USAGE" }
$used = [Convert]::ToInt32($m.Groups[1].Value,16)
Write-Output ("  OVL_USAGE  used {0,4}  free {1,4}" -f $used,(0x1000 - $used))
if($used -gt 0x1000) { throw "OVL_USAGE exceeds its 4K page" }

Write-Output "`n--- 7. create SBC deliverable ---"
Copy-Item -LiteralPath ".\SBC99.EXE" -Destination (Join-Path $DistDir "LINK99.EXE") -Force
$MonitorExe = Join-Path $MonitorDir "LINK99.EXE"
if(Test-Path -LiteralPath $MonitorDir -PathType Container) {
    Copy-Item -LiteralPath ".\SBC99.EXE" -Destination $MonitorExe -Force
    $Deployed = $MonitorExe
} else {
    $Deployed = "not deployed: no MONITOR folder at $MonitorDir"
}

Write-Output ""
Write-Output "LINK99 FileEdit-style overlay build complete."
Write-Output "OVL_USAGE: ID 1, virtual segment 8, physical page 2"
Write-Output "CODEBANKS: pages 2..11 mapped through segment C (>C000)"
Write-Output "SYMBOLS:   pages 13..15 mapped through segments 9..11"
Write-Output "Deliverable: .\dist\LINK99.EXE"
Write-Output ("Deployed: " + $Deployed)
Write-Output "All intermediate/generated files remain in build\ for inspection."

Set-Location -LiteralPath $ProjectRoot
