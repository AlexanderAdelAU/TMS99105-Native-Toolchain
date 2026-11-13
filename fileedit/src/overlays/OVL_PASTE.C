/*
** OVL_PASTE.C -- FileEdit Ctrl-V terminal paste overlay.
**
** Ctrl-V enters a modal high-speed input loop.  Clipboard paste from the host
** terminal arrives as ordinary serial bytes; this overlay consumes them
** without per-character redraw.  CR/LF/CRLF are normalized to the editor's
** internal CR delimiter.  Esc exits, after which EDITCTL performs one full
** redraw.  No clipboard protocol is required on the SBC.
*/
#asm
        AORG    08000H
#endasm

extern puts();
extern trmpos();
extern trmrev();
extern trmnorm();
extern trmclrln();
extern trmkey();
extern trmshow();
extern trmhide();
extern trmbell();
extern unsigned int ebindex();
extern ebins();
extern edxcol();

extern int etop;
extern int eline;
extern int ecol;
extern int ewant;
extern int etotal;
extern int eleft;
extern int vleft;
extern unsigned int eblen;
extern int rxovfl;

/*
** Modal paste.  The terminal cursor remains on the status line while bytes
** arrive.  The document cursor state advances in RAM but the screen is not
** repainted until this overlay returns on Esc.
*/
pasteedit()
{
    int c;
    int prevcr;
    int full;
    int startov;
    int max;
    unsigned int pos;

    pos = ebindex(eline, ecol);
    prevcr = 0;
    full = 0;
    startov = rxovfl;

    trmpos(24, 1);
    trmrev();
    puts(" PASTE MODE - use Tera Term Edit>Paste, Esc finish");
    trmclrln();
    trmnorm();
    trmshow();

    while(1) {
        c = trmkey();
        if(c == 27)
            break;

        /* Normalize CRLF to one internal CR.  A bare LF is also a newline. */
        if(c == 10 && prevcr) {
            prevcr = 0;
            continue;
        }

        if(c == 13) {
            prevcr = 1;
        }
        else {
            prevcr = 0;
            if(c == 10)
                c = 13;
        }

        if(c == 9 || c == 13 || (c >= 32 && c < 127)) {
            if(full == 0) {
                if(ebins(pos, c) == 0) {
                    full = 1;
                    trmbell();
                    trmpos(24, 1);
                    trmrev();
                    puts(" PASTE BUFFER FULL - Esc finish");
                    trmclrln();
                    trmnorm();
                }
                else {
                    pos = pos + 1;
                    if(c == 13) {
                        etotal = etotal + 1;
                        eline = eline + 1;
                        ecol = 0;
                    }
                    else
                        ecol = ecol + 1;
                    ewant = ecol;
                }
            }
            /* If full, keep draining the terminal until Esc so trailing paste
               bytes cannot escape into the normal editor command loop. */
        }
    }

    /* Make the final document cursor visible before the controller redraws. */
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

    trmhide();

    /* Queue overflow means at least one host byte was lost.  Warn immediately
       rather than silently accepting a corrupted paste. */
    if(rxovfl != startov) {
        trmpos(24, 1);
        trmrev();
        puts(" PASTE INPUT OVERRUN - press any key");
        trmclrln();
        trmnorm();
        trmshow();
        trmkey();
        trmhide();
    }

    return 0;
}
