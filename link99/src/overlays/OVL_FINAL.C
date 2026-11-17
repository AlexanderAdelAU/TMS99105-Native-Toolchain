/*
** OVL_FINAL.C -- LINK99 phase 2, the part every output needs.
**
** okay() checks the symbol table and opens the output; comout() writes
** a .COM or .LGO image and closes it.  Neither is needed while phase1 builds the image, so they live
** on their own page behind >8000, reached through the okay and comout
** thunks link99 -Y builds from OVLMAP.TXT (both :tail - main() calls
** them and nothing needs mapping back).  A paged EXE is written by
** OVL_EXE.C instead.  The file primitives they share are resident, in
** FINAL.C.
*/
#asm
        AORG    08000H
#endasm

#include <stdio.h>
#include "rel99.h"

#define NOCCARGC
#define SYM       4
#define VAL       2
#define HIGH    127
#define XRPLUS   -2
#define SECTOR  512
#define FCBSIZ   36
#define FCBLCNT  35
#define FCBFLA   17

extern getint();
extern puts2();
extern poll();
extern error();
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

#include "PUTNUM.C"

/*
** a symbol, for -L
*/
show(table)
char *table;
{
  int abs;
  abs = getint(table + VAL);
  putx(abs, 4);
  fputs("' ", stdout);
  putx(abs + cbase, 4);
  puts2(" ", table + SYM);
}
extern _cpm();
extern char *_commbuf, *_commfcb, *_dfltbuf;

okay()
{
  int err;
  char *eplast;
  err = eplast = 0;
  fputs("   ", stdout);               /* the size phase1 used to print */
  putx(csize, 4);
  puts2(" Bytes (hex)", "");
  fputs("  ", stdout);
  putu(csize);
  puts2(" Bytes (dec)", "");
  xrnext = getint(xrfirst);
  epnext = getint(epfirst);
  if(list) puts2("Entry Points:", "");
  while(1) {
    poll(1);
    if(strcmp(xrnext + SYM, epnext + SYM) > 0) {
      if(epnext == eplast) {
        puts2("-  Redundant: ", xrnext + SYM);
        err = 1;
        }
      if(list) show(epnext);
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
  status("Write  ", outfn);
  outopen();
  return 1;
}

comout()
{
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
  outdone();
}

/*
** close the output and the reference file
*/
outdone()
{
  outclose();
  if(ferror(crfd)) error2("- Error Reading ", crfn);
  close(crfd);
  status("Done   ", outfn);
}
