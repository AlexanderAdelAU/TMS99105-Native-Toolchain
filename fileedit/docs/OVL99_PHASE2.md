# FileEdit + OVL99: generated overlay glue and nested-call test

**Branch:** `ovl99-fileedit-integration` (not merged into `main`).

This is the next integration stage after the initial handwritten Statistics
thunks described in `OVL99_PHASE1.md`. The phase-one notes are retained as
historical development notes; the current branch has **replaced** the manual
thunks and adapters with generated ones.

## Single source of truth

`fileedit/OVLMAP.TXT` lists each `.C` overlay module, its physical page,
its logical overlay ID (assigned by map order), and its public functions.
There are six overlays:

| Page | Overlay | Published entries |
|---|---|---|
| 2 | WORD | `wordscan`, `ovprobea` |
| 3 | CHAR | `charscan`, `ovprobeb` |
| 4 | RPT | `report`, `ovprobec` |
| 5 | VIEW | `viewfile` |
| 6 | EDIT | `editstep` |
| 7 | PASTE | `pasteedit` |

The adapted OVL99 `tools/ovlgen.ps1` has two phases:

1. `defs`, before compilation: `OVLDEFS.INC` and `OVLDESC.TXT`.
2. `thunks`, after DREL publishes `OVLADDR.INC` and `OVLTABLE.INC`:
   `OVLTHUNK.A99`, one resident public-name thunk per published entry.

The build no longer contains hand-maintained overlay IDs, page arguments,
public DREL entry aliases, or per-function assembly adapters. The
`OVLMGR.A99` map writer and `OVCALL.A99` return-frame stack remain
resident. The old `OVLAPI.A99`, `OVLSTATS.A99` and manually maintained
`OVLDEFS.INC` have been removed.

## Critical FileEdit-specific constraint

**Code overlays map only segment 8 (`>8000–>8FFF`).** The generator
rejects DREL tables that map code overlays into any other segment.
This deliberately tightens the original OVL99 demo, where overlays could
span a 16 KB code window. FileEdit already uses `>9000–>BFFF` for
paged document text and can use `>C000–>DFFF` for further editor data.
`EBMAP.A99` retains exclusive responsibility for these windows.
BDOS and ROM remain untouched.

Functions in overlay A must not pass pointers to data or string literals
located in A when calling a function in overlay B, because B replaces A
at the same virtual address.

## Call behaviour

Application code calls its functions normally, e.g. `viewfile()` and
`editstep()`. The generated resident thunks set R1 to the overlay ID,
R2 to the DREL entry address, and branch to `OVCALL`.

`OVCALL` takes a fast path when the correct page is already mapped.
Otherwise it saves the original return address and previous overlay
owner in an internal 16-frame stack, maps the new page, calls the function,
restores the previous owner, and then returns to the original caller.
The C return value in R4 is preserved by the mapper.

## Windows cross-build

Normal local checkout with the sibling MONITOR folder:

```powershell
cd fileedit
powershell -ExecutionPolicy Bypass -File .\make_SBC_FileEdit99.ps1
```

For an isolated checkout or CI without the MONITOR folder:

```powershell
$env:FILEEDIT_SKIP_MONITOR_DEPLOY = "1"
powershell -ExecutionPolicy Bypass -File .\make_SBC_FileEdit99.ps1
```

A branch-specific Windows GitHub Actions workflow builds and uploads the
`FILEEDIT.EXE` binary. A successful Actions run proves the cross-toolchain
build and linker checks, **not** correct execution on a physical SBC.

## Hardware test — overlay nesting

Run:

```text
FILEEDIT /O
```

Expected:

```text
OVL99 NESTED PASS
```

The test is `Resident → WORD → CHAR → RPT → CHAR → WORD → Resident`:

- WORD calls `ovprobeb(7)` and expects 109.
- CHAR calls `ovprobec(8)` and expects 108.
- RPT returns 108, CHAR returns 109, WORD returns 110.
- The resident caller checks for 110 before displaying PASS.

This validates passed arguments, nested calls and returned values and
requires execution to resume at valid addresses in each restored overlay.
If the display says FAIL or the machine hangs, do not merge into `main`.

## Regression after the nesting test

1. `FILEEDIT SAMPLE.TXT /S`: compare all Statistics fields against
   a known-good `main` executable.
2. `FILEEDIT SAMPLE.TXT /E`: navigation, Find / Find Next,
   line redraw, terminal paste, Save, Save As and exit.
3. Repeat Statistics from within FileEdit's editor menu.
4. `tests/LARGE16.TXT` and `tests/LARGE30.TXT`: edit and save
   across document-bank boundaries, reopen and compare bytes.
5. Quit back to the shell, run an ordinary command, and confirm
   the shell segments and BDOS access are intact.

**Merge rule:** remain on the integration branch until the Windows
cross-build and SBC regressions have both passed.
