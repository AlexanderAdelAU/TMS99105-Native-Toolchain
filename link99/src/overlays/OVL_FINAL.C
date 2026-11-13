/*
** OVL_FINAL.C -- LINK99 post-phase1 overlay.
**
** This deliberately contains code that is not needed while phase1 is
** constructing the target image: symbol consistency checking and phase2
** output generation.  Moving it out of the resident image gives that RAM
** back to LINK99's code/symbol buffer while retaining the FILEEDIT/FILESTAT
** overlay model.
*/
#include <stdio.h>
#include "rel99.h"

#define NOCCARGC
#define SYM       4
#define HIGH    127
#define XRPLUS   -2

#asm
        AORG    08000H
        ENT     OVL_FINAL_ENTRY
OVL_FINAL_ENTRY:
        B       @ovlfinal
#endasm

/* resident functions */
extern getint();
extern putint();
extern puts2();
extern show();
extern poll();
extern error2();
extern xrseek();

/* resident state -- keep the original LINK99 types */
extern char *xrnext, *epnext, *xrfirst, *epfirst;
extern char *buffer, *cloc, *cbase, *csize, *goloc, *cdisk;
extern char outfn[], csfn[], crfn[];
extern int list, outfd, instr, addr, lgo, ref, field;
extern int csfd, crfd, xrplus;
extern unsigned ucl, ucd;

ovlfinal()
{
    if(!ovlokay()) return 0;
    ovlphase2();
    return 1;
}

ovlokay()
{
    int err;
    char *eplast;

    err = eplast = 0;
    xrnext = getint(xrfirst);
    epnext = getint(epfirst);
    if(list) puts("\nEntry Points:");

    while(1) {
        poll(1);
        if(strcmp(xrnext + SYM, epnext + SYM) > 0) {
            if(epnext == eplast) {
                puts2("-  Redundant: ", xrnext + SYM);
                err = 1;
            }
            if(list) show(epnext, "");
            eplast = epnext;
            epnext = getint(epnext);
            continue;
        }
        if(strcmp(xrnext + SYM, epnext + SYM) < 0) {
            puts2("- Unresolved: ", xrnext + SYM);
            err = 1;
            xrnext = getint(xrnext);
            continue;
        }
        if(*(xrnext + SYM) != HIGH) {
            xrnext = getint(xrnext);
            continue;
        }
        break;
    }
    if(err) return 0;
    return 1;
}

ovlphase2()
{
    outfd = open(outfn, "w");
    if(!outfd) error2("- cannot open ", outfn);

    write(outfd, &instr, 1);
    addr = cbase + goloc;
    write(outfd, &addr, 2);
    if(lgo) {
        write(outfd, &cbase, 2);
        write(outfd, &csize, 2);
    }

    cloc = -1;
    ovlreadref();
    while(++cloc < csize) {
        if(cloc != ref) {
            ucl = cloc; ucd = cdisk;
            if(ucl < ucd) field = *(cloc + buffer);
            else read(csfd, &field, 1);
            write(outfd, &field, 1);
            continue;
        }

        ucl = cloc; ucd = cdisk;
        if(ucl < ucd) field = getint(cloc + buffer);
        else read(csfd, &field, 2);
        field = field + cbase + xrplus;
        xrplus = 0;
        write(outfd, &field, 2);
        ovlreadref();
        ++cloc;
    }

    if(ferror(outfd)) error2("- Error Writing ", outfn);
    close(outfd);

    if(csfd) {
        if(ferror(csfd)) error2("- Error Reading ", csfn);
        close(csfd);
    }
    if(ferror(crfd)) error2("- Error Reading ", crfn);
    close(crfd);
}

ovlreadref()
{
    read(crfd, &ref, 2);
    if(ref == XRPLUS) {
        read(crfd, &xrplus, 2);
        read(crfd, &ref, 2);
        if(ref == XRPLUS) {
            xrplus -= cbase;
            read(crfd, &ref, 2);
        }
    }
}
