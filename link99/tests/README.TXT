SBC LINK99 TESTS
================

Every test is linked twice from the same arguments: by the Windows link99
(the oracle) and by SBC LINK99 (on the board, or in simulation).  The two
outputs must be the same bytes.

  paged\      T2.A99, a minimal -P overlay (AORG >8000, odd length, a
              reference into the resident image).  LINK99 @T2.LNK with a
              CTEST of your own; CTEST.EXE must run as CTEST.COM did.
  ovly\       the OVL99 hello demo with -Y: make_test_ovly.ps1 builds the
              objects and HELLOREF.EXE and copies everything to MONITOR.
              On the SBC: LINK99 @HELLO.LNK, then HELLO.
  fileedit\   FileEdit with -Y, its resident code from FILEEDIT.LIB:
              make_test_fileedit.ps1 builds it, links the reference and
              packs the 17 files into MONITOR\FE.PAK.  On the SBC:
              XMODEM FE.PAK, UNPACK FE, LINK99 @FILEEDIT.LNK, then
              FILEEDIT SAMPLE.TXT /S.

All three have passed on the board (17 November 2026).  SAMPLE.TXT and
EXPECTED.TXT here are from the Step 0 bootstrap.
