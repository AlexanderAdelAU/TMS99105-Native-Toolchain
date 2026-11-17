LINK99 SBC - OVERLAYS
=====================

The overlay map OVLMAP.TXT (one level up) declares every overlay; the Windows
link99 -Y places them and builds OVL_TABLE and the resident thunks.  IDs are
in include\OVLDEFS.INC and the build checks them against what link99 built.

Callable code overlays, segment 8 (>8000-8FFF), all :tail thunks called from
resident code:

  page 2  OVL_USAGE.C   usage message, LINK99 @file, switches, -M lines
  page 3  OVL_FINAL.C   symbol check, sizes, .COM/.LGO output
  page 4  OVL_EXE.C     paged .EXE output (EXE chain blocks)
  page 5  OVL_MAP.C     -Y: open and read the map, find/rename map modules
  page 6  OVL_GLUE.C    -Y: OVL_TABLE and thunks; guest/window lines
  page 7  OVL_MAPM.C    -Y: module lines of the map
  page 8  OVL_CHK.C     -Y: checks after the last module
  page 9  OVL_TAB.C     -Y: fill OVL_TABLE, list the map

Data banks (guests, never entered as code):

  OVL_CODE0..14.A99   the target image: segment C pages 2-15, then page 1
  OVL_S9/S10/S11.A99  the symbol window: segments 9-B, pages 13-15

Not built (left from earlier plans): OVL_BASE.C, OVL_GETREL.C, OVL_LNK.C,
OVL_P4T.A99, OVL_RESOLVE.C, OVL_START.C.

See ..\..\..\OVL99.md for OVL99 itself.

OVERLAY OWNERSHIP RULE
----------------------
A module that can be entered as code must map virtual segment 8 so OVLMGR
can establish CUR_WINA_ID.  Modules mapped only as data may use other
segments but must never be called.  OVLMGR_INIT must run before the first
mapping.  link99 -Y and the build script enforce this.

NO LIBRARY CODE CALLED ONLY FROM AN OVERLAY
-------------------------------------------
A library member that only overlays call is loaded after them and placed
above them, which link99 refuses.  Number output (include\PUTNUM.C) and the
-Y helpers (include\OVLYSUB.C) are compiled into each overlay instead.
