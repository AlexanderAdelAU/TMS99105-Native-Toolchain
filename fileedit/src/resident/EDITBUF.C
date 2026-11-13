/*
** EDITBUF.C -- resident editor-buffer services (Step 9 adaptive buffer).
**
** Logical document storage is assembled from:
**
**   0..24575              >9000-BFFF, physical pages 0 and 1 (12 KB each)
**   next ebheapsz bytes    the ordinary EXE heap below the first overlay
**   final 8192 bytes       >C000-DFFF, physical page 1 (shell page reclaimed)
**
** One byte is reserved for the trailing NUL.  Even with no free heap this
** gives a 32767-byte editor.  Any heap published by SHELL's FREEMEM/MEMLIMIT
** words is claimed once and added to that capacity.
**
** SHELL V6.3 proves the C/D mapping contract for COM files: its COMMON return
** gate disables page selection before branching to RETURN, and RETURN restores
** C/D to page 0.  FileEdit also restores both mapped windows in ebhome().
*/

extern fopen();
extern fclose();
extern fgetc();
extern puts();
extern fsset();
extern ebank();
extern esbank();
extern ebget();
extern ebput();
extern ebmup0();
extern unsigned int heaptop();
extern unsigned int memlimit();
extern free();

extern char *fsname;
extern int fsexist;

#define EBBANK   12288
#define EBFIXED  24576
#define EBSHELL   8192
#define IORESERVE 1096    /* two IOLIB fopen buffers: 2 * (512 + 36) */

char *ebbase;
char *ebheap;
char *ebshell;
unsigned int eblen;
int eblines;
unsigned int ebcap;
unsigned int ebheapsz;
unsigned int vidx;
int ebdirty;
int ebsaved;
int ebvalid;
int ebcurbn;
int ebcursh;
int ebready;

/*
** Cached line-start used by ebseek().  Step 9D always started at byte zero,
** so cursor/status work deep in a large file repeatedly rescanned the entire
** prefix.  The cache is only a hint: edits before the cached start discard it.
*/
int ebseekln;
unsigned int ebseekix;

/* Select page 0/1 behind >9000-BFFF. */
ebsel(bank)
int bank;
{
    if(bank < 0)
        bank = 0;
    if(bank > 1)
        bank = 1;

    if(ebcurbn != bank) {
        ebank(bank);
        ebcurbn = bank;
    }
    return bank;
}

/* Select page 0/1 behind the shell window >C000-DFFF. */
ebshsel(bank)
int bank;
{
    if(bank < 0)
        bank = 0;
    if(bank > 1)
        bank = 1;

    if(ebcursh != bank) {
        esbank(bank);
        ebcursh = bank;
    }
    return bank;
}

/*
** Claim only heap bytes that IOLIB is not using.
**
** IOLIB snapshots the shell FREEMEM word into its private _heaptop during
** startup, then _setargs() and fopen() advance that private pointer.  Reading
** the shell FREEMEM word here therefore gives a stale address and overlaps
** IOLIB's argv/file buffers.
**
** Start at IOLIB's live heaptop() instead.  Leave room for two future fopen
** buffers because cpyback() can have the source and .BAK open together.
** free(newtop) is IOLIB's heap-top setter; moving it upward reserves the
** editor-owned interval so later fopen() allocations begin after it.
*/
ebsetup()
{
    unsigned int lo;
    unsigned int hi;
    unsigned int room;

    if(ebready)
        return 1;

    ebbase = 0x9000;
    ebshell = 0xC000;
    ebheap = 0;
    ebheapsz = 0;
    ebcurbn = -1;
    ebcursh = -1;
    ebseekln = 1;
    ebseekix = 0;

    ebsel(0);
    ebshsel(0);

    lo = heaptop();
    hi = memlimit();
    if(hi > lo) {
        room = hi - lo;
        if(room > IORESERVE) {
            ebheap = lo;
            ebheapsz = room - IORESERVE;
            free(lo + ebheapsz);
        }
    }

    /* 24 KB banked + 8 KB shell - one sentinel = 32767, plus safe heap. */
    ebcap = 32767;
    ebcap = ebcap + ebheapsz;
    ebready = 1;
    return 1;
}

/* Restore ordinary page-0 views before leaving editor/viewer code. */
ebhome()
{
    ebsel(0);
    ebshsel(0);
}

/*
** ebget()/ebput() are implemented in EBMAP.A99 from Step 9G onward.
** Keeping the hot byte-access path in compact assembly avoids inflating the
** resident C image and removes most of Small-C's per-byte call/branch cost.
*/

/* Initialise an empty, valid editor arena. */
ebnew()
{
    ebsetup();
    eblen = 0;
    eblines = 0;
    vidx = 0;
    ebdirty = 0;
    ebsaved = 0;
    ebvalid = 1;
    ebseekln = 1;
    ebseekix = 0;
    ebput(0, 0);
}

/* Initialise the arena when no document is currently open. */
ebnone()
{
    ebsetup();
    eblen = 0;
    eblines = 0;
    vidx = 0;
    ebdirty = 0;
    ebsaved = 0;
    ebvalid = 0;
    fsexist = 0;
    ebseekln = 1;
    ebseekix = 0;
    ebput(0, 0);
}

/* Start a new, empty named document. */
ebnewn(name)
char *name;
{
    ebnew();
    fsset(name);
    fsexist = 0;
    return 1;
}

