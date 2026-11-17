; LINK99 overlay IDs, used by OVLAPI.A99 to map the banks.
;
; These must equal the IDs the host link99 -Y assigns from OVLMAP.TXT (first
; appearance in the map).  The build checks every one against link99's table
; and fails on a mismatch.
;
; OWNERSHIP RULE:
;   Callable/executable overlays MUST map virtual segment 8. OVLMGR uses
;   segment 8 to establish CUR_WINA_ID, the logical owner of the overlay
;   window. Data-only banks/workspaces may be explicit exceptions, but they
;   must never be entered as code. OVLMGR_INIT must run before first use and
;   explicitly resets CUR_WINA_ID to zero. The build enforces these rules.

OVL_USAGE   EQU 1
OVL_CODE0  EQU 2
OVL_CODE1  EQU 3
OVL_CODE2  EQU 4
OVL_CODE3  EQU 5
OVL_CODE4  EQU 6
OVL_CODE5  EQU 7
OVL_CODE6  EQU 8
OVL_CODE7  EQU 9
OVL_CODE8  EQU 10
OVL_CODE9  EQU 11
OVL_SYM    EQU 12
OVL_FINAL  EQU 13
OVL_EXE    EQU 14
OVL_CODE10 EQU 15
OVL_CODE11 EQU 16
OVL_CODE12 EQU 17
OVL_CODE13 EQU 18
OVL_CODE14 EQU 19
OVL_MAP    EQU 20
OVL_GLUE   EQU 21
OVL_MAPM   EQU 22
OVL_CHK    EQU 23
OVL_TAB    EQU 24
