$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# SBC LINK99 build using the same overlay construction used by FILEEDIT/FILESTAT:
#   project tree is authoritative; build\ is disposable;
#   compile overlay modules first, DREL generates OVLADDR/OVLTABLE;
#   only then assemble the resident OVLMGR + application OVLAPI;
#   resident objects precede -P<n> overlay objects in the final link.

$ProjectRoot = $PSScriptRoot
$ToolsDir    = Join-Path $ProjectRoot "tools"
$LibDir      = Join-Path $ProjectRoot "lib"
$SrcResident = Join-Path $ProjectRoot "src\resident"
$SrcOverlay  = Join-Path $ProjectRoot "src\overlays"
$IncludeDir  = Join-Path $ProjectRoot "include"
$CommonRoot  = Join-Path $ProjectRoot "..\CommonLibrary"
$CommonIncDir= Join-Path $CommonRoot "Includes"
$Rel99SrcDir = Join-Path $CommonRoot "rel99"
$BuildDir    = Join-Path $ProjectRoot "build"
$DistDir     = Join-Path $ProjectRoot "dist"
$MonitorDir  = Join-Path $ProjectRoot "..\..\TMS99105_SBC\MONITOR"

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

foreach($d in @($ToolsDir,$LibDir,$SrcResident,$SrcOverlay,$IncludeDir,$CommonRoot,$CommonIncDir,$Rel99SrcDir,$MonitorDir)) {
    Need-Dir $d
}
foreach($f in @("smallcp.exe","r99.exe","drel.exe","link99.exe")) {
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

# Overlay descriptors carry an explicit Kind. Executable entries are callable
# code and must own segment 8; Data entries are mapped storage only and must
# never be entered as code. Keep this classification explicit when adding IDs.
$Overlays = @()
$Overlays += @{ Name="OVL_USAGE"; Page=2; Segment=8; Id=1; Anchor="O_USAGE"; Kind="Executable"; Desc="OVL_USAGE.R99=2,1,OVL_USAGE_ENTRY:O_USAGE" }
foreach($i in 0..9) {
    $pg = 3 + $i
    $id = 2 + $i
    $Overlays += @{ Name=("OVL_CODE{0}" -f $i); Page=$pg; Segment=8; Id=$id; Anchor=("O_C{0}" -f $i); Kind="Data"; Desc=("OVL_CODE{0}.R99={1},{2},C{0}:O_C{0}" -f $i,$pg,$id) }
}

Write-Output "`n--- 3. compile resident + overlay C ---"
Compile-Main "LINK99"
Compile-Mod  "GETREL"
Compile-Mod  "FINAL"
Compile-Mod  "OVL_USAGE"

# Assemble generated C output first. OVLMGR/OVLAPI must wait until DREL has
# generated OVLADDR.INC and OVLTABLE.INC.
Assemble "LINK99"
Assemble "GETREL"
Assemble "FINAL"
Assemble "OVL_USAGE"
foreach($i in 0..9) { Assemble ("OVL_CODE{0}" -f $i) }
Assemble "OVL_S9"
Assemble "OVL_S10"
Assemble "OVL_S11"

$OvlFiles = @("OVL_USAGE.R99")
foreach($i in 0..9) { $OvlFiles += ("OVL_CODE{0}.R99" -f $i) }

Write-Output "`n--- 4. DREL overlay chain lint ---"
$lint = & .\drel.exe -c @OvlFiles 2>&1 | Out-String
Write-Output $lint
if($LASTEXITCODE -ne 0 -or $lint -notmatch "all chains conform") {
    throw "overlay chain lint failed"
}

$drelArgs = @("-i","OVLADDR.INC")
foreach($o in $Overlays) { $drelArgs += $o.Desc }

Write-Output "`n--- 5. DREL generated overlay tables ---"
$gen = & .\drel.exe @drelArgs 2>&1 | Out-String
Write-Output $gen
if($LASTEXITCODE -ne 0) { throw "DREL include generation failed" }
Need-File ".\OVLADDR.INC"
Need-File ".\OVLTABLE.INC"

# Add LINK99's fixed symbol/XREF workspace row.  DREL generates rows for
# executable/scratch code banks; this workspace has no callable anchor.
Add-Content -LiteralPath ".\OVLTABLE.INC" -Value "`tWORD`t9,13,10,14,11,15,0,0,0,0`t;ID 12 SYMBOLS"

Write-Output "`n--- generated OVLADDR.INC ---"
Get-Content ".\OVLADDR.INC" | Write-Output
Write-Output "`n--- generated OVLTABLE.INC ---"
Get-Content ".\OVLTABLE.INC" | Write-Output

$anchors = Get-Content ".\OVLADDR.INC" -Raw
foreach($o in $Overlays) {
    $a = $o.Anchor
    $pat = '(?im)^\s*' + [regex]::Escape($a) + '\s+EQU\s+0?([0-9A-F]{4})H\b'
    $am = [regex]::Match($anchors,$pat)
    if(-not $am.Success) { throw "missing or unparsable generated anchor $a" }
    $av = [Convert]::ToInt32($am.Groups[1].Value,16)
    if($av -lt 0x8000 -or $av -gt 0xBFFF) {
        throw ("$a is not in overlay window >8000-BFFF")
    }
    Write-Output ("Overlay anchor validated: {0}=>{1:X4}" -f $a,$av)
}

# Overlay ownership hardening. Parse one generated row at a time; do not use
# a whole-file multiline regex. The invariant is architectural, not cosmetic:
# OVLMGR records CUR_WINA_ID when segment 8 is mapped. Therefore any overlay
# that may be entered as code must explicitly own segment 8. Data-only banks
# are allowed to be exceptions, but their classification must be deliberate.
function Read-OvlTableRows($Path) {
    $rows = @{}
    foreach($line in (Get-Content -LiteralPath $Path)) {
        if($line -match '^\s*WORD\s+([^;]+)\s*;\s*(?:unused\s+)?ID\s+(\d+)') {
            $id = [int]$Matches[2]
            $vals = @()
            foreach($tok in ($Matches[1] -split ',')) {
                $t = $tok.Trim()
                if($t -notmatch '^\d+$') { throw ("OVLTABLE ID {0} has non-numeric field '{1}'" -f $id,$t) }
                $vals += [int]$t
            }
            if($vals.Count -ne 10) { throw ("OVLTABLE ID {0} must contain exactly 10 words" -f $id) }
            $rows[$id] = $vals
        }
    }
    return $rows
}

$rows = Read-OvlTableRows ".\OVLTABLE.INC"
foreach($o in $Overlays) {
    $oid = [int]$o.Id
    if(-not $rows.ContainsKey($oid)) { throw ("OVLTABLE missing ID {0} ({1})" -f $o.Id,$o.Name) }
    $row = $rows[$oid]
    if($row[0] -ne [int]$o.Segment -or $row[1] -ne [int]$o.Page) {
        throw ("OVLTABLE ID {0} ({1}) expected first mapping {2},{3}; got {4},{5}" -f $o.Id,$o.Name,$o.Segment,$o.Page,$row[0],$row[1])
    }
    if($o.Kind -eq "Executable" -and $row[0] -ne 8) {
        throw ("EXECUTABLE overlay ID {0} ({1}) violates ownership rule: first mapped segment must be 8" -f $o.Id,$o.Name)
    }
    Write-Output ("Overlay ownership: ID {0,2} {1,-12} {2,-10} first={3},{4}" -f $o.Id,$o.Name,$o.Kind,$row[0],$row[1])
}

if(-not $rows.ContainsKey(12)) { throw "OVLTABLE missing ID 12 SYMBOLS data workspace" }
$sym = $rows[12]
$wantSym = @(9,13,10,14,11,15,0,0,0,0)
for($i=0; $i -lt 10; $i++) {
    if($sym[$i] -ne $wantSym[$i]) {
        throw ("OVLTABLE ID 12 SYMBOLS mismatch at word {0}: got {1}, expected {2}" -f $i,$sym[$i],$wantSym[$i])
    }
}
Write-Output "Overlay ownership: ID 12 SYMBOLS      Data       explicit non-segment-8 exception"

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

Write-Output "`n--- 6. assemble resident overlay framework ---"
Assemble "OVLMGR"
Assemble "OVLAPI"

Write-Output "`n--- overlay page budget ---"
foreach($o in $Overlays) {
    $pat = 'MODULE\s+' + [regex]::Escape($o.Name) + '\s+size=([0-9A-F]+)'
    $sm = [regex]::Match($lint,$pat,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not $sm.Success) { throw ("no DREL size for " + $o.Name) }
    $used = [Convert]::ToInt32($sm.Groups[1].Value,16)
    $free = 0x0FC0 - $used
    Write-Output ("  {0,-12} used {1,4}  chain-free {2,4}" -f $o.Name,$used,$free)
    if($free -lt 0) { throw ($o.Name + " exceeds one-page chain-safe limit >0FC0") }
}

Write-Output "`n--- 7. resident chain lint ---"
$ResidentObjects = @("LINK99.R99","GETREL.R99","FINAL.R99","OVLMGR.R99","OVLAPI.R99")
$rLint = & .\drel.exe -c @ResidentObjects 2>&1 | Out-String
Write-Output $rLint
if($LASTEXITCODE -ne 0 -or $rLint -notmatch "all chains conform") {
    throw "resident chain lint failed"
}

$PageArgs = @()
foreach($o in $Overlays) {
    $PageArgs += "-P$($o.Page)"
    $PageArgs += "$($o.Name).R99"
}
$PageArgs += "-P13"; $PageArgs += "OVL_S9.R99"
$PageArgs += "-P14"; $PageArgs += "OVL_S10.R99"
$PageArgs += "-P15"; $PageArgs += "OVL_S11.R99"

# Match FILEEDIT's proven ordering: application resident objects, explicit
# resident I/O/runtime objects, overlay page objects, then C/string libraries.
$LinkArgs = @(
    "-O1000","-M","-S","SBC99.EXE",
    "LINK99.R99","GETREL.R99","FINAL.R99","OVLMGR.R99","OVLAPI.R99",
    "CALL.R99","IOCORE.R99","IOOPEN.R99","IOREAD.R99","IOSEEK.R99","IOWRITE.R99","CBDOS.R99"
)
$LinkArgs += $PageArgs
$LinkArgs += "CLIB99.LIB"
$LinkArgs += "STRLIB99.LIB"

Write-Output "`n--- 8. LINK99 ---"
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

Write-Output "`n--- 9. create SBC deliverable ---"
Copy-Item -LiteralPath ".\SBC99.EXE" -Destination (Join-Path $DistDir "LINK99.EXE") -Force
$MonitorExe = Join-Path $MonitorDir "LINK99.EXE"
Copy-Item -LiteralPath ".\SBC99.EXE" -Destination $MonitorExe -Force

Write-Output ""
Write-Output "LINK99 FileEdit-style overlay build complete."
Write-Output "OVL_USAGE: ID 1, virtual segment 8, physical page 2"
Write-Output "CODEBANKS: pages 3..12 mapped through segment 8"
Write-Output "SYMBOLS:   pages 13..15 mapped through segments 9..11"
Write-Output "Deliverable: .\dist\LINK99.EXE"
Write-Output ("Deployed: " + $MonitorExe)
Write-Output "All intermediate/generated files remain in build\ for inspection."

Set-Location -LiteralPath $ProjectRoot
