/*@ Fetch a PHK DNS A record and calculate current leapsecond status.
 *@ Compile:  $ cc -o leapsec phk-utcdrift.c
 *@ Fallback: $ cc -DWANT_GETHOSTBYNAME -o leapsec phk-utcdrift.c
 *@ Synopsis:
 *@   Fetching: $ ./leapsec SERVER
 *@     Encode: $ ./leapsec YEAR MONTH BASE-DRIFT ADJUSTMENT
 *
 * Written 2015 Steffen (Daode) Nurpmeso <sdaoden@users.sf.net>.
 * Public Domain.
 */

#include <sys/socket.h>

#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#if defined __STDC_VERSION__ && __STDC_VERSION__ + 0 >= 199901L
# include <stdint.h>
#else
# include <inttypes.h>
#endif

#ifndef NI_MAXHOST
# define NI_MAXHOST   1025
#endif

#define _EX_OK        EXIT_SUCCESS
#define _EX_USAGE     64
#define _EX_DATAERR   65
#define _EX_NOHOST    68

#ifndef NELEM
# define NELEM(X)     (sizeof(X) / sizeof((X)[0]))
#endif

#ifdef UINT8_MAX
typedef uint8_t           ui8_t;
typedef int8_t            si8_t;
#elif UCHAR_MAX != 255
# error UCHAR_MAX must be 255
#else
typedef unsigned char     ui8_t;
typedef signed char       si8_t;
#endif

#ifdef UINT16_MAX
typedef uint16_t          ui16_t;
typedef int16_t           si16_t;
#elif USHRT_MAX != 0xFFFFu
# error USHRT_MAX must be 0xFFFF
#else
typedef unsigned short    ui16_t;
typedef signed short      si16_t;
#endif

#ifdef UINT32_MAX
typedef uint32_t          ui32_t;
typedef int32_t           si32_t;
#elif ULONG_MAX == 0xFFFFFFFFu
typedef unsigned long int ui32_t;
typedef signed long int   si32_t;
#elif UINT_MAX != 0xFFFFFFFFu
# error UINT_MAX must be 0xFFFFFFFF
#else
typedef unsigned int      ui32_t;
typedef signed int        si32_t;
#endif

typedef enum {FAL0, TRU1} bool_t;

/*
 * PHK DNS A:
 * - Class E: 4-bit (0b1111)
 * - Months since 1972: 10-bit
 * - Base drift before leapsecond: 8-bit
 * - Drift adjustment: 2-bit
 * - CRC-8 PHK checksum: 8-bit
 */
struct dns_leapinfo {
  ui32_t  dl_addr_parts[4];
  ui8_t   _dl_pad1[1];
  si8_t   dl_adjust;
  si8_t   dl_drift;
  ui8_t   dl_month;
  ui16_t  dl_year;
  ui8_t   _dl_pad2[2];
  char    dl_addr[NI_MAXHOST];
};

static int    _encode(char **argv, struct dns_leapinfo *dlp);

static bool_t _fetch_addr(char const *host, struct dns_leapinfo *dlp);
static bool_t _dl_addr_to_aparts(struct dns_leapinfo *dlp);
/* count specifies the number of array entries to be walked */
static ui32_t _dl_crc8_phk(struct dns_leapinfo const *dlp, ui32_t count);
static bool_t _dl_explode(struct dns_leapinfo *dlp);

