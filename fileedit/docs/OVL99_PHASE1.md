# OVL99 / FileEdit integration — phase 1 (Statistics)

> **Historical.** The generator and DREL `-i` steps described here were
> replaced by LINK99 `-Y`, which builds the table and thunks from
> `OVLMAP.TXT`. See `OVL99_PHASE2.md` and the FileEdit README.

Status: **source-level integration only; not yet compiled or tested on the SBC**.

This branch is intentionally separate from `main`. The existing FileEdit
code and document buffer layout are the regression baseline.

## Scope

FileEdit's existing six overlays remain on the same physical pages:

| ID | Code overlay | Physical page | Virtual segment |
|---|---|---|---|
| 1 | OVL_WORD | 2 | 8 (>8000–>8FFF) |
| 2 | OVL_CHAR | 3 | 8 |
| 3 | OVL_RPT | 4 | 8 |
| 4 | OVL_VIEW | 5 | 8 |
| 5 | OVL_EDIT | 6 | 8 |
| 6 | OVL_PASTE | 7 | 8 |

The Statistics paths in `FILESTAT.C` and `EDITMENU.C` now call
`wordscan()`, `charscan()` and `report()` by their own public names.

`OVLSTATS.A99` supplies resident calling thunks for these names.
Each thunk provides an overlay ID and DREL-published entry address to
`OVCALL.A99`, which maps and calls the target before restoring the
caller's mapping for nested overlay calls.

`OVCALL.A99` carries the OVL99 demo's 16-frame nested-call algorithm
and now owns `ovlinit()`. The existing `OVLMGR.A99` remains the
mapper; `OVLMGR_INIT` also clears `CUR_WINA_ID`.

The editor/view/paste entry adapters in `OVLAPI.A99` are unchanged
apart from moving `ovlinit` into OVCALL. The old Statistics adapters
remain for now as unused compatibility code.

**This is an intermediate integration, not the final generated solution.**
The three Statistics thunks are currently written explicitly; bringing
in OVL99's `OVLMAP.TXT`/`ovlgen.ps1` pipeline and converting all
six overlay entry points comes **after** the first Statistics regression
test passes. Do not describe the current branch as fully generated.

## Memory safety contract

- Segment 8 (`>8000–>8FFF`): code overlays only.
- Segments 9–B (`>9000–>BFFF`): editor's independent banked text data.
- Segments C–D (`>C000–>DFFF`): shell / optional document bank.
- Segments E–F: BDOS and ROM; never changed by the overlay manager.

**Do not widen the OVL99 demonstration code window to four segments.**
The existing `EBMAP.A99` document mapping must remain independent.

Published overlay functions must never pass an address into their own
overlay's code/data (including string literals) directly across an
overlay-to-overlay mapping change.

## Build and first hardware regression

From `fileedit/` on Windows, with the supplied cross-tools and the
project's sibling `TMS99105_SBC/MONITOR` deployment directory present:

```powershell
powershell -ExecutionPolicy Bypass -File .\make_SBC_FileEdit99.ps1
```

Check that `drel -c`, `drel -i`, assembly of `OVCALL` and
`OVLSTATS`, and LINK99 complete without unresolved/duplicate symbols.
Confirm that `wordscan`, `charscan`, `report` resolve to **resident
thunks** (not `>8000` overlay addresses).

On the target SBC:

1. Run `FILEEDIT SAMPLE.TXT /S` and compare each Statistics field to the
   unmodified `main` executable's output.
2. Repeat Statistics and the main-menu Statistics action several times,
   ensuring the correct overlay is remapped on each call.
3. Run `FILEEDIT SAMPLE.TXT /E`. Check rendering, navigation, Find,
   Paste mode, Save and Save As, then exit back to the shell.
4. Exercise the bank boundaries using `tests/LARGE16.TXT` and
   `tests/LARGE30.TXT` (open/edit/save/reopen and verify data).
5. Confirm normal shell return and no changes to the document bank cache.

**Not yet proven:** build compatibility, register/stack ABI behaviour
on hardware, nested cross-overlay calls, and the full generator.
The nested-call test should be introduced only after this baseline passes.
