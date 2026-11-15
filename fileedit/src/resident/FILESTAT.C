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
}

main(argc, argv)
int argc;
char **argv;
{
    int dostat;
    int doedit;

    ovlinit();
    fsset("");

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
