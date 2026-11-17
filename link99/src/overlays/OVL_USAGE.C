/*
** OVL_USAGE.C -- LINK99 usage/error and @file overlay.
**
** First real LINK99 overlay, following the proven FILEEDIT/FILESTAT model.
** Reached through runusage(), the resident thunk link99 -Y builds from
** OVLMAP.TXT (runusage=ovlusage:tail): it maps this page and branches here.
**
** getsw(), pgnum(), outname() and openref() are the command-line
** helpers phase1 uses once each; they live here, not in resident RAM.
**
** rdargs() reads an @file.  The shell's command line holds 64
** characters, which is not enough to link anything with overlays, so
**     LINK99 @FILE.LNK
** takes the arguments from a text file instead: any whitespace or line
** break separates them, '#' starts a comment that runs to the end of the
** line, and everything is upper-cased as the shell would.  It runs once,
** before the link starts, so it costs no resident space; the arguments
** are kept at the top of the symbol window (>9000-BFFF), not in the
** heap, which the I/O units need, and the symbol table starts below
** them (symtop).
*/
#asm
        AORG    08000H
#endasm

#include <stdio.h>

#define NOCCARGC
#define RAMAX   48              /* most arguments an @file may give     */
#define RABUF  640              /* bytes of argument text               */
#define SYMWIN  0x9000          /* as LINK99.C                          */
#define SYMSIZE 0x3000

#define NAMESIZE  15
#define REFEXT  ".R$"
#define COMEXT  ".COM"
#define EXEEXT  ".EXE"

extern error();
extern error2();
extern puts2();
extern getarg();
extern newfn();
extern int rargv;
extern char *symtop;
extern mapsym();
extern int lgo, big, list, monitor, oflag, pagemode, crfd, ovlmode;
extern char ovmapfn[];
extern int field;
extern char *cloc, *cbase, modname[];

#include "PUTNUM.C"
extern char *cbase;
extern char crfn[];

ovlusage()
{
    error("Usage: LINK99 [-B] [-G#] [-L] [-M] [-O#] [-S] [-Ymap] program [[-P#] module/library...]  or  LINK99 @file");
}

rdargs(name, prog)
char *name, *prog;
{
    int fd, c, n, room, *v;
    char *p;

    fd = fopen(name, "r");
    if(!fd) error2("- cannot open ", name);
    mapsym();                           /* the symbol window, >9000-BFFF */
    v = SYMWIN + SYMSIZE - RAMAX * 2 - RABUF;
    p = v + RAMAX;                      /* int pointer: RAMAX words on   */
    symtop = v;
    v[0] = prog;
    n = 1;
    room = RABUF;
    c = getc(fd);
    while(c != EOF) {
        if(c == '#') {
            while(c != EOF && c != LF && c != CR) c = getc(fd);  /* '\n' is not LF here */
            continue;
        }
        if(c <= ' ') {
            c = getc(fd);
            continue;
        }
        if(n >= RAMAX - 1) error2("- Too many arguments in ", name);
        v[n++] = p;
        while(c != EOF && c > ' ') {
            if(--room < 1) error2("- Too much text in ", name);
            *p++ = toupper(c);
            c = getc(fd);
        }
        *p++ = 0;
        --room;
    }
    fclose(fd);
    v[n] = 0;
    rargv = v;
    return n;
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
      cbase = hexarg(arg);
      }
    else if(toupper(arg[1]) == 'O') {
      oflag = YES;
      cbase = hexarg(arg);
      }
    else if(toupper(arg[1]) == 'P') {
      if(pgnum(arg) < 1) ovlusage();
      pagemode = YES;
      }
    else if(toupper(arg[1]) == 'S') ;	/* Windows compatibility */
    else if(toupper(arg[1]) == 'Y') {	/* overlay map, OVL_MAP.C */
      if(!arg[2] || ovlmode) ovlusage();
      strcpy(ovmapfn, arg + 2);
      ovlmode = pagemode = YES;
      }
    else if(toupper(arg[1]) == 'B') big = YES;
    else if(toupper(arg[1]) == 'L') list = YES;
    else if(toupper(arg[1]) == 'M') monitor = YES;
    else ovlusage();
    }
  }

/*
** -P# -> #, or -1 if it is not a page 1-15
*/
pgnum(arg) char *arg; {
  int n;
  char c;
  n = 0;
  arg += 2;
  if(!*arg) return -1;
  while(c = *arg++) {
    if(c < '0' || c > '9') return -1;
    n = n * 10 + c - '0';
    if(n > 15) return -1;
    }
  if(n < 1) return -1;
  return n;
  }


/*
** open the phase-2 reference file, named after the program
*/
openref(name) char *name; {
  newfn(crfn, name, REFEXT);
  crfd = open(crfn, "w+");
  if(!crfd) error2("- cannot open ", crfn);
  }

/*
** is this first name an output name (.EXE or .COM) rather than a module?
*/
outname(name) char *name; {
  char *dot;
  dot = 0;
  while(*name) {
    if(*name == '.') dot = name;
    ++name;
    }
  if(!dot) return NO;
  if(!strcmp(dot, EXEEXT)) return YES;
  if(!strcmp(dot, COMEXT)) return YES;
  return NO;
  }

/*
** -G# / -O#: the hex number after the switch letter.  Not xtoi: a
** library routine only an overlay calls would be placed above them.
*/
hexarg(arg)
char *arg;
{
  int n, c;
  char *s;
  s = arg + 2;
  if(!*s) ovlusage();
  n = 0;
  while(c = toupper(*s++)) {
    if(c >= '0' && c <= '9') c = c - '0';
    else if(c >= 'A' && c <= 'F') c = c - 'A' + 10;
    else ovlusage();
    n = (n << 4) + c;
  }
  return n;
}

/*
** -M: a module's size and place, at its PSIZE
*/
monmod()
{
  fputs("  ", stdout);
  putx(field, 4);
  fputs(" Bytes at ", stdout);
  putx(cloc, 4);
  fputs("' ", stdout);
  putx(cloc + cbase, 4);
  puts2(" ", modname);
}
