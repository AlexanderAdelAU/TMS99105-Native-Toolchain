/*
** PUTNUM.C -- number output, #included by every LINK99 overlay that
** prints one.  Not itox/itou: a library member that only overlays call
** is loaded after them and placed above them, which the link refuses -
** and resident RAM is too short to keep it there.
*/

/*
** n as w hex digits
*/
putx(n, w)
int n, w;
{
  int c;
  while(w--) {
    c = (n >> (w << 2)) & 15;
    if(c < 10) putchar('0' + c);
    else putchar('A' - 10 + c);
  }
}

/*
** n as an unsigned decimal, no padding
*/
putu(n)
int n;
{
  int p, d, any;
  unsigned u, q;
  u = n;
  any = NO;
  p = 10000;
  while(p) {
    q = p;
    d = 0;
    while(u >= q) {
      u = u - q;
      ++d;
    }
    if(d) any = YES;
    if(any || p == 1) putchar('0' + d);
    if(p == 10000) p = 1000;
    else if(p == 1000) p = 100;
    else if(p == 100) p = 10;
    else if(p == 10) p = 1;
    else p = 0;
  }
}
