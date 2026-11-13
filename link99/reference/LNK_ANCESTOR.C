/* 
** LNK.C -- Small-Mac Linkage Editor
**
**                    Copyright 1985 J. E. Hendrix
**
** Usage: LNK [-B] [-G#] [-L] [-M] program [module/library...]
**
** -B                 A BIG program is being linked, so use all
**                    of free memory for the symbol table and load the
**                    program to disk entirely.  This is slower but it
**                    gets the job done.
**
** -G#                Make program absolute at address # (hex) and
**                    output as "program.LGO" instead of "program.COM".
**
** -L                 List entry point symbols.
**
** -M                 Monitor linking activity.
**
** program            A file specifier for the program being linked.
**                    The default, and only allowed, extension is REL.
**
** module/library...  A list of zero or more module (.REL) and/or
**                    library (.LIB) files.  Each module is linked to
**                    the program and the libraries are searched for
**                    just those modules which satisfy one or more
**                    unresolved external references.
**
** NOTE: Merely declaring a symbol to be external will cause
** it's module to be loaded.  It need not actually be referenced.
**
** NOTE: The symbol TMNAME is defined to be the name of the
** terminal module; i.e., the module which must be loaded last
** of all.  That module contains special code which identifies
** the physical end of the program and the beginning of free
** memory.  The linker is sensitive to its name and waits until
** all other modules are loaded before loading the terminal module.
**
** The absence of an extension, or a .REL extension, identifies a module;
** whereas, a .LIB extension identifies a library.  If necessary, a
** library is rescanned to resolve backward external references between
** modules within the library. Module files and libraries are processed
** in the order in which they occur in the command line.
**
** Drive Designators (e.g. B:):
**    - allowed with module and library names
**    - program drive designator locates the input .REL file
**    - output goes to the default drive
**
** Filename Extensions:
**    - must specify .LIB with library name
**    - standard extensions are:
**
**     .REL = relocatable object module
**     .LIB = library of object modules
**     .NDX = index to library (not user specified)
**     .COM = CP/M command file (default output)
**     .LGO = load-and-go file (-G# output)
**     .O$  = temporary overflow file
**     .R$  = temporary reference file
**
** Enter control-S to pause and control-C to abort.
**
** NOTE: Compile only with Small-C 2.1 (edit level 63) or later.
** Edit 63 fixes CSYSLIB so that when it overflows a buffer while
** writing into a file it will no longer assume that it is at the
** end of the file.  This prevents it from padding a sector with
** 1A (hex) in the middle of a file when random access is being used.
*/
#include <stdio.h>
#include "notice.h"
#include "rel.h"

#define NODEBUG			/* don't compile debug displays */
#define NOCCARGC		/* don't pass arg counts to functions */

#define NAMESIZE   15
#define MAXFIL     10
#define STACK     512		/* allow for stack space */
#define AUXBUF   2048		/* aux buffer for reference file */
#define MAXOPEN     4		/* maximum files opened */
#define OHDOPEN   164		/* memery overhead per open file */
#define COMBASE   259		/* 0100H + 3 */
#define RET       201		/* RET instruction (0C9H) */
#define JMP       195		/* JMP instruction (0C3H) */
#define RES        -1		/* value of resolved ext ref */
#define XRPLUS     -2		/* ext-ref-plus-offset flag */
#define TMNAME   "END"		/* terminal module name */
#define MODEXT  ".REL"
#define LIBEXT  ".LIB"
#define NDXEXT  ".NDX"
#define COMEXT  ".COM"
#define LGOEXT  ".LGO"
#define OFLEXT   ".O$"
#define REFEXT   ".R$"

/*
** symbol table definitions
*/
#define NXT    0		/* next-entry pointer */
#define VAL    2		/* offset value */
#define SYM    4		/* symbol */
#define SSZ (SYM+MAXSYM+1)	/* size of table entry */
#define HIGH 127		/* high-value byte */
#define CUSHION  (200*SSZ)	/* reserved for table at overflow point */
char high[] = {HIGH,0};		/* high-value symbol */

