FILEEDIT -- overlay text editor and FILESTAT lineage (Step 9)
=============================================================

FILEEDIT began as FILESTAT, a TMS9900/TMS99105 text-file analyser and evolved
into a full-screen Tera Term/VT100 editor with mapped code overlays.

CURRENT MILESTONE -- STEP 9 ADAPTIVE BUFFER
-------------------------------------------
Current functionality includes:

  full-screen editing with display-only line numbers
  arrows, Home/End, PgUp/PgDn and rapid cursor movement
  insert, Backspace, Delete, Enter and literal TAB editing
  Open, New, Save and Save As
  [MOD] dirty indication and unsaved-change protection
  rolling .BAK backup plus post-write verification
  five mapped code overlays
  64-byte interrupt-driven TMS9902 receive queue
  adaptive editor storage:
      24 KB through >9000-BFFF page 0/page 1
      plus the available EXE heap reported by SHELL V6.3
      plus 8 KB through the shell >C000-DFFF window on page 1
  unsigned 16-bit document byte indexes for files above 32767 bytes

The minimum Step 9 text capacity is 32767 bytes; detected heap is added to it.
See STEP9_ADAPTBUF.TXT for the mapper contract and limitations.

Commands
--------
    FILEEDIT SAMPLE.TXT        original analyser
    FILEEDIT SAMPLE.TXT /L     list then analyse
    FILEEDIT SAMPLE.TXT /V     read-only viewer
    FILEEDIT SAMPLE.TXT /E     editor with SAMPLE.TXT initially open
    FILEEDIT /E                editor with no initial document
    FILEEDIT /I                isolated INT4/TMS9902 diagnostic

Editor keys
-----------
    Arrow keys       move cursor
    PgUp/PgDn        move by a screen
    Home/End         beginning/end of logical line
    Tab              insert a real ASCII 09 TAB
    Backspace        delete left
    Delete           delete under cursor
    Enter            split line
    Ctrl-O           Save + verify
    Ctrl-X           return to menu

Overlay assignment
------------------
    page 2  OVL_WORD
    page 3  OVL_CHAR
    page 4  OVL_RPT
    page 5  OVL_VIEW
    page 6  OVL_EDIT

Segment 8 (>8000-8FFF) is the code-overlay window.  The document mapper does
not alter it.  Segment E remains BDOS and segment F remains ROM.

TMS9902 receive path
--------------------
FILEEDIT temporarily replaces only the writable INT4 PC word at >0012 and
retains the MONITOR's INT4 workspace at >0010.  RXISR drains TMS9902 receive
bytes into a 64-byte queue and always chains to the saved prior INT4 handler.

Build note
----------
Run make_SBC_FileEdit99.ps1 on the normal Windows build machine.  The source
archive intentionally does not present the stale pre-Step-9 FILEEDIT.EXE as a
new build.
