/*
** OVL_TAB.C -- LINK99 -Y: fill OVL_TABLE and list it.
**
** ovtable(): for each overlay, its (segment,page) pairs sorted by
** segment - segment 8 first (a guest never maps it), contiguous, inside
** the window, at most five - into its row of OVL_TABLE, and one line of
** the listing.  A :tail thunk called from phase1(), after ovcheck().
*/
#asm
        AORG    08000H
#endasm

#include <stdio.h>
#include "rel99.h"
#include "OVLY.H"

#define NOCCARGC
#define SYM      4
#define VAL      2

extern error2();
extern status();
extern puts2();
extern codeputw();
extern char symbol[];
extern char ovmapfn[];
extern char *cloc, *cmod, *epprev, *epfirst, *xrprev, *xrfirst;
extern int type, field, pmorg;
extern int *pmva;

#include "PUTNUM.C"
#include "OVLYSUB.C"

ovtable()
{
  int *h, id, i, j, k, np, s0, si, sj, t, tbl;
  int seg[OVPAIRS], pg[OVPAIRS];
  char *mr, *mp, *mo, *og, *em, *ef, *eo;

  h = OVHDR;
  mr = T_MROW;
  mp = T_MPAGE;
  mo = T_MOVL;
  og = T_OGUEST;
  em = T_EMOD;
  ef = T_EFLG;
  eo = T_EORD;

  puts2("Overlay map ", ovmapfn);
  tbl = h[H_TBL];
  for(id = 1; id <= h[H_NOVO]; ++id) {
    np = 0;
    for(i = 0; i < h[H_NOVM]; ++i) {
      if(mo[i] != id) continue;
      if(np == OVPAIRS) ovdie("more than 5 pages in overlay ", T_ONAME + (id - 1) * OVNM);
      s0 = (pmva[mr[i] - 1] >> 12) & 15;
      j = np++;                         /* insert, sorted by segment */
      while(j > 0 && seg[j - 1] > s0) {
        seg[j] = seg[j - 1];
        pg[j] = pg[j - 1];
        --j;
        }
      seg[j] = s0;
      pg[j] = mp[i];
      }
    if(og[id - 1]) {
      if(seg[0] <= OVWINLO)
        ovdie("guest maps segment 8, so it would own the window: ", T_ONAME + (id - 1) * OVNM);
      }
    else if(seg[0] != OVWINLO)
      ovdie("does not map segment 8 first: overlay ", T_ONAME + (id - 1) * OVNM);
    if(seg[np - 1] > h[H_WINHI])
      ovdie("maps a segment outside the window: overlay ", T_ONAME + (id - 1) * OVNM);
    for(j = 1; j < np; ++j)
      if(seg[j] != seg[j - 1] + 1)
        ovdie("segments not contiguous (or shared) in overlay ", T_ONAME + (id - 1) * OVNM);

    fputs("  ID ", stdout);
    putu(id);
    fputs(" ", stdout);
    fputs(T_ONAME + (id - 1) * OVNM, stdout);
    fputs(" ", stdout);
    for(j = 0; j < np; ++j) {
      codeputw(tbl + id * OVPAIRS * 4 + j * 4, seg[j]);
      codeputw(tbl + id * OVPAIRS * 4 + j * 4 + 2, pg[j]);
      fputs(" ", stdout);
      putx(seg[j], 1);
      fputs("/", stdout);
      putu(pg[j]);
      }
    if(og[id - 1]) fputs(" (guest)", stdout);
    for(t = 0; t < h[H_NOVE]; ++t)
      if(mo[em[eo[t]]] == id) {
        fputs(" ", stdout);
        fputs(T_ENAME + eo[t] * OVNM, stdout);
        }
    puts2("", "");
    }
}
