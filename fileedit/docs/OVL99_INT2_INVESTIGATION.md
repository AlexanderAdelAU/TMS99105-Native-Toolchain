# OVL99 / FileEdit — INT2 during shell TYPE (hardware regression)

Status: **RETEST ON REPLACEMENT DISK IMAGE / DO NOT MERGE TO MAIN YET.**
Previous disk image was reported corrupted by the user. All prior INT2/TYPE
results are historical observations from that image, not confirmed OVL99 regressions.

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

## Update: replacement disk image (15 November 2026)

The user reports that the **previous disk image was corrupted** and has
loaded a replacement image. New screenshot shows an image/transfer
`LOAD ADDRESS: 1000` ending `SUCCESS.`, then `DIR2` without exception.

The new volume lists `SAMPLE.TXT` at **10752 bytes** and `FILEEDIT.EXE`
at **39936 bytes**; the old `SAMPLE.BAK` and `OVLTEST` files are not
present. The older image had listed four 6144-byte text files. The
difference reinforces treating prior read anomalies as specific to the
old image; it does **not by itself** prove the OVL99 build is safe.

**Reset the test baseline:** On the replacement disk, first read
`SAMPLE.TXT` to completion with the shell's TYPE; next run
`FILEEDIT /O`; then open the sample for editing, Save As to a unique
new filename (leave original unchanged), modify one character and
save again to exercise backup creation. Exit and read both new primary
and backup files from the shell. Report any INT2 and stop writes if it
recurs. Merge remains blocked until these tests pass.

No shell, BDOS, backup, or overlay code fixes should be made merely in
response to failures observed with the reportedly corrupted image.


## Replacement image: TYPE and LOAD address clarified

User confirmed that `TYPE SAMPLE.TXT` works correctly on the replacement
disk image, displaying text well beyond the initial lines and returning
to the shell prompt without exception. This is strong evidence the old
disk image caused the prior read/interrupt symptoms, though FileEdit's
write/backup regression still needs to be repeated on the new image.

The user also noticed that original `SAMPLE.TXT` has `DIR2 LOAD >1000`,
while FileEdit-created `.TXT` and `.BAK` on the old image displayed
`LOAD >0000`. Source review shows this is expected: in `BDOS61.A99`,
`FLA EQU 16` is directory metadata and `MAKFIL` zeros all user-FCB
metadata beyond the filename before storing the new entry. IOLIB
`fopen(name,"w")` invokes BDOS create-file and does not specify a
load address. Thus `>0000` for newly created text files is normal;
the shell `TYPE` command reads text records and does not launch them
at FLA. An original text file made with a loader or shell SAVE may carry
`>1000` instead. The LOAD metadata discrepancy is **not a demonstrated
OVL99 fault**.

Remaining gate: rerun clean-image `FILEEDIT /O`, Save As,
subsequent save with automatic backup, then verify both new files with
the shell and test larger document-bank boundaries. No merge yet.


## Clean-image FileEdit save/backup regression (user screenshots, 15 Nov 2026)

**Passed on hardware:**
- `FILEEDIT /O` printed `OVL99 NESTED PASS`.
- `TYPE SAMPLE.TXT` completed normally on the replacement image.
- `FILEEDIT SAMPLE.TXT /E`, then Save As `OVLTEST.TXT`, printed
  `Saved and verified: OVLTEST.TXT`.
- User edited the start of OVLTEST.TXT (inserted an `A`) and saved again.
- After returning normally to the shell, `DIR2` lists `OVLTEST.TXT`
  and `OVLTEST.BAK`, both 10752 bytes; no INT2 was reported.
- `TYPE OVLTEST.TXT` shows the inserted `A` at the start.

**Still pending:**
- Read `OVLTEST.BAK` and verify that it contains the *pre-edit*
  first line; existence and equal file sizes alone cannot prove this.
- Verify full-document content and bank-boundary edits/reopens with
  larger files, before considering merge to main.

These results strongly suggest earlier TYPE/INT2 failures were related
to the previously reported corrupted disk image rather than proven
OVL99 overlay or return-stack failures. Do not treat the earlier image's
errors as confirmed OVL99 regressions.


## Backup contents verified on hardware (15 Nov 2026)

The user read `OVLTEST.BAK` in the shell and supplied a screenshot
showing its first line begins `/*` (the original text). The modified
`OVLTEST.TXT` screenshot instead showed `A/*` at the beginning.
Thus the automatic backup demonstrably contains the pre-edit content
at the modified position, not merely a same-sized duplicate. Save,
backup, and normal shell return have passed on the clean replacement
disk image. Large-file bank-boundary editing remains to be tested.

Earlier-image INT2 symptoms remain historical observations associated
with the reportedly corrupted disk image; they have not recurred in
the clean-image tests shown so far. Do not merge before the large-file
regression is complete.


## New INT2 after pagination Enter (15 November 2026)

Following clean-image OVL99 Save/Save As and creation of OVLTEST.BAK,
the user ran shell `TYPE OVLTEST.BAK`. The backup's first line was
confirmed to be the unmodified `/*`, while OVLTEST.TXT began `A/*`.
**However, after pressing Enter during TYPE, the machine interrupted:**

