/*
** OVL_MAP.C -- LINK99 -Y: read the overlay map; find and rename map
** modules as they load.
**
** The map is the Windows link99's (3.10.x) OVL99 overlay map, read the
** same way, so one OVLMAP.TXT serves both linkers:
**
**     # module   page   overlay  entries
**     OVLHELLO   4      GREET    hello greet
**     OVL_USAGE  2      USAGE    runusage=ovlusage:tail
**     guest CODE0
**     window 8-12
**
**   entry  foo            foo is renamed ~foo in its module and a thunk
**                         called foo takes its place
**          pub=routine    a thunk called pub reaches ~routine, an added
**                         copy of routine, which keeps its own name
**          either :tail   the thunk maps and branches (no OVCALL frame)
**
** Differences from Windows: a page span (lo-hi) is refused, and the
** tables are smaller (OVLY.H).
**
** Reading is split over two pages; resident main() drives it:
**     ovopen();  while(ovline()) if(!ovmisc()) ovmod();
**   ovopen()       clear the tables, open the map
**   ovline()       read and split one line; at the end, close and check
**   ovmisc()       blank, guest or window line: YES when handled (OVL_GLUE)
**   ovmod()        a module line (OVL_MAPM.C)
** and during phase 1:
**   ovfind(fn)     a command-line module's map index, or -1; sets ovpg
**   ovloaded()     after a map module has loaded: remember its -P row
**   ovrename()     at each EPOINT of a map module: ~rename a published
**                  routine; YES when an alias needs a ~copy as well
**   ovtilde()      symbol -> ~symbol, for that copy
** All are :tail thunks called from resident code.  OVL_GLUE.C writes the
** table and thunks and checks the result.
*/
#asm
        AORG    08000H
#endasm

#include <stdio.h>
#include "OVLY.H"

#define NOCCARGC
#define MAXSYM    15

extern error2();
extern char symbol[];
extern char ovmapfn[];
extern int ovcur, ovpg, pmn, pmorg;

#include "PUTNUM.C"
#include "OVLYSUB.C"

ovopen()
{
  int i, *h;
  char *p;
  p = OVT;
  i = OVTABSZ;
  while(i--) *p++ = 0;
  h = OVHDR;
  h[H_WINHI] = OVWINHI;
  h[H_FD] = fopen(ovmapfn, "r");
  if(!h[H_FD]) ovdie("cannot open it", "");
}

/*
** read one line into T_LB and split it into T_TOK; at the end of the
** file close it, check, and return NO
*/
ovline()
{
  int c, n, fd, *h, *tok;
  char *q, *lb;
  h = OVHDR;
  tok = T_TOK;
  lb = T_LB;
  fd = h[H_FD];
  c = getc(fd);
  if(c == EOF) {
    fclose(fd);
    h[H_LINE] = 0;
    if(!h[H_NOVM]) ovdie("declares no modules", "");
    return NO;
  }
  n = 0;
  while(c != EOF) {
    if(c == LF) break;                  /* '\n' is not LF here */
    if(c == CR) break;
    if(n < OVLBMAX) lb[n++] = c;
    c = getc(fd);
  }
  lb[n] = 0;
  h[H_LINE] = h[H_LINE] + 1;
  n = 0;
  q = lb;
  while(*q) {
    if(*q == '#') break;
    if(*q == ' ' || *q == 9) {
      ++q;
      continue;
    }
    if(n == OVMAXTOK) ovdie("too many fields", "");
    tok[n++] = q;
    while(*q) {
      if(*q == ' ' || *q == 9 || *q == '#') break;
      ++q;
    }
    if(*q == '#') *q = 0;
    else if(*q) *q++ = 0;
  }
  h[H_NTOK] = n;
  return YES;
}

/*
** map index of a command-line file, by base name, or -1
*/
ovfind(fn)
char *fn;
{
  char base[20], *s, *mp;
  int i, *h;
  h = OVHDR;
  s = fn;
  if(s[0]) if(s[1] == ':') s += 2;
  i = 0;
  while(*s && *s != '.' && i < MAXSYM) base[i++] = *s++;
  base[i] = 0;
  for(i = 0; i < h[H_NOVM]; ++i)
    if(oveq(base, T_MNAME + i * OVNM)) {
      mp = T_MROW;
      if(mp[i]) ovdie("module loaded twice: ", base);
      mp = T_MPAGE;
      ovpg = mp[i];
      return i;
    }
  return -1;
}

/*
** a map module is in: remember which -P row is its (row + 1)
*/
ovloaded()
{
  char *mp;
  mp = T_MROW;
  if(pmorg) mp[ovcur] = pmn;
}

/*
** EPOINT of map module ovcur: a plain published entry becomes ~name;
** an alias keeps its name and returns YES for load() to add ~name too
*/
ovrename()
{
  int i, ren, dup, *h;
  char *mp, *fl;
  h = OVHDR;
  mp = T_EMOD;
  fl = T_EFLG;
  ren = dup = NO;
  for(i = 0; i < h[H_NOVE]; ++i)
    if(mp[i] == ovcur) if(!strcmp(symbol, T_EREAL + i * OVNM)) {
      fl[i] = fl[i] | EFSEEN;
      if(fl[i] & EFALIAS) dup = YES;
      else ren = YES;
    }
  if(ren) {
    ovtilde();
    return NO;
  }
  return dup;
}

ovtilde()
{
  int n;
  n = slen(symbol);
  if(n > MAXSYM - 1) ovdie("routine name too long for its ~copy: ", symbol);
  while(n >= 0) {
    symbol[n + 1] = symbol[n];
    --n;
  }
  symbol[0] = '~';
}
