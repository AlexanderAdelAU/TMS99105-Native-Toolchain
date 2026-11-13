/*
** OVL_LNK.C -- LINK99 phase-1 link/search overlay.
**
** Keep GETREL/load/newsym resident.  This overlay contains routines that
** take no C arguments and use resident global state only.
*/
#include <stdio.h>
#include "rel99.h"

#define NOCCARGC
/* YES and NO come from stdio.h; do not redefine them here. */
#define VAL       2
#define SYM       4
#define HIGH    127
#define TMNAME  "END"
#define NDXEXT  ".NDX"

#asm
        AORG    08000H
        ENT     LNK
        ENT     SRCH
LNK:
        B       @ovllink
SRCH:
        B       @ovlsearch
#endasm

extern char *xr, *nxt, *ep;
extern char *buffer, *sfree, *cdisk, *cbase;
extern char *xrfirst, *xrprev, *xrnext;
extern char *epfirst, *epnext;
extern char infn[], ndxfn[], tmfn[], modname[];
extern int monitor, csfd, ndxfd, inrel, inrem;
extern int inblock, inbyte, tmblock, tmbyte;
extern unsigned ucl, ucd;

extern getint();
extern putint();
extern ctell();
extern ctellc();
extern cseekc();
extern strcmp();
extern strcpy();
extern newfn();
extern open();
extern close();
extern read();
extern write();
extern rewind();
extern lseek();
extern tell();
extern error2();
extern ifilelbuf();
extern nxtmod();
extern getrel();
extern poll();
extern isunres();
extern load();
extern xrseek();

ovllink() {
  int cspg, csch;

  /*
   * csfd is 0 when the code fits in memory, which is now the normal
   * case - CUSHION used to be bigger than the whole buffer, so the .O$
   * file always existed and these calls always had a real unit.
   *
   * ctell(0) reaches IOLIB99's _fchk with index -5 and it reports
   * "INVALID UNIT NUMBER".  Every use of csfd has to be guarded.
   */
  cspg = csch = 0;
  if(csfd) {
    cspg = ctell(csfd);			/* remember temp file position */
    csch = ctellc(csfd);
    }
  xrnext = getint(xrprev = xrfirst);	/* first external reference */
  epnext = getint(epfirst);		/* first entry point */
  while(YES) {
    if(strcmp(xrnext + SYM, epnext + SYM) > 0) {	/* xr > ep */
      epnext = getint(epnext);
      continue;
      }
    if(strcmp(xrnext + SYM, epnext + SYM) < 0) {	/* xr < ep */
      xrnext = getint(xrprev = xrnext);
      continue;
      }
    if(*(xrnext + SYM) != HIGH) {			/* xr = ep */
      ovlresolve();			/* resolve this ext ref */
      putint(xrprev, getint(xrnext));	/* delink from xr chain */
      putint(xrnext, sfree);		/* link to prev freed entry */
      sfree = xrnext;			/* make first freed entry */
      xrnext = getint(xrprev);		/* advance to next ext ref */
      continue;				/* same ext ref in diff modules? */
      }
    break;
    }
  if(csfd) cseekc(csfd, cspg, csch);	/* restore exact temp file position */
  }

/*
** load a module
*/
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

ovlsearch() {
  int linked, ndxpos;
  linked = NO;
  newfn(ndxfn, infn, NDXEXT);
  ndxfd = open(ndxfn, "r");

  if(!ndxfd) error2("- cannot open ", ndxfn);
  inrel = open(infn, "r");
  if(!inrel) error2(infn, " - cannot open");
  ifilelbuf();                     /* new library file */
  inrem = 0;
  while(YES) {					/* rescan till done */
    while(nxtmod()) {
      if(strcmp(modname, TMNAME) == 0) {	/* will load this one last */
        strcpy(tmfn, infn);
        tmblock = inblock;
        tmbyte = inbyte;
        continue;
        }
      while(getrel() == ENAME) {
        poll(YES);
        if(isunres()) {				/* unresolved reference? */
          /*
           * SBC/IOLIB99: do not keep the .NDX unit open while loading.
           * IOLIB allocates 548 bytes per open unit.  Keeping .R$, .LIB,
           * .NDX and .O$ open together leaves only 52 bytes for LINK99's
           * code/symbol buffer.
           *
           * Save the next-index byte position, close NDX, load/link the
           * selected member, then reopen NDX and restore that position.
           * This caps simultaneous units at three and returns 548 bytes
           * to the linker buffer.
           */
          ndxpos = tell(ndxfd);
          close(ndxfd);
          ndxfd = 0;
          load();				/* load module */
          ovllink();				/* link to previous ones */
          ndxfd = open(ndxfn, "r");
          if(!ndxfd) error2("- cannot reopen ", ndxfn);
          if(lseek(ndxfd, ndxpos, 0) < 0) error2("- NDX seek error ", ndxfn);
          linked = YES;
          break;
          }
        }
      }
    if(!linked) break;
    linked = NO;
    rewind(ndxfd);
    }
  if(ndxfd) close(ndxfd);
  close(inrel);
  }

/*
** seek to next member in old library
*/