```text
INT2 PC:04D2 WP:04C4 ST:C084 SEG:0000 PAGE:0000
MAP:0000 ... 0000
<TMS9900 DISC MONITOR V5.5F>
```

The PC and WP are in the common-memory buffer range `>0300–>04FF`;
they are anomalous for normal TYPE command execution (TYPE lives in
the `>D000` command window with the shell workspace at `>0230`).
The capture is interrupt vector 2, not definitive proof of an illegal
instruction. We cannot yet establish whether a bad disk/FCB operation,
interrupt corruption, stack/return-address corruption, or a TYPE
pagination problem led to the saved context.

**Crucial isolation:** shell `TYPE.A99` enters the `TYVOMIT` path on
Enter at the 22-line pagination pause, setting TYPFLG to -1 and then
restoring saved R7/R6. A fault at that moment is not uniquely explained
by FileEdit backup; the TYPE read and pagination must be tested
independently.

**Read-only comparison after clean boot, without running FileEdit:**
run `TYPE SAMPLE.TXT`, advance first pause with **Space** (single
page); reboot and run `TYPE SAMPLE.TXT`, advance with **Enter**
(remaining pages); stop at first unexpected interrupt. If both pass,
repeat with `OVLTEST.TXT` before `OVLTEST.BAK`. Record whether failure
occurs at a consistent page/sector boundary and whether it occurs
only for the backup. Avoid all disk writes pending isolation. No code
fix is justified by these observations alone.

**Status correction:** OVL99 Save As and backup *creation* passed;
backup full-file read and reliable post-save shell operation are NOT
yet verified. No merge to main.


## CTRL-Q during cold-boot TYPE stall (follow-up)

User reports `TYPE SAMPLE.TXT` stalls mid-word even after a cold boot
without running FileEdit. Pressing Ctrl-Q does not resume serial output:
the screen subsequently shows `<TMS9900 DISC MONITOR V5.5F>` and the
monitor's `>` prompt, then `??` when an unrecognized input is
entered. No INT2 dump accompanies this specific screenshot.

The monitor source (`TMS99105-SBC/Disc_Monitor/DISC_MONITOR_V56F.A99`)
prints this banner in `BANNER`, which is *not* the normal shell TYPE
pagination UI; its command table has a literal uppercase `Q` QBOOT
command but no explicit Ctrl-Q/XON monitor command. The image therefore
does not establish whether Ctrl-Q triggered a reset/reentry or whether
the machine had already lost its shell execution context.

Separate confirmed TYPE source concern: shell `TYPE.A99` swaps R3
before `COUT`, and swaps R3 again afterwards to test for LF, but BDOS
`BDOS61.A99` `COUT` itself performs `SWPB R3` and does *not*
restore R3. Consequently the LF comparison in TYPE examines the
wrong byte (typically the preceding character), making pagination
unreliable. This is a source-level defect and a candidate for a
separate, reviewed shell fix, **not yet proven to cause the mid-word
stall or INT2 reports**.

Do not attribute a cold-boot TYPE stall to FileEdit's automatic
backup without further evidence. Keep OVL99 unmerged. Avoid disk
writes and preserve the files pending controlled shell/BDOS testing.


## Standalone reproduction after SYSGEN: OVL99 is not running

User reports a fresh SYSGEN and boot banner:

```text
Shell Version 6.5
TMS99105 SBC V4 - Paged Memory
```

`DIR` shows only shell/BDOS/command modules, XMODEM, DIR2. No
`FILEEDIT.EXE` is listed. User transferred the approximately 16 KiB
bank-boundary test using `XMODEM LARGE.TXT` and received
`LOAD ADDRESS: 1000` and `SUCCESS.`. The standalone shell command
`TYPE LARGE.TXT` then printed four complete 0001-0004 lines and
part of line 0005 before:

```text
INT2 PC:9808 WP:0230 ST:2080 SEG:0009 PAGE:0000
MAP:0000 ... (all zeros)
<TMS9900 DISC MONITOR V5.5F>
```

This is an **independent reproduction with no FileEdit or OVL99 run**.
It rules out OVL99's live paging and FileEdit's automatic backup as
the immediate cause of this occurrence. It does not independently
establish that the transferred file is intact, that the hardware is
healthy, or which shell/BDOS/monitor instruction caused it.

The interrupted `PC >9808` is in segment 9 rather than the shell's
paged TYPE code at `>D000`; `WP >0230` is the shell workspace. The
stoppage occurs within the first ~512 bytes of display (around the
fifth ~70-byte line), suggesting the console output/execution path is
worth auditing before suspecting a second sector read or crossing the
4-KiB block chain. An unverified exact file byte count is not enough
to exclude file data corruption outright.

Investigate independently under the shell project:
- TYPE's BDOS `COUT` call/return path, register preservation, and
  `R3` double byte-swap; this is a genuine TYPE pagination defect,
  but not yet a demonstrated cause of INT2.
