/*
** OVL_EXE.C -- LINK99 phase 2 for a paged EXE.
**
** exeout() writes the image as the shell's chain of blocks.  It runs
** once, from main(), when any -P was given; it has its own page because
** OVL_FINAL's is full.  Reached through the exeout thunk (:tail).
**
**   .EXE  the chain of blocks:
**             next_offset  word   >200 to the next header, 0 = last
**             page         word   0 = resident (flat)
**             start        word   load address
**             size         word   bytes the loader copies
**             data         up to >1F8 bytes
**         Every block but the last fills exactly one 512-byte sector.
**         Written exactly as the Windows link99 3.10.3 writes it:
**           - the image is cut into regions: the -P modules (LINK99.C's
**             pm rows) and the resident runs between them, at cbase +
**             their place in the image;
**           - adjacent regions on the same page merge; paged ones only
**             within one segment (pages are per segment);
**           - each region is cut into >1F8-byte blocks; every block
**             but the last is padded to >1F8 and says >1F8, except a
**             paged block whose padding would cross its segment, which
**             says its true size; the last block is padded to even.
*/
#asm
        AORG    08000H
#endasm

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
#define EXEBLK  0x1F8           /* data bytes in a full chain block */

extern getint();
extern puts2();
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
extern _cpm();
extern char *_commbuf, *_commfcb, *_dfltbuf;
extern int pagemode, pmn, *pmls, *pmle, *pmva, *pmpg;

/* region iterator (see rraw/rnext) */
int rk, rcur, rhave;
int r_ls, r_le, r_va, r_pg;     /* raw region                       */
int m_ls, m_le, m_va, m_pg;     /* merged region                    */
int hold;                       /* second byte of a relocated word  */

/*
** ---------------------------------------------------------------------
** EXE chain output
** ---------------------------------------------------------------------
*/

/*
** next byte of the relocated image, in order from offset 0
*/
genb()
{
  int v;
  if(hold >= 0) {
    v = hold;
    hold = -1;
    ++cloc;
    return v;
    }
  if(cloc == ref) {
    field = codegetw(cloc) + cbase + xrplus;
    xrplus = 0;
    readref();
    hold = field & 255;
    ++cloc;
    return (field >> 8) & 255;
    }
  v = codegetb(cloc);
  ++cloc;
  return v;
}

rstart()
{
  rk = rcur = 0;
  rhave = 0;
}

/*
** next non-empty raw region: a -P row, or the resident run before it
*/
rraw()
{
  int hi;
  while(1) {
    if(rk < pmn) if(rcur == pmls[rk]) {
      r_ls = pmls[rk];
      r_le = pmle[rk];
      r_va = pmva[rk];
      r_pg = pmpg[rk];
      rcur = r_le;
      ++rk;
      if(r_le != r_ls) return 1;
      continue;
      }
    if(rk < pmn) hi = pmls[rk];
    else hi = csize;
    if(rcur == hi) return 0;            /* only when the rows are done */
    r_ls = rcur;
    r_le = hi;
    r_va = cbase + rcur;
    r_pg = 0;
    rcur = hi;
    return 1;
  }
}

/*
** next merged region, in m_*
*/
rnext()
{
  if(!rhave) if(!rraw()) return 0;
  rhave = 0;
  m_ls = r_ls; m_le = r_le; m_va = r_va; m_pg = r_pg;
  while(rraw()) {
    if(r_pg == m_pg)
      if(r_ls == m_le)
        if(r_va == m_va + (m_le - m_ls))
          if(m_pg == 0 || ((r_va >> 12) & 15) == ((m_va >> 12) & 15)) {
            m_le = r_le;
            continue;
            }
    rhave = 1;
    break;
    }
  return 1;
}

/*
** blocks a region of n bytes needs
*/
nblocks(n)
int n;
{
  int b;
  b = 0;
  while(n) {
    ++b;
    ucl = n;
    if(ucl <= EXEBLK) break;
    n = n - EXEBLK;
    }
  return b;
}

exeout()
{
  int total, done, n, chunk, va, sz, i;
  unsigned winlo, rend, u;
  char str[8];

  /* pass 1: count the blocks; every resident run must end below the
     lowest overlay address (Windows link99 v3.10.2) */
  total = 0;
  winlo = 0xFFFF;
  rend = 0;
  rstart();
  while(rnext()) {
    total = total + nblocks(m_le - m_ls);
    u = m_va;
    if(m_pg) { if(u < winlo) winlo = u; }
    else {
      u = m_va + (m_le - m_ls);
      if(u > rend) rend = u;
      }
    }
  if(winlo != 0xFFFF) if(rend > winlo)
    error("- Resident code runs into the overlay window: name the libraries before the first -P module");

  /* pass 2: write them */
  cloc = 0;
  hold = -1;
  xrplus = 0;
  readref();
  done = 0;
  rstart();
  while(rnext()) {
    ucl = cloc; ucd = m_ls;
    while(ucl < ucd) {          /* never: regions tile the image */
      genb();
      ucl = cloc;
      }
    va = m_va;
    n = m_le - m_ls;
    while(n) {
      ucl = n;
      if(ucl > EXEBLK) chunk = EXEBLK; else chunk = n;
      ++done;
      if(done == total) {
        sz = chunk + (chunk & 1);
        outword(0);
        }
      else {
        sz = EXEBLK;
        if(m_pg) if((va & 0x0FFF) + EXEBLK > 0x1000) sz = chunk;
        outword(SECTOR);
        }
      outword(m_pg);
      outword(va);
      outword(sz);
      i = chunk;
      while(i--) outbyte(genb());
      if(done == total) { if(chunk & 1) outbyte(0); }
      else {
        i = EXEBLK - chunk;
        while(i--) outbyte(0);
        }
      if(list) {
        fputs("Block page ", stdout);
        itox(m_pg, str, 3); fputs(str, stdout);
        itox(va, str, 6);
        puts2(" at", str);
        }
      va = va + chunk;
      n = n - chunk;
      }
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
