/*
** OVLYSUB.C -- helpers #included by each -Y overlay (OVL_MAP, OVL_MAPM,
** OVL_GLUE).  Each overlay page needs its own copy: one overlay cannot
** call another here (this linker has no OVCALL), and nothing an overlay
** calls may come from a library, or the library member would be placed
** above the overlays.
*/

/*
** report a fault in the map and stop
*/
ovdie(a, b)
char *a, *b;
{
  int *h;
  h = OVHDR;
  fputs("*** Overlay map ", stdout);
  fputs(ovmapfn, stdout);
  if(h[H_LINE]) {
    fputs(" line ", stdout);
    putu(h[H_LINE]);
  }
  fputs(": ", stdout);
  error2(a, b);
}

/*
** case-blind compare, YES when equal
*/
oveq(a, b)
char *a, *b;
{
  while(toupper(*a) == toupper(*b)) {
    if(!*a) return YES;
    ++a;
    ++b;
  }
  return NO;
}

/*
** length of s (not strlen: see PUTNUM.C - nothing resident calls it)
*/
slen(s)
char *s;
{
  int n;
  n = 0;
  while(*s++) ++n;
  return n;
}
