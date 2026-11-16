# SBC LINK99

SBC LINK99 is a ground-up small-machine linker project for the TMS9900/TMS99105 SBC. It starts from the compact historical `LNK.C` algorithm and uses the current **CommonLibrary REL definitions as the canonical object-format contract**. The current Windows `LINK99` remains the regression oracle and, initially, the host linker used to build the SBC version.

The development method deliberately follows the successful FileEdit project: begin with a small, understandable resident program; add one proven capability at a time; keep persistent state separate from disposable passes; and introduce overlays only at natural architectural boundaries.

## Step 0

Step 0 establishes the project and build pipeline. The generated SBC `LINK99.EXE` is only a bootstrap program; it does not link REL files yet. Step 1 will add a canonical REL record reader/dump based on `common/rel99` and `common/Includes`.

## Layout

```text
src/resident/       resident linker/controller source
src/overlays/       future linker code overlays
include/            LINK99-specific interfaces/configuration
common/Includes/    canonical CommonLibrary REL headers
common/rel99/       canonical GETREL/PUTREL/SEEREL sources
common/cfunctions/  shared Small-C helpers
reference/           historical/reference implementations
lib/                 target runtime libraries used to build LINK99
 tools/               Windows-hosted compiler/assembler/linker (link99 3.10.1 or later)
 tests/               repeatable test inputs and expected results
 docs/                architecture and milestone notes
 build/               disposable staged build directory
 dist/                final deliverables only
```

## Build

From PowerShell:

```powershell
.\make_SBC_link99.ps1
```

The script deletes and recreates `build/` and `dist/`, stages the host tools and target libraries into `build/`, compiles and assembles the target sources, then links with the Windows `link99 -YOVLMAP.TXT`. The host linker builds the overlay table and the `runusage` thunk from [`OVLMAP.TXT`](OVLMAP.TXT); the build checks the table it built and that `include/OVLDEFS.INC` agrees with its IDs. The image is linked as `SBC99.EXE` and delivered as `dist\LINK99.EXE`, because the host `link99.exe` and the target `LINK99.EXE` cannot coexist in one folder on Windows. It is also copied to the nearest `TMS99105_SBC\MONITOR` above the project.

Successful Step 0 output:

```text
dist\LINK99.EXE
```

Run on the SBC:

```text
LINK99
```

and expect the bootstrap banner/usage text.

## Overlay-aware from the beginning

The first milestones are resident, but the state/API boundaries are designed so the linker can later map functional passes into an overlay window. Likely future overlays are REL ingest, symbol resolution, library scanning, executable emission and map/diagnostics. Persistent symbol/module/output state will remain resident.

The target executable model is also planned to distinguish **module identity from virtual address**, allowing multiple overlay modules to occupy the same runtime window without confusing external references.

See `docs/ARCHITECTURE.TXT`, `docs/OVERLAY_OWNERSHIP_CONTRACT.TXT`, and `docs/LNK_DECOMPOSITION.TXT`.

## Baseline rule

`common/` is authoritative for REL format definitions. LINK99 must not invent a private duplicate of REL item numbers or grouped-reference semantics.
