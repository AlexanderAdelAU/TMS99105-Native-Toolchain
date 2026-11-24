# PACK99 / UNPACK — many files in one XMODEM transfer

XMODEM moves one file at a time. To get a whole set of files onto the SBC — object
modules, `.LIB`/`.NDX` libraries, an overlay map, a `.LNK` file — pack them on Windows
into one `.PAK` archive, send that once, and unpack it on the SBC.

| Side | Tool | What it does |
| --- | --- | --- |
| Windows | `pack99.ps1` | Packs any number of files into one `.PAK` |
| SBC | `UNPACK.COM` | Writes every file in a `.PAK` back out under its own name |

## One-time setup: put `UNPACK.COM` on the SBC

1. On Windows, build it:
   ```powershell
   cd pack99
   powershell -ExecutionPolicy Bypass -File .\make_unpack.ps1
   ```
   - Assembles `UNPACK.A99` with `link99\tools\r99.exe` and links it with
     `link99\tools\link99.exe` into a flat `UNPACK.COM` at `>1000`.
   - Output is `pack99\build\UNPACK.COM`. It is also copied to your SBC upload folder
     if `$env:SBC_MONITOR_DIR` is set, or a `TMS99105_SBC\MONITOR` folder is found above
     the repository.
2. On the SBC, `XMODEM UNPACK.COM`, then send the file from Tera Term.

After that, `UNPACK` is on the disk for good.

## Every time: pack, send, unpack

1. **Pack on Windows**, in PowerShell:
   ```powershell
   & .\pack99\pack99.ps1 JOB.PAK FILE1.R99 FILE2.LIB FILE2.NDX *.TXT
   ```
   - First argument: the archive to write (give a full path to write it straight into
     your upload folder).
   - Then any number of files or wildcards; each wildcard must match at least one file.
   - It prints each file with its SBC name, size and sectors, then the total.
2. **Send it**: on the SBC `XMODEM JOB.PAK`, then send `JOB.PAK` from Tera Term.
3. **Unpack on the SBC**:
   ```
   %UNPACK JOB
   UNPACK 1.0
     FILE1.R99
     FILE2.LIB
     ...
   5 FILE(S) UNPACKED.
   ```
   - No extension means `.PAK`; `UNPACK JOB.PAK` also works.
   - Files are written into the **current folder** (`CHDIR` first to unpack elsewhere).
   - A file that already exists is **replaced** without asking.
   - `JOB.PAK` stays on the disk; `ERA JOB.PAK` when you are done.

## Even simpler: XMODEM 1.9R unpacks it for you

From XMODEM 1.9R (TMS99105-SBC), receiving a `.PAK` unpacks it straight away into the
current folder, and erases the `.PAK` if every file was written:

```
[TOOLS]%XMODEM JOB.PAK
...SUCCESS.
UNPACKING:
  FILE1.R99
  ...
5 FILE(S) UNPACKED.
  JOB.PAK ERASED.
```

After an error the `.PAK` is kept, so `UNPACK JOB` can be run on it later. `UNPACK.COM` is
still the way to unpack a `.PAK` that is already on the disk.

## Example: everything LINK99 needs

`link99\tests\fileedit\make_test_fileedit.ps1` packs the 17 files needed to link FileEdit
on the SBC. Done by hand from its build folder, that is roughly:

```powershell
& .\pack99\pack99.ps1 C:\...\MONITOR\FE.PAK FILESTAT.R99 FILEEDIT.LIB FILEEDIT.NDX `
    IOLIB99.LIB IOLIB99.NDX CLIB99.LIB CLIB99.NDX OVL_*.R99 FEMAP.TXT FILEEDIT.LNK SAMPLE.TXT
```
```
%XMODEM FE.PAK
%UNPACK FE
%LINK99 @FILEEDIT.LNK
```

The OVL99 demos in the TMS99105-SBC repository build their own `.PAK` the same way
(`OVLDEMO.PAK`, `OVLTEST.PAK`), so they can be linked on the SBC with `UNPACK` and
`LINK99 @...LNK`.

## File names

- The SBC takes 8.3 names, upper case, `A-Z 0-9 _` only. `pack99.ps1` upper-cases names
  and **refuses** any other character, so you find out on Windows, not on the SBC.
- A longer name is **cut** to 8 + 3, exactly as the SBC's own FCB code cuts it:
  `OVL_NAMEIO.R99` → `OVL_NAME.R99`. A program or `.LNK` that names `OVL_NAMEIO.R99`
  still opens the right file. The listing shows the original name in brackets when it
  was cut.
- Two files that cut to the same SBC name are refused.

## File type and load address

Each file gets the same directory type XMODEM would give it:

| Extension | Type |
| --- | --- |
| `.COM` | 1 |
| `.EXE` | 2 |
| `.TXT` | 3 |
| `.BAS` | 4 |
| `.PRO` | 5 |
| anything else (`.R99`, `.LIB`, `.NDX`, `.LNK` …) | 0 |

The load address is always `>1000`, as XMODEM's default. A `.COM` built to run anywhere
else must be sent with XMODEM on its own, or its load address fixed after unpacking.

## Archive format

Everything is in whole 512-byte sectors, so UNPACK only ever moves sectors.

- For each file: one **header sector**, then the file's data sectors. The last data
  sector is padded with `>1A`, as a Tera Term XMODEM transfer pads it, so a file arrives
  exactly as if XMODEM had brought it on its own.
- At the end: one header sector with an empty name.

Header sector (words are big-endian):

| Bytes | Contents |
| --- | --- |
| 0–3 | `PK99` |
| 4–14 | Name in FCB form: 8 + 3, space-padded, upper case |
| 15 | File type (table above) |
| 16–17 | Load address (`>1000`) |
| 18–19 | Number of data sectors that follow |
| 20–23 | Exact length in bytes (information only) |

## UNPACK messages

| Message | Meaning |
| --- | --- |
| `** USAGE: UNPACK <ARCHIVE> ...` | No archive name given |
| `** ARCHIVE NOT FOUND **` | No such `.PAK` in the current folder |
| `** NOT A PACK99 ARCHIVE **` | A header sector does not start `PK99` |
| `** ARCHIVE ENDS EARLY - NO END SECTOR **` | The transfer was cut short between files |
| `** ARCHIVE ENDS INSIDE A FILE **` | The transfer was cut short in a file's data |
| `** FILE CREATE ERROR **` / `WRITE` / `CLOSE` | The BDOS refused; usually a full disk or directory |

Files written before an error are kept.
