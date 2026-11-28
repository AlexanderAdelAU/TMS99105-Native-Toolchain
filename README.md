# TMS99105 Native Toolchain

The native development tools for the **TMS99105 SBC4**: a C compiler, assembler, linker and
full-screen editor that all run **on the SBC itself**. Once they are on the board you can edit,
compile, assemble, link and run programs without a PC.

| Tool | Runs on the SBC as | What it does | Source |
|---|---|---|---|
| SMALLC99 | `SMALLC99.EXE` | Small-C compiler with structs, unions and multi-dimensional arrays | [SmallC99-TMS99105-Native-C-Compiler](https://github.com/AlexanderAdelAU/SmallC99-TMS99105-Native-C-Compiler) |
| SBCR99 | `R99.COM` | Relocating assembler: `.A99` → `.R99` | [`r99/`](r99/) |
| SBC LINK99 | `LINK99.EXE` | Linker: `.R99` + libraries → `.COM`, or a paged `.EXE` with overlays (`-P`, `-Y` overlay map) | [`link99/`](link99/) |
| FileEdit | `FILEEDIT.EXE` | Full-screen VT100/ANSI text editor | [`fileedit/`](fileedit/) |
| UNPACK | `UNPACK.COM` | Unpacks a PACK99 archive: many files in one XMODEM transfer (packed on Windows by `pack99.ps1`) | [`pack99/`](pack99/) |

Ready-built copies of the first four are in [`bin/`](bin/). `SMALLC99.EXE` is
current (SmallC99 main, 28 Nov 2026); `R99.COM`, `LINK99.EXE` and `FILEEDIT.EXE`
date from the repository's first commit, and the build scripts below make the
current versions.

---

## Two toolchains, two stages

There are **two toolchains with the same tool names**, and it matters which one you are using:

- **Cross toolchain (Windows):** `smallcp.exe`, `r99.exe`, `link99.exe` and `drel.exe` run on a PC
  and produce code for the TMS9900. They are only needed to *build* the native tools.
- **Native toolchain (SBC4):** `SMALLC99`, `R99`, `LINK99` and `FILEEDIT` run on the TMS99105.
  This is what you use day to day on the board.

```
Stage 1 – on Windows, with the cross toolchain
  smallcp.exe ─► r99.exe ─► link99.exe
       │
       ▼  builds
  SMALLC99.EXE   R99.COM   LINK99.EXE   FILEEDIT.EXE

Stage 2 – on the SBC4, with the native toolchain
  copy those files to the SBC, then:
  FILEEDIT ─► SMALLC99 ─► R99 ─► LINK99 ─► your program
  (no PC needed from here on)
```

Once Stage 1 has produced the native tools, they run independently of the cross toolchain.

**If you only want to use the tools on the SBC, skip Stage 1** and copy the files from
[`bin/`](bin/) to the board.

---

## Stage 2 – using the tools on the SBC

Copy `SMALLC99.EXE`, `R99.COM`, `LINK99.EXE` and `FILEEDIT.EXE` to the SBC, together with the
run-time library `IOLIB99.LIB` and its index `IOLIB99.NDX` (in the SmallC99 repository's `lib/`
folder). Then:

```
[TOOLS]%FILEEDIT HELLO.C
[TOOLS]%SMALLC99 HELLO
[TOOLS]%R99 HELLO
[TOOLS]%LINK99 HELLO.R99 IOLIB99.LIB
[TOOLS]%HELLO
```

A link with more arguments than the shell's 64-character command line goes in a text file:
`LINK99 @PROG.LNK`. See the [SBC LINK99 README](link99/README.md) for overlays (`-P`, `-Y`).

### Moving files to the SBC

- **One file:** `XMODEM NAME.EXT` on the SBC, then send it from Tera Term (XMODEM, CRC or 1K).
  XMODEM 1.9Q or later takes `_` in names, e.g. `XMODEM OVL_WORD.R99`.
- **Many files:** pack them on Windows into one archive, send that, unpack it on the SBC:

  ```powershell
  & .\pack99\pack99.ps1 C:\...\MONITOR\JOB.PAK file1.R99 file2.LIB *.TXT
  ```
  ```
  %XMODEM JOB.PAK
  %UNPACK JOB
  ```
  `UNPACK.COM` is built by `pack99\make_unpack.ps1` and sent once with XMODEM.
- **Names** on the SBC are 8.3, upper case, `A-Z 0-9 _`. A longer name is cut to 8 + 3
  (`OVL_NAMEIO.R99` is opened as `OVL_NAME.R99`); `pack99.ps1` cuts names the same way.

## Stage 1 – building the native tools on Windows

Each tool has its own folder with a PowerShell build script and its own copy of the Windows cross
tools, so each can be built on its own:

| Tool | Build script | Cross tools used from |
|---|---|---|
| SBCR99 | `r99\make_R99_SBC.ps1` | `r99\toolchain\` |
| SBC LINK99 | `link99\make_SBC_link99.ps1` | `link99\tools\` |
| FileEdit | `fileedit\make_SBC_FileEdit99.ps1` | `fileedit\tools\` |
| UNPACK | `pack99\make_unpack.ps1` | `link99\tools\` |
| SMALLC99 | `make_smallc99.ps1` in the [SmallC99 repository](https://github.com/AlexanderAdelAU/SmallC99-TMS99105-Native-C-Compiler) | its `toolchain\` |

Run a script from PowerShell in its own folder, for example:

```
cd r99
powershell -ExecutionPolicy Bypass -File .\make_R99_SBC.ps1
```

The scripts finish by copying the result into the "MONITOR" folder used to download files to the
SBC: the nearest `TMS99105_SBC\MONITOR` in a folder above the repository, or the folder named by
the `SBC_MONITOR_DIR` environment variable.

**Building on Windows remains the normal route** for the tools themselves and for FileEdit: one
`.EXE` to download. Linking on the SBC is for programs developed on the SBC.

The source of the Windows cross tools themselves is in
[Relocating-Assembler-and-Linker-Loader-for-TMS99000](https://github.com/AlexanderAdelAU/Relocating-Assembler-and-Linker-Loader-for-TMS99000)
(`r99`, `link99`, `drel`) and
[Small-C-Plus-for-TMS9900-99000](https://github.com/AlexanderAdelAU/Small-C-Plus-for-TMS9900-99000)
(`smallcp`).

---

## How FileEdit's OVL99 overlays work

FileEdit now uses **seven physical code overlays** behind the shared
`>8000–>8FFF` window. The application makes ordinary C calls (for example
`viewfile()`); *resident thunks* select the correct overlay through
`OVCALL`/`OVLMGR`, including return to a previously mapped overlay after
nested calls.

**The Windows LINK99 builds the overlay glue itself** (3.10.x, `-Y`), as
2.11BSD's `ovld` did. `OVLMAP.TXT` is the only declaration: the linker places
each module on its page, builds the overlay table and one thunk per published
entry, and checks the window rules at link time. No generator script, DREL
step or generated include file is involved. The map format is documented in
the [link99 README](https://github.com/AlexanderAdelAU/Relocating-Assembler-and-Linker-Loader-for-TMS99000#overlay-map--y).
This has been tested on the TMS99105 SBC, including nested overlay calls and a
roughly 33 KB FileEdit save-and-backup test.

The native SBC LINK99 reads the same map (`-Y`) and builds the same glue. FileEdit is normally
linked on the PC; [`link99/tests/fileedit`](link99/tests/fileedit/) links it on the SBC from one
`FE.PAK` archive (`XMODEM FE.PAK`, `UNPACK FE`, `LINK99 @FILEEDIT.LNK`), and the result is the
same `FILEEDIT.EXE` the Windows link99 makes from those files.

**[OVL99.md](OVL99.md) is the reference** for the runtime, the table, the map and
the rules.

The current build still assigns **whole modules to pages manually**;
automatic module/function placement is a proposed future toolchain
phase, not a current feature. See the
[step-by-step implementation explanation](fileedit/README.md#how-transparent-overlays-work)
and [FileEdit overlay map](fileedit/OVLMAP.TXT).

---

## Related

- [TMS99105-SBC](https://github.com/AlexanderAdelAU/TMS99105-SBC): the hardware
- [TMS99105-SBC-V4-Paged-Memory-System](https://github.com/AlexanderAdelAU/TMS99105-SBC-V4-Paged-Memory-System): the 1MB memory mapper the tools' overlays use
- [BDOS-FOR-THE-TMS9900](https://github.com/AlexanderAdelAU/BDOS-FOR-THE-TMS9900) and [Small-Shell-for-the-TMS9900](https://github.com/AlexanderAdelAU/Small-Shell-for-the-TMS9900): the operating system and shell
