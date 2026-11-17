# make_test_fileedit.ps1 -- the SBC LINK99 stage 4 test: link FileEdit on the SBC.
#
# Runs fileedit\make_SBC_FileEdit99.ps1 (which builds every object and
# links FILEEDIT.EXE with the Windows link99 -Y, the reference), then
# copies to MONITOR everything LINK99 needs on the SBC, under 8.3 names:
#   the 25 objects, CLIB99.LIB/.NDX, FEMAP.TXT (FileEdit's OVLMAP.TXT)
#   FILEEDIT.LNK, and SAMPLE.TXT to run it on.
# On the SBC:   LINK99 @FILEEDIT.LNK    then    FILEEDIT SAMPLE.TXT /S
# The board's FILEEDIT.EXE must match the reference size printed below,
# rounded up to whole 512-byte records.
$ErrorActionPreference = "Stop"
$Here = $PSScriptRoot
$Repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Here))
$FE   = Join-Path $Repo "fileedit"
& (Join-Path $FE "make_SBC_FileEdit99.ps1")
$Build = Join-Path $FE "build"
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
$ref = Get-Item (Join-Path $Build "FILEEDIT.EXE")
Write-Output ("`nReference FILEEDIT.EXE (Windows link99): {0} bytes, SHA256 {1}" -f $ref.Length, (Get-FileHash $ref.FullName -Algorithm SHA256).Hash.Substring(0,12))
$objs = @("FILESTAT","FILEIO","FILEDATA","TERMIO","CONRX","EBMAP","EDITBUF","VIEWCTL","EDITCTL","EDITMENU",
          "OVLMGR","OVCALL","CALL","IOCORE","IOOPEN","IOREAD","IOWRITE","CBDOS",
          "OVL_WORD","OVL_CHAR","OVL_RPT","OVL_VIEW","OVL_EDIT","OVL_PASTE","OVL_NAMEIO")
$sent = @()
foreach($o in $objs) {
    $src = Get-ChildItem -LiteralPath $Build -Filter ($o + ".R99") | Select-Object -First 1
    if(-not $src) { throw "fileedit\build has no $o.R99" }
    $short = $o
    if($short.Length -gt 8) { $short = $short.Substring(0,8) }     # what the SBC opens
    Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $MonitorDir ($short + ".R99")) -Force
    $sent += ($short + ".R99")
}
foreach($f in @("CLIB99.LIB","CLIB99.NDX")) {
    $src = Get-ChildItem -LiteralPath $Build -Filter $f | Select-Object -First 1
    if(-not $src) { throw "fileedit\build has no $f" }
    Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $MonitorDir $f) -Force
    $sent += $f
}
Copy-Item -LiteralPath (Join-Path $Build "OVLMAP.TXT") -Destination (Join-Path $MonitorDir "FEMAP.TXT") -Force
Copy-Item -LiteralPath (Join-Path $Here "FILEEDIT.LNK") -Destination (Join-Path $MonitorDir "FILEEDIT.LNK") -Force
Copy-Item -LiteralPath (Join-Path $Build "SAMPLE.TXT") -Destination (Join-Path $MonitorDir "SAMPLE.TXT") -Force
$sent += "FEMAP.TXT"
$sent += "SAMPLE.TXT"
$sent += "FILEEDIT.LNK"
Write-Output ("Copied to " + $MonitorDir + " (" + $sent.Count + " files):")
Write-Output ("  " + ($sent -join " "))
Set-Location -LiteralPath $Repo
