# OVL99 — code overlays on the TMS99105 SBC

OVL99 lets a program be larger than the 28K of common memory by keeping parts of its
code on physical pages that are mapped into the window at `>8000`–`>BFFF` when they
are called. A call into an overlay is an ordinary C call; the linker and a small
resident runtime do the rest. FileEdit, SMALLC99, the SBC LINK99 and the OVL99
hello demo all use it.

This page is the reference. The per-application notes are in
[FileEdit's README](fileedit/README.md#how-transparent-overlays-work), the
[SMALLC99 Readme](https://github.com/AlexanderAdelAU/SmallC99-TMS99105-Native-C-Compiler#ovl99-how-a-call-crosses-overlays)
and the [link99 README](https://github.com/AlexanderAdelAU/Relocating-Assembler-and-Linker-Loader-for-TMS99000#overlay-map--y)
(the map format in full).

---

## 1. The pieces

| Piece | What it is | Where it comes from |
|---|---|---|
| `OVLMAP.TXT` | The overlay map: each overlay module, its page, its overlay and the functions others may call. The **only** place an overlay is declared | written by you |
| `link99 -Y` | Places each map module on its page, renames its published functions, writes `OVL_TABLE` and one resident thunk per published function, and checks the rules in §5 | the Windows link99 3.10.x, or the SBC LINK99 |
| `OVL_TABLE` | One row per overlay: the (segment, page) pairs to map | built by the linker |
| thunks | 12 bytes each, resident, under the published name | built by the linker |
| `OVLMGR.A99` | Maps an overlay's row | resident, in your program |
| `OVCALL.A99` | The call gate: saves the caller's overlay, maps the callee, calls it, maps the caller back | resident, in your program |

## 2. Memory

The TMS99105 addresses 64K as sixteen 4K **segments**. Behind each segment are
sixteen physical **pages**, chosen by that segment's map register. Pages are per
segment: page 3 behind `>8000` is not page 3 behind `>9000`.

| Segments | Use while a program runs |
|---|---|
| 0 | common memory: vectors, the shell's workspace and FCB, the BDOS gate, the stack |
| 1–7 (`>1000`–`>7FFF`) | the program's resident code and data, then its heap |
| 8–B (`>8000`–`>BFFF`) | the overlay window |
| C, D | page 0 is the shell. Page 1 is the shell's private page for a `.COM` run. **D pages 2–10 hold the shell's internal commands** (shell 6.5) and must never be written. Other C/D pages are free while an EXE runs |
| E, F | the BDOS and the ROM |

A program with overlays is a **paged EXE**: a chain of blocks, each saying which page
to map behind which address. The shell's loader:

- clears every map register before loading, and the shell resets them all when the
  program exits;
- maps **only the segment a block starts in**, so a block never crosses a segment;
- refuses any block at or above `>C000`;
- sets the heap to end at the lowest overlay address (`MEMLIMIT`), and to start after
  the last resident block (`FREEMEM`);
- chooses the EXE loader from the file's **type** in the directory (2), not its
  extension. XMODEM sets it from `.EXE`; a program that writes an EXE (LINK99) must
  set it itself, after MAKE and again before CLOSE.

## 3. A call into an overlay

```
caller                 resident                                   overlay
  viewfile()  ──►  viewfile thunk  ──►  OVCALL  ──►  OVLMGR maps VIEW  ──►  ~viewfile
                   LI   R1,id            │ push return address + owner
                   LI   R2,~viewfile     │ map the callee, CALL it
                   B    @OVCALL          │ pop, map the caller's overlay back
                                         ▼ return to the caller
```

- **The thunk** is what every outside call binds to: the linker gives it the
  function's own name and renames the overlay's copy `~viewfile`, so nothing can
  reach the overlay copy without mapping it first.
- **`OVCALL`** keeps a 16-frame stack of (return address, window owner). On return it
  maps the caller's **whole** overlay back, all its pages, so an overlay may call
  another overlay and carry on. The C call frame and `R4` (the return value) pass
  through untouched. Too deep a nest prints `>DEAD` and stops.
- **A `:tail` entry** has the thunk `LI R1,id / CALL @OVLMGR / B @~routine`: it maps
  and branches, with no frame. Use it only for a function called from resident code
  that needs nothing mapped back afterwards, such as a top-level pass.
- **Inside one overlay,** calls are direct: the compiler resolves them, no thunk is
  involved.

### `OVL_TABLE` and `OVLMGR`

- Row *n* is overlay ID *n* (IDs start at 1, in order of first appearance in the
  map); row 0 is unused. A row is 20 bytes: five (segment, page) word pairs, sorted
  by segment, ended early by a segment of 0.
- `OVLMGR` takes the ID in `R1`, maps each pair through the CRU (`>80C0` + 2 ×
  segment), and skips a register that already holds that page. It keeps the
  current page and ID per segment, and **`CUR_WINA_ID`**: the overlay that last
  mapped segment 8, the window's owner. It uses `R0`, `R2`, `R3`, `R5` and `R12`;
  `R1` and `R4` survive.
- `OVLMGR_INIT` clears all of that. Call **`ovlinit()`** (in `OVCALL.A99`: it calls
  `OVLMGR_INIT` and resets the frame stack) first thing in `main()`, before anything
  maps an overlay.

### The two versions of `OVCALL`

| Version | Used by | Behaviour |
|---|---|---|
| with a fast path | FileEdit, the hello demo | if the callee already owns the window (`R1` = `CUR_WINA_ID`) it branches straight to the routine: no frame, no mapping |
| always framed | SMALLC99 | always takes a frame. Required by a **guest** overlay (§4), which maps part of the window without becoming its owner, so "already owner" does not mean "already mapped" |

A program with a `guest` overlay must use the always-framed version.

## 4. The overlay map

```
# module    page   overlay   entries
OVLHELLO    4      GREET     hello greet
OVLGRET2    6      GREET     shout
OVLBYE      5      BYE       farewell count:tail
CC_CL99     12     CLI       R_GETOPTS=getoptions
guest CLI
```

(`CC_CL99` is SMALLC99's command-line overlay: it is `AORG`'d at `>A000`, so it maps
segment A only, and is declared a guest.)

- **module** is the object file's base name; **page** is 1–15; modules with the same
  **overlay** name are one overlay, mapped together (GREET maps two pages).
- **entries** are the functions callable from outside the module, or `-`. A plain
  `foo` is renamed `~foo` and its thunk is named `foo`; `pub=routine` makes a thunk
  `pub` for `routine` and leaves `routine`'s own name alone (SMALLC99's `R_` names);
  either may end `:tail`.
- **The segment comes from the module's own `AORG`**, never from the map. A C overlay
  starts with
  ```c
  #asm
          AORG    08000H
  #endasm
  ```
  and is compiled as a module (`smallcp -M`, `SMALLC99 -M`).
- `window 8-n` limits overlays to segments 8..n (default 8–B), leaving the rest for
  data banks; `guest NAME` marks an overlay that must **not** map segment 8.

## 5. Rules

The linker refuses a link that breaks the first group; the second group is yours to keep.

**Checked by the linker**

- Every executable overlay maps **segment 8 first**, exactly once; a guest never maps
  it. `OVCALL` saves one owner, and `OVLMGR` takes it from segment 8.
- An overlay's segments are contiguous, inside the window, at most five.
- No (segment, page) pair is used by two modules.
- Every map module is on the command line, has an `AORG`, and exports every routine
  the map names.
- A module stays inside one 4K segment (the loader maps a block's first segment
  only).
- **No resident module may sit above the overlays.** A module's address is its place
  in the link, so a library member loaded after the overlays lands above them, by
  their size. Name the libraries **before** the first overlay module. A library
  routine called **only** from an overlay is loaded late however you order things:
  keep such code resident, or compile a copy into the overlay (the SBC LINK99 does
  this with `include/PUTNUM.C`).
- Every external reference is a word its module left for it (the reference-slot
  check).

**Yours to keep**

- **Never call another overlay directly.** Call its published name, or a resident
  function that does.
- **No pointers into another overlay's data.** An overlay's static data and string
  literals are in its page; a callee in another overlay may replace that page while
  the pointer is in use. Pass resident buffers.
- **Budget: one 4K page per module.** The build scripts check each overlay's size
  from the link listing and fail above `>1000`.
- **Data banks** (a mapped workspace, like FileEdit's document buffer or LINK99's code
  banks) are declared as **guest** overlays with no entries, or mapped by the program
  itself, outside the overlay window it gives to code.

## 6. Adding overlays to a program

The OVL99 hello demo, in [`link99/tests/ovly`](link99/tests/ovly/), is the smallest
complete example: `MAIN.C` calls `hello()` and `farewell()` like any functions; three
overlay modules; `HELLOMAP.TXT`; `OVLMGR.A99` and `OVCALL.A99`.

1. Move the code into a module of its own and put `AORG 08000H` at the top.
2. Add one line to the map: module, a free page, an overlay name, the functions
   other modules call.
3. Link `OVLMGR.R99` and `OVCALL.R99` resident, and call `ovlinit()` first in
   `main()`.
4. Link with `-O1000 -Y<map>`, listing the resident modules, then the libraries, then
   the overlay modules (no `-P`):

   ```
   link99 -O1000 -S -YHELLOMAP.TXT HELLO.EXE STARTUP.R99 MAIN.R99 OVLMGR.R99 OVCALL.R99 CONOUT.R99 CALL.R99 OVLHELLO.R99 OVLGRET2.R99 OVLBYE.R99 CLIB99.LIB
   ```

   On the SBC the same arguments go in a file: `LINK99 @HELLO.LNK`.
5. Read the map listing the linker prints: each overlay's (segment, page) pairs and
   its entries. The Windows link99's `-M` listing also shows where every reference
   was bound.

## 7. History

OVL99 began as hand-written trampolines in SMALLC99 and generated tables in FileEdit
(DREL `-i`, PowerShell generators). From link99 3.10.0 the linker builds the glue from
the map, as 2.11BSD's `ovld` did; 3.10.1 added the reference-slot check, 3.10.2 the
"nothing resident above the overlays" check, and 3.10.3 per-segment pages and the
full 4K page budget. The SBC LINK99 reads the same map and writes the same bytes; it
does not take page spans (`lo-hi`). The development notes are in
`fileedit/docs/OVL99_PHASE1.md`, `OVL99_PHASE2.md` and SMALLC99's
`docs/OVL99_PORT_PLAN.md`.
