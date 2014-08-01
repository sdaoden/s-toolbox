/*@ s-base64, en-/decode data to/from Base64 encoding (RFC 2045).
 *@ Compile: $ c99 -O 1 -o s-base64 s-base64.c
 *@ Use    : $ s-base64 --help
 * XXX What about mbtowc and iswspace() instead of isspace()??
 * TODO This utility is plain shit :)
 *
 * Copyright (c) 2013 - 2014 Steffen (Daode) Nurpmeso <sdaoden@users.sf.net>.
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

/*
 * Code taking from S-nail(1):
 * Base64 code core taken from NetBSDs mailx(1): */
/*	$NetBSD: mime_codecs.c,v 1.9 2009/04/10 13:08:25 christos Exp $	*/
/*
 * Copyright (c) 2006 The NetBSD Foundation, Inc.
 * All rights reserved.
 *
 * This code is derived from software contributed to The NetBSD Foundation
 * by Anon Ymous.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE NETBSD FOUNDATION, INC. AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#undef HAVE_ENCODE_TEXT /* TODO */

#include <ctype.h>
#include <locale.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#define B64_LINESIZE (4 * 19  +1)      /* Max. compl. Base64 linesize (+1) */
#define BUF_SIZE     (1024 * 32)       /* Stack buffer size for fread()+ */

static bool b64_encode(void);
#ifdef HAVE_ENCODE_TEXT
static bool b64_encode_text(void);
#endif
static bool b64_decode(void);

int
main(int argc, char **argv)
{
   bool (*fun)(void) = &b64_encode;
   bool error = true;
   char *cp;

   (void)setlocale(LC_ALL, "");

   if (argc == 1)
      goto jrun;
   if (argc > 1 + 3)
      goto jhelp;

   /* Mode */
   cp = *++argv;
   if (!strcmp(cp, "--") || !strcmp(cp, "--encode") || !strcmp(cp, "-e"))
      ;
#ifdef HAVE_ENCODE_TEXT
   else if (!strcmp(cp, "--encode-text") || !strcmp(cp, "-t"))
      fun = &b64_encode_text;
#endif
   else if (!strcmp(cp, "--decode") || !strcmp(cp, "-d"))
      fun = &b64_decode;
   else if (!strcmp(cp, "--help") || !strcmp(cp, "-h")) {
      error = false;
      goto jhelp;
   } else
      goto jstdin;

   /* STDIN (XXX if we don't reopen "b" mode is not set) */
   cp = *++argv;
   if (cp == NULL)
      goto jrun;
jstdin:
   if ((cp[0] != '-' || cp[1] != '\0') &&
         freopen(cp, (fun == &b64_decode ? "r" : "rb"), stdin) == NULL) {
      perror(cp);
      goto jleave;
   }

   /* STDOUT (XXX if we don't reopen "b" mode is not set) */
   cp = *++argv;
   if (cp == NULL)
      goto jrun;
   if ((cp[0] != '-' || cp[1] != '\0') &&
         freopen(cp, (fun == &b64_decode ? "wb" : "w"), stdout) == NULL) {
      perror(cp);
      goto jleave;
   }

jrun:
   error = (*fun)();

jleave:
   return error;

jhelp:
   fprintf(error ? stderr : stdout,
"Synopsis:\n"
"  s-base64 --help|-h\n"
"  s-base64 [--encode|-e|--] [input-file [output-file]]\n"
#ifdef HAVE_ENCODE_TEXT
"  s-base64 --encode-text|-t [input-file [output-file]]\n"
#endif
"  s-base64 --decode|-d      [input-file [output-file]]\n"
"\n"
"s-base64 reads input data and encodes or decodes it on the fly.\n"
#ifdef HAVE_ENCODE_TEXT
"The difference in between --encode-text and --encode is that the former\n"
"assumes that the input data is text material and converts line breaks into\n"
"CRLF sequences as required by RFC 2045, section 6.8.\n"
#else
"Note that the encode mode does not convert line breaks into CRLF sequences\n"
"as required by RFC 2045, section 6.8.  Use a pre-filter to convert those,\n"
"e.g., \"$ awk 'BEGIN{ORS=\"\\r\\n\"}{print}'\" will do the trick.\n"
#endif
"*input-file* defaults to STDIN, *output-file* defaults to STDOUT; hyphen (-)\n"
"can be used to explicitly choose STDIN/STDOUT.  If *output-file* is a real\n"
"file it'll be created as necessary; yet existent contents are overwritten.\n"
"The decoder ignores *any* encountered whitespace.\n"
"\n"
"Copyright (c) 2013 - 2014 Steffen (Daode) Nurpmeso <sdaoden@users.sf.net>.\n"
"This software is provided under the terms of the ISC license.\n"
"It incorporates code that is subject to the 2-clause (Net)BSD license.\n"
   );
   goto jleave;
}

typedef unsigned char   uc_it;
typedef unsigned int    ui_it;

static inline void      _b64_encode(char b64[4], char const *inb, size_t inl);
static inline ssize_t   _b64_decode(char oub[3], char const b64[4]);

