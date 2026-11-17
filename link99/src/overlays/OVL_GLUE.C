/*
** OVL_GLUE.C -- LINK99 -Y: the overlay glue, and the final checks.
**
** ovemit()   called once, just before the first map module loads, so
**            the glue is resident and BELOW the overlays (a resident
**            module sits at cbase + its place in the image).  Writes,
**            exactly as the Windows link99 writes OVLGLUE.R99:
**              OVL_TABLE   (overlays + 1) rows of 5 (segment,page)
**                          pairs, zero until ovfinish fills them
**              thunks      12 bytes per entry, by ID then map order:
**                framed    LI R1,id / LI R2,~routine / B @OVCALL
**                :tail     LI R1,id / CALL @OVLMGR   / B @~routine
**            and enters OVL_TABLE and every thunk as entry points.
** ovmisc()  a blank, guest or window line of the map: YES when handled
**            (here for room; OVL_MAP.C and OVL_MAPM.C read the rest).
** :tail thunks called from resident code.  The checks at the end
** are OVL_CHK.C's ovcheck(), the table OVL_TAB.C's ovtable().
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
extern newsym();
extern link();
extern codeneed();
extern codeputb();
extern codeputw();
extern getint();
extern putint();
extern char symbol[];
extern char ovmapfn[];
extern char *cloc, *cmod, *epprev, *epfirst, *xrprev, *xrfirst;
extern int type, field, pmorg;
extern int *pmva;

#include "PUTNUM.C"
#include "OVLYSUB.C"

/*
** a blank, guest or window line: YES when handled here
*/
ovmisc()
{
  int k, *h, *tok;
  char *s;
  h = OVHDR;
  tok = T_TOK;
  if(!h[H_NTOK]) return YES;
  if(oveq(tok[0], "guest")) {
    if(h[H_NTOK] != 2) ovdie("want: guest OVERLAY", "");
    if(slen(tok[1]) > MAXSYM) ovdie("name too long: ", tok[1]);
    if(h[H_NOVG] == OVOVL) ovdie("too many guest lines", "");
    strcpy(T_GNAME + h[H_NOVG] * OVNM, tok[1]);
    h[H_NOVG] = h[H_NOVG] + 1;
    return YES;
  }
  if(!oveq(tok[0], "window")) return NO;
  s = tok[1];
  if(h[H_NTOK] != 2) s = "";
  if(h[H_WINSET]) s = "";
  if(*s++ != '8') ovdie("want one 'window 8' to 'window 8-13'", "");
  k = OVWINLO;
  if(*s == '-') {
    ++s;
    k = 0;
    while(*s >= '0' && *s <= '9') k = k * 10 + *s++ - '0';
  }
  if(*s || k < OVWINLO || k > OVWINMAX) ovdie("want 'window 8' to 'window 8-13', not ", tok[1]);
  h[H_WINHI] = k;
  h[H_WINSET] = YES;
  return YES;
}



/*
** one word of glue at cloc
*/
gword(w)
int w;
{
  codeputw(cloc, w);
  cloc = cloc + 2;
}

/*
** a reference to name at cloc: a one-link XREFS chain, as load() builds
*/
gref(name)
char *name;
{
  strcpy(symbol, name);
  field = 0;
  type = ABS;
  newsym(&xrprev, xrfirst, "xr");
  codeputw(cloc, getint(xrprev + VAL));
  putint(xrprev + VAL, cloc);
  cloc = cloc + 2;
}

/*
** ~routine for entry e
*/
gtarget(e, out)
int e;
char *out;
{
  out[0] = '~';
  strcpy(out + 1, T_EREAL + e * OVNM);
}

ovemit()
{
  int *h, id, i, j, t, nove, tbl;
  char *mo, *em, *eo, *ef, tn[20];

  h = OVHDR;
  mo = T_MOVL;
  em = T_EMOD;
  eo = T_EORD;
  ef = T_EFLG;
  nove = h[H_NOVE];
  t = 0;                        /* thunk order: by ID, then map order */
  for(id = 1; id <= h[H_NOVO]; ++id)
    for(i = 0; i < h[H_NOVM]; ++i)
      if(mo[i] == id)
        for(j = 0; j < nove; ++j)
          if(em[j] == i) eo[t++] = j;
  tbl = (h[H_NOVO] + 1) * OVPAIRS * 4;

  status("Glue   ", ovmapfn);
  cmod = cloc;
  pmorg = 0;
  epprev = epfirst;
  xrprev = xrfirst;
  h[H_TBL] = cloc;
  codeneed(tbl + nove * 12);
  for(i = 0; i < tbl; ++i) codeputb(cloc++, 0);
  for(t = 0; t < nove; ++t) {
    j = eo[t];
    gtarget(j, tn);
    gword(0x0201);                      /* LI   R1,id          */
    gword(mo[em[j]]);
    if(ef[j] & EFTAIL) {
      gword(0x2DA0);                    /* CALL @OVLMGR        */
      gref("OVLMGR");
      gword(0x0460);                    /* B    @~routine      */
      gref(tn);
      }
    else {
      gword(0x0202);                    /* LI   R2,~routine    */
      gref(tn);
      gword(0x0460);                    /* B    @OVCALL        */
      gref("OVCALL");
      }
    }
  strcpy(symbol, "OVL_TABLE");
  field = 0;
  type = PREL;
  newsym(&epprev, epfirst, "ep");
  for(t = 0; t < nove; ++t) {
    strcpy(symbol, T_ENAME + eo[t] * OVNM);
    field = tbl + t * 12;
    type = PREL;
    newsym(&epprev, epfirst, "ep");
    }
  link();
}
