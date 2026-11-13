/*
** EDITCTL.C -- small resident editor lifetime controller (Step 6.3).
**
** Persistent cursor/document state stays resident.  The heavier key parser,
** navigation and editing operations now live in OVL_EDIT.  OVL_VIEW renders
** frames and OVL_EDIT processes exactly one key, so neither overlay ever calls
** another overlay while it is mapped.
*/

extern runview();
extern runedit();
extern runpaste();
extern trmshow();
extern trmhide();
extern trmclear();
extern ebseek();
extern ebedln();
extern unsigned int ebindex();
extern ebhome();

extern int vmode;
extern int vleft;
extern unsigned int eblen;
extern ebget();

int etop;
int eline;
int ecol;
int ewant;
int etotal;
int eleft;
int edflag;

/*
** Shared visual-column helpers must be resident because both OVL_VIEW and
** OVL_EDIT use them.  Keeping them here also prevents an overlay-to-overlay
** call through the common >8000 window.
*/
edxcol()
{
    unsigned int i;
    unsigned int end;
    int c;
    int col;

    i = ebindex(eline, eleft);
    end = ebindex(eline, ecol);
    col = 1;
    while(i < end && i < eblen) {
        c = ebget(i);
        if(c == 9)
            col = col + (4 - ((col - 1) % 4));
        else
            col = col + 1;
        i = i + 1;
    }
    return col;
}

edvcol()
{
    int save;
    int col;
    save = eleft;
    eleft = 0;
    col = edxcol();
    eleft = save;
    return col;
}

editctl()
{
    int redraw;
    int oldtotal;

    etotal = ebedln();
    etop = 1;
    eline = 1;
    ecol = 0;
    ewant = 0;
    eleft = 0;
    vleft = 0;
    vmode = 1;
    edflag = 1;
    redraw = 1;

    trmclear();
    trmhide();

    while(edflag != 2) {
        if(redraw == 4) {
            runview();
            edflag = 1;
            redraw = 1;
            continue;
        }
        if(redraw == 5) {
            runpaste();
            edflag = 1;
            redraw = 1;
            continue;
        }
        if(redraw == 1) {
            ebseek(etop);
            runview();
        }
        else if(redraw == 3) {
            /* Fast edit path: OVL_VIEW repaints only the current row. */
            ebseek(eline);
            runview();
        }

        /* OVL_EDIT waits for and processes exactly one key. */
        oldtotal = etotal;
        runedit();

        /* Backspace/Delete can remove a CR.  They request the cheap line path
           in OVL_EDIT; a changed logical-line count promotes it here. */
        if(edflag == 3 && etotal != oldtotal)
            edflag = 1;
        redraw = edflag;
    }

    trmshow();
    ebhome();
    trmclear();
    vmode = 0;
}
