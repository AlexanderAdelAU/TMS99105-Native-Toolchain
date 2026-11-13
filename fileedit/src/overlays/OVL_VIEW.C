/*
** OVL_VIEW.C -- FileEdit Step 7 shared one-frame renderer with line gutter.
**
** OVL_VIEW remains the fourth/last code overlay in segment 8.  It renders
** either the read-only viewer (vmode=0) or the in-memory editor
** (vmode=1) from the banked persistent EDITBUF arena behind >9000-BFFF.
**
** It owns no application lifetime.  edflag==4 enters the modal Ctrl-F Find
** session; the prompt remains active until Esc returns to the controller.
*/
#asm
        AORG    08000H
#endasm

extern putchar();
extern puts();
extern trmesc();
extern trmrev();
extern trmnorm();
extern trmpos();
extern trmclrln();
extern trmnum();
extern trmrule();
extern trmkey();
extern trmbell();
extern trmshow();
extern trmhide();
extern char *fsname;
extern ebget();
extern unsigned int eblen;
extern unsigned int ebindex();
extern int eblines;
extern unsigned int vidx;
extern int vtop;
extern int vtotal;
extern int vmode;
extern int vleft;
extern int etop;
extern int eline;
extern int ecol;
extern int ewant;
extern int etotal;
extern int eleft;
extern int ebdirty;
extern int edflag;
extern edvcol();
extern edxcol();
extern vfind();
extern int fsexist;

/* Editor gutter: five right-aligned digits plus one separator space. */
vlnum(n)
int n;
{
    if(n < 10000) putchar(' ');
    if(n < 1000) putchar(' ');
    if(n < 100) putchar(' ');
    if(n < 10) putchar(' ');
    trmnum(n);
    putchar(' ');
}


/* Render one logical buffer line on one terminal row. */
vline(row, lno)
int row, lno;
{
    int c;
    int col;
    int n;
    int skip;
    int lim;

    trmpos(row, 1);
    trmclrln();

    /* The gutter is display-only.  No line-number bytes enter EDITBUF. */
    if(vmode) {
        if(lno <= etotal)
            vlnum(lno);
        else
            puts("      ");
        lim = 73;             /* columns 7..79 belong to document text */
    }
    else
        lim = 79;

    if(vidx >= eblen) {
        /* The editor exposes one final empty logical line after a trailing CR. */
        if(vmode && lno <= etotal)
            return 1;
        return 0;
    }

    /* Horizontal offset is reserved for the editor's later long-line step. */
    skip = 0;
    while(skip < vleft && vidx < eblen && ebget(vidx) != 13) {
        vidx = vidx + 1;
        skip = skip + 1;
    }

    if(vidx >= eblen)
        return 1;

    c = ebget(vidx);
    vidx = vidx + 1;
    col = 1;

    while(c != 13) {
        if(c == 9) {
            n = 4 - ((col - 1) % 4);
            while(n > 0) {
                if(col <= lim)
                    putchar(' ');
                col = col + 1;
                n = n - 1;
            }
        }
        else if(c == 10) {
            /* Ignore a bare LF if one reaches the normalized buffer. */
        }
        else if(c >= 32 && c < 127) {
            if(col <= lim)
                putchar(c);
            col = col + 1;
        }
        else {
            if(col <= lim)
                putchar('.');
            col = col + 1;
        }

        if(vidx >= eblen)
            return 1;

        c = ebget(vidx);
        vidx = vidx + 1;
    }

    return 1;
}

