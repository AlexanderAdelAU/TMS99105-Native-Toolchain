# make_unpack.ps1 -- build UNPACK.COM and copy it, with pack99.ps1's
# instructions, to the SBC MONITOR folder.
#
# UNPACK.A99 is assembled with r99 and linked with link99 (both from
# link99\tools) into a flat .COM at >1000.  Send it to the SBC once with
# XMODEM UNPACK.COM; after that one XMODEM of an archive brings any number
# of files (see pack99.ps1).
$ErrorActionPreference = "Stop"
$Here  = $PSScriptRoot
$Repo  = Split-Path -Parent $Here
$Tools = Join-Path $Repo "link99\tools"
$Build = Join-Path $Here "build"
if(Test-Path -LiteralPath $Build) { Remove-Item -LiteralPath $Build -Recurse -Force }
New-Item -ItemType Directory -Path $Build | Out-Null
Copy-Item (Join-Path $Tools "r99.exe"), (Join-Path $Tools "link99.exe"), (Join-Path $Here "UNPACK.A99") $Build -Force
Push-Location $Build
[Environment]::CurrentDirectory = (Get-Location).Path
try {
    $o = & .\r99.exe UNPACK SCHCLC 2>&1 | Out-String
    if($o -notmatch "No error\(s\)") { Write-Output $o; throw "assemble failed: UNPACK" }
    $o = & .\link99.exe -O1000 UNPACK.COM UNPACK.R99 2>&1 | Out-String
    if($o -match '(?im)^\s*-\s*Unresolved:|\*{3}\s*FATAL' -or -not (Test-Path ".\UNPACK.COM")) { Write-Output $o; throw "link failed: UNPACK" }
    $com = Get-Item ".\UNPACK.COM"
    Write-Output ("UNPACK.COM {0} bytes" -f $com.Length)
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
    if($MonitorDir -and (Test-Path -LiteralPath $MonitorDir -PathType Container)) {
        Copy-Item ".\UNPACK.COM" (Join-Path $MonitorDir "UNPACK.COM") -Force
        Write-Output ("Copied to " + (Join-Path $MonitorDir "UNPACK.COM"))
    } else {
        Write-Output ("No MONITOR folder found; UNPACK.COM is in " + $Build)
    }
}
finally {
    Pop-Location
    [Environment]::CurrentDirectory = (Get-Location).Path
}
