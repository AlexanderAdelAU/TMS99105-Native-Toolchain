/*
 * R99 build-size configuration.
 *
 * SBC native profile.
 *
 * R99.COM is loaded at >1000 by the paged SHELL and may occupy memory up
 * to (but not including) >E000.  The XREF accumulator is dynamic: pass 2
 * allocates one 4-byte node per actual external reference, so small
 * assemblies do not pay for unused XREF capacity.
 */

#define LINLEN          128	/*  Must be at least 102: the 4-symbols-per-line table
                                dump at the end of main writes 4 * 25 + 2 bytes into
                                linbuf.  At 96 it spilled 6 bytes into binbuf.  */
#define BUFSIZE          16
#define SYMBOLS         300	/*  Symbol-table slots.  slookup() now uses bounded
                                linear probing, so every slot is reachable.  */
#define INCLUDE_DEPTH     1