/*
** global variables
*/
char
 *xr,				/* external reference */
 *nxt,				/* next in ext ref chain */
 *ep,				/* entry point */
 *buffer,			/* beginning of code buffer */
 *bnext,			/* next byte in code buffer */
 *sfree,			/* head of freed entry list */
 *snext,			/* next symbol table entry */
 *cloc,				/* location counter */
 *cmod,				/* module location */
 *cbase,			/* base address */
 *csize,			/* program size (fake unsigned) */
 *goloc,			/* go location */
 *cdisk,			/* disk overflow location */
 *epfirst,			/* first entry point */
 *epprev,			/* previous entry point */
 *epnext,			/* next entry point */
 *xrfirst,			/* first external reference */
 *xrprev,			/* previous external reference */
 *xrnext,			/* next external reference */
  modname[MAXSYM+1],		/* name of current module */
  infn   [NAMESIZE],		/* input filename */
  ndxfn  [NAMESIZE],		/* index filename */
  tmfn   [NAMESIZE],		/* terminal-module library name */
  csfn   [NAMESIZE],		/* code seg filename */
  crfn   [NAMESIZE],		/* code rel filename */
  outfn  [NAMESIZE];		/* output filename */

int
  lgo,		/* load-and-go format? */
  list,		/* list symbols? */
  monitor,	/* monitor activity? */
  instr,	/* instruction to plant at 0000 */
  addr,		/* start address */
  ref,		/* reference to program relative item */
  big,		/* linking a big program? */
  xrplus,	/* value of offset for next ext ref */
  xrpflag=XRPLUS,	/* value of xrplus flag */
  ndxfd,	/* index fd */
  inblock,	/* block of next library member */
  inbyte,	/* byte in block of next library member */
  tmblock,	/* block of terminal module in tmfn */
  tmbyte,	/* byte of terminal module in tmblock */
  csfd,		/* code segment fd */
  crfd,		/* code relative index fd */
  outfd;	/* output fd */

extern int Uchrpos[];		/* lives in CSYSLIB */

main(argc,argv) int argc, argv[]; {
  fputs("Small-Mac Linkage Editor, ", stderr); fputs(VERSION, stderr);
  fputs(CRIGHT1, stderr);
  getsw(argc, argv);		/* fetch and remember switches */
  getmem();			/* acquire maximum memory buffer */
  phase1(argc, argv);		/* load and link */
  if(!okay()) abort(7);		/* quit early */
  phase2();			/* generate final output */
  }

/*
** get as much memory as possible for symbol table
*/
getmem() {
  char sz[8];
  int max;
  max = avail(YES);			/* how much available? */
  max -= STACK + AUXBUF + (MAXOPEN * OHDOPEN);
  buffer = bnext = malloc(max);		/* allocate space */
  snext  = buffer + (max - SSZ);	/* first entry */
  sfree  = 0;				/* no reusable entries yet */
#ifdef DEBUG
  if(monitor) {itou(max, sz, 8); puts2(sz, " Byte Buffer");}
#endif
  newtbl(&epfirst);			/* set low and high ent pts */
  newtbl(&xrfirst);			/* set low and high ext refs */
  }

/*
** get next module name
*/
getname() {
  if(getrel() == PNAME) {
    strcpy(modname, symbol);
    return (YES);
    }
  if(item == EFILE) return (NO);
  error2(infn, " - Corrupted");
  }

/*
** read next entry from library index file
*/
getndx() {
  if(read(ndxfd, &inblock, 2) != 2 ||	/* next block */
     read(ndxfd, &inbyte, 2) != 2) {	/* next byte in block */
    error2("- Error Reading ", infn);
    } 
  }

/*
** get switches from command line
*/
getsw(argc, argv) int argc, *argv; {
  char arg[NAMESIZE];
  int argnbr, b, len;
  argnbr = 0;
  while(getarg(++argnbr, arg, NAMESIZE, argc, argv) != EOF) {
    if(arg[0] != '-') continue;			/* skip file names */
    if(toupper(arg[1]) == 'G') {
      lgo = YES;
      len = xtoi(arg + 2, &b);
      if(len >= 0 && !arg[len + 2]) cbase = b; else usage();
      }
    else if(toupper(arg[1]) == 'B') big = YES;
    else if(toupper(arg[1]) == 'L') list = YES;
    else if(toupper(arg[1]) == 'M') monitor = YES;
    else usage();
    }
  }

/*
** is symbol an unresolved ext ref?
** on return of true, xrnext -> matching xr entry
*/
isunres() {
  int i;
  xrnext = getint(xrfirst);
  while(xrnext) {
    if((i = strcmp(symbol, xrnext + SYM)) < 0) return (NO);
    if(i == 0)  return (YES);
    xrnext = getint(xrnext);
    }
  return (NO);
  }

