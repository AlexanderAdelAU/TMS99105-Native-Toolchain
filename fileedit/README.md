
# FileEdit for the TMS9900/TMS99105 SBC

FileEdit is a small full-screen text editor for a TMS9900-family
single-board computer, designed for use through a VT100/ANSI terminal
such as Tera Term.

It began as **FILESTAT**, a technical tutorial project demonstrating a
resident kernel with mapped code overlays. It then evolved milestone by
milestone into an editor while retaining the original file-statistics
functionality.

## Current milestone

Current features include full-screen VT100/ANSI editing, a display-only
line-number gutter, cursor navigation, insertion/deletion, real ASCII
TABs, Open/New/Save/Save As, `[MOD]` dirty-state indication, rolling
`.BAK` backups, post-save verification, the original FILESTAT
statistics, seven generated OVL99 code overlays, and interrupt-buffered
TMS9902 receive input using a 64-byte resident ring.

`FILESTAT.EXE` is still produced as a byte-identical compatibility
alias, but **FILEEDIT.EXE** is the primary application.

## Screenshots

### FileEdit main menu

![FileEdit Step 7 main menu in Tera Term](fileedit-menu.png)

The main menu provides Edit, Open, New, Save, Save As, View, Statistics and Quit while retaining the current document in resident editor state.

### Full-screen editor with display-only line numbers

![FileEdit editing TEST.C with line-number gutter in Tera Term](fileedit-editor.png)

The editor runs directly in the VT100/ANSI terminal. The line-number gutter is rendered by `OVL_VIEW`; the numbers are not part of the document and are never saved. The status line shows the logical line/column and the principal navigation and save commands.

## Typical use

```text
FILEEDIT TEST.C /E    Open the full-screen editor
FILEEDIT TEST.C /S    Run file statistics
FILEEDIT /O           Test nested cross-overlay calls
```

`FILEEDIT /O` should report `OVL99 NESTED PASS` on the SBC. The current
`FILESTAT.C` command-line parser exposes these three modes; older tutorial
examples of `/L`, `/V` and `/I` are historical and are not current CLI modes.

## Editor keys

  Key           Action
  ------------- -----------------------------------
  Arrow keys    Move cursor
  Home / End    Start / end of logical line
  PgUp / PgDn   Move by a screen
  Tab           Insert a real ASCII `09` TAB
  Backspace     Delete character to the left
  Delete        Delete character under the cursor
  Enter         Split the line
  Ctrl-O        Save and verify
  Ctrl-X        Return to the FileEdit menu

Line numbers are rendered screen decoration. They are not stored,
editable, saved, or included in FILESTAT statistics.

## Architecture

```text
>1000-7FFF   resident FileEdit, OVCALL/OVLMGR, editor state, I/O, RX
>8000-8FFF   one OVL99-mapped code overlay at a time (segment 8)
>9000-BFFF   12 KB editor data window, physical pages 0 and 1
>C000-DFFF   shell page 0 / 8 KB editor data in page 1 while active
>E000-EFFF   BDOS (untouched by FileEdit)
>F000-FFFF   ROM / MONITOR
```

The document also uses safely claimed resident heap space between
banked regions. At runtime, editor capacity is `32767 + ebheapsz` bytes,
with a byte reserved for the trailing sentinel.

Overlay assignments:

``` text
page 2   OVL_WORD   statistics word/line pass
page 3   OVL_CHAR   character-class pass
page 4   OVL_RPT    report formatter
page 5   OVL_VIEW   viewer/editor frame renderer
page 6   OVL_EDIT   key decoding and editing operations
page 7   OVL_PASTE  terminal paste/edit handling
page 8   OVL_NAMEIO filename prompt
```

`OVLMAP.TXT` is the source of truth for module IDs, physical pages and
published entry names. `tools/ovlgen.ps1` and DREL produce the address
includes, overlay table and resident calling thunks (`OVLTHUNK.A99`).
Calls such as `viewfile()` and `editstep()` go through those thunks and
`OVCALL` rather than manually mapping overlays. The manager maintains
a 16-frame stack for nested overlay calls, and generated map validation
prevents code overlays from overwriting the data banks.

DREL also lints relocation chains and checks one-page overlay size limits.
The build checks that published overlay functions resolve to resident
thunks rather than directly to virtual overlay addresses.

## TMS9902 receive architecture

Blocking console input worked until full-screen scrolling became
expensive enough for bytes of VT100 cursor-key sequences to be lost.
`ESC [ B`, for example, could be reduced to a lone `B` and inserted into
the document.

FileEdit now temporarily hooks the writable **INT4 handler PC at
`>0012`**, retaining the MONITOR's existing INT4 workspace at `>0010`.

``` text
Tera Term
   |
TMS9902
   |
INT4
   |
FileEdit RXISR
   |
64-byte resident ring
   |
TERMIO / ANSI decoder
   |
OVL_EDIT
```

