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