/*
** link external references to entry points
*/
link() {
  int cspg, csch;
  cspg = ctell(csfd);			/* remember temp file position */
  csch = ctellc(csfd);
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
      resolve();			/* resolve this ext ref */
      putint(xrprev, getint(xrnext));	/* delink from xr chain */
      putint(xrnext, sfree);		/* link to prev freed entry */
      sfree = xrnext;			/* make first freed entry */
      xrnext = getint(xrprev);		/* advance to next ext ref */
      continue;				/* same ext ref in diff modules? */
      }
    break;
    }
  cseek(csfd, cspg, 0);			/* restore temp file position */
  Uchrpos[csfd] = csch;
  }

/*
** load a module
*/
load() {
  char str[8], *offloc;
  offloc = -1;
  epprev = epfirst;			/* start at the very beginning */
  xrprev = xrfirst;
  do {
    poll(YES);
    switch(getrel()) {
      case    ABS: if(csfd) write(csfd, &field, 1);	/* put on disk */
                   else *bnext++ = field;		/* put in memory */
                   if(offloc == cloc) {		/* end of xr chain */
                     write(crfd, &xrpflag, 2);	/* flag for -cbase adj */
                     write(crfd, &cloc,  2);	/* reference for pass 2 */
                     }
                   ++cloc;
                   break;
      case   PREL: field = field + cmod;
                   if(csfd) write(csfd, &field, 2);	/* put on disk */
                   else {				/* put in memory */
                     putint(bnext, field);
                     bnext += 2;
                     }
                   write(crfd, &cloc,  2);	/* reference for pass 2 */
                   cloc += 2;
                   break;
      case  DSIZE: if(!field) break;
          default: error("- Unsupported Link Item");
      case    ERR: error("- Corrupt Module");
      case  EPROG: if(type == PREL) {
                     puts2("Start In ", modname);
                     goloc = field + cmod;
                     }
      case  ENAME: break;			/* bypass enames */
      case XCHAIN: newsym(&xrprev, xrfirst, "xr");
                   break;
      case EPOINT: newsym(&epprev, epfirst, "ep");
                   break;
      case  PSIZE: cmod = cloc;
                   if(monitor) {
                     itox(field, str, 8);
                     fputs(str, stdout); fputs(" Bytes at", stdout);
                     itox(cloc,  str, 6);
                     fputs(str, stdout); fputs("'", stdout);
                     itox(cloc+cbase,  str, 6);
                     fputs(str, stdout); puts2(" ", modname);
                     }
                   if(!csfd &&
                     (big || (bnext + field) > (snext - CUSHION))) {
                     cdisk = cloc;		/* disk overflow point */
                     csfd = open(csfn, "w+");	/* open overflow file */
#ifdef DEBUG
                     if(monitor) {
                       itox(cdisk, str, 8); puts2(str, " Overflow Point");
                       }
#endif
                     }
                   break;
      case  SETLC: field = field + cmod;
                   while(cloc < field) {		/* adj loc ctr */
                     if(csfd) write(csfd, "\0", 1);
                     else *bnext++ = 0;
                     ++cloc;
                     }
                     break;
      case  XPOFF: write(crfd, &xrpflag, 2);		/* flag xr plus */
                   write(crfd, &field, 2);		/* xr offset */
                   offloc = cloc;	/* remember in case ABS follows */ 
                   break;
      }
    } while(item != EPROG);
  }

/*
** create new file specifier from an old one
*/
newfn(dest, sour, ext) char *dest, *sour, *ext; {
  if(sour[1] == ':' && strcmp(ext, NDXEXT)) sour += 2;
  while(*sour && *sour != '.') *dest++ = *sour++;
  strcpy(dest, ext);
  }

/*
** store new symbol table entry
** they arrive in alphanumeric order
*/
newsym(prev, first, ts) int *prev, first; char *ts; {
  char at[8], *cp, *new;
  if(new = sfree) sfree = getint(sfree);	/* use old entry */
  else {
    new = snext;
    if((snext -= SSZ) < bnext) error("- Must Specify -B Switch");
    }
  if(strcmp(symbol, *prev + SYM) < 0)
    *prev = first;				/* tolerate M80 blunder */
  cp = *prev;
  while(strcmp(symbol, cp + SYM) >= 0) {	/* find position */
    *prev = cp;
    cp = getint(cp);
    }
  putint(new, cp);			/* point new entry ahead */
  putint(*prev, new);			/* point prev entry here */
  *prev = new;				/* this becomes prev entry */
  if(type == PREL) field = field + cmod;/* adjust for module location */
  putint(new + VAL, field);		/* load value */
  strcpy(new + SYM, symbol);		/* load symbol */
#ifdef DEBUG
  if(monitor) show(new, ts);
#endif
  }

