/*@ showkey.c v5: show keyboard scancodes for FreeBSD, OpenBSD, NetBSD.
 *@ Compile     : $ gcc -W -Wall -pedantic -ansi -o showkey showkey.c
 *@ Run         : $ ./showkey [ktv]  (keycode, termios seq., termios vals)
 *@ Exit status : 0=timeout, 1=signal/read error, 3=use/setup failure
 *
 * Copyright (c) 2012 Steffen Daode Nurpmeso <sdaoden@users.sourceforge.net>.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* How many seconds of inactivity before program terminates? */
#define ALARM_DELAY     5

/**  >8  **  8<  **/

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include <err.h>
#include <termios.h>
#include <unistd.h>

#include <sys/ioctl.h>
#include <sys/time.h>

#ifdef __FreeBSD__
# define USE_SYSCONS
# include <sys/kbio.h>
#elif defined __OpenBSD__ || defined __NetBSD__ /* TODO NetBSD not tested! */
# define USE_WSCONS
# include <dev/wscons/wsconsio.h>
# include <dev/wscons/wsksymdef.h>
#else
# error Operating system not supported
#endif

static int              tios_only, caught_sig;
static struct termios   tios_orig, tios_raw;

/* Signal handler, exit 0 if SIGALRM, 1 otherwise */
static void     onsig(int sig);

/* Modes which handle input */
static ssize_t  mode_term(unsigned char *buf, ssize_t len),
                mode_value(unsigned char *buf, ssize_t len),
                mode_keycode(unsigned char *buf, ssize_t len);

/* Terminal handling */
static void     raw_init(void), raw_on(void), raw_off(void);

int
main(int argc, char **argv)
{
    ssize_t (*mode)(unsigned char*, ssize_t) = &mode_keycode;
    ssize_t i, skip;
    auto struct sigaction sa;
    auto struct itimerval it;
    auto unsigned char buf[64];

    if (argc > 1)
        switch (**++argv) {
        case 'k':
            mode = &mode_keycode;
            break;
        case 't':
            mode = &mode_term;
            tios_only = 1;
            break;
        case 'v':
            mode = &mode_value;
            tios_only = 1;
            break;
        default:
            mode = NULL;
            break;
        }
    if (mode == NULL)
        errx(3, "Usage: showkey [ktv]  (keycode, termios, value)");

    if (! isatty(STDIN_FILENO))
        err(3, "STDIN is not a terminal");
    raw_init();

    sa.sa_handler = &onsig;
    sa.sa_flags = 0;
    (void)sigfillset(&sa.sa_mask);
    for (i = 0; i++ < NSIG;)
        if (sigaction((int)i, &sa, NULL) < 0 && i == SIGALRM)
            err(3, "Can't install SIGALRM signal handler");

    it.it_value.tv_sec = ALARM_DELAY;
    it.it_value.tv_usec = 0;
    it.it_interval.tv_sec = it.it_interval.tv_usec = 0;

    raw_on();
    printf("You may now use the keyboard;\r\n"
        "After %d seconds of inactivity the program terminates\r\n",
        ALARM_DELAY);

    for (i = skip = 0;;) {
        if (setitimer(ITIMER_REAL, &it, NULL) < 0) {
            raw_off();
            err(3, "Can't install wakeup timer");
        }

        i = read(STDIN_FILENO, buf + skip, sizeof(buf) - skip);
        if (i <= 0)
            break;
        i += skip;

        skip = (*mode)(buf, i);
    }

    raw_off();

    return (caught_sig < 2);
}

static void
onsig(int sig)
{
    caught_sig = 1 + (sig == SIGALRM);
    return;
}

static ssize_t
mode_term(unsigned char *buf, ssize_t len)
{
    if (*buf == 0x1B)
        while (--len >= 0) {
            printf("0x%02X ", (unsigned int)*buf++);
            if (len > 0 && *buf == 0x1B) /* XXX May be incomplete seq.?? */
                printf("\r\n");
        }
    else
        while (--len >= 0)
            printf("0x%02X ", (unsigned int)*buf++);
    printf("\r\n");

    return (0);
}

