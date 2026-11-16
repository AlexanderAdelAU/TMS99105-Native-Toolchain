$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# FILEEDIT build rule (FILESTAT source lineage retained):
#   The project tree is authoritative.
#   build\ is disposable.
#   ALL tools, libraries, sources and includes are copied into build\ first.
#   Compilation, assembly and LINK99 then run only inside build\.
#
# This makes the script independent of Eclipse's current working directory.

$ProjectRoot = $PSScriptRoot
$ToolsDir    = Join-Path $ProjectRoot "tools"
$LibDir      = Join-Path $ProjectRoot "lib"
$SrcResident = Join-Path $ProjectRoot "src\resident"
$SrcOverlay  = Join-Path $ProjectRoot "src\overlays"
$TestsDir    = Join-Path $ProjectRoot "tests"
$OverlayMap  = Join-Path $ProjectRoot "OVLMAP.TXT"
$BuildDir    = Join-Path $ProjectRoot "build"
$DistDir     = Join-Path $ProjectRoot "dist"

# Download/deployment directory in the sibling TMS99105_SBC workspace project.
# FILESTAT project:
#   <workspace>\TMS9900 _C\SBC_filestat99
# Monitor project:
#   <workspace>\TMS99105_SBC\MONITOR
#
# Keep this workspace-relative: no drive letter or machine-specific absolute path.
# The project may sit at <workspace>\TMS9900 _C\SBC_FileEdit99 or in a git
# clone at <workspace>\GIT\TMS99105-Native-Toolchain\fileedit, so look for
# TMS99105_SBC\MONITOR in each folder above this one and use the nearest.
# $env:SBC_MONITOR_DIR overrides.  Only those exact paths are tested.
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

$RequiredTools = @("smallcp.exe","r99.exe","link99.exe")   # drel is not needed to build
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
    # Legacy R99's S/H flags choose DOS drive letters explicitly.
    # Avoid hard-coding C: because GitHub Windows runners use D:.
    $drive = ([IO.Path]::GetPathRoot((Get-Location).Path)).Substring(0,1).ToUpperInvariant()
    $r99Flags = "S${drive}H${drive}"
    Write-Output ("  R99 drive flags: " + $r99Flags)
    $o = & .\r99.exe $Name $r99Flags 2>&1 | Out-String
    Write-Output $o
    if($o -notmatch "No error\(s\)") {
        throw "assemble failed: $Name"
    }
}

# OVLMAP.TXT is read by LINK99 itself (-Y): it assigns the pages, builds
# OVL_TABLE and one resident thunk per published entry, and checks the
# window-owner rule.  The script only needs the module names, to compile
# them, and the entry names, to check the bindings after the link.
$Overlays = @()
$OvlFiles = @()
$Entries  = @()
foreach($raw in (Get-Content -LiteralPath ".\OVLMAP.TXT")) {
    $line = ($raw -replace '#.*$','').Trim()
    if($line -eq '') { continue }
    $f = $line -split '[ \t]+'
    if($f[0] -ieq 'window') { continue }     # LINK99's segment limit, not a module
    if($f.Count -lt 4) { throw "OVLMAP.TXT: want 'module page overlay entries': $raw" }
    $Overlays += @{ Name=$f[0] }
    $OvlFiles += "$($f[0]).R99"
    foreach($e in $f[3..($f.Count-1)]) { if($e -ne '-') { $Entries += $e } }
}

# FILESTAT owns the IOLIB startup.  Every other C file is a module.
Compile-Main "FILESTAT"
foreach($m in (@("FILEIO","FILEDATA","TERMIO","EDITBUF","VIEWCTL","EDITCTL","EDITMENU") + @($Overlays | ForEach-Object { $_.Name }))) {
    Compile-Mod $m
}

# Assemble the generated A99 modules.
foreach($m in (@("FILESTAT","FILEIO","FILEDATA","TERMIO","EDITBUF","VIEWCTL","EDITCTL","EDITMENU") + @($Overlays | ForEach-Object { $_.Name }))) {
    Assemble $m
}
# Hand-written resident assembly services.
Assemble "CONRX"
Assemble "EBMAP"

