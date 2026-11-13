/*
** OVL_BASE.C
**
** LINK99 overlay-container baseline.
**
** This overlay is intentionally tiny and is not called by the resident
** linker yet.  Its purpose is to make the LINK99 executable use the same
** page/chain-block EXE construction model as FILEEDIT before real linker
** functions are moved into overlays.
*/

/*
** *** AN OVERLAY MUST BE LOCATED IN THE OVERLAY WINDOW. ***
**
** OVLMGR's window A is >8000-BFFF, segments 8..11.  Without this AORG
** the linker leaves this module at whatever address it had reached -
** 6072 - and tags it page 2.  The loader then writes a page-2 block
** over resident memory, and the two page-0 runs overlap by 66 bytes:
**
**     blocks 0..40  page 0  1000 .. 60B8
**     block  41     PAGE 2  6072            <- inside the resident
**     blocks 42..45 page 0  6076 .. 67A6    <- starts BELOW 60B8
**
** Every FILESTAT overlay begins with exactly this, which is where I
** took it from - OVL_CHAR.C, OVL_WORD.C and OVL_RPT.C all do it.
*/
#asm
        AORG    08000H
#endasm

ovlbase()
{
    return 0;
}