/*
** initial table entries
*/
newtbl(low) int *low; {
  *low = snext;				/* always points to low entry */
  strcpy(snext + SYM, "");		/* store low symbol */
  putint(snext, snext - SSZ);		/* link to next (high) symbol */
  snext -= SSZ;				/* now point to next entry */
  strcpy(snext + SYM, high);		/* store high symbol */
  putint(snext, 0);			/* end of chain */
  snext -= SSZ;				/* bump to next entry */
  }

/*
** get next module name
*/
nxtmod() {
  getndx();				/* get location and */
  seek();				/* go straight to next member */
  return (getname());
  }

/*
** report the outcome and decide whether to quit
*/
okay() {
  int err; char *eplast;
  err = eplast = 0;
  xrnext = getint(xrfirst);		/* first external reference */
  epnext = getint(epfirst);		/* first entry point */
  if(list) puts("\nEntry Points:");
  while(YES) {
    poll(YES);
    if(strcmp(xrnext + SYM, epnext + SYM) > 0) {	/* ext > ent */
      if(epnext == eplast) {
        puts2("-  Redundant: ", xrnext + SYM);
        err = YES;
        }
      if(list) show(epnext, "");
      eplast = epnext;
      epnext = getint(epnext);
      continue;
      }
    if(strcmp(xrnext + SYM, epnext + SYM) < 0) {	/* ext < ent */
      puts2("- Unresolved: ", xrnext + SYM);
      err = YES;
      xrnext = getint(xrnext);
      continue;
      }
    if(*(xrnext + SYM) != HIGH) {			/* ext = ent */
      xrnext = getint(xrnext);
      continue;			/* same ext ref in diff modules? */
      }
    break;
    }
  if(err) return (NO);
  return (YES);
  }

/*
** load input files and library members
*/
phase1(argc, argv) int argc, *argv; {
  char sz[8];
  int i, lib, eof;
  eof = EOF;
  cdisk = -1;				/* high value for pointer */
  if(lgo) instr = RET;			/* load and go format */
  else {instr = JMP; cbase = COMBASE;}	/* COM file format */
  i = 0;
  while(getarg(++i, infn, NAMESIZE, argc, argv) != EOF) {
    if(infn[0] == '-') continue;	/* skip switches */
    if(extend(infn, MODEXT, LIBEXT))
         lib = YES;
    else lib = NO;
    if(!*outfn) {			/* first file name */
      if(lgo) newfn(outfn, infn, LGOEXT);
      else    newfn(outfn, infn, COMEXT);
      newfn(csfn, infn, OFLEXT);
      newfn(crfn, infn, REFEXT);
      crfd = open(crfn, "w+");		/* open reference file */
      auxbuf(crfd, AUXBUF);	/* extra buffering lowers head movement */
      }
    if(lib) search();	/* search library if unresolved ext refs */
    else {
      inrel = open(infn, "r");		/* must open */
      getname();			/* program name */
      load();				/* load module */
      link();				/* link previous modules */
      close(inrel);			/* must close */
      }
    }
  if(!*outfn) usage();
  if(*tmfn) {				/* must get terminal module */
    inrel = open(tmfn, "r");
    inblock = tmblock; inbyte = tmbyte;
    seek(); getname(); load(); link();
    close(inrel);
    }
  csize = cloc;
  if(ferror(crfd)) error2("- Error Writing ", crfn);
  write(crfd, &eof, 2);
  rewind(crfd);
  if(ferror(csfd)) error2("- Error Writing ", csfn);
  rewind(csfd);
  itox(csize, sz, 8); puts2(sz, " Bytes (hex)");
  itou(csize, sz, 8); puts2(sz, " Bytes (dec)");
  }

