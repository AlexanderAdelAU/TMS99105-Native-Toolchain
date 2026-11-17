# make_test_fileedit.ps1 -- the SBC LINK99 stage 4 test: link FileEdit on the SBC.
#
# 1. Runs fileedit\make_SBC_FileEdit99.ps1, which builds every object.
# 2. Puts FileEdit's resident objects (all but FILESTAT, which carries the
#    entry and must load first) into FILEEDIT.LIB with lib99, and links the
#    reference FILEEDIT.EXE with the Windows link99 from FILEEDIT.LNK's
#    arguments.
# 3. Copies to MONITOR what LINK99 needs on the SBC (17 files):
#      FILESTAT.R99  FILEEDIT.LIB/.NDX  IOLIB99.LIB/.NDX  CLIB99.LIB/.NDX
#      the 7 overlays (OVL_PASTE and OVL_NAMEIO as the 8.3 files
#      OVL_PAST.R99 and OVL_NAME.R99)  FEMAP.TXT (FileEdit's OVLMAP.TXT)
#      FILEEDIT.LNK  SAMPLE.TXT
# On the SBC:   LINK99 @FILEEDIT.LNK    then    FILEEDIT SAMPLE.TXT /S
# The board's FILEEDIT.EXE must match the reference size printed below,
# rounded up to whole 512-byte records.
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$L99  = Split-Path -Parent (Split-Path -Parent $Here)
$Repo = Split-Path -Parent $L99
$FE   = Join-Path $Repo "fileedit"
& (Join-Path $FE "make_SBC_FileEdit99.ps1")
$FEBuild = Join-Path $FE "build"

$MonitorDir = $env:SBC_MONITOR_DIR
if(-not $MonitorDir) {
    $up = $Repo
    while($up) {
        $c = Join-Path $up "TMS99105_SBC\MONITOR"
        if(Test-Path -LiteralPath $c -PathType Container) { $MonitorDir = $c; break }
        $next = Split-Path -Parent $up
        if(-not $next -or $next -eq $up) { break }
        $up = $next
    }
}
if(-not $MonitorDir -or -not (Test-Path -LiteralPath $MonitorDir -PathType Container)) {
    throw "No TMS99105_SBC\MONITOR folder found above $Repo (set SBC_MONITOR_DIR)"
}

# FileEdit's resident objects that go into FILEEDIT.LIB
$libMods = @("FILEIO","FILEDATA","TERMIO","CONRX","EBMAP","EDITBUF","VIEWCTL","EDITCTL","EDITMENU","OVLMGR","OVCALL")
$ovls    = @("OVL_WORD","OVL_CHAR","OVL_RPT","OVL_VIEW","OVL_EDIT","OVL_PASTE","OVL_NAMEIO")

$Build = Join-Path $Here "build"
if(Test-Path -LiteralPath $Build) { Remove-Item -LiteralPath $Build -Recurse -Force }
New-Item -ItemType Directory -Path $Build | Out-Null
Copy-Item (Join-Path $L99 "tools\lib99.exe"), (Join-Path $L99 "tools\link99.exe") $Build -Force
foreach($f in (@("FILESTAT") + $libMods + $ovls)) {
    $src = Get-ChildItem -LiteralPath $FEBuild -Filter ($f + ".R99") | Select-Object -First 1
    if(-not $src) { throw "fileedit\build has no $f.R99" }
    Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $Build ($f + ".R99")) -Force
}
foreach($f in @("iolib99.LIB","iolib99.NDX","clib99.LIB","clib99.NDX","OVLMAP.TXT","SAMPLE.TXT")) {
    $src = Get-ChildItem -LiteralPath $FEBuild -Filter $f | Select-Object -First 1
    if(-not $src) { throw "fileedit\build has no $f" }
    Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $Build $f.ToUpper()) -Force
}
Copy-Item -LiteralPath (Join-Path $Build "OVLMAP.TXT") -Destination (Join-Path $Build "FEMAP.TXT") -Force
Copy-Item -LiteralPath (Join-Path $Here "FILEEDIT.LNK") -Destination $Build -Force

Push-Location $Build
[Environment]::CurrentDirectory = (Get-Location).Path
try {
    $o = & .\lib99.exe -U FILEEDIT @libMods 2>&1 | Out-String
    if(-not (Test-Path ".\FILEEDIT.LIB") -or -not (Test-Path ".\FILEEDIT.NDX")) { Write-Output $o; throw "lib99 made no FILEEDIT.LIB" }
    Write-Output "FILEEDIT.LIB: $($libMods -join ' ')"

    # the reference: FILEEDIT.LNK's arguments, comments removed
    $args99 = @()
    foreach($line in (Get-Content ".\FILEEDIT.LNK")) {
        $t = ($line -replace '#.*$','').Trim()
        if($t -ne '') { $args99 += @($t -split '\s+') }
    }
    $o = & .\link99.exe @args99 2>&1 | Out-String
    if($o -match '(?im)^\s*-\s*Unresolved:|\*{3}\s*FATAL') { Write-Output $o; throw "reference link failed" }
    $ref = Get-Item ".\FILEEDIT.EXE"
    Write-Output ("Reference FILEEDIT.EXE (Windows link99, same arguments): {0} bytes, SHA256 {1}" -f $ref.Length, (Get-FileHash $ref.FullName -Algorithm SHA256).Hash.Substring(0,12))

    $send = @("FILESTAT.R99","FILEEDIT.LIB","FILEEDIT.NDX","IOLIB99.LIB","IOLIB99.NDX","CLIB99.LIB","CLIB99.NDX")
    foreach($f in $send) { Copy-Item ".\$f" (Join-Path $MonitorDir $f) -Force }
    foreach($o8 in $ovls) {
        $short = $o8
        if($short.Length -gt 8) { $short = $short.Substring(0,8) }     # what the SBC opens
        Copy-Item ".\$o8.R99" (Join-Path $MonitorDir ($short + ".R99")) -Force
        $send += ($short + ".R99")
    }
    foreach($f in @("FEMAP.TXT","FILEEDIT.LNK","SAMPLE.TXT")) {
        Copy-Item ".\$f" (Join-Path $MonitorDir $f) -Force
        $send += $f
    }
    Write-Output ("Copied to " + $MonitorDir + " (" + $send.Count + " files, plus LINK99.EXE from its own build):")
    Write-Output ("  " + ($send -join " "))
}
finally {
    Pop-Location
    [Environment]::CurrentDirectory = (Get-Location).Path
}
Set-Location -LiteralPath $Repo
