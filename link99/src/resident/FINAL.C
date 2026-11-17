/*
** FINAL.C -- LINK99 output file primitives, resident.
**
** Phase 2 itself runs from overlays: okay() and comout() from OVL_FINAL
** (page 3), exeout() from OVL_EXE (page 4), each called from main().
** What they share stays here: the output FCB and sector buffer, the
** byte/word writers and the reference-file reader.
*/
#include <stdio.h>
#include "rel99.h"

#define NOCCARGC
#define SYM       4
#define HIGH    127
#define XRPLUS   -2
#define SECTOR  512
#define FCBSIZ   36
#define FCBLCNT  35
#define FCBFLA   17
#define FCBFTY   11             /* directory file type: the shell runs */
#define FTYEXE    2             /* type 2 through its paged EXE loader */

extern getint();
extern puts2();
extern show();
extern poll();
extern error2();
extern status();
extern codegetb();
extern codegetw();

extern char *xrnext, *epnext, *xrfirst, *epfirst;
extern char *cloc, *cbase, *csize, *goloc;
extern char outfn[], crfn[];
extern int list, outfd, instr, addr, lgo, ref, field;
extern int crfd, xrplus;
extern unsigned ucl, ucd;
extern _cpm();
extern char *_commbuf, *_commfcb, *_dfltbuf;
extern int pagemode;

int outcnt, outerr;
char outfcb[40];
char outbuf[520];

upper(c)
char c;
{
  if(c < 'a') return c;
  if(c > 'z') return c;
  return c - 32;
}

mkfcb(name, fcb)
char *name, *fcb;
{
  int i;
  char c;

  i = FCBSIZ;
  while(i--) fcb[i] = 0;

  i = 0;
  while(i < 11) fcb[i++] = ' ';

  if(name[1] == ':') name += 2;

  i = 0;
  while((c = upper(*name++)) && c != '.') {
    if(i < 8) fcb[i++] = c;
    }

  if(c == '.') {
    i = 8;
    while((c = upper(*name++)) && i < 11) fcb[i++] = c;
    }
}

outstage()
{
  char *s, *d;
  int i;

  s = outfcb;
  d = _commfcb;
  i = FCBSIZ;
  while(i--) *d++ = *s++;
}

outunstage()
{
  char *s, *d;
  int i;

  s = _commfcb;
  d = outfcb;
  i = FCBSIZ;
  while(i--) *d++ = *s++;
}


setfla(addr)
int addr;
{
  outfcb[FCBFLA - 1] = addr >> 8;
  outfcb[FCBFLA] = addr;
}

outopen()
{
  int r;

  mkfcb(outfn, outfcb);
  setfla(cbase);
  /*
   * The shell picks the loader from the directory's file type (FCB byte
   * 11), not from the extension: type 0 or 1 runs flat, type 2 through
   * the chain-block EXE loader.  A paged EXE left at 0 is run as a flat
   * image - its first block header executed as code - and returns
   * without a word.  .COM/.LGO keep 0, as they always have.
   */
  if(pagemode) outfcb[FCBFTY] = FTYEXE;

  outstage();
  _cpm(19, _commfcb);
  outunstage();

  outstage();
  r = _cpm(22, _commfcb);
  outunstage();

  if(r < 0 || r == 255) error2("- cannot open ", outfn);
  setfla(cbase);
  outcnt = 0;
  outerr = 0;
}

outflush()
{
  char *s, *d;
  int i, r;

  if(outcnt == 0) return;

  i = outcnt;
  while(i < SECTOR) outbuf[i++] = 0;

  s = outbuf;
  d = _commbuf;
  i = SECTOR;
  while(i--) *d++ = *s++;

  _cpm(26, _commbuf);
  outstage();
  r = _cpm(21, _commfcb);
  outunstage();
  _cpm(26, _dfltbuf);

  if(r) outerr = 1;
  outcnt = 0;
}

outclose()
{
  int n, r;

  n = outcnt;
  if(n == 0) n = SECTOR;

  outflush();
  outfcb[FCBLCNT] = n;
  setfla(cbase);

  outstage();
  r = _cpm(16, _commfcb);
  outunstage();
  _cpm(26, _dfltbuf);

  if(r < 0 || r == 255 || outerr) error2("- Error Writing ", outfn);
}

outbyte(value)
int value;
{
  outbuf[outcnt++] = value;
  if(outcnt == SECTOR) outflush();
}

outword(value)
int value;
{
  outbyte(value >> 8);
  outbyte(value);
}

readref()
{
  read(crfd, &ref, 2);
  if(ref == XRPLUS) {
    read(crfd, &xrplus, 2);
    read(crfd, &ref, 2);
    if(ref == XRPLUS) {
      xrplus -= cbase;
      read(crfd, &ref, 2);
      }
    }
}