/*
** Load without risking the current document.  First pass only counts; if the
** file exceeds this run's detected capacity, the existing RAM image is kept.
*/
ebloadn(name)
char *name;
{
    int in;
    int c;
    unsigned int n;
    int last;

    ebsetup();

    in = fopen(name, "r");
    if(in == 0) {
        puts("FILESTAT: cannot open ");
        puts(name);
        puts("\n");
        return 0;
    }

    n = 0;
    c = fgetc(in);
    while(c != -1) {
        /* IOLIB99 text input has already collapsed CRLF/CR/LF to one LF.
           EDITBUF deliberately keeps CR (13) as its internal line delimiter,
           so every logical input character consumes exactly one buffer byte. */
        n = n + 1;
        if(n > ebcap) {
            fclose(in);
            puts("FILESTAT: file is too large for available editor memory\n");
            return 0;
        }
        c = fgetc(in);
    }
    fclose(in);

    in = fopen(name, "r");
    if(in == 0) {
        puts("FILESTAT: file could not be reopened\n");
        return 0;
    }

    ebnew();
    last = -1;
    c = fgetc(in);
    while(c != -1) {
        /* IOLIB99 returns logical newline as LF (10).  The editor's existing
           cursor, renderer and edit code use CR (13) internally.  Convert only
           at this I/O boundary instead of changing the editor representation. */
        if(c == 10)
            c = 13;

        ebput(eblen, c);
        eblen = eblen + 1;
        if(c == 13)
            eblines = eblines + 1;
        last = c;
        c = fgetc(in);
    }
    fclose(in);

    if(last != -1 && last != 13)
        eblines = eblines + 1;

    ebput(eblen, 0);
    vidx = 0;
    ebdirty = 0;
    ebsaved = 0;
    ebvalid = 1;
    fsset(name);
    fsexist = 1;
    ebhome();
    return 1;
}

/* Compatibility wrapper. */
ebload()
{
    return ebloadn(fsname);
}

ebtotln()
{
    if(eblines == 0)
        return 1;
    return eblines;
}

/* A terminal CR exposes one final empty editable line. */
ebedln()
{
    if(eblen == 0)
        return 1;

    if(ebget(eblen - 1) == 13)
        return eblines + 1;

    if(eblines == 0)
        return 1;

    return eblines;
}

/*
** Position the shared renderer index at the first byte of logical line n.
**
** Step 9D restarted at byte zero for every lookup.  Editor status/cursor code
** calls ebseek() several times per key, making work proportional to the file
** prefix rather than the local line.  Keep the last known line start and walk
** from there in either direction.  No document bytes or line semantics change.
*/
unsigned int ebseek(n)
int n;
{
    unsigned int i;
    unsigned int j;
    int line;

    if(n < 1)
        n = 1;

    i = ebseekix;
    line = ebseekln;

    if(line < 1 || i > eblen) {
        i = 0;
        line = 1;
    }

    /* Walk forward from the cached line start. */
    while(i < eblen && line < n) {
        if(ebget(i) == 13)
            line = line + 1;
        i = i + 1;
    }

    /* An out-of-range request may end at EOF rather than a line start.
       Return the old Step 9D result, but do not poison the cached anchor. */
    if(line < n) {
        vidx = i;
        return i;
    }

    /* Walk backward by locating the preceding CR-delimited line start. */
    while(line > n && i > 0) {
        j = i - 1;
        while(j > 0 && ebget(j - 1) != 13)
            j = j - 1;
        i = j;
        line = line - 1;
    }

    ebseekln = line;
    ebseekix = i;
    vidx = i;
    return i;
}

/* Logical character length of line n, excluding CR. */
ebllen(n)
int n;
{
    unsigned int i;
    int len;

    ebseek(n);
    i = vidx;
    len = 0;

    while(i < eblen && ebget(i) != 13) {
        len = len + 1;
        i = i + 1;
    }

    return len;
}

/* Buffer index corresponding to line/character column. */
unsigned int ebindex(line, col)
int line, col;
{
    unsigned int i;

    ebseek(line);
    i = vidx;

    while(col > 0 && i < eblen && ebget(i) != 13) {
        i = i + 1;
        col = col - 1;
    }

    return i;
}

/* Insert one byte at buffer index pos. */
ebins(pos, c)
unsigned int pos;
int c;
{
    unsigned int i;
    int d;

    if(pos > eblen)
        pos = eblen;

    if(eblen >= ebcap)
        return 0;

    i = eblen;

    /* Keep everything above bank 0 on the known-good path. */
    while(i > pos && i > EBBANK) {
        d = ebget(i - 1);
        ebput(i, d);
        i = i - 1;
    }

    /* Move the one bank-0 -> bank-1 boundary byte with proven accessors. */
    if(i > pos && i == EBBANK) {
        d = ebget(i - 1);
        ebput(i, d);
        i = i - 1;
    }

    /* Only the physically contiguous bank-0 run uses the leaf fast path. */
    if(i > pos) {
        ebsel(0);
        ebmup0(pos, i);
    }

    ebput(pos, c);
    eblen = eblen + 1;
    ebput(eblen, 0);

    if(pos < ebseekix) {
        ebseekln = 1;
        ebseekix = 0;
    }

    ebdirty = 1;
    return 1;
}

/* Delete one byte at buffer index pos. */
ebdel(pos)
unsigned int pos;
{
    int c;
    int d;
    unsigned int i;

    if(pos >= eblen)
        return -1;

    c = ebget(pos);
    i = pos;
    while(i < eblen - 1) {
        d = ebget(i + 1);
        ebput(i, d);
        i = i + 1;
    }

    eblen = eblen - 1;
    ebput(eblen, 0);

    if(pos < ebseekix) {
        ebseekln = 1;
        ebseekix = 0;
    }

    ebdirty = 1;
    return c;
}