int
main(int argc, char **argv)
{
  struct dns_leapinfo dl;
  int rv;

  rv = _EX_USAGE;
  if (argc != 2 && argc != 5) {
    fprintf(stderr,
      "Synopsis fetch : %s SERVER\n"
      "         encode: %s YEAR MONTH BASE-DRIFT ADJUSTMENT\n",
      argv[0], argv[0]);
    goto jleave;
  }

  if (argc == 5)
    argc = _encode(argv + 1, &dl);
  else {
    argc = _EX_OK;
    rv = _EX_NOHOST;
    if (!_fetch_addr(argv[1], &dl)) {
      fprintf(stderr, "! DNS failed to resolve `%s'\n", argv[1]);
      goto jleave;
    }
  }

  rv = _EX_DATAERR;
  if (!_dl_addr_to_aparts(&dl)) {
    fprintf(stderr, "! Bogus IP address content: `%s'\n", dl.dl_addr);
    goto jprint;
  }

  if (_dl_crc8_phk(&dl, NELEM(dl.dl_addr_parts)) != 0) {
    fprintf(stderr, "! CRC checksum failure\n");
    goto jprint;
  }

  if (!_dl_explode(&dl)) {
    fprintf(stderr, "! Bogus leapsecond data / non-class E address: `%s'\n",
      dl.dl_addr);
    goto jprint;
  }

  rv = (argc != _EX_OK) ? argc : _EX_OK;
jprint:
  printf("%s -> %s %04u-%02u %s%d %s%d\n",
    dl.dl_addr, (rv == _EX_OK ? "OK" : "BAD"),
    (ui32_t)dl.dl_year, (ui32_t)dl.dl_month,
    (dl.dl_drift < 0 ? "" : "+"), (si32_t)dl.dl_drift,
    (dl.dl_adjust < 0 ? "" : "+"), (si32_t)dl.dl_adjust);
jleave:
  return rv;
}

static int
_encode(char **argv, struct dns_leapinfo *dlp)
{
  ui32_t y, m, i;
  si32_t drift, adj;
  int rv = _EX_OK;

  /* Regarding strto*() handling */
  fprintf(stderr, "Warning: encode mode doesn't truly verify arguments!\n");

  y = (ui32_t)strtoul(argv[0], NULL, 0);
  if (y < 1972 || y > 2057) {
    fprintf(stderr, "! Invalid (non-representable) year: %u\n", y);
    rv = _EX_DATAERR;
  }
  m = (ui32_t)strtoul(argv[1], NULL, 0);
  if (m < 1 || m > 12 || (y == 2057 && m > 4)) {
    fprintf(stderr, "! Invalid (non-representable) month %u (for year %u)\n",
      m, y);
    rv = _EX_DATAERR;
  }
  drift = (si32_t)strtol(argv[2], NULL, 0);
  if (drift < -128 || drift > 127) {
    fprintf(stderr, "! Invalid (non-representable) drift: %d\n", drift);
    rv = _EX_DATAERR;
  }
  adj = (si32_t)strtol(argv[3], NULL, 0);
  if (adj < -1 || adj > 1) {
    fprintf(stderr, "! Invalid adjustment: %d\n", adj);
    rv = _EX_DATAERR;
  }

  i = (y - 1972) * 12 + (m - 1);
  i <<= 8;
  i |= drift;
  i <<= 2;
  switch (adj) {
  case  1: i |= 0x1; break;
  case -1: i |= 0x3; break;
  default: break;
  }
  i <<= 8;
  i |= 0xF0000000u;

  dlp->dl_addr_parts[0] = i >> 24;
  dlp->dl_addr_parts[1] = (i >> 16) & 0xFF;
  dlp->dl_addr_parts[2] = (i >>  8) & 0xFF;
  dlp->dl_addr_parts[3] = _dl_crc8_phk(dlp, NELEM(dlp->dl_addr_parts) - 1);

#if defined __STDC_VERSION__ && __STDC_VERSION__ + 0 >= 199901L
  snprintf
#else
  sprintf
#endif
    (dlp->dl_addr,
#if defined __STDC_VERSION__ && __STDC_VERSION__ + 0 >= 199901L
      sizeof dlp->dl_addr,
#endif
    "%u.%u.%u.%u",
    dlp->dl_addr_parts[0], dlp->dl_addr_parts[1], dlp->dl_addr_parts[2],
    dlp->dl_addr_parts[3]
  );
  return rv;
}

#ifndef WANT_GETHOSTBYNAME
static bool_t
_fetch_addr(char const *host, struct dns_leapinfo *dlp)
{
  struct addrinfo hints, *res;
  int i;
  bool_t rv = FAL0;

  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  res = NULL;

  if ((i = getaddrinfo(host, NULL, &hints, &res)) != 0) {
    fprintf(stderr, "! Cannot resolve `%s': %s\n", host, gai_strerror(i));
    goto jleave;
  }

  if ((i = getnameinfo(res->ai_addr, res->ai_addrlen,
      dlp->dl_addr, sizeof dlp->dl_addr, NULL, 0, NI_NUMERICHOST)) != 0) {
    fprintf(stderr, "! Cannot resolve name `%s': %s\n", host, gai_strerror(i));
    goto jleave;
  }

  rv = TRU1;
jleave:
  if (res != NULL)
    freeaddrinfo(res);
  return rv;
}

