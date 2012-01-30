/*@ showkey.c  : show keyboard scancodes for +BSD wscons(4), version 0.3.
 *@ Compile    : $ gcc -W -Wall -pedantic -ansi -o showkey showkey.c
 *@ Run        : $ ./showkey [ktv]  (keycode, termios-only, termios-only values)
 *@ Exit status: 0=timeout, 1=signal (crash), 2=read error, 3=use/setup failure
 *
 * Copyright (c) 2012 Steffen Daode Nurpmeso <sdaoden@googlemail.com>.
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

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include <err.h>
#include <termios.h>
#include <unistd.h>

#include <sys/ioctl.h>
#include <sys/time.h>

#include <dev/wscons/wsconsio.h>
#include <dev/wscons/wsksymdef.h>

static int              tios_only;
static struct termios   tios_orig, tios_raw;

/* Signal handler, exit 0 if SIGALRM, 1 otherwise */
static void     onsig(int sig);

/* If skip > 0, leave that many bytes at front of buf unused.
 * Return amount of bytes read;  raises SIGALRM after 5 seconds */
static ssize_t  safe_read(unsigned char *buf, size_t buf_sizeof, ssize_t skip);

/* Terminal handling */
static void     raw_init(void), raw_on(void), raw_off(void);

/* Modes which handle input */
static ssize_t  mode_keycode(unsigned char *buf, ssize_t len),
                mode_term(unsigned char *buf, ssize_t len),
                mode_value(unsigned char *buf, ssize_t len);

int
main(int argc, char **argv)
{
    ssize_t (*mode)(unsigned char*, ssize_t) = &mode_keycode;
    ssize_t i;
    auto struct sigaction sa;
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
    if (! mode)
        errx(3, "Usage: showkey [ktv]  (keycode, termios, value)");

    if (!isatty(STDIN_FILENO))
        err(3, "STDIN is not a terminal");
    raw_init();

    sa.sa_handler = &onsig;
    sa.sa_flags = 0;
    (void)sigfillset(&sa.sa_mask);
    for (i = 0; i < NSIG; ++i)
        if (sigaction((int)i + 1, &sa, NULL) < 0 && i == SIGALRM)
            err(3, "Can't install SIGALRM signal handler");

    printf( "You may now use the keyboard;\n"
            "After five seconds of inactivity the program terminates\n");
    for (i = 0;;) {
        i = safe_read(buf, sizeof(buf), i);
        if (i <= 0)
            break;
        i = (*mode)(buf, i);
    }
    /* Read error */
    return 2;
}

static void
onsig(int sig)
{
    raw_off();
    exit(sig != SIGALRM);
}

static ssize_t
safe_read(unsigned char *buf, size_t buf_sizeof, ssize_t skip)
{
    ssize_t br;
    auto struct itimerval it;

    --buf_sizeof;
    if (skip < 0)
        skip = 0;
    else {
        buf += skip;
        buf_sizeof -= skip;
    }

    it.it_value.tv_sec = 5; it.it_value.tv_usec = 0;
    it.it_interval.tv_sec = it.it_interval.tv_usec = 0;
    if (setitimer(ITIMER_REAL, &it, NULL) < 0)
        err(3, "Can't install wakeup timer");

    raw_on();
    br = read(STDIN_FILENO, buf, buf_sizeof);
    if (br >= 0)
        br += skip;
    raw_off();

    it.it_value.tv_sec = it.it_value.tv_usec = 0;
    (void)setitimer(ITIMER_REAL, &it, NULL);

    return br;
}

/*
 * See src/sys/dev/wscons/wsksymdef.h
 */

static ssize_t
mode_keycode(unsigned char *buf, ssize_t len)
{
    unsigned char *cursor = buf;
    const char *group;
    unsigned int kc, rc, isdown;

    while (--len >= 0) {
        kc = rc = *cursor++;
        if ((rc & 0xF0) == 0xE0 || (rc & 0xF8) == 0xF0) {
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

        switch (KS_GROUP(rc)) {
#define G(g) case g: group = #g; break;
        G(KS_GROUP_Mod)
        G(KS_GROUP_Keypad)
        G(KS_GROUP_Function)
        G(KS_GROUP_Command)
        G(KS_GROUP_Internal)
        /* Not encoded?? */
        G(KS_GROUP_Dead)
        G(KS_GROUP_Keycode)
        default:
# ifdef KS_GROUP_Plain
        G(KS_GROUP_Plain)
# else
        case KS_GROUP_Ascii: group = "KS_GROUP_Plain"; break;
# endif
#undef G
        }
        isdown = 0 == (kc & 0x80);

        kc &= ~0x0080;
        printf( "keycode %3u %-7s "
                "(0x%04X: %17s | %c | 0x%04X\n",
                kc, (isdown ? "press" : "release"),
                rc, group, (isdown ? 'v' : '^'), kc);
    }

    return len;
}

static ssize_t
mode_term(unsigned char *buf, ssize_t len)
{
    if (*buf == 0x1B)
        while (--len >= 0) {
            printf("0x%02X ", (unsigned int)*buf++);
            if (len > 0 && *buf == 0x1B) /* XXX May be incomplete seq.?? */
                printf("\n");
        }
    else
        while (--len >= 0)
            printf("0x%02X ", (unsigned int)*buf++);
    printf("\n");
    return 0;
}

static ssize_t
mode_value(unsigned char *buf, ssize_t len)
{
    while (--len >= 0) {
        unsigned int v = (unsigned int)*buf++;
        printf("%4d 0%03o 0x%02X  ", v, v, v);
    }
    printf("\n");
    return 0;
}

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
        errno = arg;
        err(3, ((arg == ENOTTY)
                ? "This program mode won't work on pseudo terminals"
                : "Can't put keyboard in raw mode ("
                  "the WSDISPLAY_COMPAT_RAWKBD kernel option is mandatory)"));
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

/* vim:set fenc=utf-8 filetype=c syntax=c ts=4 sts=4 sw=4 et tw=79: */
