$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# SBC LINK99 build:
#   project tree is authoritative; build\ is disposable;
#   the host link99 (3.10.1 or later) reads OVLMAP.TXT (-Y): it places the
#   overlay and bank modules on their pages and builds OVL_TABLE and the
#   resident thunks (runusage, getsw, okay, exeout and the rest).  No DREL step and no
#   generated include file.

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
Need-File (Join-Path $SrcOverlay  "OVL_USAGE.C")
Need-File (Join-Path $SrcResident "FINAL.C")
Need-File (Join-Path $SrcOverlay  "OVL_FINAL.C")
Need-File (Join-Path $SrcOverlay  "OVL_EXE.C")
Need-File (Join-Path $SrcOverlay  "OVL_MAP.C")
Need-File (Join-Path $SrcOverlay  "OVL_GLUE.C")
Need-File (Join-Path $SrcOverlay  "OVL_MAPM.C")
Need-File (Join-Path $SrcOverlay  "OVL_CHK.C")
Need-File (Join-Path $SrcOverlay  "OVL_TAB.C")
foreach($i in 0..14) { Need-File (Join-Path $SrcOverlay ("OVL_CODE{0}.A99" -f $i)) }
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
Compile-Mod  "OVL_USAGE"
Compile-Mod  "FINAL"
Compile-Mod  "OVL_FINAL"
Compile-Mod  "OVL_EXE"
Compile-Mod  "OVL_MAP"
Compile-Mod  "OVL_GLUE"
Compile-Mod  "OVL_MAPM"
Compile-Mod  "OVL_CHK"
Compile-Mod  "OVL_TAB"

Assemble "LINK99"
Assemble "GETREL"
Assemble "OVL_USAGE"
Assemble "FINAL"
Assemble "OVL_FINAL"
Assemble "OVL_EXE"
Assemble "OVL_MAP"
Assemble "OVL_GLUE"
Assemble "OVL_MAPM"
Assemble "OVL_CHK"
Assemble "OVL_TAB"
foreach($i in 0..14) { Assemble ("OVL_CODE{0}" -f $i) }
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

# Application resident objects, explicit resident I/O/runtime objects, the
# C/string libraries, the overlay page objects, then the libraries again.
# The libraries come BEFORE the overlays so every member is placed below
# them: a resident module is placed at cbase + its place in the link, and
# one loaded after the overlays would sit above them by their size (link99
# refuses that).  The second listing must find nothing: no overlay calls a
# library member the resident code does not (PUTNUM.C, hexarg).  No -P: the pages come from OVLMAP.TXT.
$LinkArgs = @(
    "-O1000","-M","-S","-YOVLMAP.TXT","SBC99.EXE",
    "LINK99.R99","GETREL.R99","FINAL.R99","OVLMGR.R99","OVLAPI.R99",
    "CALL.R99","IOCORE.R99","IOOPEN.R99","IOREAD.R99","IOSEEK.R99","IOWRITE.R99","CBDOS.R99"
)
$LinkArgs += "CLIB99.LIB"
$LinkArgs += "STRLIB99.LIB"
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
#   USAGE  8/2              callable: usage message and @file reader
#   FINAL  8/3              callable: symbol check, COM/LGO output
#   EXE    8/4              callable: paged EXE output
#   MAP    8/5              callable: -Y map reader, entry renaming
#   GLUE   8/6              callable: -Y table, thunks and checks
#   MAPM   8/7              callable: -Y map lines
#   CHK    8/8              callable: -Y checks at the end
#   TAB    8/9              callable: -Y OVL_TABLE fill and listing
#   CODEn  C/(2+n)          the target-code banks, n = 0..13 (guests),
#   CODE14 C/1              and bank 14 on the shell's spare COM page
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
$expect = [ordered]@{ USAGE = "8/2"; FINAL = "8/3"; EXE = "8/4"; MAP = "8/5"; GLUE = "8/6"; MAPM = "8/7"; CHK = "8/8"; TAB = "8/9" }
foreach($i in 0..13) { $expect[("CODE{0}" -f $i)] = ("C/{0}" -f (2 + $i)) }
$expect["CODE14"] = "C/1"
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
Write-Output "Overlay table audit: USAGE 8/2, FINAL 8/3, EXE 8/4, MAP 8/5, GLUE 8/6, MAPM 8/7, CHK 8/8, TAB 8/9, CODE0-13 C/2..C/15, CODE14 C/1, SYM 9/13 A/14 B/15 (guests); OVLDEFS.INC agrees."

# Page budget for the callable overlays, from link99's -M listing.
foreach($ov in @("OVL_USAGE","OVL_FINAL","OVL_EXE","OVL_MAP","OVL_GLUE","OVL_MAPM","OVL_CHK","OVL_TAB")) {
    $m = [regex]::Match($linkOut, ('(?im)^\s*([0-9A-F]+) Code Bytes at\s+\S+\s+\S+\s+{0}\s*$' -f $ov))
    if(-not $m.Success) { throw "link99 listed no size for $ov" }
    $used = [Convert]::ToInt32($m.Groups[1].Value,16)
    Write-Output ("  {0,-10} used {1,4}  free {2,4}" -f $ov,$used,(0x1000 - $used))
    if($used -gt 0x1000) { throw "$ov exceeds its 4K page" }
}

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
Write-Output "OVL_FINAL: ID 13, virtual segment 8, physical page 3"
Write-Output "OVL_EXE:   ID 14, virtual segment 8, physical page 4"
Write-Output "OVL_MAP:   ID 20, virtual segment 8, physical page 5"
Write-Output "OVL_GLUE:  ID 21, virtual segment 8, physical page 6"
Write-Output "OVL_MAPM:  ID 22, virtual segment 8, physical page 7"
Write-Output "OVL_CHK:   ID 23, virtual segment 8, physical page 8"
Write-Output "OVL_TAB:   ID 24, virtual segment 8, physical page 9"
Write-Output "CODEBANKS: pages 2..15 and 1 mapped through segment C (>C000)"
Write-Output "SYMBOLS:   pages 13..15 mapped through segments 9..11"
Write-Output "Deliverable: .\dist\LINK99.EXE"
Write-Output ("Deployed: " + $Deployed)
Write-Output "All intermediate/generated files remain in build\ for inspection."

Set-Location -LiteralPath $ProjectRoot
