/*
** MERSENNE.C -- is 2^p - 1 prime?  The Lucas-Lehmer test on the SBC.
**
**   MERSENNE p     test 2^p - 1; if it is prime, print all its digits
**   MERSENNE       test a list of small exponents
**
** Lucas-Lehmer: s = 4, then p - 2 times s = s*s - 2 mod 2^p - 1.
** 2^p - 1 (p an odd prime) is prime exactly when s ends at 0.
**
** The work is p - 2 squarings of a p-bit number, in MPLL.A99.  The
** numbers live in the free memory above the program, three p-bit
** buffers' worth (x, and the double-length square z).  Printing uses
** LCALL (itol, ltod).
**
**   link99 -O1000 MERSENNE.COM STARTUP.R99 MERSENNE.R99 MPLL.R99
**          CONOUT.R99 CALL.R99 LCALL.R99
*/

#define CMDBUF  160             /* >00A0: the command line         */
#define CMDSIZ  162             /* >00A2: its length               */
#define FREEMEM 166             /* >00A6: first free byte          */
#define MEMLIM  176             /* >00B0: end of free memory       */

/* The shell sets FREEMEM to the end of the program's last sector and,
** for a .COM, MEMLIM to >E000.  The free space is then more than 32767
** bytes, which a signed int sees as negative, so it is capped.  */

int *x, *z;
int maxw;                       /* words per number that fit       */
int t[2];
char s[12];

pnum(n) int n;
{
    itol(t, n);
    pstr(ltod(s, t));
}

isprime(p) int p;
{
    int d;
    if(p < 2) return 0;
    for(d = 2; d <= 181; ++d) {         /* 181 * 181 < 32768       */
        if(d * d > p) break;
        if(p % d == 0) return 0;
    }
    return 1;
}

/* is x 0 mod 2^p - 1: all zero, or all p bits one */
iszero(n, p) int n, p;
{
    int i, r, top;
    for(i = 0; i < n; ++i) if(x[i]) break;
    if(i == n) return 1;
    r = p % 16;
    if(r) top = (1 << r) - 1;
    else top = -1;
    for(i = 0; i < n - 1; ++i) if(x[i] != -1) return 0;
    return x[n - 1] == top;
}

nwords(p) int p;
{
    int n;
    n = p / 16;
    if(p % 16) ++n;
    return n;
}

/* the Lucas-Lehmer test; dots show progress when dots is set */
llt(p, dots) int p, dots;
{
    int n, i, k, every, left;
    if(p == 2) return 1;                /* 3: the one even case     */
    n = nwords(p);
    for(i = 0; i < n; ++i) x[i] = 0;
    x[0] = 4;
    k = p - 2;
    every = k / 50 + 1;
    left = every;
    while(k) {
        mpsqr(z, x, n);
        mpmod(x, z, n, p);
        mpsub2(x, n, p);
        --k;
        if(dots) if(--left == 0) { pstr("."); left = every; }
    }
    if(dots) pstr("\n");
    return iszero(n, p);
}

/* 2^p - 1 in decimal: divide by 10000 into groups of four digits,
** lowest first, kept in z, then print them highest first */
digits(p) int p;
{
    int n, i, r, g, nd, col;
    n = nwords(p);
    for(i = 0; i < n; ++i) x[i] = -1;
    r = p % 16;
    if(r) x[n - 1] = (1 << r) - 1;
    g = 0;
    while(n) {
        z[g++] = mpdiv1(x, n, 10000);
        while(n) { if(x[n - 1]) break; --n; }
    }
    itol(t, z[g - 1]);
    nd = (g - 1) * 4 + strlen(ltod(s, t));
    pnum(nd); pstr(" digits:\n");
    col = 0;
    while(g--) {
        i = z[g];
        if(col) {                       /* not the leading group   */
            if(i < 1000) pstr("0");
            if(i < 100) pstr("0");
            if(i < 10) pstr("0");
        }
        pnum(i);
        if(++col == 16) { pstr("\n"); col = 0; }
    }
    pstr("\n");
}

strlen(s) char *s;
{
    int n;
    n = 0;
    while(*s++) ++n;
    return n;
}

/* the number on the command line, or 0 */
getp()
{
    int *vp, cnt, p;
    char *c;
    vp = CMDBUF;
    c = *vp;
    vp = CMDSIZ;
    cnt = *vp;
    while(cnt) { if(*c != ' ') break; ++c; --cnt; }
    if(cnt) if(*c > '9') {              /* skip the program's name */
        while(cnt) { if(*c == ' ') break; ++c; --cnt; }
        while(cnt) { if(*c != ' ') break; ++c; --cnt; }
    }
    p = 0;
    while(cnt) {
        if(*c < '0') break;
        if(*c > '9') break;
        p = p * 10 + *c - '0';
        ++c; --cnt;
    }
    return p;
}

int list[] = { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 61, 89, 107,
               127, 521, 607, 1279, 0 };

main()
{
    int *vp, fm, lim, p, i, maxp;
    vp = FREEMEM;
    fm = (*vp + 1) & -2;                /* word aligned             */
    vp = MEMLIM;
    lim = *vp;                          /* >E000 for a .COM        */
    lim = lim - fm;                     /* bytes free: over 32767  */
    if(lim < 0) lim = 32766;            /* is negative to Small-C  */
    maxw = lim / 6;                     /* x, then z twice as long */
    x = fm;
    z = x + maxw;
    maxp = 32767;
    if(maxw < 2048) maxp = maxw * 16;
    p = getp();
    if(p == 0) {
        pstr("Lucas-Lehmer test of 2^p-1\n");
        for(i = 0; list[i]; ++i) {
            p = list[i];
            if(p > maxp) break;
            pstr("2^"); pnum(p); pstr("-1 ");
            if(llt(p, 0)) pstr("is prime\n");
            else pstr("is composite\n");
        }
        return;
    }
    if(p < 2 || p > maxp) {
        pstr("p must be 2 to "); pnum(maxp); pstr("\n");
        return;
    }
    if(isprime(p) == 0) {
        pstr("2^"); pnum(p); pstr("-1 is composite: "); pnum(p);
        pstr(" is not prime\n");
        return;
    }
    pstr("Testing 2^"); pnum(p); pstr("-1, "); pnum(p - 2);
    pstr(" squarings of "); pnum(nwords(p)); pstr(" words\n");
    if(llt(p, 1)) {
        pstr("2^"); pnum(p); pstr("-1 is prime, ");
        digits(p);
    } else {
        pstr("2^"); pnum(p); pstr("-1 is composite\n");
    }
}
