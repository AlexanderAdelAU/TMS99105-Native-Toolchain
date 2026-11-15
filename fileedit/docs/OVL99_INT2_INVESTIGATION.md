# OVL99 / FileEdit — INT2 during shell TYPE (hardware regression)

Status: **OPEN / DO NOT MERGE TO MAIN.** Windows cross-build and `FILEEDIT /O`
nested-call test passed, but post-save shell behaviour is not yet cleared.

## Observed on SBC (15 November 2026)

1. Under OVL99 FileEdit, editing and rendering worked; `FILEEDIT /O`
   returned `OVL99 NESTED PASS`.
2. An earlier `Ctrl-O` save of an existing `SAMPLE.TXT` failed to
   create `SAMPLE.BAK`. A subsequent Save As to the new filename
   `SAMPLE.BAK` succeeded and was verified; the shell could read it.
3. The next OVL99 build moved NAMEIO into physical page 8 to recover
   resident heap space. A new `OVLTEST.TXT` and its automatic
   `OVLTEST.BAK` were created, with both names visible in `DIR`.
4. **After FileEdit had returned to the shell**, shell command
   `TYPE OVLTEST.BAK` printed several lines, then the monitor reported:

   ```text
   INT2 PC:C10E WP:C100 ST:C003 SEG:000C PAGE:0000
   MAP: 0000 0000 ... (all printed zeros)
   <TMS9900 DISC MONITOR V5.5F>
   ```

The printout means **interrupt level 2**, NOT necessarily an invalid
instruction or corrupted PC. The interrupt handler in the monitor
source (`TMS99105-SBC/Disc_Monitor/DISC_MONITOR_V56F.A99`) records
the interrupted PC/WP/ST and map-register values and enters the monitor
rather than returning to the interrupted program. The monitor vector
table labels the low interrupt vectors as FDC1797 interrupt vectors.
ST low nibble `3` enables interrupt levels up to three.

**Further source cross-check:** `Small-Shell-for-the-TMS9900/CORE.INC`
(the generated symbol map for Shell V6.5) places `CHKSYS` at `>C10A`,
so `>C10E` is the next instruction in the shell's normal command-dispatch
path (`JNE DOCMD1`). If the board runs this same shell layout, the
interrupt occurred in command dispatch, **not** in TYPE's command-page
output loop. We have not verified that the loaded shell is byte-identical
to this repository's V6.5 listing. That means the unexpected INT2 is
especially worth isolating from any early EOF/truncation in OVLTEST.BAK.

The PC `>C10E` lies in the shell core address range; this occurred
during shell TYPE rather than during execution of FileEdit's backup
copy loop. The cause (unacknowledged hardware interrupt, filesystem/
disk access, disk buffer corruption, residual mapping state, or other
problem) is **NOT yet established**.

## Low-risk discrimination tests

**Do not overwrite, delete or mutate the existing files yet.**

After a fresh power-on/reboot to establish known mapper state, without
running the new FileEdit first:

1. `DIR` — verify the files are visible. Run read-only `DIR2` (present on
   the user's volume) if supported, and compare the reported sizes of
   SAMPLE.TXT, OVLTEST.TXT and OVLTEST.BAK.
2. `TYPE SAMPLE.TXT` — previously existing file; stop after one page
   if needed.
3. `TYPE OVLTEST.TXT` — new primary file.
4. Only if the first two TYPE tests run safely, `TYPE OVLTEST.BAK`.
5. Record whether INT2 occurs, approximate line/sector position,
   and the complete `PC/WP/ST/SEG/PAGE/MAP` dump.
6. If possible, reboot and repeat `TYPE SAMPLE.TXT` **without**
   launching FileEdit at all. This helps distinguish a TYPE/BDOS/
   hardware problem from residual FileEdit state.

Interpretation:
- Failure on pre-existing SAMPLE.TXT immediately after clean boot
  points toward shell/BDOS/interrupt/hardware, not necessarily
  the backup contents.
- Failure only on OVLTEST.BAK indicates a file-chain/backup-write
  issue worth examining.
- Works after reboot but fails after FileEdit suggests cleanup/
  interrupt/map state must be investigated.
- Intermittent failures with varying PC/timing are consistent with
  hardware interrupt timing, but do not by themselves prove an IRQ fault.

The FileEdit `FILEIO.C` backup routine itself is unchanged relative
to `main`. No code changes should be made solely on the strength of
this monitor dump.

## Branch status

The revised build with seven overlays still cross-compiles and
links successfully in GitHub Actions, and FileEdit's name prompt is
now its own generated thunk. It must NOT be promoted to `main`
until the cause of this INT2 observation is understood and the
large-file and save/restore regression suite passes.


## Follow-up after cold boot (user screenshots, 15 November 2026)

The user obtained the following **read-only** results:

- `DIR2` lists `SAMPLE.TXT`, `SAMPLE.BAK`, `OVLTEST.TXT` and
  `OVLTEST.BAK` at **6144 bytes each** (12 sectors; two 4 KiB blocks).
  Directory size alone does not validate BAT chains or sector contents.
- After a cold boot, `TYPE SAMPLE.TXT` started output and apparently
  hung before the expected end of the file.
- `TYPE OVLTEST.TXT` displayed the document prologue and then the
  monitor printed `INT2 PC:980E WP:0230 ST:8080 SEG:0009 PAGE:0000`
  followed by a zeroed mapper dump and monitor prompt.
- Another screenshot displays the shell banner and a longer section of
  the ARTEST content, but does not establish successful end-of-file.
- User suspects the same text group/buffer is being reread. This is
  **not yet byte-for-byte verified**; it could be repeated physical
  contents or repeated DMA/sector output.

Interpretation:

- `>980E` is segment 9 (FileEdit's document-window address space),
  **not a valid shell execution address**. The monitor captured shell
  workspace `>0230`. This may be a bad PC/return address, erroneous
  mapping, interrupt/context issue or a memory/data corruption event;
  these observations do not establish the cause.
- The earlier `>C10E` interrupt occurred in the shell command-
  dispatcher address range. Different PCs strengthen the case for
  preserving logs and isolating the IRQ context, rather than assuming
  one failing FileEdit instruction.
- In the available monitor source `INT2` is interrupt-vector 2.
  It is **not a generic CPU exception label**. The source's
  INT2 handler prints the interrupted context and re-enters monitor.
- Because this recurs after a cold boot when FileEdit is not running,
  a stale resident OVL99 return frame alone is insufficient to explain
  the current symptoms. Disk content/chain damage, BDOS sequential
  read behaviour, TYPE command code, or hardware interrupt handling
  remain possible.
- The supplied `FILEIO.C` `cpyback()` opens two files; a success
  message from `fssave()` only verifies the newly written main file.
  The backup's correctness is not checked byte-for-byte after writing.

**Safety decision:** No more WRITE, ERA, SAVE, or FileEdit update tests
on this volume until the user's disk data can be preserved. Keep the
working `main` branch and the OVL99 integration branch separate. Do not
patch the runtime or disk writer on a guess.

Next useful evidence, ideally from a disk image or read-only sector
inspector rather than a command that rewrites filesystem metadata:
file directory starting block, its BAT successor(s) for each of the
four files, and the first/last 512-byte sectors of each. For 6144-byte
files the chain should have two distinct blocks and terminate at EOF;
two directory entries should not point into the same allocated chain
unless hard linking is an explicitly supported filesystem feature.

If no read-only image/inspector exists, test a known-good file under
a clean boot with the old FileEdit binary or without FileEdit at all
and capture when repetition begins. Stop at the first interrupt.