- The shell's segment-D PSEL/gate state and the monitor's INT2 vector.
- The TX/interrupt handling and its effect on the shell workspace/stack.
- Compare a short text file under 512 bytes with LARGE.TXT, and
  record whether the interrupt recurs at a fixed displayed offset.

Leave OVL99 unchanged and unmerged. Do not ask the user to delete
backups or rerun FileEdit to reproduce this particular fault.


## Additional standalone shell result: LARGE.TXT succeeds repeatedly

User reports that `TYPE LARGE.TXT` has subsequently completed
successfully **four times**, displaying through line 0220 of the
banked-buffer regression text. The screenshot shows the final
lines 0199–0220 and the user confirms four successful runs.

This **falsifies a deterministic first-sector, sustained-output-length
or >300-byte threshold explanation** for the earlier crash.
The standalone shell failures are intermittent based on current
evidence. The source-level R3 swap/pagination concern is separate
and has not been demonstrated to cause INT2.

Do not change TYPE, BDOS, OVL99 or LINK99 on the assumption that
large output consistently fails. Continue the original OVL99 hardware
validation with a read-only LARGE.TXT FileEdit editor test after a
clean shell run, noting that intermittent faults may still recur.


## Read-only FileEdit >12 KiB document-bank navigation passes on SBC

User supplied a screenshot from the OVL99 FileEdit editor displaying
`LARGE.TXT` lines 165 through 184 with correct, sequential line
numbers and text. The status reports `Ln 184/221 Col 1`. The known
test document has ~75 bytes per line, so this position crosses the
first 12 KiB document-bank boundary near line 164. No visible
corruption or INT2 in this observed editor session.

**Verified:** read-only navigation/rendering beyond the first
`>9000–>BFFF` editor-data bank using the generated OVL99 overlays.

**Not yet verified:** last-line navigation, saving a modification at
this boundary, reloading to verify content, and a larger file that
crosses the editor's 24 KiB/shell-window boundary.

No merge to `main` until these regressions are evaluated.


## End-of-file navigation passes on 16 KiB banked document

The user scrolled to the end of `LARGE.TXT` in the OVL99 FileEdit
editor and supplied a screenshot displaying lines 202–220 correctly,
with the blank trailing line 221 and status `Ln 221/221 Col 1`.
There was no observed display corruption, hang or INT2 in this test.

This completes the **read-only navigation/rendering** regression for
the 16 KiB / 221-line test file, including navigation beyond the first
12 KiB editor bank and to EOF.

Next safe test: use FileEdit's Save As to create a new filename before
editing anything; modify a character around line 170 in the *copy*,
save and verify the new file and its preceding-version `.BAK`.
Preserve original `LARGE.TXT`. Afterward exercise the 30 KiB file
that crosses the editor's shell-window data-bank boundary.


## 16 KiB test: edit/save across 12 KiB data-bank boundary (SBC)

The user used the OVL99 FileEdit build to Save As a copy of
`LARGE.TXT` as `L16TEST.TXT`, navigated to line 171 (beyond the
first 12 KiB `>9000–>BFFF` bank), and inserted an `X` before
the line's `0171 BANKED BUFFER...` prefix. The editor screenshot
shows `Ln 171/221 Col 2`, the inserted `X`, and no `[MOD]`
flag after saving.

A subsequent `DIR2` screenshot shows `L16TEST.TXT` and
`L16TEST.BAK` at **16,896 bytes each**, alongside the untouched
`LARGE.TXT`. No exception is shown.

This supports a successful editor-side modification and save
across the 12 KiB bank boundary, with automatic backup **creation**.
It does not yet verify that the persisted `L16TEST.TXT`
contains the `X` when reopened or that `L16TEST.BAK`
contains the unmodified line. Next check: reopen each file and
inspect line 171. Do not mark byte-for-byte backup verification
as complete until then.


## 16 KiB bank-boundary edit/save/backup: verified (15 Nov 2026)

The user reopened BOTH test files in the OVL99 FileEdit editor at the
12 KiB document-bank crossing:

- `L16TEST.TXT`, line 171: `X0171 BANKED BUFFER REGRESSION LINE: ...`
- `L16TEST.BAK`, line 171: `0171 BANKED BUFFER REGRESSION LINE: ...`
  (no prefixed `X`)

Both show the surrounding lines 162-181 consistently, and their previously
observed `DIR2` sizes are 16896 bytes each. This confirms the saved edit
persisted across reopening and the automatic backup retained the preceding
contents at the changed location. The 16 KiB / 12 KiB bank-boundary regression
is **PASS** for the observed navigation, edit, save and backup operations.

**Next:** On the same isolated OVL99 branch, transfer
`fileedit/tests/LARGE30.TXT` (30,000 bytes, lines 0001-0447 plus a
trailing X row) using a distinct name, then navigate beyond approximately
24 KiB to exercise the optional shell-window document bank. Test reading
first; avoid overwriting the supplied original. The full 30 KiB edit/save
regression and intermittent independent TYPE/INT2 investigation remain open.
