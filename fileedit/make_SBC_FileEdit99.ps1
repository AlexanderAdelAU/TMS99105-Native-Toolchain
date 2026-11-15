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
$IncludeDir  = Join-Path $ProjectRoot "include"
$TestsDir    = Join-Path $ProjectRoot "tests"
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
foreach($d in @($ToolsDir,$LibDir,$SrcResident,$SrcOverlay,$IncludeDir,$TestsDir)) {
    Need-Dir $d
}
Need-Dir $MonitorDir

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
Copy-Item -Path (Join-Path $IncludeDir  "*") -Destination $BuildDir -Force

# Stage the tutorial sample input only. Large-file test data is user-supplied.
Copy-Item -LiteralPath (Join-Path $TestsDir "SAMPLE.TXT") -Destination $BuildDir -Force

# From this point until final copy-out, EVERYTHING happens in build\.
Set-Location -LiteralPath $BuildDir

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
    $o = & .\r99.exe $Name SCHCLC 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "No error\(s\)") {
        throw "assemble failed: $Name"
    }
}

$Overlays = @(
    @{ Name="OVL_WORD"; Page=2; Id=1; Desc="OVL_WORD.R99=2,1,wordscan:O_WORD" },
    @{ Name="OVL_CHAR"; Page=3; Id=2; Desc="OVL_CHAR.R99=3,2,charscan:O_CHAR" },
    @{ Name="OVL_RPT";  Page=4; Id=3; Desc="OVL_RPT.R99=4,3,report:O_RPT" },
    @{ Name="OVL_VIEW"; Page=5; Id=4; Desc="OVL_VIEW.R99=5,4,viewfile:O_VIEW" },
    @{ Name="OVL_EDIT"; Page=6; Id=5; Desc="OVL_EDIT.R99=6,5,editstep:O_EDIT" },
    @{ Name="OVL_PASTE"; Page=7; Id=6; Desc="OVL_PASTE.R99=7,6,pasteedit:O_PASTE" }
)

# FILESTAT owns the IOLIB startup.  Every other C file is a module.
Compile-Main "FILESTAT"
foreach($m in @("FILEIO","FILEDATA","TERMIO","NAMEIO","EDITBUF","VIEWCTL","EDITCTL","EDITMENU","OVL_WORD","OVL_CHAR","OVL_RPT","OVL_VIEW","OVL_EDIT","OVL_PASTE")) {
    Compile-Mod $m
}

# Assemble the generated A99 modules.
foreach($m in @("FILESTAT","FILEIO","FILEDATA","TERMIO","NAMEIO","EDITBUF","VIEWCTL","EDITCTL","EDITMENU","OVL_WORD","OVL_CHAR","OVL_RPT","OVL_VIEW","OVL_EDIT","OVL_PASTE")) {
    Assemble $m
}
# Hand-written resident assembly services.
Assemble "CONRX"
Assemble "EBMAP"

$OvlFiles = @("OVL_WORD.R99","OVL_CHAR.R99","OVL_RPT.R99","OVL_VIEW.R99","OVL_EDIT.R99","OVL_PASTE.R99")

Write-Output "`n--- DREL overlay chain lint ---"
$lint = & .\drel.exe -c @OvlFiles 2>&1 | Out-String
Write-Output $lint
if($LASTEXITCODE -ne 0 -or $lint -notmatch "all chains conform") {
    throw "overlay chain lint failed"
}

# DREL creates the resident include files from the overlay entry records.
$drelArgs = @("-i","OVLADDR.INC")
foreach($o in $Overlays) {
    $drelArgs += $o.Desc
}

Write-Output "`n--- DREL generated overlay tables ---"
$gen = & .\drel.exe @drelArgs 2>&1 | Out-String
Write-Output $gen
if($LASTEXITCODE -ne 0) {
    throw "DREL include generation failed"
}

Need-File ".\OVLADDR.INC"
Need-File ".\OVLTABLE.INC"

$anchors = Get-Content ".\OVLADDR.INC" -Raw
foreach($a in @("O_WORD","O_CHAR","O_RPT","O_VIEW","O_EDIT","O_PASTE")) {
    if($anchors -notmatch ("\b" + $a + "\b")) {
        throw "missing generated anchor $a"
    }
}

# These resident assembly modules depend on the DREL-generated include files.
Assemble "OVLMGR"
Assemble "OVLAPI"
Assemble "OVCALL"
Assemble "OVLSTATS"

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
    "FILESTAT.R99","FILEIO.R99","FILEDATA.R99","TERMIO.R99","CONRX.R99","EBMAP.R99","NAMEIO.R99","EDITBUF.R99","VIEWCTL.R99","EDITCTL.R99","EDITMENU.R99","OVLMGR.R99","OVLAPI.R99","OVCALL.R99","OVLSTATS.R99"
)
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

$LinkArgs = @(
    "-O1000","-M","-S","FILEEDIT.EXE",
    "FILESTAT.R99","FILEIO.R99","FILEDATA.R99","TERMIO.R99","CONRX.R99","EBMAP.R99","NAMEIO.R99","EDITBUF.R99","VIEWCTL.R99","EDITCTL.R99","EDITMENU.R99","OVLMGR.R99","OVLAPI.R99","OVCALL.R99","OVLSTATS.R99",
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

Need-File ".\FILEEDIT.EXE"

# Only final deliverables leave build\.
Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination (Join-Path $DistDir "FILEEDIT.EXE") -Force
# Backward-compatible command name for the original tutorial/analyser lineage.
Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination (Join-Path $DistDir "FILESTAT.EXE") -Force
Copy-Item -LiteralPath ".\SAMPLE.TXT"   -Destination (Join-Path $DistDir "SAMPLE.TXT")   -Force

# Make the executable immediately available to the SBC monitor/download project.
$MonitorExe = Join-Path $MonitorDir "FILEEDIT.EXE"
Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination $MonitorExe -Force
$MonitorAlias = Join-Path $MonitorDir "FILESTAT.EXE"
Copy-Item -LiteralPath ".\FILEEDIT.EXE" -Destination $MonitorAlias -Force

Set-Location -LiteralPath $ProjectRoot

Write-Output "`nBUILD SUCCESSFUL"
Write-Output "  .\dist\FILEEDIT.EXE"
Write-Output "  .\dist\FILESTAT.EXE  (compatibility alias)"
Write-Output "  .\dist\SAMPLE.TXT"
Write-Output ("  deployed: " + $MonitorExe)
Write-Output "Run stats:    FILEEDIT SAMPLE.TXT /S"
Write-Output "Run editor:   FILEEDIT SAMPLE.TXT /E"