static ssize_t
mode_value(unsigned char *buf, ssize_t len)
{
    while (--len >= 0) {
        unsigned int v = (unsigned int)*buf++;
        printf("%4d 0%03o 0x%02X  ", v, v, v);
    }
    printf("\r\n");

    return (0);
}

#if defined USE_SYSCONS || defined USE_WSCONS
static ssize_t
mode_keycode(unsigned char *buf, ssize_t len)
{
    unsigned char *cursor = buf;

    while (--len >= 0) {
        unsigned int isplain = 1, kc = *cursor++, rc = kc, isdown;

        if ((rc & 0xF0) == 0xE0 || (rc & 0xF8) == 0xF0) {
            isplain = 0;
            if (--len < 0) {
                *buf = (unsigned char)rc;
                len = 1;
                break;
            }

            kc <<= 8;
            kc |= *cursor++;
            rc = kc;
            kc &= ((kc & 0xF000) == 0xE000) ? 0x0FFF : 0x00FF;
        }

        isdown = (0 == (kc & 0x80));
        kc &= ~0x0080;
        if (! isplain)
            kc |= 0x80;

        printf("keycode %3u %-7s (0x%04X: 0x%04X | %c)\r\n",
            kc, (isdown ? "press" : "release"),
            rc, (kc & ~0x80), (isdown ? 'v' : '^'));
    }

    return ((len <= 0) ? 0 : len);
}
#endif /* defined USE_SYSCONS || defined USE_WSCONS */

#ifdef USE_SYSCONS
static void
raw_init(void)
{
    if (tcgetattr(STDIN_FILENO, &tios_orig) < 0)
        err(3, "Can't query terminal attributes");
    tios_raw = tios_orig;
    (void)cfmakeraw(&tios_raw);
    return;
}

static void
raw_on(void)
{
    if (tcsetattr(STDIN_FILENO, TCSANOW, &tios_raw) < 0)
        err(3, "Can't set terminal attributes");

    if (! tios_only && ioctl(STDIN_FILENO, KDSKBMODE, (int)K_RAW) < 0) {
        int sverr = errno;
        (void)tcsetattr(STDIN_FILENO, TCSANOW, &tios_orig);
        errx(3, ((sverr == ENOTTY)
            ? "This program mode won't work on pseudo terminals"
            : "Can't put keyboard in raw mode (shouldn't happen ;()"));
    }
    return;
}

static void
raw_off(void)
{
    if (! tios_only)
        (void)ioctl(STDIN_FILENO,  KDSKBMODE, (int)K_XLATE);
    (void)tcsetattr(STDIN_FILENO, TCSANOW, &tios_orig);
    return;
}
#endif /* USE_SYSCONS */

#ifdef USE_WSCONS
static void
raw_init(void)
{
    if (tcgetattr(STDIN_FILENO, &tios_orig) < 0)
        err(3, "Can't query terminal attributes");
    tios_raw = tios_orig;
    (void)cfmakeraw(&tios_raw);
    return;
}

static void
raw_on(void)
{
    auto int arg = WSKBD_RAW;

    if (tcsetattr(STDIN_FILENO, TCSANOW, &tios_raw) < 0)
        err(3, "Can't set terminal attributes");

    if (! tios_only && ioctl(STDIN_FILENO, WSKBDIO_SETMODE, &arg) < 0) {
        arg = errno;
        (void)tcsetattr(STDIN_FILENO, TCSANOW, &tios_orig);
        errx(3, ((arg == ENOTTY)
            ? "This program mode won't work on pseudo terminals"
            : ("Can't put keyboard in raw mode "
               "(WSDISPLAY_COMPAT_RAWKBD kernel option present?)")));
    }
    return;
}

static void
raw_off(void)
{
    auto int arg = WSKBD_TRANSLATED;

    if (! tios_only)
        (void)ioctl(STDIN_FILENO, WSKBDIO_SETMODE, &arg);
    (void)tcsetattr(STDIN_FILENO, TCSANOW, &tios_orig);
    return;
}
#endif /* USE_WSCONS */

/* vim:set fenc=utf-8 filetype=c syntax=c ts=4 sts=4 sw=4 et tw=79: */
