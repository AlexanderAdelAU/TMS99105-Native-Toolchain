/*
** FINAL.C -- LINK99 resident final pass.
**
** Phase 2 must be resident because the target code image is now stored
** in banked pages mapped through >8000.  Executing phase2 from the same
** window would replace its own code whenever it reads a target-code bank.
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

int outcnt, outerr;
char outfcb[40];
char outbuf[520];

final()
{
  if(!okay()) return 0;
  status("Write  ", outfn);
  phase2();
  status("Done   ", outfn);
  return 1;
}

okay()
{
  int err;
  char *eplast;

  err = eplast = 0;
  xrnext = getint(xrfirst);
  epnext = getint(epfirst);
  if(list) puts("\nEntry Points:");

  while(1) {
    poll(1);
    if(strcmp(xrnext + SYM, epnext + SYM) > 0) {
      if(epnext == eplast) {
        puts2("-  Redundant: ", xrnext + SYM);
        err = 1;
        }
      if(list) show(epnext, "");
      eplast = epnext;
      epnext = getint(epnext);
      continue;
      }
    if(strcmp(xrnext + SYM, epnext + SYM) < 0) {
      puts2("- Unresolved: ", xrnext + SYM);
      err = 1;
      xrnext = getint(xrnext);
      continue;
      }
    if(*(xrnext + SYM) != HIGH) {
      xrnext = getint(xrnext);
      continue;
      }
    break;
    }
  if(err) return 0;
  return 1;
}

phase2()
{
  outopen();

  /*
   * Normal SBC .COM is a raw TMS9900 image at cbase.  Do not write the
   * old CP/M/Z80 three-byte JMP prefix; it corrupts word alignment.
   *
   * LGO keeps its historical header for now, but bytes/words are emitted
   * explicitly so host integer byte order cannot leak into the file.
   */
  if(lgo) {
    outbyte(instr);
    addr = cbase + goloc;
    outword(addr);
    outword(cbase);
    outword(csize);
    }

  cloc = -1;
  readref();
  while(1) {
    ++cloc;
    ucl = cloc;
    ucd = csize;
    if(ucl >= ucd) break;

    if(cloc != ref) {
      field = codegetb(cloc);
      outbyte(field);
      continue;
      }

    field = codegetw(cloc);
    field = field + cbase + xrplus;
    xrplus = 0;
    outword(field);
    readref();
    ++cloc;
    }

  outclose();

  if(ferror(crfd)) error2("- Error Reading ", crfn);
  close(crfd);
}

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