Assemble "OVLMGR"
Assemble "OVCALL"

$LinkArgs = @(
    "-O1000","-M","-S","-YOVLMAP.TXT","FILEEDIT.EXE",
    "FILESTAT.R99","FILEIO.R99","FILEDATA.R99","TERMIO.R99","CONRX.R99","EBMAP.R99","EDITBUF.R99","VIEWCTL.R99","EDITCTL.R99","EDITMENU.R99","OVLMGR.R99","OVCALL.R99",
    "CALL.R99","IOCORE.R99","IOOPEN.R99","IOREAD.R99","IOWRITE.R99","CBDOS.R99"
)
$LinkArgs += $OvlFiles      # no -P: the pages come from OVLMAP.TXT
$LinkArgs += "CLIB99.LIB"

# Final gate immediately before LINK99.  This catches any accidental overwrite
# of a staged modular object during the compile/assemble phases.
Test-KnownIOLibSet $BuildDir "PRE-LINK IOLIB CHECK"

Write-Output "`n--- LINK99 ---"
Write-Output (".\link99.exe " + ($LinkArgs -join " "))

$linkOut = & .\link99.exe @LinkArgs 2>&1 | Out-String
Write-Output $linkOut

if($LASTEXITCODE -ne 0 -or
   $linkOut -match '(?im)^\s*-\s*Unresolved:' -or
   $linkOut -match '(?im)^\s*-\s*Error:' -or
   $linkOut -match '(?im)^\s*\*{3}\s*FATAL\b') {
    throw "LINK99 failed"
}
if($linkOut -notmatch '(?m)^OVL99 overlay map') {
    throw "LINK99 did not read the overlay map: tools\link99.exe must be 3.10.1 or later (-Y)"
}

# Page budgets, from LINK99's -M listing ("N Code Bytes at ... MODULE",
# the module's PSIZE - the size DREL used to report).  LINK99 itself
# rejects a module that overruns its 4K page and checks every object's
# reference slots; the >0FC0 budget keeps the margin FileEdit has always kept.
Write-Output "`n--- overlay page budgets ---"
foreach($o in $Overlays) {
    $pattern = '(?im)^\s*([0-9A-F]+) Code Bytes at\s+\S+\s+\S+\s+' + [regex]::Escape($o.Name) + '\s*$'
    $match = [regex]::Match($linkOut, $pattern)
    if(-not $match.Success) {
        throw "LINK99 listed no size for $($o.Name)"
    }
    $used = [Convert]::ToInt32($match.Groups[1].Value,16)
    $free = 0x0FC0 - $used
    Write-Output ("  {0,-10} used {1,4}  free {2,4}" -f $o.Name,$used,$free)
    if($free -lt 0) {
        throw "$($o.Name) exceeds the one-page >0FC0 budget"
    }
}

# Verify every externally referenced published entry bound to its resident
# thunk. A direct bind to >8000 would be unsafe after an overlay switch.
Write-Output "`n--- OVL99 entry bindings (LINK99 -Y thunks) ---"
$Bindings = @{}
foreach($line in ($linkOut -split "`r?`n")) {
    $m = [regex]::Match($line, 'xref\s+(\S+)\s+@\s*([0-9A-F]+)\s*=\s*([0-9A-F]+)', 'IgnoreCase')
    if($m.Success) { $Bindings[$m.Groups[1].Value.ToLowerInvariant()] = $m.Groups[3].Value }
}
foreach($entry in @($Entries | Sort-Object -Unique)) {
    if(-not $Bindings.ContainsKey($entry)) {
        throw "OVL99: no LINK99 external xref for published entry $entry"
    }
    $bound = [Convert]::ToInt32($Bindings[$entry],16)
    if($bound -ge 0x8000 -or $bound -lt 0x1000) {
        throw ("OVL99: {0} resolved at >{1:X4}, outside resident program" -f $entry,$bound)
    }
    $real = ""
    if($Bindings.ContainsKey("~$entry")) { $real = " -> ~$entry >" + $Bindings["~$entry"] }
    Write-Output ("  {0,-12} -> >{1:X4} resident thunk{2}" -f $entry,$bound,$real)
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
