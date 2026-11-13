/*
** OVL_START.C -- LINK99 startup overlay
*/
#include <stdio.h>
#include "rel99.h"

#define NAMESIZE   15
#define STACK     512
#define AUXBUF      0
#define MAXOPEN     3
#define OHDOPEN   548
#define NXT    0
#define VAL    2
#define SYM    4
#define SSZ (SYM+MAXSYM+1)

extern int gargc, gargv;
extern int lgo, list, monitor, big;
extern int cbase;
extern char *buffer, *bnext, *snext, *sfree, *epfirst, *xrfirst;
extern char high[];

#asm
        AORG    08000H
        ENT     STRT
STRT:
        B       @ovlstart
#endasm

ovlstart()
{
  ovlgetsw(gargc, gargv);
  ovlgetmem();
  }

ovlgetmem()
{
  char sz[12];
  int max;
  max = avail(YES);
  max -= STACK + AUXBUF + (MAXOPEN * OHDOPEN);
  buffer = bnext = malloc(max);
  if(buffer == -1 || !buffer) error("- malloc failed\n");
  snext  = buffer + (max - SSZ);
  sfree  = 0;
#ifdef DEBUG
  if(monitor) {itou(max, sz, 8); puts2(sz, " Byte Buffer");}
#endif
  ovlnewtbl(&epfirst);
  ovlnewtbl(&xrfirst);
  }

ovlgetsw(argc, argv) int argc, *argv; {
  char arg[NAMESIZE];
  int argnbr, b, len;
  argnbr = 0;
  while(getarg(++argnbr, arg, NAMESIZE, argc, argv) != EOF) {
    if(arg[0] != '-') continue;
    if(toupper(arg[1]) == 'G') {
      lgo = YES;
      len = xtoi(arg + 2, &b);
      if(len >= 0 && !arg[len + 2]) cbase = b; else runusage();
      }
    else if(toupper(arg[1]) == 'B') big = YES;
    else if(toupper(arg[1]) == 'L') list = YES;
    else if(toupper(arg[1]) == 'M') monitor = YES;
    else runusage();
    }
  }

ovlnewtbl(low) int *low; {
  *low = snext;
  strcpy(snext + SYM, "");
  putint(snext, snext - SSZ);
  snext -= SSZ;
  strcpy(snext + SYM, high);
  putint(snext, 0);
  snext -= SSZ;
  }
