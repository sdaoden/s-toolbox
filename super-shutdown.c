/*@ super-shutdown.c: single setuid root program to shutdown/reboot.
 *@ Compile: $ gcc -W -Wall -pedantic -o super-shutdown super-shutdown.c
 *@ Run    : $ super-shutdown reboot
 *@ Run    : $ super-shutdown shutdown
 *
 * 2003-01-20.
 * Public Domain.
 * (You've been warned!)
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
    const char *pav[4] = { "shutdown", NULL, "now", NULL };
    uid_t euid;
    enum ExStats ret = BAD_RUN;

    if (argc != 2)
        goto jhelp;

    ++argv;
    if (! strcmp(*argv, "reboot"))
        pav[1] = "-r";
    else if (! strcmp(*argv, "shutdown"))
        pav[1] = "-p";
    else
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
