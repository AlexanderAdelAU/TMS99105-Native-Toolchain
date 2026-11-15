# OVL99 glue generator, adapted from the supplied ovl99/tools/ovlgen.ps1.
# FileEdit-specific addition: require EVERY executable overlay to use only
# virtual segment 8; segments 9-B contain bank-switched document data.
#
# -Phase defs:   OVLMAP.TXT -> OVLDEFS.INC, OVLDESC.TXT
# -Phase thunks: OVLMAP.TXT + DREL includes -> OVLTHUNK.A99
param(
    [Parameter(Mandatory=$true)][ValidateSet("defs","thunks")][string]$Phase,
    [Parameter(Mandatory=$true)][string]$Map,
    [string]$Dir=".",
    [string]$DefsOut="OVLDEFS.INC",
    [string]$DescOut="OVLDESC.TXT",
    [string]$ThunkOut="OVLTHUNK.A99"
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version 2.0

function Fail([string]$Message) { throw "*** OVLGEN: $Message" }
if(-not (Test-Path -LiteralPath $Map -PathType Leaf)) { Fail "missing map $Map" }
if(-not (Test-Path -LiteralPath $Dir -PathType Container)) { Fail "missing output directory $Dir" }
$Dir = (Resolve-Path -LiteralPath $Dir).Path

$mods=@()
$ids=@{}
$order=@()
$seenPages=@{}
$seenEntries=@{}
$aliases=@{}
$lineNo=0
foreach($raw in (Get-Content -LiteralPath $Map)) {
    $lineNo++
    $line=($raw -replace '#.*$','').Trim()
    if($line -eq '') { continue }
    $f=@($line -split '[ \t]+' | Where-Object { $_ -ne '' })
    if($f.Count -lt 4) { Fail "map line $lineNo needs module, page, overlay, entries" }
    $module=$f[0]; $page=0; $overlay=$f[2]
    if($module -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or
       $overlay -cnotmatch '^[A-Z][A-Z0-9_]*$') { Fail "bad module or overlay name at line $lineNo" }
    if(-not [int]::TryParse($f[1],[ref]$page) -or $page -lt 1 -or $page -gt 15) {
        Fail "invalid physical page at line $lineNo"
    }
    if($seenPages.ContainsKey($page)) { Fail "page $page used by more than one module" }
    $seenPages[$page]=$module
    if(-not $ids.ContainsKey($overlay)) {
        $order += $overlay
        $ids[$overlay]=$order.Count
    }
    $entries=@()
    foreach($entry in $f[3..($f.Count-1)]) {
        if($entry -eq '-') { continue }
        if($entry -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $entry.Length -gt 12) {
            Fail "entry '$entry' has invalid assembler symbol at line $lineNo"
        }
        if($seenEntries.ContainsKey($entry)) { Fail "entry '$entry' published twice" }
        $seenEntries[$entry]=$module
        $alias='O_'+$entry.ToUpperInvariant()
        if($alias.Length -gt 12) { $alias=$alias.Substring(0,12) }
        if($aliases.ContainsValue($alias)) { Fail "DREL alias collision on $alias" }
        $aliases[$entry]=$alias
        $entries += $entry
    }
    $mods += [pscustomobject]@{Name=$module;Page=$page;Overlay=$overlay;Id=$ids[$overlay];Entries=$entries}
}
if($mods.Count -eq 0) { Fail "empty overlay map" }
if($order.Count -gt 15) { Fail "too many logical overlay IDs (max 15)" }

if($Phase -eq 'defs') {
    $defs=@('; GENERATED: overlay IDs from OVLMAP.TXT, do not edit','')
    foreach($overlay in $order) {
        $defs += ("OVL_{0} EQU {1}" -f $overlay,$ids[$overlay])
    }
    $descriptors=@()
    foreach($m in $mods) {
        $parts=@()
        foreach($entry in $m.Entries) { $parts += "$($entry):$($aliases[$entry])" }
        if($parts.Count -eq 0) { $parts += '-:-' }
        $descriptors += ("{0}.R99={1},{2},{3}" -f $m.Name,$m.Page,$m.Id,($parts -join ','))
    }
    [IO.File]::WriteAllText((Join-Path $Dir $DefsOut),($defs -join "`r`n")+"`r`n",[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $Dir $DescOut),($descriptors -join "`r`n")+"`r`n",[Text.Encoding]::ASCII)
    Write-Output ("OVLGEN defs: {0} overlays, {1} modules, {2} entries" -f $order.Count,$mods.Count,$seenEntries.Count)
    exit 0
}

$addrFile=Join-Path $Dir 'OVLADDR.INC'
$tableFile=Join-Path $Dir 'OVLTABLE.INC'
foreach($file in @($addrFile,$tableFile)) {
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "missing $file; run DREL -i first" }
}
$addressText=Get-Content -LiteralPath $addrFile -Raw
foreach($entry in @($seenEntries.Keys)) {
    $alias=$aliases[$entry]
    if($addressText -notmatch ('(?im)^\s*'+[regex]::Escape($alias)+'\s+EQU\s+0*[0-9A-F]+H')) {
        Fail "DREL did not publish $alias for $entry"
    }
}

