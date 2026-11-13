# TMS99105 Native Toolchain

The native development tools for the **TMS99105 SBC4**: a C compiler, assembler, linker and
full-screen editor that all run **on the SBC itself**. Once they are on the board you can edit,
compile, assemble, link and run programs without a PC.

| Tool | Runs on the SBC as | What it does | Source |
|---|---|---|---|
| SMALLC99 | `SMALLC99.EXE` | Small-C compiler with structs, unions and multi-dimensional arrays | [SmallC99-TMS99105-Native-C-Compiler](https://github.com/AlexanderAdelAU/SmallC99-TMS99105-Native-C-Compiler) |
| SBCR99 | `R99.COM` | Relocating assembler: `.A99` → `.R99` | [`r99/`](r99/) |
| SBC LINK99 | `LINK99.EXE` | Linker: `.R99` + libraries → `.COM` / `.EXE` | [`link99/`](link99/) |
| FileEdit | `FILEEDIT.EXE` | Full-screen VT100/ANSI text editor | [`fileedit/`](fileedit/) |

Ready-built copies of all four are in [`bin/`](bin/).

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
run-time library `IOLIB99.LIB` (in the SmallC99 repository's `lib/` folder). Then:

```
[TOOLS]%FILEEDIT HELLO.C
[TOOLS]%SMALLC99 HELLO
[TOOLS]%R99 HELLO
[TOOLS]%LINK99 HELLO.R99 IOLIB99.LIB
[TOOLS]%HELLO
```

## Stage 1 – building the native tools on Windows

Each tool has its own folder with a PowerShell build script and its own copy of the Windows cross
tools, so each can be built on its own:

| Tool | Build script | Cross tools used from |
|---|---|---|
| SBCR99 | `r99\make_R99_SBC.ps1` | `r99\toolchain\` |
| SBC LINK99 | `link99\make_SBC_link99.ps1` | `link99\tools\` |
| FileEdit | `fileedit\make_SBC_FileEdit99.ps1` | `fileedit\tools\` |
| SMALLC99 | `make_smallc99.ps1` in the [SmallC99 repository](https://github.com/AlexanderAdelAU/SmallC99-TMS99105-Native-C-Compiler) | its `toolchain\` |

Run a script from PowerShell in its own folder, for example:

```
cd r99
powershell -ExecutionPolicy Bypass -File .\make_R99_SBC.ps1
```

Some scripts finish by copying the result into a local "MONITOR" folder used to download files to
the SBC. If that folder does not exist on your machine, edit the path near the top of the script.

The source of the Windows cross tools themselves is in
[Relocating-Assembler-and-Linker-Loader-for-TMS99000](https://github.com/AlexanderAdelAU/Relocating-Assembler-and-Linker-Loader-for-TMS99000)
(`r99`, `link99`, `drel`) and
[Small-C-Plus-for-TMS9900-99000](https://github.com/AlexanderAdelAU/Small-C-Plus-for-TMS9900-99000)
(`smallcp`).

---

## Related

- [TMS99105-SBC](https://github.com/AlexanderAdelAU/TMS99105-SBC): the hardware
- [TMS99105-SBC-V4-Paged-Memory-System](https://github.com/AlexanderAdelAU/TMS99105-SBC-V4-Paged-Memory-System): the 1MB memory mapper the tools' overlays use
- [BDOS-FOR-THE-TMS9900](https://github.com/AlexanderAdelAU/BDOS-FOR-THE-TMS9900) and [Small-Shell-for-the-TMS9900](https://github.com/AlexanderAdelAU/Small-Shell-for-the-TMS9900): the operating system and shell
