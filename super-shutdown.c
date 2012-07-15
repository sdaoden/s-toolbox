/*@ super-shutdown.c: single setuid root BSD program to shutdown/reboot.
 *@ Works on FreeBSD/NetBSD/OpenBSD.  You've been warned!
 *@ Compile: $ gcc -W -Wall -pedantic -o super-shutdown super-shutdown.c
 *@ Prepare: $ chown root:wheel super-shutdown; chmod 4550 super-shutdown
 *@ Run    : $ super-shutdown reboot
 *@ Run    : $ super-shutdown shutdown
 *
 * 2003-01-20.  2012-07-15 (NetBSD, OpenBSD).
 * Public Domain.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>

extern char **environ;

enum ExStats {
    BAD_RUN     = 10,
    PRIV_ERR,
    EXEC_ERR
};

int
main(int argc, char **argv)
{
    const char *pav[5] = { "shutdown", NULL, "now", NULL, NULL };
    uid_t euid;
    enum ExStats ret = BAD_RUN;

    if (argc != 2)
        goto jhelp;

    ++argv;
    if (! strcmp(*argv, "reboot"))
        pav[1] = "-r";
    else if (! strcmp(*argv, "shutdown")) {
        pav[1] = "-p";
#if defined __NetBSD__ || defined __OpenBSD__
        pav[3] = pav[2];
        pav[2] = "-h";
#endif
    } else
        goto jhelp;

    ret = PRIV_ERR;
    euid = geteuid();
    if (euid != 0 || setuid(euid) != 0)
        goto jhelp;

    ret = EXEC_ERR;
    execve("/sbin/shutdown", (char*const*)pav, (char*const*)environ);

jhelp:
    fprintf(stderr,
        "Unsupported invocation or not setuid root; or execve(2) failed.\r\n"
        "USAGE: super (reboot|shutdown)\r\n");

    return (ret);
}

/* vim:set fenc=utf-8 filetype=c syntax=c ts=4 sts=4 sw=4 et tw=79: */
