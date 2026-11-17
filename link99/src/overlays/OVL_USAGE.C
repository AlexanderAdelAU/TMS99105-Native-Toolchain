/*
** OVL_USAGE.C -- LINK99 usage/error overlay.
**
** First real LINK99 overlay, following the proven FILEEDIT/FILESTAT model.
** Reached through runusage(), the resident thunk link99 -Y builds from
** OVLMAP.TXT (runusage=ovlusage:tail): it maps this page and branches here.
*/
#asm
        AORG    08000H
#endasm

extern error();

ovlusage()
{
    error("Usage: LNK [-B] [-G#] [-L] [-M] program [module/library...]");
}
