/*
** FILESTAT.C -- FileEdit resident program driver.
**
** Public command line:
**   FILEEDIT filename /S   display file statistics
**   FILEEDIT filename /E   edit file
**
** Any other command line displays usage.
*/

extern puts();
extern ovlinit();
extern fsset();
extern fsreset();
extern fsopen();
extern fsclose();
extern fsrewind();
extern fslist();
extern wordscan();
extern charscan();
extern report();
extern ovprobea();
extern viewctl();
extern editmenu();
extern ebload();
extern ebhome();
extern rxinit();
extern rxfini();
extern rxtest();
extern putnum();
extern int rxticks;

extern char *fsname;
extern int dolst;

/* Dedicated nested-overlay gate test; no file or editor bank needed. */
isovtest(p)
char *p;
{
    if(p[0] != '/' && p[0] != '-') return 0;
    if(p[1] != 'O' && p[1] != 'o') return 0;
    return p[2] == 0;
}

isstat(p)
char *p;
{
    if(p[0] != '/' && p[0] != '-')
        return 0;
    if(p[1] != 'S' && p[1] != 's')
        return 0;
    if(p[2] != 0)
        return 0;
    return 1;
}

isedit(p)
char *p;
{
    if(p[0] != '/' && p[0] != '-')
        return 0;
    if(p[1] != 'E' && p[1] != 'e')
        return 0;
    if(p[2] != 0)
        return 0;
    return 1;
}

usage()
{
    puts("FILEEDIT - overlay text editor with FILESTAT analysis\n");
    puts("Usage:\n");
    puts("  FILEEDIT filename /S    Display file statistics\n");
    puts("  FILEEDIT filename /E    Edit file\n");
    puts("  FILEEDIT /O             Test nested overlay calls\n");
}

main(argc, argv)
int argc;
char **argv;
{
    int dostat;
    int doedit;

    ovlinit();
    fsset("");

    if(argc == 2 && isovtest(argv[1])) {
        if(ovprobea() == 110)
            puts("OVL99 NESTED PASS\n");
        else
            puts("OVL99 NESTED FAIL\n");
        return;
    }

    if(argc != 3) {
        usage();
        return;
    }

    dostat = isstat(argv[2]);
    doedit = isedit(argv[2]);

    if(dostat == 0 && doedit == 0) {
        usage();
        return;
    }

    fsset(argv[1]);
    dolst = 0;

    if(doedit) {
        rxinit();
        editmenu();
        ebhome();
        rxfini();
        return;
    }

    fsreset();

    if(fsopen() == 0)
        return;

    wordscan();

    if(fsrewind() == 0)
        return;

    charscan();
    fsclose();
    report();
}
