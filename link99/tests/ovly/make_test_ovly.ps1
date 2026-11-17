# make_test_ovly.ps1 -- build the SBC LINK99 -Y test (the OVL99 hello demo).
#
# Compiles and assembles the demo with link99\tools, links HELLOREF.EXE
# with the Windows link99 -Y as the reference, and copies to MONITOR
# everything LINK99 needs on the SBC:
#     STARTUP.R99 MAIN.R99 OVLMGR.R99 OVCALL.R99 CONOUT.R99 CALL.R99
#     OVLHELLO.R99 OVLGRET2.R99 OVLBYE.R99 CLIB99.LIB CLIB99.NDX
#     HELLOMAP.TXT HELLO.LNK
# On the SBC:   LINK99 @HELLO.LNK    then    HELLO
# HELLO.EXE must have the size printed below for HELLOREF.EXE.
$ErrorActionPreference = "Stop"
$Here  = $PSScriptRoot
$L99   = Split-Path -Parent (Split-Path -Parent $Here)
$Build = Join-Path $Here "build"
$MonitorDir = $env:SBC_MONITOR_DIR
if(-not $MonitorDir) {
    $up = Split-Path -Parent $L99
    while($up) {
        $c = Join-Path $up "TMS99105_SBC\MONITOR"
        if(Test-Path -LiteralPath $c -PathType Container) { $MonitorDir = $c; break }
        $next = Split-Path -Parent $up
        if(-not $next -or $next -eq $up) { break }
        $up = $next
    }
}
if(Test-Path -LiteralPath $Build) { Remove-Item -LiteralPath $Build -Recurse -Force }
New-Item -ItemType Directory -Path $Build | Out-Null
Copy-Item (Join-Path $L99 "tools\*.exe") $Build -Force
Copy-Item (Join-Path $L99 "lib\call.R99"), (Join-Path $L99 "lib\clib99.LIB"), (Join-Path $L99 "lib\clib99.NDX") $Build -Force
Copy-Item (Join-Path $Here "*.C"), (Join-Path $Here "*.A99"), (Join-Path $Here "HELLOMAP.TXT"), (Join-Path $Here "HELLO.LNK") $Build -Force
Push-Location $Build
[Environment]::CurrentDirectory = (Get-Location).Path
try {
    foreach($c in @("OVLHELLO","OVLGRET2","OVLBYE")) {
        $o = & .\smallcp.exe -C -M $c 2>&1 | Out-String
        if($o -notmatch "Errors:\s+0") { Write-Output $o; throw "compile failed: $c" }
    }
    $o = & .\smallcp.exe -C MAIN 2>&1 | Out-String
    if($o -notmatch "Errors:\s+0") { Write-Output $o; throw "compile failed: MAIN" }
    foreach($a in @("OVLHELLO","OVLGRET2","OVLBYE","MAIN","STARTUP","CONOUT","OVLMGR","OVCALL")) {
        $o = & .\r99.exe $a SCHC 2>&1 | Out-String
        if($o -notmatch "No error\(s\)") { Write-Output $o; throw "assemble failed: $a" }
    }
    # the reference: the same arguments as HELLO.LNK, output HELLOREF.EXE
    $args99 = @("-O1000","-S","-YHELLOMAP.TXT","HELLOREF.EXE","STARTUP.R99","MAIN.R99","OVLMGR.R99","OVCALL.R99","CONOUT.R99","CALL.R99","OVLHELLO.R99","OVLGRET2.R99","OVLBYE.R99","CLIB99.LIB")
    $o = & .\link99.exe @args99 2>&1 | Out-String
    if($o -match '(?im)^\s*-\s*Unresolved:|\*{3}\s*FATAL') { Write-Output $o; throw "reference link failed" }
    $ref = Get-Item ".\HELLOREF.EXE"
    Write-Output ("HELLOREF.EXE {0} bytes  SHA256 {1}" -f $ref.Length, (Get-FileHash $ref.FullName -Algorithm SHA256).Hash.Substring(0,12))
    $send = @("STARTUP.R99","MAIN.R99","OVLMGR.R99","OVCALL.R99","CONOUT.R99","call.R99","OVLHELLO.R99","OVLGRET2.R99","OVLBYE.R99","clib99.LIB","clib99.NDX","HELLOMAP.TXT","HELLO.LNK")
    if($MonitorDir -and (Test-Path -LiteralPath $MonitorDir -PathType Container)) {
        foreach($f in $send) { Copy-Item ".\$f" (Join-Path $MonitorDir $f.ToUpper()) -Force }
        Write-Output ("Copied to " + $MonitorDir + ": " + ($send -join " "))
    } else {
        Write-Output ("No MONITOR folder found; the files are in " + $Build)
    }
}
finally {
    Pop-Location
    [Environment]::CurrentDirectory = (Get-Location).Path
}
