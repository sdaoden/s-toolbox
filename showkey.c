/*@ showkey.c v8: show keyboard scancodes for FreeBSD, OpenBSD, (NetBSD), Linux.
 *@ - Linux should be completely correct since v8.
 *@ - OpenBSD should work fine except for some; you can always compare against
 *@   '$ wsconsctl keyboard.map' for problems with NumLock key combinations+.
 *@   TODO I need to take a very deep look to fix the rest of OpenBSD.
 *@ - TODO FreeBSD: K_CODE mode isn't supported at all, FIXME keycodes wrong!?!
 *@ - TODO I've no access to NetBSD, but assume the same approach as OpenBSD.
 *@ Compile     : $ gcc -W -Wall -pedantic -o showkey showkey.c
 *@ Run         : $ ./showkey [ksv]  (keycodes, scancodes, values)
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
#define ALARM_DELAY     9

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
#elif defined __linux__
# define USE_LINUX
# include <linux/kd.h>
#else
# error Operating system not supported
#endif

enum operation {
    op_SCANCODE,
#ifdef USE_LINUX
    op_KEYCODE,
#else
    op_KEYCODE  = op_SCANCODE,
#endif
    op_VALUE
};

static enum operation   op_mode;
static int              caught_sig;
static struct termios   tios_orig, tios_raw;

/* Signal handler, exit 0 if SIGALRM, 1 otherwise */
static void     onsig(int sig);

/* Terminal handling */
static void     raw_init(void), raw_on(void), raw_off(void);

/* Actual modes */
static ssize_t  mode_value(unsigned char *buf, ssize_t len),
#ifdef USE_LINUX
                mode_keycode(unsigned char *buf, ssize_t len),
#else
# define        mode_keycode mode_scancode
#endif
                mode_scancode(unsigned char *buf, ssize_t len);

int
main(int argc, char **argv)
{
    auto struct sigaction sa;
    auto struct itimerval it;
    auto unsigned char buf[64];
    ssize_t (*mode)(unsigned char*, ssize_t);
    ssize_t i, skip;

    if (argc > 1)
        switch (**++argv) {
        case 'k':
            op_mode = op_KEYCODE;
            mode = &mode_keycode;
            break;
        case 's':
            op_mode = op_SCANCODE;
            mode = &mode_scancode;
            break;
        case 'v':
            op_mode = op_VALUE;
            mode = &mode_value;
            break;
        default:
            mode = NULL;
            break;
        }
    if (mode == NULL)
        errx(3, "Usage: showkey [ksv]  (keycode, scancode, value)");

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

static void
raw_init(void)
{
    if (tcgetattr(STDIN_FILENO, &tios_orig) < 0)
        err(3, "Can't query terminal attributes");

    tios_raw = tios_orig;
    if (op_mode != op_VALUE)
        (void)cfmakeraw(&tios_raw);
    else {
        tios_raw.c_lflag &= ~(ICANON | ISIG);
        tios_raw.c_lflag |= ECHO | ECHOCTL;
        tios_raw.c_iflag = 0;
        tios_raw.c_cc[VMIN] = 1;
        tios_raw.c_cc[VTIME] = 0;
    }

    return;
}

#if defined USE_SYSCONS || defined USE_LINUX
static int  kbmode_raw, kbmode_orig;

static void
raw_on(void)
{
# ifdef USE_LINUX
    kbmode_raw = (op_mode == op_KEYCODE) ? K_MEDIUMRAW : K_RAW;
# else
    kbmode_raw = K_RAW; /* TODO K_CODE support on FreeBSD */
    if (op_mode == op_KEYCODE) /* FIXME FreeBSD */
        fprintf(stderr, "WARNING: FreeBSD keycodes are most likely wrong\r\n"
            "WARNING: the scancodes (in parenthesis) are fine\r\n");
# endif

    if (op_mode != op_VALUE &&
            ioctl(STDIN_FILENO, KDGKBMODE, (long)&kbmode_orig) < 0)
        err(3, "Can't query keyboard mode (on a pty?)");

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &tios_raw) < 0)
        err(3, "Can't set terminal attributes");

    if (op_mode != op_VALUE &&
            ioctl(STDIN_FILENO, KDSKBMODE, (long)kbmode_raw) < 0) {
        int sverr = errno;
        (void)tcsetattr(STDIN_FILENO, TCSAFLUSH, &tios_orig);
        /* Used to test for ENOTTY, but Linux seems not to use it.
         * So re-set errno and simplify error message */
        errno = sverr;
        err(3, "Can't set keyboard mode (on a pty?)");
    }

    return;
}

