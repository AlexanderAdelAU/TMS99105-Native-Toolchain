/*
** OVL_CHK.C -- LINK99 -Y: the checks after the last module.
**
** ovcheck(): every map module loaded; guest lines name overlays (and a
** guest's entries are not :tail); every published routine was found as
** an entry point of its module; no (segment,page) holds two modules.
** OVL_TAB.C then fills OVL_TABLE.  A :tail thunk called from phase1().
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

ovcheck()
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

  for(i = 0; i < h[H_NOVM]; ++i)
    if(!mr[i]) ovdie("module not on the command line: ", T_MNAME + i * OVNM);
  for(i = 0; i < h[H_NOVG]; ++i) {
    for(k = 0; k < h[H_NOVO]; ++k)
      if(!strcmp(T_GNAME + i * OVNM, T_ONAME + k * OVNM)) break;
    if(k == h[H_NOVO]) ovdie("guest names no overlay in the map: ", T_GNAME + i * OVNM);
    og[k] = YES;
    }
  for(i = 0; i < h[H_NOVE]; ++i) {
    if(ef[i] & EFTAIL) if(og[mo[em[i]] - 1])
      ovdie("a guest overlay's entry cannot be :tail: ", T_ENAME + i * OVNM);
    if(!(ef[i] & EFSEEN))
      ovdie("not an entry point of its module (spelled as exported?): ", T_EREAL + i * OVNM);
    }

  /* no (segment,page) may hold two modules */
  for(i = 0; i < h[H_NOVM]; ++i)
    for(j = i + 1; j < h[H_NOVM]; ++j) {
      si = (pmva[mr[i] - 1] >> 12) & 15;
      sj = (pmva[mr[j] - 1] >> 12) & 15;
      if(si == sj) if(mp[i] == mp[j])
        ovdie("two modules use one segment and page: ", T_MNAME + j * OVNM);
      }

}
