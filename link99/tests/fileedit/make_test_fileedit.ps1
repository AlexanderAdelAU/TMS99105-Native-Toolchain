# make_test_fileedit.ps1 -- the SBC LINK99 stage 4 test: link FileEdit on the SBC.
#
# Runs fileedit\make_SBC_FileEdit99.ps1 (which builds every object and
# links FILEEDIT.EXE with the Windows link99 -Y, the reference), then
# copies to MONITOR everything LINK99 needs on the SBC:
#   the 25 objects, CLIB99.LIB/.NDX, FEMAP.TXT (FileEdit's OVLMAP.TXT),
#   FILEEDIT.LNK (written here), and SAMPLE.TXT to run it on.
#
# SBC names: no underscore (the board's XMODEM refuses "_" in a name)
# and at most 8 characters - OVL_WORD.R99 goes as OVLWORD.R99,
# OVL_NAMEIO.R99 as OVLNAMEI.R99.  The map and FILEEDIT.LNK use the same
# names.  -Y matches map modules by FILE name, not by the name inside the
# object, and that name is in none of the output, so FILEEDIT.EXE is the
# same either way (checked in simulation).
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
function SbcName([string]$n) {
    $n = $n -replace '_',''
    if($n.Length -gt 8) { $n = $n.Substring(0,8) }
    return $n.ToUpper()
}
$sent = @()
$lnkObjs = @()
foreach($o in $objs) {
    $src = Get-ChildItem -LiteralPath $Build -Filter ($o + ".R99") | Select-Object -First 1
    if(-not $src) { throw "fileedit\build has no $o.R99" }
    $short = (SbcName $o) + ".R99"
    Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $MonitorDir $short) -Force
    $sent += $short
    $lnkObjs += $short
}
foreach($f in @("CLIB99.LIB","CLIB99.NDX")) {
    $src = Get-ChildItem -LiteralPath $Build -Filter $f | Select-Object -First 1
    if(-not $src) { throw "fileedit\build has no $f" }
    Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $MonitorDir $f) -Force
    $sent += $f
}
# the map, with each module renamed as above; comments, window and guest
# lines as they are
$map = @()
foreach($line in (Get-Content -LiteralPath (Join-Path $Build "OVLMAP.TXT"))) {
    $f = @((($line -replace '#.*$','').Trim()) -split '[ \t]+')
    if($f.Count -ge 4) {
        $m = [regex]::Match($line, '^\s*(\S+)')
        $line = $line.Substring(0, $m.Groups[1].Index) + (SbcName $m.Groups[1].Value) + $line.Substring($m.Groups[1].Index + $m.Groups[1].Length)
    }
    $map += $line
}
Set-Content -LiteralPath (Join-Path $MonitorDir "FEMAP.TXT") -Value $map -Encoding Ascii
$lnk = @("# FILEEDIT.LNK -- on the SBC:  LINK99 @FILEEDIT.LNK",
         "-O1000 -S -YFEMAP.TXT FILEEDIT.EXE") + $lnkObjs + @("CLIB99.LIB")
Set-Content -LiteralPath (Join-Path $MonitorDir "FILEEDIT.LNK") -Value $lnk -Encoding Ascii
Copy-Item -LiteralPath (Join-Path $Build "SAMPLE.TXT") -Destination (Join-Path $MonitorDir "SAMPLE.TXT") -Force
$sent += "FEMAP.TXT"
$sent += "SAMPLE.TXT"
$sent += "FILEEDIT.LNK"
Write-Output ("Copied to " + $MonitorDir + " (" + $sent.Count + " files):")
Write-Output ("  " + ($sent -join " "))
Set-Location -LiteralPath $Repo
