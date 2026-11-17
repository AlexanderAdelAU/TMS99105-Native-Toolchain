/*
** OVL_MAPM.C -- LINK99 -Y: one module line of the overlay map.
**
**     module   page   overlay   entries...
**
** ovmod() checks and records a module line (OVLY.H tables): the module's page,
** its overlay (IDs in order of first appearance) and each entry,
**     foo   pub=routine   either with :tail   or "-" for none.
** A :tail thunk called from resident main() (see OVL_MAP.C).  Its own
** page because Small-C's code for it does not fit beside OVL_MAP's.
*/
#asm
        AORG    08000H
#endasm

#include <stdio.h>
#include "OVLY.H"

#define NOCCARGC
#define MAXSYM    15

extern error2();
extern char ovmapfn[];

#include "PUTNUM.C"
#include "OVLYSUB.C"

/*
** index of name in a table of OVNM slots, or -1
*/
ovindex(name, tab, n)
char *name, *tab;
int n;
{
  int i;
  for(i = 0; i < n; ++i)
    if(!strcmp(name, tab + i * OVNM)) return i;
  return -1;
}

/*
** die unless s is at most max characters
*/
ovlen(s, max)
char *s;
int max;
{
  if(slen(s) > max) ovdie("name too long: ", s);
}

ovmod()
{
  int i, j, k, n, ne, *h, *tok;
  char *ent, *eq, *co, *mp, *fl;

  h = OVHDR;
  tok = T_TOK;
  if(h[H_NTOK] < 4) ovdie("want: module page overlay entries...", "");

  /* module */
  n = h[H_NOVM];
  if(n == OVMOD) ovdie("too many modules", "");
  ovlen(tok[0], MAXSYM);
  for(i = 0; i < n; ++i)
    if(oveq(tok[0], T_MNAME + i * OVNM)) ovdie("module listed twice: ", tok[0]);
  strcpy(T_MNAME + n * OVNM, tok[0]);

  /* page: 1-15; lo-hi only as lo = hi (no spans here) */
  co = tok[1];
  k = 0;
  while(*co >= '0' && *co <= '9') k = k * 10 + *co++ - '0';
  if(*co == '-') {
    ++co;
    j = 0;
    while(*co >= '0' && *co <= '9') j = j * 10 + *co++ - '0';
    if(j != k) ovdie("page spans (lo-hi) are not supported on the SBC: ", tok[1]);
  }
  if(*co || k < 1 || k > 15) ovdie("page must be 1-15, not ", tok[1]);
  mp = T_MPAGE;
  mp[n] = k;

  /* overlay: IDs in order of first appearance */
  ovlen(tok[2], MAXSYM);
  k = ovindex(tok[2], T_ONAME, h[H_NOVO]);
  if(k < 0) {
    k = h[H_NOVO];
    if(k == OVOVL) ovdie("too many overlays", "");
    strcpy(T_ONAME + k * OVNM, tok[2]);
    h[H_NOVO] = k + 1;
  }
  mp = T_MOVL;
  mp[n] = k + 1;

  /* entries: name | public=real, either with :tail */
  mp = T_EMOD;
  fl = T_EFLG;
  for(i = 3; i < h[H_NTOK]; ++i) {
    ent = tok[i];
    if(!strcmp(ent, "-")) continue;
    ne = h[H_NOVE];
    if(ne == OVENT) ovdie("too many entries", "");
    fl[ne] = 0;
    co = ent;
    while(*co && *co != ':') ++co;
    if(*co) {
      if(!oveq(co, ":tail")) ovdie("only :tail may follow an entry, not ", co);
      *co = 0;
      fl[ne] = EFTAIL;
    }
    eq = ent;
    while(*eq && *eq != '=') ++eq;
    if(*eq) {
      *eq++ = 0;
      if(!*ent) ovdie("want public=routine", "");
      if(!*eq) ovdie("want public=routine", "");
      ovlen(ent, MAXSYM);
      ovlen(eq, MAXSYM - 1);            /* ~routine must fit */
      fl[ne] = fl[ne] | EFALIAS;
    }
    else {
      ovlen(ent, MAXSYM - 1);
      eq = ent;
    }
    if(ovindex(ent, T_ENAME, ne) >= 0) ovdie("public name used twice: ", ent);
    for(j = 0; j < ne; ++j)             /* ~routine must be unique */
      if(mp[j] != n) if(!strcmp(T_EREAL + j * OVNM, eq))
        ovdie("routine published by two modules: ", eq);
    strcpy(T_ENAME + ne * OVNM, ent);
    strcpy(T_EREAL + ne * OVNM, eq);
    mp[ne] = n;
    h[H_NOVE] = ne + 1;
  }
  h[H_NOVM] = n + 1;
}