The ISR is pure assembly: no C calls, BDOS calls, stack use, terminal
output, disk work, or overlay mapping. Because interrupt entry switches
workspace, it explicitly loads `R12` with the TMS9902 serial CRU base
`>0080`.

For a received byte it inhibits/acknowledges receiver interrupts with
`SBZ 18`, drains the receive buffer with `STCR`, queues the byte, and
re-arms the receiver with `SBO 18`.

FileEdit then **always chains to the previously installed INT4
handler**. The previous owner remains responsible for timer or other
INT4 work and performs the final `RTWP`. FileEdit therefore adds an RX
service without claiming exclusive ownership of INT4.

The original development notes include a standalone `/I` interrupt test.
The current OVL99 `FILESTAT.C` command-line driver does not expose that
historical diagnostic; use the editor's keyboard navigation to check
normal RX behaviour.

## Save safety

For an existing target FileEdit first makes a `.BAK`, writes the editor
contents, closes and reopens the file, and verifies it against the RAM
document. Dirty state is cleared only after verification succeeds.

## Building

The supplied Windows-hosted toolchain contains:

-   `smallcp.exe`
-   `r99.exe`
-   `drel.exe`
-   `link99.exe`

From the `fileedit/` directory run on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\make_SBC_FileEdit99.ps1
```

Set `$env:FILEEDIT_SKIP_MONITOR_DEPLOY = "1"` when building without the
sibling monitor directory. `.github/workflows/ovl99-fileedit.yml` runs
the same build in Windows GitHub Actions.

The script stages inputs into `build\`, compiles resident modules and
overlays, runs DREL chain lint, generates overlay tables, checks
one-page overlay budgets, links, and writes:

``` text
dist\FILEEDIT.EXE
dist\FILESTAT.EXE
dist\SAMPLE.TXT
```

The script also deploys to a sibling MONITOR workspace. Adjust
`$MonitorDir` if your checkout layout differs.

## Repository layout

``` text
src\resident\      resident C and assembly modules
src\overlays\      mapped code overlays
OVLMAP.TXT         canonical overlay declarations
tools\ovlgen.ps1    generated overlay descriptors and thunks
lib\               runtime objects and libraries
tools\             compiler/assembler/DREL/linker
tests\             repeatable sample input
docs\              architecture and milestone notes
build\             disposable build directory
dist\              final executable output
```

## Hardware assumptions

The current build assumes a TMS9900-family/TMS99105-compatible SBC,
TMS9902 at serial CRU base `>0080`, its interrupt connected to CPU INT4,
writable interrupt vectors in common RAM, the MONITOR-provided INT4
workspace/timer service, the existing BDOS interface, and VT100/ANSI
terminal behavior compatible with Tera Term.

## Documentation

The repository deliberately preserves the development/tutorial history.
Particularly useful files are:

-   `docs/STEP6_3_OVLEDIT.TXT` --- introduction of the fifth overlay;
-   `docs/STEP7_FILEEDIT.TXT` --- FileEdit rename and display-only
    line-number gutter;
-   `docs/STEP7_1_INT4RX.TXT` --- interrupt-driven receive development;
-   `docs/MEMMAP.TXT` --- current memory and overlay map;
-   `EDITSTEP*.TXT` --- short hardware bench-test cards.

## OVL99 hardware verification (November 2026)

The TMS99105 SBC has reported `OVL99 NESTED PASS` for the test path
`Resident → WORD → CHAR → RPT → CHAR → WORD → Resident`.

After transfer to a replacement disk image, a regular document was edited,
saved, and automatically backed up. The modified main file and original
backup content were verified by reopening. A 16 KB regression document
crossing the 12 KB editor-bank boundary was navigated, edited on line 171,
saved, and reopened. `L16TEST.TXT` retained `X0171`; `L16TEST.BAK`
retained the original `0171`.

The user also concatenated two 16 KB tests into an approximately 33 KB
document. FileEdit navigated to EOF, then saved a copy as `L33TEST.TXT`,
changed the beginning of line 430, saved again, and reopened both files:
the main file retained `X0211` while `L33TEST.BAK` retained `0211`.
That exercises the adaptive heap plus shell-window data bank while
OVL99 controls the independent code-overlay window.

The Windows cross-build has passed. An intermittent `TYPE` / INT2 fault
has also been reproduced after SYSGEN **without FileEdit installed or
running**. Its cause remains unresolved, and it is tracked separately in
`docs/OVL99_INT2_INVESTIGATION.md`; it must not be reported as fixed by
these overlay tests.

For implementation and regression details, see `docs/OVL99_PHASE2.md`.
The original tutorial documentation is retained for historical context.

## Historical note

Internal source names such as `FILESTAT.C` are intentionally retained.
FILESTAT is the project's origin and remains the statistics subsystem;
renaming every internal module would add churn without improving the
architecture.