static inline void
_b64_encode(char b64[4], char const *inb, size_t inl)
{
   static char const b64table[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
   ui_it a = (uc_it)inb[0], b, c;

   b64[0] = b64table[a >> 2];
   switch (inl) {
   case 1:
      b64[1] = b64table[((a & 0x3) << 4)];
      b64[2] =
      b64[3] = '=';
      break;
   case 2:
      b = (uc_it)inb[1];
      b64[1] = b64table[((a & 0x3) << 4) | ((b & 0xf0) >> 4)];
      b64[2] = b64table[((b & 0xf) << 2)];
      b64[3] = '=';
      break;
   default:
      b = (uc_it)inb[1];
      c = (uc_it)inb[2];
      b64[1] = b64table[((a & 0x3) << 4) | ((b & 0xf0) >> 4)];
      b64[2] = b64table[((b & 0xf) << 2) | ((c & 0xc0) >> 6)];
      b64[3] = b64table[c & 0x3f];
      break;
   }
}

static inline ssize_t
_b64_decode(char oub[3], char const b64[4])
{
   static signed char const b64index[] = {
      -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
      -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
      -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,62, -1,-1,-1,63,
      52,53,54,55, 56,57,58,59, 60,61,-1,-1, -1,-2,-1,-1,
      -1, 0, 1, 2,  3, 4, 5, 6,  7, 8, 9,10, 11,12,13,14,
      15,16,17,18, 19,20,21,22, 23,24,25,-1, -1,-1,-1,-1,
      -1,26,27,28, 29,30,31,32, 33,34,35,36, 37,38,39,40,
      41,42,43,44, 45,46,47,48, 49,50,51,-1, -1,-1,-1,-1
   };
#define EQU          (ui_it)-2
#define BAD          (ui_it)-1
#define uchar64(c)   \
   ((uc_it)(c) >= sizeof(b64index) ? BAD : (ui_it)b64index[(uc_it)(c)])

   ssize_t ret = -1;
   uc_it *p = (uc_it*)oub;
   ui_it a = uchar64(b64[0]), b = uchar64(b64[1]), c = uchar64(b64[2]),
      d = uchar64(b64[3]);

   if (a >= EQU || b >= EQU || c == BAD || d == BAD)
      goto jleave;

   *p++ = ((a << 2) | ((b & 0x30) >> 4));
   if (c == EQU) {
      if (d != EQU)
         goto jleave;
      goto jdone;
   }
   *p++ = (((b & 0x0f) << 4) | ((c & 0x3c) >> 2));
   if (d == EQU)
      goto jdone;
   *p++ = (((c & 0x03) << 6) | d);
jdone:
   ret = (ssize_t)(p - (uc_it*)oub);

#undef uchar64
#undef EQU
#undef BAD
jleave:
   return ret;
}

static bool
b64_encode(void)
{
   char ib[BUF_SIZE + (3 - (BUF_SIZE % 3))], ob[4], *cp = NULL/* UNINIT */;
   ssize_t ir, il, ol;

   for (ir = ol = 0;
         (il = fread(ib + ir, sizeof *ib, sizeof(ib) - ir, stdin)) != 0;) {
      il += ir;
      for (cp = ib; il >= 3; cp += 3, il -= 3) Jput: {
         _b64_encode(ob, cp, il);
         if (fwrite(ob, sizeof *ob, sizeof ob, stdout) != 4 ||
               ((ol += 4) > B64_LINESIZE - 4 && (ol = 0,
               fputc('\n', stdout)) == EOF)) {
            perror("b64_encode output failed");
            goto jleave;
         }
      }
      if (il < 0) {
         il ^= il;
         goto jleave;
      }
      ir = il;
   }
   if ((il = ir) != 0)
      goto Jput;
jleave:
   return (il != 0);
}

static bool
b64_decode(void)
{
   char ib[BUF_SIZE + (4 - (BUF_SIZE % 4))], rib[4], ob[3], *cp;
   size_t il, ril;
   bool seeneot = false, error = true;

   for (il = ril = 0; (il = fread(ib, sizeof *ib, sizeof ib, stdin)) != 0;) {
      for (cp = ib; il != 0;) {
         /* Ignore WS; we need exactly four octets */
         for (; il != 0 && ril != 4; ++cp, --il)
            if (!isspace(*cp))
               rib[ril++] = *cp;

         if (il == 0 && ril != 4)
            break;
         if (seeneot)
            break;
         ril = 0;

         ssize_t dl = _b64_decode(ob, rib);
         if (dl < 0)
            goto jbail;
         if (fwrite(ob, sizeof *ob, dl, stdout) != (size_t)dl) {
            perror("b64_decode output failed");
            goto jleave;
         }
         if (dl != 3)
            seeneot = true;
      }
   }
   error = (ril != 0);

   if (error)
jbail:
      fprintf(stderr, "Data stream contained invalid Base64: output is most "
         "likely corrupted\n");
jleave:
   return error;
}

/* s-it-mode */
