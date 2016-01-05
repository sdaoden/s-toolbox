/*@ s-idn, simple GNU Libidn based IDN en-/decoder.
 *@ (Rather identical to the idn utility that comes with that one, but i needed
 *@ to get comfortable with Libidn and so i've wrote it.)
 *@ Compile: gcc -O2 -Wall -Wextra -pedantic -o s-idn s-idn.c -lidn
 *@ Use    : $ s-idn --help
 *
 * Copyright (c) 2012, 2016 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
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

#include <locale.h>
#include <stdio.h>
#include <string.h>

#include <idna.h>
#include <stringprep.h>
#include <tld.h>

static void enc_l(char const*ln), enc_u(char const*ln), dec(char const*ln);

int
main(int argc, char **argv)
{
   char buf[LINE_MAX], *as;
   void (*fun)(char const*ln) = &enc_l;

   (void)argc;

   (void)setlocale(LC_ALL, "");

   as = *++argv;
   if (as == NULL)
      goto jstdin;

   if (strcmp(as, "--unicode") == 0 || strcmp(as, "-u") == 0)
      fun = &enc_u, as = *++argv;
   else if (strcmp(as, "--decode") == 0 || strcmp(as, "-d") == 0)
      fun = &dec, as = *++argv;
   else if (strcmp(as, "--help") == 0 || strcmp(as, "-h") == 0)
      goto jsyn;

   if (as == NULL) {
jstdin:
      while((as = fgets(buf, sizeof buf, stdin)) != NULL && as[0] && as[1]) {
         as[strlen(as) - 1] = '\0';
         (*fun)(as);
      }
   } else do
      if (*as) {
         (void)printf("%s\n", as);
         (*fun)(as);
      }
   while ((as = *++argv) != NULL);

jleave:
   return (0);

jsyn:
   as = argv[-1];
   printf(
"Synopsis:\n"
"  s-idn --help|-h                  show this help and exit\n"
"  s-idn --decode|-d [:IDN:]        decode IDNs\n"
"  s-idn [--unicode|-u] [:STRING:]  encode locale (unicode) strings to IDN\n"
"\n"
"If the IDN or STRING arguments are missing, data is read from standard "
   "input.\n"
"Errors will be printed on standard error with an \"ERR:\" prefix.\n"
"\n"
"Copyright (c) 2012, 2016 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.\n"
"This software is provided under the terms of the ISC license.\n"
   );
   goto jleave;
}

/*
 * Basically idna_to_ascii_lz()
 */
static void
enc_l(char const*ln)
{
   char *utf8;

   utf8 = stringprep_locale_to_utf8(ln);
   if (utf8 == NULL)
      fprintf(stderr, "ERR: failed to convert input to UTF-8\n");
   else {
      enc_u(utf8);
      free(utf8);
   }
}

static void
enc_u(char const*ln)
{
   char *idna_ascii;
   uint32_t *idna_uni;
   size_t sz;
   int rc;

   rc = idna_to_ascii_8z(ln, &idna_ascii, IDNA_USE_STD3_ASCII_RULES);
   if (rc != IDNA_SUCCESS) {
      fprintf(stderr, "ERR: TO-ASCII normalization: %s\n", idna_strerror(rc));
      goto j_leave;
   }

   /* Due to normalization that may have occurred we must convert back to be
    * able to check for top level domain issues */
   rc = idna_to_unicode_8z4z(idna_ascii, &idna_uni, 0);
   if (rc != IDNA_SUCCESS) {
      fprintf(stderr, "ERR: normalized ASCII TO-UNICODE: %s\n",
         idna_strerror(rc));
      goto jleave;
   }

   rc = tld_check_4z(idna_uni, &sz, NULL);
   free(idna_uni);
   if (rc != TLD_SUCCESS) {
      fprintf(stderr, "ERR: TLD check failed at %lu: %s\n",
         (unsigned long)sz, tld_strerror(rc));
      goto jleave;
   }

   puts(idna_ascii);
jleave:
   free(idna_ascii);
j_leave:
;}

static void
dec(char const*ln)
{
   char *idna_locale;
   size_t lmax, sz;
   int rc;

   for (lmax = strlen(ln), sz = 0; sz < lmax; ++sz)
      if ((unsigned char)ln[sz] >= 0x7F) {
         fprintf(stderr, "ERR: not an IDN: non-ASCII codepoint at %lu\n",
            (unsigned long)sz);
         goto j_leave;
      }

   rc = idna_to_unicode_lzlz(ln, &idna_locale, 0);
   if (rc != IDNA_SUCCESS) {
      fprintf(stderr, "ERR: FROM-ASCII to locale failed: %s\n",
         idna_strerror(rc));
      goto j_leave;
   }

   rc = tld_check_lz(idna_locale, &sz, NULL);
   if (rc != TLD_SUCCESS) {
      fprintf(stderr, "ERR: TLD check of <%s> failed at %lu: %s\n",
         idna_locale, (unsigned long)sz, tld_strerror(rc));
      goto jleave;
   }

   puts(idna_locale);
jleave:
   free(idna_locale);
j_leave:
;}

/* vim:set fenc=utf-8 syntax=c ts=8 sts=3 sw=3 et tw=79: */