# DREL's table format is WORD <segment,page,...> ; ... ID <n>.
# The original OVL99 allows 16K contiguous code overlays. FileEdit cannot:
# its live text arena occupies 9-B, so require exactly one segment: 8.
$rows=@{}
foreach($line in (Get-Content -LiteralPath $tableFile)) {
    $match=[regex]::Match($line,'^\s*WORD\s+([0-9, \t]+?)\s*;[^\r\n]*\bID\s+(\d+)\b','IgnoreCase')
    if(-not $match.Success) { continue }
    $words=@()
    foreach($value in ($match.Groups[1].Value -split ',')) {
        if($value.Trim() -ne '') { $words += [int]$value.Trim() }
    }
    $rows[[int]$match.Groups[2].Value]=$words
}
foreach($overlay in $order) {
    $id=$ids[$overlay]
    if(-not $rows.ContainsKey($id)) { Fail "DREL table missing overlay ID $id ($overlay)" }
    $words=$rows[$id]
    $segments=@()
    for($i=0; $i -lt $words.Count; $i+=2) {
        if($words[$i] -ne 0) { $segments += $words[$i] }
    }
    if($segments.Count -ne 1 -or $segments[0] -ne 8) {
        Fail "OVL_$overlay maps segments [$($segments -join ',')]; FileEdit allows only segment 8"
    }
}

$thunks=@(
    '; GENERATED OVL99 public-function thunks. Do not edit.',
    '; Names and overlay IDs come from OVLMAP.TXT, entry addresses from DREL.',
    '        DXOP CALL,6',
    '        DXOP RET,7',
    'R1      EQU 1',
    'R2      EQU 2',
    '        INCL "OVLDEFS.INC"',
    '        INCL "OVLADDR.INC"',
    '        EXT OVCALL',
    ''
)
foreach($overlay in $order) {
    foreach($m in @($mods | Where-Object { $_.Overlay -eq $overlay })) {
        foreach($entry in $m.Entries) {
            $thunks += ("{0}:" -f $entry)
            $thunks += ("        LI R1,OVL_{0}" -f $overlay)
            $thunks += ("        LI R2,{0}" -f $aliases[$entry])
            $thunks += '        B @OVCALL'
            $thunks += ''
        }
    }
}
foreach($entry in @($seenEntries.Keys | Sort-Object)) {
    $thunks += ("        ENT {0}" -f $entry)
}
$thunks += '        END'
[IO.File]::WriteAllText((Join-Path $Dir $ThunkOut),($thunks -join "`r`n")+"`r`n",[Text.Encoding]::ASCII)
Write-Output ("OVLGEN thunks: {0} resident thunks; every code overlay uses only segment 8" -f $seenEntries.Count)
exit 0
