/*
** OVLY.H -- the -Y overlay map tables, shared by OVL_MAP.C, OVL_MAPM.C
** and OVL_GLUE.C (three overlay pages: Small-C needs that much room).
**
** They live at a fixed place in the symbol window (>9000-BFFF), just
** above LINK99.C's -P rows and EXT+offset table at >9000, so neither
** overlay page nor resident RAM pays for them.  getmem() raises the
** symbol table's floor past them when -Y is given (OVTABSZ).
**
** Struct-of-arrays, indexed by module, overlay or entry number:
**   modules   T_MNAME  name (base name, as in the map)    T_MPAGE  page
**             T_MOVL   overlay ID (1-based)               T_MROW   -P row + 1, 0 = not loaded
**   overlays  T_ONAME  name                               T_OGUEST 1 = guest
**   guests    T_GNAME  the names on "guest" lines (resolved at the end)
**   entries   T_ENAME  public name    T_EREAL  routine (= T_ENAME unless alias)
**             T_EMOD   module         T_EFLG   EFTAIL | EFALIAS | EFSEEN
**             T_EORD   entries in thunk order (by ID, then map order)
**   header    int counters, see H_*
**   T_LB      the map line being read, split in place
**   T_TOK     pointers to its fields
*/
#define OVT      0x9180         /* = SYMWIN + 8*MAXPM + 4*XAMAX (LINK99.C getmem) */
#define OVMOD    36             /* modules in the map                  */
#define OVOVL    24             /* overlays (IDs 1..OVOVL)             */
#define OVENT    40             /* published entries                   */
#define OVNM     16             /* name slot: 15 characters + NUL      */
#define OVPAIRS   5             /* (segment,page) pairs per table row  */
#define OVWINLO   8             /* the window starts at segment 8      */
#define OVWINHI  11             /* default end: >BFFF                  */
#define OVWINMAX 13             /* "window 8-13" at most               */

#define H_NOVM    0             /* header words                        */
#define H_NOVO    1
#define H_NOVE    2
#define H_NOVG    3
#define H_WINHI   4
#define H_WINSET  5
#define H_TBL     6             /* image offset of OVL_TABLE           */
#define H_NTOK    7             /* fields on the current map line      */
#define H_LINE    8             /* its line number                     */
#define H_FD      9             /* the map file's unit while reading   */
                                /* (16 header words: H_* < 16)         */

/* Literal addresses: Small-C's line buffer is too short for the nested
   sums.  Each starts where the one before ends; recompute all of them
   if a size above changes.                                          */
#define OVHDR     0x9180     /* + 16 header words =   32 bytes */
#define T_MNAME   0x91A0     /* + OVMOD * OVNM    =  576 bytes */
#define T_MPAGE   0x93E0     /* + OVMOD           =   36 bytes */
#define T_MOVL    0x9404     /* + OVMOD           =   36 bytes */
#define T_MROW    0x9428     /* + OVMOD           =   36 bytes */
#define T_ONAME   0x944C     /* + OVOVL * OVNM    =  384 bytes */
#define T_OGUEST  0x95CC     /* + OVOVL           =   24 bytes */
#define T_GNAME   0x95E4     /* + OVOVL * OVNM    =  384 bytes */
#define T_ENAME   0x9764     /* + OVENT * OVNM    =  640 bytes */
#define T_EREAL   0x99E4     /* + OVENT * OVNM    =  640 bytes */
#define T_EMOD    0x9C64     /* + OVENT           =   40 bytes */
#define T_EFLG    0x9C8C     /* + OVENT           =   40 bytes */
#define T_EORD    0x9CB4     /* + OVENT           =   40 bytes */
#define T_LB      0x9CDC     /* + one map line    =  132 bytes */
#define T_TOK     0x9D60     /* + OVMAXTOK words  =   32 bytes */
#define OVTEND    0x9D80
#define OVTABSZ   3072        /* OVTEND - OVT */
#define OVMAXTOK  16          /* fields on a map line */
#define OVLBMAX   131

#define EFTAIL    1
#define EFALIAS   2
#define EFSEEN    4
