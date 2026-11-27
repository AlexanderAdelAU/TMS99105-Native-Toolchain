# gen_ltest.py -- writes LTEST.C, the LCALL test.
# Every expected value is computed here, in Python, independently of LCALL.
# The C program is table-driven: the vectors and answers are data, and a few
# loops check every function against them.
import random
random.seed(9900)
M = 1 << 32
def s32(x): x %= M; return x - M if x >= 1 << 31 else x
def u32(x): return x % M
def w(x):
    x &= 0xFFFF; return x - 0x10000 if x >= 0x8000 else x
def hl(x): x = u32(x); return [w(x >> 16), w(x & 0xFFFF)]

edge = [0, 1, -1, 2, -2, 0x7FFFFFFF, -0x80000000, 0xFFFF, 0x10000, 0x7FFF, 0x8000, -0x8000,
        65535 * 65535, 1000000007, -123456789, 0x12345678, 0xFEDCBA98, 10, -10, 0x0001FFFF]
vals = [s32(v) for v in edge] + [s32(random.getrandbits(32)) for _ in range(8)] \
     + [s32(random.getrandbits(20)) for _ in range(4)]
pairs = [(vals[i], vals[(i * 7 + 3) % len(vals)]) for i in range(len(vals))]
pairs += [(random.getrandbits(32), random.getrandbits(17)) for _ in range(6)]
pairs += [(random.getrandbits(32), random.getrandbits(32) >> random.randint(0, 15)) for _ in range(6)]
pairs += [(-0x80000000, 0x7FFFFFFF), (0x7FFFFFFF, -0x80000000), (5, 0), (-7, 2), (7, -2),
          (-7, -2), (100000, 100000), (0xFFFFFFFF, 1), (0xFFFFFFFF, 0xFFFFFFFF), (0xFFFFFFFF, 0x10000)]
pairs = [(s32(a), s32(b)) for a, b in pairs]

def cdiv(a, b):
    if b == 0: return 0, 0
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0): q = -q
    return q, a - b * q
