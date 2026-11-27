# SBC LINK99

SBC LINK99 is the linker that runs on the TMS9900/TMS99105 SBC. It starts from the compact historical `LNK.C` algorithm and uses the **CommonLibrary REL definitions as the canonical object-format contract**. The Windows `link99` is its regression oracle and the host linker that builds it.

The development method deliberately follows the successful FileEdit project: begin with a small, understandable resident program; add one proven capability at a time; keep persistent state separate from disposable passes; and introduce overlays only at natural architectural boundaries.

## What it does now

- Links `.R99` modules and `.LIB` libraries on the SBC into a `.COM`, a `.LGO` (`-G#`), or a **paged `.EXE`** (`-P#` or an overlay map, `-Y`).
- Output is byte-identical to the Windows `link99` 3.10.3 given the same arguments (checked in simulation: CTEST `.COM`/`.EXE`, FileEdit's `-P` and `-Y` links, the OVL99 hello demo, and a map using aliases, `:tail` and a guest).
- Usage: `LINK99 [-B] [-G#] [-L] [-M] [-O#] [-S] [-Ymap] program [[-P#] module/library...]`
  - `-O#` origin of the resident image (hex, default `1000`); `-S` is accepted and ignored, as on Windows.
  - `-P#` puts the module(s) that follow on page `#` (1-15) until a library resets it to 0, as on Windows. Each must `AORG` itself (e.g. `>8000`) and stay inside one 4K segment.
  - The first name may be the output name (`FILEEDIT.EXE`); otherwise the output is named after the first module.
  - Libraries must come **before** the first `-P` module, or a member loaded after the overlays lands above them and the link is refused.
- `LINK99 @FILE.LNK` reads the arguments from a text file (the shell's command line is 64 characters). Whitespace or line breaks separate them; `#` starts a comment.
- File names are 8.3 on the SBC: `OVL_PASTE.R99` on a command line opens `OVL_PAST.R99`, so such modules must be on the SBC under the cut name. `pack99.ps1` (see [`../pack99`](../pack99/)) cuts names the same way, so packed files arrive right.
- `-Ymap` reads the same OVL99 overlay map as the Windows `link99 -Y` (module page overlay entries; `pub=routine`; `:tail`; `guest`; `window`), places the map modules, renames published entries `~name`, and writes `OVL_TABLE` and the thunks itself (no `OVLGLUE.R99`), with the same checks. Not on the SBC: page spans (`lo-hi`). Limits: 36 modules, 24 overlays, 40 entries.
- `EXT+offset` references (`@OVL_TABLE+2`) keep their offset (up to 32 per program).
- Tests (each makes a Windows reference from the same arguments):
  - `tests/paged`: a `-P` overlay, `LINK99 @T2.LNK` with a CTEST of your own.
  - `tests/ovly`: the OVL99 hello demo with `-Y` (`make_test_ovly.ps1`, then `LINK99 @HELLO.LNK` and `HELLO`).
  - `tests/fileedit`: FileEdit from libraries with `-Y`, sent as one archive (`make_test_fileedit.ps1`, then `XMODEM FE.PAK`, `UNPACK FE`, `LINK99 @FILEEDIT.LNK`).
  - `tests/lcall`: LCALL, the 32-bit arithmetic companion to `CALL.R99` (`make_test_lcall.ps1`, then `LTEST`: 1504 checks against answers computed by `gen_ltest.py`).
- Hardware-tested: `-P` (CTEST + T2), `-Y` (hello demo), and the FileEdit link above, which runs.

## Memory

- Resident code at `>1000`, heap up to `>8000` (three I/O units).
- Overlays behind `>8000` (segment 8): `OVL_USAGE` page 2 (usage, `@file`, argument helpers, `-M` lines), `OVL_FINAL` page 3 (symbol check, sizes, `.COM` output), `OVL_EXE` page 4 (`.EXE` output), and for `-Y` `OVL_MAP` 5, `OVL_GLUE` 6, `OVL_MAPM` 7, `OVL_CHK` 8, `OVL_TAB` 9.
- No number formatting or other library code is called only from an overlay: such a member would be placed above the overlays (`include/PUTNUM.C`, `include/OVLYSUB.C` are compiled into each overlay instead).
- Symbol window `>9000-BFFF` (pages 13-15 of segments 9-B): the `-P` rows and `EXT+offset` table at `>9000`, the `-Y` tables from `>9180` (`include/OVLY.H`), the symbol table, and `@file` arguments at its top.
- Target image in fifteen 4K banks behind segment C: pages 2-15, then page 1 (60K). Segment D is never touched (shell 6.5 keeps its internal commands on D pages 2-10).

## Layout

```text
src/resident/       resident linker/controller source
src/overlays/       linker code overlays and bank markers
include/            LINK99-specific interfaces/configuration
common/Includes/    canonical CommonLibrary REL headers
common/rel99/       canonical GETREL/PUTREL/SEEREL sources
common/cfunctions/  shared Small-C helpers
reference/          historical/reference implementations
lib/                target runtime libraries used to build LINK99
tools/              Windows-hosted smallcp, r99, link99 (3.10.3), lib99, drel
tests/              board tests: paged, ovly, fileedit, lcall
docs/               architecture and overlay notes
build/              disposable staged build directory
dist/               final deliverables only
```

## Build

From PowerShell:

```powershell
.\make_SBC_link99.ps1
```

The script deletes and recreates `build/` and `dist/`, stages the host tools and target libraries into `build/`, compiles and assembles the target sources, then links with the Windows `link99 -YOVLMAP.TXT`. The host linker builds the overlay table and the resident thunks from [`OVLMAP.TXT`](OVLMAP.TXT); the build checks the table it built and that `include/OVLDEFS.INC` agrees with its IDs. The image is linked as `SBC99.EXE` and delivered as `dist\LINK99.EXE`, because the host `link99.exe` and the target `LINK99.EXE` cannot coexist in one folder on Windows. It is also copied to the nearest `TMS99105_SBC\MONITOR` above the project.

See `docs/ARCHITECTURE.TXT`, `docs/OVERLAY_OWNERSHIP_CONTRACT.TXT`, and `docs/LNK_DECOMPOSITION.TXT`.

## Baseline rule

`common/` is authoritative for REL format definitions. LINK99 must not invent a private duplicate of REL item numbers or grouped-reference semantics.