/*
** generate absolute output in COM or LGO format
**
** COM format: JMP <start> <program>
**
** LGO format: RET <start> <prog-base> <prog-size> <program>
*/
phase2() {
  char at[5];
  outfd = open(outfn, "w");
  write(outfd, &instr, 1);	/* plant first instruction */
  addr = cbase + goloc;
  write(outfd, &addr, 2);	/* with its address */
  if(lgo) {
    write(outfd, &cbase, 2);	/* where to load for execution */
    write(outfd, &csize, 2);	/* how many bytes to load */
    }
  cloc = -1;			/* allow efficient pre-increment */
  readref();			/* get first reference */
  while(++cloc < csize) {	/* while more code */
    if(cloc != ref) {		/* not relative reference */
      if(cloc < cdisk)
        field = *(cloc + buffer);
      else read(csfd, &field, 1);
      write(outfd, &field, 1);	/* copy one byte as is */
      continue;
      }
    if(cloc < cdisk)		/* get next 2-byte relative item */
      field = getint(cloc + buffer);
    else read(csfd, &field, 2);
    field = field + cbase + xrplus;	/* make absolute & apply offset */
    xrplus = 0;			/* reset offset value */
    write(outfd, &field, 2);	/* copy 2 bytes adjusted */
    readref();			/* get next reference */
    ++cloc;			/* need additional increment */
    }
  if(ferror(outfd))  error2("- Error Writing ", outfn);
  close(outfd);
  if(csfd) {
    if(ferror(csfd)) error2("- Error Reading ", csfn);
    close(csfd);
    delete(csfn);
    }
  if(ferror(crfd))   error2("- Error Reading ", crfn);
  close(crfd);
  delete(crfn);
  }

/*
** read next reference
*/
readref() {
  read(crfd, &ref, 2);			/* get next reference */
  if(ref == XRPLUS) {			/* ext ref offset flag? */
    read(crfd, &xrplus, 2);		/* yes, get offset value */
    read(crfd, &ref, 2);		/* then get reference */
    if(ref == XRPLUS) {			/* offseting tail of chain? */
      xrplus -= cbase;			/* yes, undo resolve()'s fix */
      read(crfd, &ref, 2);		/* then get reference */
      }
    }
  }

/*
** resolve external references to a given symbol
*/
resolve() {
  char at[5];
  if(!(xr = getint(xrnext + VAL))) return;	/* head of ext ref chain */
  ep = getint(epnext + VAL);			/* entry point address */
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
    if(xr < cdisk) {				/* in memory */
      nxt = getint(xr + buffer);  
      if(nxt == 0) ep += cbase;		/* end of chain is absolute */
      putint(xr + buffer, ep);
      }
    else {					/* on disk */
      xrseek(xr - cdisk); read(csfd, &nxt, 2);
      if(nxt == 0) ep += cbase;		/* end of chain is absolute */
      xrseek(xr - cdisk); write(csfd, &ep, 2);
      }
    } while(xr = nxt);
  }

/*
** search a library
*/
search() {
  int linked;
  linked = NO;
  newfn(ndxfn, infn, NDXEXT);
  ndxfd = open(ndxfn, "r");
  inrel = open(infn, "r");
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
          load();				/* load module */
          link();				/* link to previous ones */
          linked = YES;
          break;
          }
        }
      }
    if(!linked) break;
    linked = NO;
    rewind(ndxfd);
    }
  close(ndxfd);
  close(inrel);
  }

/*
** seek to next member in old library
*/
seek() {
  if(inblock == EOF) error("- Premature End of Index");
  if(cseek(inrel, inblock, 0) == EOF)
    error("- Corrupt Library or Index");
  Uchrpos[inrel] = inbyte;
  inrem = 0;			/* force getrel() to read a byte */
  }

/*
** show a symbol
*/
show(table, type) char *table, *type; {
  char str[8];  int abs;
  itox(abs = getint(table + VAL), str, 8);
  fputs( str, stdout); fputs("'", stdout);
  itox(abs + cbase, str, 6);
  fputs( str, stdout); fputs(" ", stdout);
  fputs(type, stdout); fputs(" ", stdout);
  puts(table + SYM);
  }

/*
** abort with a usage message
*/
usage() {
  error("Usage: LNK [-B] [-G#] [-L] [-M] program [module/library...]");
  }

/*
** seek external reference
*/
xrseek(byte) int byte; {
  if(cseek(csfd, (byte >> 7) & 511, 0) == EOF)
    error2("- Seek Error in ", csfn);
  Uchrpos[csfd] = byte & 127;
  }
  