static void
raw_off(void)
{
    if (op_mode != op_VALUE)
        (void)ioctl(STDIN_FILENO,  KDSKBMODE, (long)kbmode_orig);

    (void)tcsetattr(STDIN_FILENO, TCSAFLUSH, &tios_orig);
    return;
}

#endif /* USE_SYSCONS || USE_LINUX */
#ifdef USE_WSCONS

static void
raw_on(void)
{
    auto int arg = WSKBD_RAW;

    if (tcsetattr(STDIN_FILENO, TCSANOW, &tios_raw) < 0)
        err(3, "Can't set terminal attributes");

    if (op_mode != op_VALUE && ioctl(STDIN_FILENO, WSKBDIO_SETMODE, &arg) < 0) {
        arg = errno;
        (void)tcsetattr(STDIN_FILENO, TCSANOW, &tios_orig);
        /* Mode won't work on pseudo terminals and needs
         * WSDISPLAY_COMPAT_RAWKBD kernel option */
        errno = arg;
        err(3, "Can't set keyboard mode (on a pty?)");
    }

    return;
}

static void
raw_off(void)
{
    auto int arg = WSKBD_TRANSLATED;

    if (op_mode != op_VALUE)
        (void)ioctl(STDIN_FILENO, WSKBDIO_SETMODE, &arg);

    (void)tcsetattr(STDIN_FILENO, TCSANOW, &tios_orig);
    return;
}

#endif /* USE_WSCONS */

static ssize_t
mode_value(unsigned char *buf, ssize_t len)
{
    while (--len >= 0) {
        unsigned int v = (unsigned int)*buf++;
        printf("\t%4d 0%03o 0x%02X\r\n", v, v, v);
    }

    return (0);
}

#ifdef USE_LINUX

static ssize_t
mode_keycode(unsigned char *buf, ssize_t len)
{
    unsigned char *cursor;

    for (cursor = buf; --len >= 0;) {
        unsigned int kc = *cursor++, rc = kc & 0x7F;

        if (rc == 0) {
            if (len < 2) {
                buf[0] = (unsigned char)kc;
                if (++len == 2)
                    buf[1] = *cursor;
                break;
            }

            if ((cursor[0] & 0x80) != 0 && (cursor[1] & 0x80) != 0) {
                rc  = *(cursor++) & 0x7F;
                rc <<= 7;
                rc |= *(cursor++) & 0x7F;
                len -= 2;
            }
        }

        printf("keycode %3u %s\r\n", rc, ((kc & 0x80) ? "release" : "press"));
    }

    return ((len <= 0) ? 0 : len);
}

#endif /* USE_LINUX */

static ssize_t
mode_scancode(unsigned char *buf, ssize_t len)
{
    unsigned char *cursor;

    for (cursor = buf; --len >= 0;) {
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

        if (isplain) {
#ifndef USE_LINUX
            printf("keycode %3u %-7s (     0x%02X: 0x%02X  | %c)\r\n",
                kc, (isdown ? "press" : "release"),
                rc, kc, (isdown ? 'v' : '^'));
#else
            printf("scancode      0x%02X (0x%04X | %s)\r\n",
                (rc & 0xFF), kc, (isdown ? "press" : "release"));
#endif
        } else {
            kc |= 0x80;
#ifndef USE_LINUX
            printf("keycode %3u %-7s (0x%02X 0x%02X: 0x%-3X | %c)\r\n",
                kc, (isdown ? "press" : "release"),
                (rc & 0xFF00) >> 8, (rc & 0xFF),
                kc, (isdown ? 'v' : '^'));
#else
            printf("scancode 0x%02X 0x%02X (0x%04X | %s)\r\n",
                (rc & 0xFF00) >> 8, (rc & 0xFF),
                kc, (isdown ? "press" : "release"));
#endif
        }
    }

    return ((len <= 0) ? 0 : len);
}

/* vim:set fenc=utf-8 filetype=c syntax=c ts=4 sts=4 sw=4 et tw=79: */