viewfile()
{
    int row;
    int shown;
    int last;
    int top;
    int total;

    if(vmode && edflag == 4) {
        vfind();
        return;
    }

    /* edflag 3 is the editor fast path.  EDITCTL has positioned vidx at the
       current logical line, so reuse the normal line renderer without touching
       the title, rules, neighbouring rows or footer. */
    if(vmode && edflag == 3) {
        row = 3 + (eline - etop);
        if(row >= 3 && row <= 22)
            vline(row, eline);
        return;
    }

    if(vmode) {
        top = etop;
        total = etotal;
    }
    else {
        top = vtop;
        total = vtotal;
    }

    trmpos(1, 1);
    trmrev();
    if(vmode)
        puts(" FILEEDIT  ");
    else
        puts(" FILEEDIT VIEWER  ");
    puts(fsname);
    if(vmode) {
        if(fsexist == 0)
            puts("  [NEW]");
        if(ebdirty)
            puts("  [MOD]");
    }
    puts(" ");
    trmesc("[K");
    trmnorm();

    trmrule(2);

    row = 3;
    shown = 0;
    while(row <= 22) {
        if(vline(row, top + shown) == 0)
            row = 23;
        else {
            shown = shown + 1;
            row = row + 1;
        }
    }

    row = 3 + shown;
    while(row <= 22) {
        trmpos(row, 1);
        trmclrln();
        row = row + 1;
    }

    last = top + shown - 1;
    if(shown == 0)
        last = top;
    if(last > total)
        last = total;

    trmrule(23);

    trmpos(24, 1);
    trmrev();

    if(vmode) {
        puts(" Ln ");
        trmnum(eline);
        puts("/");
        trmnum(etotal);
        puts(" Col ");
        trmnum(edvcol());
        trmpos(24, 27);
        puts("Home End PgUp/Dn ^F Find ^V PasteMode ^O Save ^X Menu");
    }
    else {
        if(vtotal == 0)
            puts(" Empty file  ");
        else {
            puts(" Lines ");
            trmnum(vtop);
            puts("-");
            trmnum(last);
            puts(" of ");
            trmnum(vtotal);
            puts("  ");
        }
        puts("Up/Down  PgUp/PgDn  Home  Q quit ");
    }

    trmesc("[K");
    trmnorm();
}

/*
** Modal case-sensitive forward find.  Ctrl-F enters this routine and the
** bottom line remains the Find prompt until Esc.  Enter or Ctrl-F finds the
** next occurrence.  After a match the next search begins at hit+1 so repeated
** searches advance, including through overlapping matches.
**
** The pattern remains local because OVL_VIEW stays mapped for the whole Find
** session.  No resident search state is needed and the document is never
** modified.
*/
vfind()
{
    char pat[33];
    int c;
    int len;
    int j;
    int line;
    int col;
    int found;
    int max;
    int miss;
    unsigned int next;
    unsigned int pos;
    unsigned int hit;
    unsigned int i;

    len = 0;
    pat[0] = 0;
    next = ebindex(eline, ecol);
    miss = 0;
    found = 0;

    trmshow();
    while(1) {
        trmpos(24, 1);
        trmrev();
        puts(" Find: ");
        trmnorm();
        puts(pat);
        if(miss)
            puts("  [Not found]");
        trmclrln();

        /* Keep Find active on row 24, but after a successful search place
           the visible terminal cursor on the first character of the match.
           Pattern editing clears found below and returns the cursor here. */
        if(found)
            trmpos(3 + (eline - etop), edxcol() + 6);

        c = trmkey();
        if(c == 27) {
            trmhide();
            return 0;
        }

        if(c == 13 || c == 10 || c == 6) {
            if(len == 0) {
                trmbell();
                continue;
            }

            pos = next;
            found = 0;
            hit = 0;
            while(pos < eblen && found == 0) {
                if(pos + len <= eblen) {
                    j = 0;
                    while(j < len && ebget(pos + j) == pat[j])
                        j = j + 1;
                    if(j == len) {
                        found = 1;
                        hit = pos;
                    }
                }
                pos = pos + 1;
            }

            if(found == 0) {
                miss = 1;
                trmbell();
                continue;
            }

            line = 1;
            col = 0;
            i = 0;
            while(i < hit) {
                c = ebget(i);
                if(c == 13) {
                    line = line + 1;
                    col = 0;
                }
                else
                    col = col + 1;
                i = i + 1;
            }

            eline = line;
            ecol = col;
            ewant = col;

            if(eline < etop)
                etop = eline;
            if(eline > etop + 19)
                etop = eline - 19;
            max = etotal - 19;
            if(max < 1) max = 1;
            if(etop < 1) etop = 1;
            if(etop > max) etop = max;

            eleft = 0;
            while(eleft < ecol && edxcol() > 73)
                eleft = eleft + 1;
            vleft = eleft;

            next = hit + 1;
            miss = 0;

            /* Refresh the document around the match, then immediately restore
               the Find prompt on row 24.  Setting edflag away from 4 prevents
               viewfile() from re-entering vfind(). */
            vidx = ebindex(etop, 0);
            edflag = 1;
            viewfile();
            edflag = 4;
            continue;
        }

        if(c == 8 || c == 127) {
            if(len > 0) {
                len = len - 1;
                pat[len] = 0;
                next = ebindex(eline, ecol);
                miss = 0;
                found = 0;
            }
            else
                trmbell();
        }
        else if(c >= 32 && c < 127) {
            if(len < 32) {
                pat[len] = c;
                len = len + 1;
                pat[len] = 0;
                next = ebindex(eline, ecol);
                miss = 0;
                found = 0;
            }
            else
                trmbell();
        }
        else
            trmbell();
    }
}
