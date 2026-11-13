/*
** OVL_RESOLVE.C -- LINK99 phase-1 resolve overlay
*/
#include <stdio.h>
#include "rel99.h"

#define VAL 2

extern char *xr, *nxt, *ep;
extern char *buffer, *cbase, *cdisk;
extern char *xrnext, *epnext;
extern int monitor, csfd;
extern unsigned ucl, ucd;

extern getint();
extern putint();
extern poll();
extern itox();
extern puts2();
extern xrseek();
extern read();
extern write();

#asm
        AORG    08000H
        ENT     RSLV
RSLV:
        B       @ovlresolve
#endasm

ovlresolve() {
  char at[9];
  if(!(xr = getint(xrnext + VAL))) return;	/* head of ext ref chain */

  /*
   * ABSOLUTE ONCE, FOR EVERY REFERENCE IN THE CHAIN.
   *
   * The entry point's value is buffer-relative - newsym rebased it by
   * cmod, the module's position - so the address to plant is ep+cbase.
   * EVERY slot needs it, not just the last.
   *
   * The original added cbase inside the loop, guarded by "if(nxt == 0)",
   * so only the slot holding the terminator came out absolute and any
   * symbol referenced more than once in a module got buffer-relative
   * addresses at every other site.  With one reference per chain - which
   * is all HELLO.R99 has - the fault is invisible.
   */
  ep = getint(epnext + VAL) + cbase;		/* absolute entry point */
  do {
#ifdef DEBUG
    if(monitor) {
      poll(YES);
      fputs("Resolving ", stdout);
      itox(xr, at, 5); fputs(at, stdout);
      fputs(" to ", stdout);
      itox(ep, at, 5); fputs(at, stdout);
      puts2(" ", xrnext + SYM);
      }
#endif
    ucl = xr; ucd = cdisk;
    if(ucl < ucd) {				/* in memory */
      nxt = getint(xr + buffer);	/* read the link BEFORE overwriting */
      putint(xr + buffer, ep);
      }
    else {					/* on disk */
      xrseek(xr - cdisk); read(csfd, &nxt, 2);
      xrseek(xr - cdisk); write(csfd, &ep, 2);
      }
    } while(xr = nxt);
  }