#else /* !WANT_GETHOSTBYNAME */
static bool_t
_fetch_addr(char const *host, struct dns_leapinfo *dlp)
{
  struct hostent *hp;
  struct in_addr *iaddr;
  char const *saddr;
  size_t i;
  bool_t rv = FAL0;

  if ((hp = gethostbyname(host)) == NULL) {
    char const *emsg;

    switch (h_errno) {
    case HOST_NOT_FOUND:
      emsg = "host not found";
      break;
    default:
    case TRY_AGAIN:
      emsg = "(maybe) try again later";
      break;
    case NO_RECOVERY:
      emsg = "non-recoverable server error";
      break;
    case NO_DATA:
      emsg = "valid name without IP address";
      break;
    }
    fprintf(stderr, "! Cannot resolve `%s': %s\n", host, emsg);
    goto jleave;
  }

  if (hp->h_addrtype != AF_INET) {
    fprintf(stderr, "! DNS didn't return IPv4 address for `%s'\n", host);
    goto jleave;
  }

  /* (Don't check h_length etc..) */
  iaddr = (struct in_addr*)hp->h_addr_list[0];
  saddr = inet_ntoa(*iaddr);

  i = strlen(saddr) +1;
  if (i <= sizeof dlp->dl_addr) {
    memcpy(dlp->dl_addr, saddr, i);
    rv = TRU1;
  }
jleave:
  return rv;
}
#endif /* WANT_GETHOSTBYNAME */

static bool_t
_dl_addr_to_aparts(struct dns_leapinfo *dlp)
{
  ui32_t i;
  char *eptr;
  char const *sptr = dlp->dl_addr;
  bool_t rv = FAL0;

  for (i = 0;; ++i) {
    unsigned long l = strtoul(sptr, &eptr, 10);
    if (l != (ui32_t)l)
      goto jleave;
    dlp->dl_addr_parts[i] = (ui32_t)l;

    if (sptr == eptr)
      goto jleave;
    switch (*eptr) {
    case '.':
      if (i == 3)
        goto jleave;
      sptr = eptr + 1;
      break;
    case '\0':
      if (i == 3)
        rv = TRU1;
      /* FALLTHRU */
    default:
      goto jleave;
    }
  }

  rv = TRU1;
jleave:
  return rv;
}

static ui32_t
_dl_crc8_phk(struct dns_leapinfo const *dlp, ui32_t count)
{
  ui32_t const poly = 0xCF;
  ui32_t crc, i, slot, j, mix;

  for (crc = i = 0; i < count; ++i)
    for (slot = dlp->dl_addr_parts[i], j = 0; j < 8; ++j) {
      mix = (crc ^ slot) & 0x01;
      crc >>= 1;
      if (mix != 0)
        crc ^= poly;
      slot >>= 1;
    }
  return crc;
}

static bool_t
_dl_explode(struct dns_leapinfo *dlp)
{
  ui32_t i;
  bool_t rv = FAL0;

  i = dlp->dl_addr_parts[0] << 16;
  i |= dlp->dl_addr_parts[1] << 8;
  i |= dlp->dl_addr_parts[2];

  /* Must be class E address */
  if ((i & 0xF00000) != 0xF00000)
    goto jleave;
  i &= ~0xF00000;

  switch ((dlp->dl_adjust = (si8_t)(i & 0x03))) {
  case 0x02:
    goto jleave;
  case 0x03:
    dlp->dl_adjust = -1;
  case 0x00:
  default:
    break;
  }
  i >>= 2;
  dlp->dl_drift = (si8_t)(i & 0xFF);
  i >>= 8;
  dlp->dl_month = (ui8_t)(i % 12) + 1;
  dlp->dl_year = (ui16_t)(i / 12) + 1972;

  rv = TRU1;
jleave:
  return rv;
}

/* s-it2-mode */