def udiv(a, b):
    a, b = u32(a), u32(b)
    return (0, 0) if b == 0 else (a // b, a % b)

SH = [0, 1, 4, 15, 16, 17, 31, 33]

ptab = []
for a, b in pairs:
    ok = not (a == -0x80000000 and b == -1)
    q, m = cdiv(a, b) if ok else (0, 0)
    uq, um = udiv(a, b)
    row = hl(a) + hl(b) + hl(a + b) + hl(a - b) + hl(a * b) + hl(q) + hl(m) + hl(uq) + hl(um)
    row += [(a > b) - (a < b), (u32(a) > u32(b)) - (u32(a) < u32(b))]
    ptab.append(row)
vtab, text = [], []
for a in vals:
    row = hl(a) + hl(-a) + [hl(a)[1]]
    for n in SH:
        row += hl(a << (n % 32)) + hl(u32(a) >> (n % 32)) + hl(a >> (n % 32))
    vtab.append(row)
    text += [str(a), str(u32(a)), "%08X" % u32(a)]
m16 = [(65535, 65535), (40000, 50000), (1, 65535), (0, 1234), (256, 256), (32768, 2)]
itab = [0, 1, -1, 32767, -32768, 1234, -1234]

def ints(name, rows):
    flat = [v for r in rows for v in r]
    lines = []
    for k in range(0, len(flat), 12):
        lines.append("    " + ", ".join(str(v) for v in flat[k:k + 12]))
    return "int %s[] = {\n%s\n};" % (name, ",\n".join(lines))
def chars(name, strs):
    flat = [c for s in strs for c in [ord(ch) for ch in s] + [0]]
    lines = []
    for k in range(0, len(flat), 16):
        lines.append("    " + ", ".join(str(v) for v in flat[k:k + 16]))
    return "char %s[] = {\n%s\n};" % (name, ",\n".join(lines))

PW, VW = len(ptab[0]), len(vtab[0])
src = f"""/*
** LTEST.C -- the LCALL test: every function against answers computed
** independently by gen_ltest.py, which writes this file.
**
**   link99 -O1000 LTEST.COM STARTUP.R99 LTEST.R99 CONOUT.R99 CALL.R99 LCALL.R99
*/

#define NP {len(ptab)}
#define PW {PW}
#define NV {len(vtab)}
#define VW {VW}
#define NM {len(m16)}
#define NI {len(itab)}

/* pairs: a, b, a+b, a-b, a*b, a/b, a%b, a/b and a%b unsigned (2 words
** each), then lcmp and lucmp */
{ints("ptab", ptab)}

/* values: a, -a, ltoi(a), then for each shift count a<<n, a>>n logical,
** a>>n arithmetic */
{ints("vtab", vtab)}
int shn[] = {{{", ".join(str(n) for n in SH)}}};

/* for each value: ltod, ltou, ltox */
{chars("ttab", text)}

int mtab[] = {{
{",".join("    %d, %d, %d, %d" % (w(a), w(b), *hl(a * b)) for a, b in m16).replace(",    ", ",\n    ")}
}};
int itab[] = {{{", ".join(str(v) for v in itab)}}};

int pass, fail;
int r[2], e[2];
char s[16];

/* check r against the two words at q */
ck(name, n, q) char *name; int n, *q;
{{
    char t[12];
    int k[2];
    if(lcmp(r, q) == 0) {{ ++pass; return; }}
    ++fail;
    pstr("FAIL "); pstr(name); pstr(" #"); itol(k, n); pstr(ltod(t, k));
    pstr(" got "); pstr(ltox(t, r)); pstr(" want "); pstr(ltox(t, q)); pstr("\\n");
}}

/* check the string s against the one at q; return the next one */
cks(name, n, q) char *name, *q; int n;
{{
    char *p, *w;
    char t[12];
    int k[2];
    p = s; w = q;
    while(*w) ++w;
    while(*p == *q) {{
        if(*p == 0) {{ ++pass; return w + 1; }}
        ++p; ++q;
    }}
    ++fail;
    pstr("FAIL "); pstr(name); pstr(" #"); itol(k, n); pstr(ltod(t, k));
    pstr(" got "); pstr(s); pstr("\\n");
    return w + 1;
}}

/* check two ints */
ckw(name, n, got, want) char *name; int n, got, want;
{{
    char t[12];
    int k[2];
    if(got == want) {{ ++pass; return; }}
    ++fail;
    pstr("FAIL "); pstr(name); pstr(" #"); itol(k, n); pstr(ltod(t, k)); pstr("\\n");
}}

pairs()
{{
    int i, *a, *b, *x;
    for(i = 0; i < NP; ++i) {{
        a = ptab + i * PW;
        b = a + 2;
        x = a + 4;
        ladd(r, a, b);  ck("ladd", i, x);
        lsub(r, a, b);  ck("lsub", i, x + 2);
        lmul(r, a, b);  ck("lmul", i, x + 4);
        ldiv(r, a, b);  ck("ldiv", i, x + 6);
        lmod(r, a, b);  ck("lmod", i, x + 8);
        ludiv(r, a, b); ck("ludiv", i, x + 10);
        lumod(r, a, b); ck("lumod", i, x + 12);
        ckw("lcmp", i, lcmp(a, b), x[14]);
        ckw("lucmp", i, lucmp(a, b), x[15]);
    }}
}}

values()
{{
    int i, j, *a, *x;
    char *t, *p;
    t = ttab;
    for(i = 0; i < NV; ++i) {{
        a = vtab + i * VW;
        lneg(r, a);  ck("lneg", i, a + 2);
        ckw("ltoi", i, ltoi(a), a[4]);
        x = a + 5;
        for(j = 0; j < 8; ++j) {{
            lshl(r, a, shn[j]); ck("lshl", i * 10 + j, x);
            lshr(r, a, shn[j]); ck("lshr", i * 10 + j, x + 2);
            lsar(r, a, shn[j]); ck("lsar", i * 10 + j, x + 4);
            x = x + 6;
        }}
        p = dtol(r, t); ck("dtol", i, a); ckw("dtol end", i, *p, 0);
        ltod(s, a); t = cks("ltod", i, t);
        ltou(s, a); t = cks("ltou", i, t);
        ltox(s, a); t = cks("ltox", i, t);
    }}
}}

others()
{{
    int i, *m;
    char *p;
    for(i = 0; i < NM; ++i) {{
        m = mtab + i * 4;
        lmul16(r, m[0], m[1]); ck("lmul16", i, m + 2);
    }}
    for(i = 0; i < NI; ++i) {{
        itol(r, itab[i]); lset(e, itab[i] < 0 ? -1 : 0, itab[i]); ck("itol", i, e);
        utol(r, itab[i]); lset(e, 0, itab[i]); ck("utol", i, e);
    }}
    lset(e, 4660, 22136);                       /* 0x12345678 */
    lset(r, 4077, -13398);                      /* 0x0FEDCBAA */
    ladd(e, e, r); lset(r, 8738, 8738);         /* = 0x22222222 */
    ck("alias", 0, e);
    lsub(r, r, r); lset(e, 0, 0); ck("alias", 1, e);
    p = dtol(r, "+42x"); lset(e, 0, 42); ck("dtol+", 0, e); ckw("dtol+ end", 0, *p, 'x');
    p = dtol(r, "abc"); lset(e, 0, 0); ck("dtol0", 0, e); ckw("dtol0 end", 0, *p, 'a');
}}

main()
{{
    int k[2];
    pass = 0; fail = 0;
    pstr("LTEST: LCALL 32-bit arithmetic\\n");
    pairs();
    values();
    others();
    pstr("LTEST: "); itol(k, pass); pstr(ltod(s, k)); pstr(" passed, ");
    itol(k, fail); pstr(ltod(s, k)); pstr(" failed\\n");
}}
"""
open("LTEST.C", "w").write(src)
print(len(ptab), "pairs,", len(vtab), "values")
