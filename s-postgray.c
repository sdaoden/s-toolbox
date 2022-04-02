/*@ s-postgray(8) - postfix protocol policy (RFC 6647 graylisting) server.
 *@ We assume postfix(1) protocol constraints:
 *@ - No whitespace (at BOL and EOL, nor) in between key, =, and value.
 *@ - Lowercase keys.
 *@ - XXX-1 - VERP delimiters are +=, and are not configurable.
 *@ - XXX-2 - We assume numeric IDs in VERP addresses come after the delimiter.
 *@ - XXX-3 - E-Mail addresses must be normalized and stripped of comments etc.
 *@ - XXX-MONO - We use CLOCK_REALTIME and 0 negative drifts; instead we could
 *@   XXX-MONO   use CLOCK_MONOTONIC and _REALTIME only when saving/loading.
 *@
 *@ Further:
 *@ - With $SOURCE_DATE_EPOCH "minutes" are indeed "seconds".
 *@
 *@ Possible improvements:
 *@ - We may want to make the server startable on its own?
 *@ - May want to make policy return on ENOMEM/limit excess configurable?
 *@ - We do not sleep per policy instance=, but per-question.
 *@   This could add a lot of delay per-message.  Restore instance= handling
 *@   from git history, and sleep only once per instance?  The documented "it
 *@   should be impossible to reach the graylist bypass limit" no longer true!
 *@   calculation is no longer true then however, since one mes
 *@ - We could add a in-between-delay counter, and if more than X messages
 *@   come in before the next delay expires, we could auto-blacklist.
 *@   Just extend the DB format to a 64-bit integer, and use bits 32..48.
 *@   (Adding this feature should work with existing DBs.)
 *@ - XXX-ARGS May want to do parsing like in first draft: just parse it :),
 *@   keep [AaBb] in an allocated list, parse that in server or in --test-mode.
 *@   Currently -R is parsed two times.  (I messed it now it is weird.)
 *
 * Copyright (c) 2022 Steffen Nurpmeso <steffen@sdaoden.eu>.
 * SPDX-License-Identifier: ISC
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
#define su_FILE s_postgray

/* */
#define a_VERSION "0.7.0"
#define a_CONTACT "Steffen Nurpmeso <steffen@sdaoden.eu>"

/* Maximum accept(2) backlog */
#define a_SERVER_LISTEN 5

/**/

/* Maximum size of the triple recipient/sender/client_address we look out for,
 * anything beyond is DUNNO.  RFC 5321 limits:
 *    4.5.3.1.1.  Local-part
 *    The maximum total length of a user name or other local-part is 64 octets.
 *    4.5.3.1.2.  Domain
 *    The maximum total length of a domain name or number is 255 octets.
 * We also store client_name for configurable domain whitelisting, but be easy
 * and treat that as local+domain, too.
 * And finally we also use the buffer for gray savings, so add room */
#define a_BUF_SIZE \
   (Z_ALIGN(INET6_ADDRSTRLEN +1) + ((64 + 256 +1) * 3) +\
    1 + su_IENC_BUFFER_SIZE + 1)

/* Minimum number of minutes in between DB cleanup runs.
 * Together with --limit-delay this forms a barrier against limit excess */
#define a_DB_CLEANUP_MIN_DELAY (1 * su_TIME_HOUR_MINS)

/* The default built-in defer message (see manual) */
#define a_DEFER_MSG "DEFER_IF_PERMIT 4.2.0 Service temporarily faded to Gray"

/* When hitting limit, new entries are delayed that long */
#define a_LIMIT_DELAY_SECS 1 /* xxx configurable? */

/**/
#define a_OPENLOG_FLAGS (LOG_NDELAY | LOG_PID)

/* */
#define a_DBGIF 0
#define a_DBG(X)
#define a_DBG2(X)
#define a_NYD_FILE "/tmp/" VAL_NAME ".dat"

/* -- >8 -- 8< -- */

/*
#define _POSIX_C_SOURCE 200809L
#define _ATFILE_SOURCE
*/
#define _GNU_SOURCE /* Always the same mess */

/* TODO all std or posix, nono */
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/uio.h>

#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <netinet/in.h>

#include <su/avopt.h>
#include <su/boswap.h>
#include <su/cs.h>
#include <su/cs-dict.h>
#include <su/icodec.h>
#include <su/mem.h>
#include <su/path.h>
#include <su/time.h>

#if a_DBGIF
/*# define NYDPROF_ENABLE*/
# define NYD_ENABLE
# define NYD2_ENABLE
#endif
#include "su/code-in.h"

/* defines, enums, types, rodata, bss {{{ */
/* I18N */
#define _(X) X
#define N_(X) X
#define V_(X) X

/* No need for _CASE since keys are normalized already.  No _AUTO_SHRINK! */
#define a_PG_WB_CA_FLAGS (su_CS_DICT_HEAD_RESORT)
#define a_PG_WB_CNAME_FLAGS (su_CS_DICT_HEAD_RESORT)

/* Gray list; that is balanced() after resize; no _ERR_PASS, set later on!
 * It is always in FROZEN state to delay resize costs to balance()!
 * MIN_LIMIT is also used for considering whether _this_ balance() is needed */
#define a_PG_GRAY_FLAGS \
   (su_CS_DICT_HEAD_RESORT | su_CS_DICT_STRONG /*| su_CS_DICT_ERR_PASS*/)
#define a_PG_GRAY_TS 4
#define a_PG_GRAY_MIN_LIMIT 1000
#define a_PG_GRAY_DB_NAME "s-postgray.db"

enum a_pg_flags{
   a_PG_F_NONE,
   a_PG_F_TEST_MODE = 1u<<1, /* -# */
   a_PG_F_CLIENT_ONCE_MODE = 1u<<2, /* -o */
   a_PG_F_CLIENT_SHUTDOWN_MODE = 1u<<3, /* -. */
   a_PG_F_MASTER_DELAY_PROGRESSIVE = 1u<<4, /* -p */
   a_PG_F_V = 1u<<6, /* Verbosity */
   a_PG_F_VV = 1u<<7,
   a_PG_F_V_MASK = a_PG_F_V | a_PG_F_VV,

   a_PG_F_SETUP_MASK = 0xFFu,

   /* */
   a_PG_F_TEST_ERRORS = 1u<<13,
   a_PG_F_NOFREE_DEFER_MSG = 1u<<14,
   a_PG_F_NOFREE_STORE_PATH = 1u<<15,

   /* Client */
   a_PG_F_CLIENT_NONE,

   /* Master */
   a_PG_F_MASTER_NONE = 0,
   a_PG_F_MASTER_ACCEPT_SUSPENDED = 1u<<16,
   a_PG_F_MASTER_LIMIT_EXCESS_LOGGED = 1u<<17,
   a_PG_F_MASTER_NOMEM_LOGGED = 1u<<18
};

enum a_pg_avo_args{
   a_PG_AVO_NONE,
   a_PG_AVO_FULLER = 1u<<0, /* Like _FULL less AaBb */
   a_PG_AVO_FULL = 1u<<1,
   a_PG_AVO_RELOAD = 1u<<2
};

enum a_pg_answer{
   a_PG_ANSWER_DUNNO,
   a_PG_ANSWER_DEFER,
   a_PG_ANSWER_DEFER_SLEEP,
   a_PG_ANSWER_REJECT
};

/* Fuzzy search */
enum a_pg_srch_flags{
   a_PG_SRCH_NONE,
   a_PG_SRCH_IPV4 = 1u<<0,
   a_PG_SRCH_IPV6 = 1u<<1
};

union a_pg_srch_ip{
   /* (Let's just place that align thing, ok?  I feel better that way) */
   u64 align;
   struct in_addr v4;
   struct in6_addr v6;
   /* And whatever else is needed to use this */
   char *cp;
};

/* Fuzzy search white/blacklist */
struct a_pg_srch{
   struct a_pg_srch *pgs_next;
   BITENUM_IS(u8,a_pg_srch_flags) pgs_flags;
   u8 pgs_mask; /* SRCH_IP*: CIDR mask */
   u8 pgs__pad[su_6432(6,2)];
   union a_pg_srch_ip pgs_ip;
};

struct a_pg_wb{
   struct a_pg_srch *pgwb_srch; /* ca list, fuzzy */
   struct su_cs_dict pgwb_ca; /* client_address=, exact */
   struct su_cs_dict pgwb_cname; /* client_name=, exact + fuzzy */
};

struct a_pg_wb_cnt{
   ul pgwbc_ca;
   ul pgwbc_ca_fuzzy;
   ul pgwbc_cname;
   ul pgwbc_cname_fuzzy;
};

struct a_pg_master{
   char const *pgm_sockpath;
   s32 *pgm_cli_fds;
   u32 pgm_cli_no;
   u16 pgm_cleanup_cnt;
   s16 pgm_epoch_min; /* Relative minutes of .pgm_base_epoch .. .pgm_epoch */
   s64 pgm_epoch; /* Of last tick */
   s64 pgm_base_epoch; /* ..of relative minutes; reset by gray_cleanup() */
   struct a_pg_wb pgm_white;
   struct a_pg_wb pgm_black;
   struct su_cs_dict pgm_gray;
   struct a_pg_wb_cnt pgm_cnt_white;
   struct a_pg_wb_cnt pgm_cnt_black;
   ul pgm_cnt_gray_new;
   ul pgm_cnt_gray_defer;
   ul pgm_cnt_gray_pass;
};

struct a_pg{
   BITENUM_IS(uz,a_pg_flags) pg_flags;
   struct a_pg_master *pg_master;
   /* Configuration; values always <= signed type max */
   u8 pg_4_mask;
   u8 pg_6_mask;
   u16 pg_delay_min;
   u16 pg_delay_max;
   u16 pg_gc_rebalance;
   u16 pg_gc_timeout;
   u16 pg_server_timeout;
   su_64( u8 pg__pad[4]; )
   u32 pg_count;
   u32 pg_limit;
   u32 pg_limit_delay;
   u32 pg_server_queue;
   char const *pg_defer_msg;
   char const *pg_store_path;
   /**/
   char **pg_argv;
   u32 pg_argc;
   s32 pg_clima_fd; /* Client/Master comm fd */
   /* Triple data plus client_name, pointing into .pg_buf */
   char *pg_r;
   char *pg_s;
   char *pg_ca;
   char *pg_cname;
   char pg_buf[Z_ALIGN(a_BUF_SIZE)];
};

static char const a_sopts[] =
      "4:6:" "A:a:B:b:" "c:D:d:pG:g:L:l:" "q:t:" "R:" "s:" "m:"
      "o" "." "#" "vHh";
static char const * const a_lopts[] = {
   "4-mask:;4;" N_("IPv4 mask to strip off addresses before match"),
   "6-mask:;6;" N_("IPv6 mask to strip off addresses before match"),

   "allow-file:;A;" N_("load a file of whitelist entries"),
   "allow:;a;" N_("add domain/address/CIDR to whitelist"),
   "block-file:;B;" N_("load a file of blacklist entries"),
   "block:;b;" N_("add domain/address/CIDR to blacklist"),

   "count:;c;" N_("of SMTP retries before accepting sender"),
   "delay-max:;D;" N_("until an email \"is not a retry\" but new (minutes)"),
   "delay-min:;d;" N_("before an email \"is a retry\" (minutes)"),
   "delay-progressive;p;"
      N_("double delay-min for each retry until count is reached"),
   "gc-rebalance:;G;" N_("no of GC DB cleanup runs before rebalance"),
   "gc-timeout:;g;" N_("until unused gray DB entry is removed (minutes)"),
   "limit:;L;" N_("DB entries after which new ones are not handled"),
   "limit-delay:;l;" N_("DB entries after which new ones cause sleeps"),

   "server-queue:;q;"
      N_("number of clients a server supports (not SIGHUP)"),
   "server-timeout:;t;"
      N_("until client-less server exits (0=never; minutes)"),

   "resource-file:;R;" N_("path to configuration file with long options"),

   "store-path:;s;" N_("DB and server/client socket directory (not SIGHUP)"),

   "defer-msg:;m;" N_("defer_if_permit message (read manual; not SIGHUP)"),

   /**/
   "once;o;" N_("process only one request in this client invocation"),

   "shutdown;.;"
      N_("force a running server to exit, synchronize on that, then exit"),

   "test-mode;#;" N_("check and list configuration, then exit status"),

   "verbose;v;" N_("increase syslog verbosity (multiply for more verbosity)"),
   "long-help;H;" N_("this listing"),
   "help;h;" N_("short help"),
   NIL
};

static struct a_pg_master ATOMIC *a_pgm; /* xxx only used as on/off: s32? */
static s32 ATOMIC a_server_hup;
static s32 ATOMIC a_server_usr1;
static s32 ATOMIC a_server_usr2;
/* }}} */

/* client */
static s32 a_client(struct a_pg *pgp);

static s32 a_client__loop(struct a_pg *pgp);
static s32 a_client__req(struct a_pg *pgp);

/* server */
static s32 a_server(struct a_pg *pgp, char const *sockpath);

static s32 a_server__setup(struct a_pg *pgp, char const *sockpath);
static s32 a_server__reset(struct a_pg *pgp);
static s32 a_server__wb_setup(struct a_pg *pgp, boole reset);
static void a_server__wb_reset(struct a_pg_master *pgmp);
static s32 a_server__loop(struct a_pg *pgp);
static void a_server__log_stat(struct a_pg *pgp);
static void a_server__cli_ready(struct a_pg *pgp, u32 client);
static char a_server__cli_req(struct a_pg *pgp, u32 client, uz len);
static boole a_server__cli_lookup(struct a_pg *pgp, struct a_pg_wb *pgwp,
      struct a_pg_wb_cnt *pgwbcp);
static void a_server__on_sig(int sig);

static void a_server__gray_create(struct a_pg *pgp);
static void a_server__gray_load(struct a_pg *pgp);
static void a_server__gray_save(struct a_pg *pgp);
static void a_server__gray_cleanup(struct a_pg *pgp, boole force);
static char a_server__gray_lookup(struct a_pg *pgp, char const *key);

/* conf; _conf__(arg|A|a)() return a negative exit status on error */
static void a_conf_setup(struct a_pg *pgp, BITENUM_IS(u32,a_pg_avo_flags) f);
static void a_conf_finish(struct a_pg *pgp, BITENUM_IS(u32,a_pg_avo_flags) f);
static void a_conf_list_values(struct a_pg *pgp);
static s32 a_conf__arg(struct a_pg *pgp, s32 o, char const *arg,
      BITENUM_IS(u32,a_pg_avo_flags) f);
static s32 a_conf__AB(struct a_pg *pgp, char const *path,
      struct a_pg_wb *pgwbp);
static s32 a_conf__ab(struct a_pg *pgp, char *entry, struct a_pg_wb *pgwbp);
static s32 a_conf__R(struct a_pg *pgp, char const *path,
      BITENUM_IS(u32,a_pg_avo_flags) f);
static s32 a_conf_chdir_store_path(struct a_pg *pgp);
static void a_conf_error(struct a_pg *pgp, char const *msg, ...);

/* normalization; can fail for effectively empty or bogus input!
 * XXX As long as we do not have ip_addr, _ca() uses inet_ntop() that may grow,
 * XXX so ensure .pg_ca has enough room in it! */
static boole a_norm_triple_r(struct a_pg *pgp);
static boole a_norm_triple_s(struct a_pg *pgp);
static boole a_norm_triple_ca(struct a_pg *pgp);
static boole a_norm_triple_cname(struct a_pg *pgp);

/* misc */

/* Unless when running on a terminal, log via this */
static void a_main_log_write(u32 lvl_a_flags, char const *msg, uz len);

static void a_main_usage(FILE *fp);
static boole a_main_dump_doc(up cookie, boole has_arg, char const *sopt,
      char const *lopt, char const *doc);

#if a_DBGIF
static void a_main_oncrash(int signo);
static void a_main_oncrash__dump(up cookie, char const *buf, uz blen);
#endif

/* client {{{ */
static s32
a_client(struct a_pg *pgp){
   struct sockaddr_un soaun;
   u32 erefused;
   s32 rv;
   NYD_IN;

   if(LIKELY(!su_state_has(su_STATE_REPRODUCIBLE))){
      openlog(VAL_NAME, a_OPENLOG_FLAGS, LOG_MAIL);
      su_log_set_write_fun(&a_main_log_write);
   }

   if((rv = a_conf_chdir_store_path(pgp)) != su_EX_OK)
      goto jleave;

   erefused = 0;
   if(0){
jretry_socket:
      close(pgp->pg_clima_fd);
   }

   STRUCT_ZERO(struct sockaddr_un, &soaun);
   soaun.sun_family = AF_UNIX;
   LCTAV(FIELD_SIZEOF(struct sockaddr_un,sun_path
      ) >= sizeof(VAL_NAME) -1 + sizeof(".socket"));
   su_cs_pcopy(su_cs_pcopy(soaun.sun_path, VAL_NAME), ".socket");

   if((pgp->pg_flags & a_PG_F_CLIENT_SHUTDOWN_MODE) &&
         access(soaun.sun_path, F_OK) && su_err_no_by_errno() == su_ERR_NOENT){
      rv = su_EX_TEMPFAIL;
      goto jleave;
   }

   if((pgp->pg_clima_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1){
      su_log_write(su_LOG_CRIT, _("cannot open client/server socket(): %s"),
         su_err_doc(su_err_no_by_errno()));
      rv = su_EX_NOINPUT;
      goto jleave;
   }

   rv = su_EX_IOERR;

   if(bind(pgp->pg_clima_fd, R(struct sockaddr const*,&soaun), sizeof(soaun))){
      /* The server may be running yet */
      if(su_err_no_by_errno() != su_ERR_ADDRINUSE){
         su_log_write(su_LOG_CRIT, _("cannot bind() socket: %s"),
            su_err_doc(-1));
         goto jleave_close;
      }
   }else{
      if(pgp->pg_flags & a_PG_F_CLIENT_SHUTDOWN_MODE){
         su_path_rm(soaun.sun_path);
         rv = su_EX_TEMPFAIL;
         goto jleave_close;
      }

      /* We are responsible for starting up the server! */
      if((rv = a_server(pgp, soaun.sun_path)) != su_EX_OK)
         goto jleave; /* (socket closed there then) */
      goto jretry_socket;
   }

   /* */
   while(connect(pgp->pg_clima_fd, R(struct sockaddr const*,&soaun),
         sizeof(soaun))){
      s32 e;

      if((e = su_err_no_by_errno()) == su_ERR_AGAIN || e == su_ERR_TIMEDOUT)
         su_time_msleep(250, TRU1);
      else{
         if(e == su_ERR_CONNREFUSED && ++erefused < 5)
            goto jretry_socket;
         su_log_write(su_LOG_CRIT, _("cannot connect() socket: %s"),
            su_err_doc(e));
         if(erefused == 5)
            su_log_write(su_LOG_CRIT,
               _("maybe a stale socket?  Please remove %s/%s\n"),
               pgp->pg_store_path, soaun.sun_path);
         goto jleave_close;
      }
   }
   /*erefused = 0;*/

   if(pgp->pg_flags & a_PG_F_CLIENT_SHUTDOWN_MODE)
      goto jshutdown;

   rv = a_client__loop(pgp);
   if(rv < 0){
      /* After connect(2) succeeded once we may not restart from scratch by
       * ourselfs since likely some circumstance beyond our horizon exists
       * XXX if not we need a flag to continue working on current block!
       *goto jretry_socket;*/
      rv = -rv;
   }

jleave_close:
   close(pgp->pg_clima_fd);

jleave:
   NYD_OU;
   return rv;

jshutdown:
   for(;;){
      static char const nulnul[2] = {'\0','\0'};

      if(write(pgp->pg_clima_fd, nulnul, 2) == -1){
         if(su_err_no_by_errno() == su_ERR_INTR)/* xxx why? */
            continue;
         rv = su_EX_IOERR;
         goto jleave_close;
      }
      break;
   }

   /* Blocks until descriptor goes away */
   for(;;){
      if(read(pgp->pg_clima_fd, &soaun, 1) == -1){
         if(su_err_no_by_errno() == su_ERR_INTR)/* xxx why? */
            continue;
      }
      break;
   }

   rv = su_EX_OK;
   goto jleave;
}

static s32
a_client__loop(struct a_pg *pgp){
   char *lnb, *bp, *cp;
   ssize_t lnr;
   boole use_this, seen_any;
   size_t lnl;
   s32 rv;
   NYD_IN;

   /* Ignore signals that may happen */
   signal(SIGCHLD, SIG_IGN);
   signal(SIGHUP, SIG_IGN);
   signal(SIGUSR1, SIG_IGN);
   signal(SIGUSR2, SIG_IGN);

   rv = su_EX_OK;

   /* Main loop: while we receive policy queries, collect the triple(s) we are
    * looking for, ask our server what he thinks about that, act accordingly */
   lnl = 0;
   lnb = NIL;/* XXX lnb+lnl : su_cstr */
jblock:
   bp = pgp->pg_buf;
   pgp->pg_r = pgp->pg_s = pgp->pg_ca = pgp->pg_cname = NIL;
   use_this = TRU1;
   seen_any = FAL0;

   while((lnr = getline(&lnb, &lnl, stdin)) != -1){
      cp = lnb;
      if(lnr > 0){
         if(cp[lnr - 1] == '\n') /* xxx if not this is bogus! */
            cp[--lnr] = '\0';
      }

      /* Until an empty line ends one block, collect data */
      if(lnr == 0){
         /* Query complete?  Normalize data and ask server about triple */
         if(use_this &&
               pgp->pg_r != NIL && pgp->pg_s != NIL && pgp->pg_ca != NIL &&
               pgp->pg_cname != NIL){
            if((rv = a_client__req(pgp)) != su_EX_OK)
               break;
         }else if(seen_any){
            ssize_t srvx;

            srvx = fputs("action=DUNNO\n\n", stdout);
            if(srvx == EOF || fflush(stdout) == EOF){
               rv = su_EX_IOERR;
               break;
            }
         }

         if(pgp->pg_flags & a_PG_F_CLIENT_ONCE_MODE)
            break;
         goto jblock;
      }else{
         /* We assume no WS at BOL and EOL, nor in between key, =, and value.
          * We use the first value shall an attribute appear multiple times;
          * this also aids in bp handling simplicity */
         uz i;
         char *xcp;

         seen_any = TRU1;

         if(!use_this)
            continue;

         if((xcp = su_cs_find_c(cp, '=')) == NIL){
            rv = su_EX_PROTOCOL;
            break;
         }

         i = P2UZ(xcp++ - cp);
         lnr -= i + 1;

         if(lnr == 0)
            continue;

         if(i == sizeof("request") -1 &&
               !su_mem_cmp(cp, "request", sizeof("request") -1)){
            if(lnr != sizeof("smtpd_access_policy") -1 ||
                  su_mem_cmp(xcp, "smtpd_access_policy",
                     sizeof("smtpd_access_policy") -1)){
               /* We are the wrong policy server for this -- log? */
               a_DBG( su_log_write(su_LOG_DEBUG,
                  "client got wrong request=%s (-> DUNNO)", xcp); )
               use_this = FAL0;
               continue;
            }
         }else if(i == sizeof("recipient") -1 &&
               !su_mem_cmp(cp, "recipient", sizeof("recipient") -1)){
            if(pgp->pg_r != NIL)
               continue;
            pgp->pg_r = bp;
         }else if(i == sizeof("sender") -1 &&
               !su_mem_cmp(cp, "sender", sizeof("sender") -1)){
            if(pgp->pg_s != NIL)
               continue;
            pgp->pg_s = bp;
         }else if(i == sizeof("client_address") -1 &&
               !su_mem_cmp(cp, "client_address", sizeof("client_address") -1)){
            if(pgp->pg_ca != NIL)
               continue;
            pgp->pg_ca = bp;
         }else if(i == sizeof("client_name") -1 &&
               !su_mem_cmp(cp, "client_name", sizeof("client_name") -1)){
            if(pgp->pg_cname != NIL)
               continue;
            pgp->pg_cname = bp;
         }else
            continue;

         /* XXX We do have no control over inet_ntop(3) formatting, so in order
          * XXX to be able, reserve INET6_A8N bytes! -> SU ip_addr */
         if(UCMP(z, lnr, >=, P2UZ(&pgp->pg_buf[sizeof(pgp->pg_buf) -
                  Z_ALIGN(INET6_ADDRSTRLEN +1) -1] - bp))){
            a_DBG( su_log_write(su_LOG_DEBUG, "client buffer too small!!!"); )
            use_this = FAL0;
         }else{
            char *top;

            top = (pgp->pg_ca == bp) ? &bp[Z_ALIGN(INET6_ADDRSTRLEN +1)] : NIL;
            bp = &su_cs_pcopy(bp, xcp)[1];
            if(top != NIL){
               ASSERT(bp <= top);
               bp = top;
            }
         }
      }
   }
   if(rv == su_EX_OK && !feof(stdin) &&
         !(pgp->pg_flags & a_PG_F_CLIENT_ONCE_MODE))
      rv = su_EX_IOERR;

   if(lnb != NIL)
      free(lnb);

   NYD_OU;
   return rv;
}

static s32
a_client__req(struct a_pg *pgp){
   struct iovec iov[5], *iovp;
   u8 resp;
   ssize_t srvx;
   s32 rv, c;
   NYD_IN;

   rv = su_EX_OK;

   if(!a_norm_triple_r(pgp))
      goto jex_dunno;
   if(!a_norm_triple_s(pgp))
      goto jex_dunno;
   if(!a_norm_triple_ca(pgp))
      goto jex_dunno;
   if(!a_norm_triple_cname(pgp))
      goto jex_dunno;

   iov[0].iov_len = su_cs_len(iov[0].iov_base = pgp->pg_r) +1;
   iov[1].iov_len = su_cs_len(iov[1].iov_base = pgp->pg_s) +1;
   iov[2].iov_len = su_cs_len(iov[2].iov_base = pgp->pg_ca) +1;
   iov[3].iov_len = su_cs_len(iov[3].iov_base = pgp->pg_cname) +1;
   iov[4].iov_base = UNCONST(char*,su_empty);
   iov[4].iov_len = sizeof(su_empty[0]);

   if(pgp->pg_flags & a_PG_F_VV)
      su_log_write(su_LOG_INFO,
         "asking R=%u<%s> S=%u<%s> CA=%u<%s> CNAME=%u<%s>",
         iov[0].iov_len -1, iov[0].iov_base,
         iov[1].iov_len -1, iov[1].iov_base,
         iov[2].iov_len -1, iov[2].iov_base,
         iov[3].iov_len -1, iov[3].iov_base);

   iovp = iov;
   c = NELEM(iov);
jredo_write:
   srvx = writev(pgp->pg_clima_fd, iovp, c);
   if(srvx == -1){
      if((rv = su_err_no_by_errno()) == su_ERR_INTR)/* XXX no more in client */
         goto jredo_write;
      goto jioerr;
   }else{
      for(; c > 0; ++iovp, --c){
         if(UCMP(z, srvx, <, iovp->iov_len)){
            iovp->iov_base = S(char*,iovp->iov_base) + srvx;
            iovp->iov_len -= S(uz,srvx);
            goto jredo_write;
         }
         srvx -= iovp->iov_len;
      }
      /* We do not care whether OS wrote more than we */
   }

   /* Get server response byte */
jredo_read:
   srvx = read(pgp->pg_clima_fd, &resp, sizeof(resp));
   if(srvx == -1){
      if((rv = su_err_no_by_errno()) == su_ERR_INTR)/* XXX no more in client */
         goto jredo_read;
jioerr:
      su_log_write(su_LOG_ERR, _("I/O error in server communication: %s"),
         su_err_doc(rv));
      /* If the server is gone, then restart cycle from our point of view */
      rv = (rv == su_ERR_PIPE) ? -su_EX_IOERR : su_EX_IOERR;
      goto jex_dunno;
   }else if(UCMP(z, srvx, !=, sizeof(resp))){
      /* This cannot happen here */
      rv = su_ERR_AGAIN;
      goto jioerr;
   }
   rv = su_EX_OK;

   switch(resp){
   case a_PG_ANSWER_DUNNO:
jex_dunno:
      a_DBG( su_log_write(su_LOG_DEBUG, "answer DUNNO"); )
      srvx = fputs("action=DUNNO\n\n", stdout);
      break;
   case a_PG_ANSWER_DEFER_SLEEP:
      su_time_msleep(a_LIMIT_DELAY_SECS * su_TIMESPEC_SEC_MILLIS, TRU1);
      FALLTHRU
   case a_PG_ANSWER_DEFER:
      a_DBG( su_log_write(su_LOG_DEBUG, "answer %s", pgp->pg_defer_msg); )
      srvx = (fprintf(stdout, "action=%s\n\n", pgp->pg_defer_msg) < 0
            ) ? EOF : 0;
      break;
   case a_PG_ANSWER_REJECT:
      a_DBG( su_log_write(su_LOG_DEBUG, "answer REJECT"); )
      srvx = fputs("action=REJECT\n\n", stdout);
      break;
   }

   if(srvx == EOF || fflush(stdout) == EOF)
      rv = su_EX_IOERR;

   NYD_OU;
   return rv;
}
/* }}} */

/* server {{{ */
static s32
a_server(struct a_pg *pgp, char const *sockpath){
   struct a_pg_master pgm;
   s32 rv;
   NYD_IN;

   /* We listen(2) before we fork(2) the server so the client can directly
    * connect(2) on the socket without getting ECONNREFUSED while at the same
    * time acting as a proper synchronization with server startup */
   if(listen(pgp->pg_clima_fd, a_SERVER_LISTEN)){
      su_log_write(su_LOG_CRIT, _("cannot listen() on server socket: %s"),
         su_err_doc(su_err_no_by_errno()));
      rv = su_EX_IOERR;
   }else switch(fork()){
   case -1:
      /* Error */
      su_log_write(su_LOG_CRIT, _("cannot start server process: %s"),
         su_err_doc(su_err_no_by_errno()));
      rv = su_EX_OSERR;
      break;

   default:
      /* Parent (client) */
      rv = su_EX_OK;
      break;

   case 0:
      /* Child (server) */
      /* Close the channels postfix(8)s spawn(8) opened for us; in test mode we
       * need to keep STDERR open, of course */
      close(STDIN_FILENO);
      close(STDOUT_FILENO);

      if(LIKELY(!su_state_has(su_STATE_REPRODUCIBLE))){
         closelog();
         openlog(VAL_NAME "/server", a_OPENLOG_FLAGS, LOG_MAIL);

         close(STDERR_FILENO);

         setsid();
      }else
         su_program = VAL_NAME "/server";

      pgp->pg_master = &pgm;
      if((rv = a_server__setup(pgp, sockpath)) == su_EX_OK)
         rv = a_server__loop(pgp);

      /* C99 */{
         s32 xrv;

         xrv = a_server__reset(pgp);
         if(rv == su_EX_OK)
            rv = xrv;
      }

      su_state_gut(rv == su_EX_OK
         ? su_STATE_GUT_ACT_NORM /*DVL( | su_STATE_GUT_MEM_TRACE )*/
         : su_STATE_GUT_ACT_QUICK);
      exit(rv);
   }

   /* In-client cleanup */
   if(rv != su_EX_OK){
      close(pgp->pg_clima_fd);

      if(!su_path_rm(sockpath))
         su_log_write(su_LOG_CRIT, _("cannot remove socket %s/%s: %s"),
            pgp->pg_store_path, sockpath, su_err_doc(-1));
   }

   NYD_OU;
   return rv;
}

/* __(white_)(setup|reset)?() {{{ */
static s32
a_server__setup(struct a_pg *pgp, char const *sockpath){
   sigset_t ssn, sso;
   s32 rv;
   struct a_pg_master *pgmp;
   NYD_IN;

   sigfillset(&ssn);
   sigprocmask(SIG_BLOCK, &ssn, &sso);

   pgmp = pgp->pg_master;
   STRUCT_ZERO(struct a_pg_master, pgmp);

   pgmp->pgm_sockpath = sockpath;
   pgmp->pgm_cli_fds = su_TALLOC(s32, pgp->pg_server_queue);

   su_cs_dict_create(&pgmp->pgm_white.pgwb_ca, a_PG_WB_CA_FLAGS, NIL);
   su_cs_dict_create(&pgmp->pgm_white.pgwb_cname, a_PG_WB_CNAME_FLAGS, NIL);
   su_cs_dict_create(&pgmp->pgm_black.pgwb_ca, a_PG_WB_CA_FLAGS, NIL);
   su_cs_dict_create(&pgmp->pgm_black.pgwb_cname, a_PG_WB_CNAME_FLAGS, NIL);
   rv = a_server__wb_setup(pgp, FAL0);

   if(rv == su_EX_OK)
      a_server__gray_create(pgp);

   sigprocmask(SIG_SETMASK, &sso, NIL);

   NYD_OU;
   return rv;
}

static s32
a_server__reset(struct a_pg *pgp){
   sigset_t ssn, sso;
   s32 rv;
   struct a_pg_master *pgmp;
   NYD_IN;

   sigfillset(&ssn);
   sigprocmask(SIG_BLOCK, &ssn, &sso);

   close(pgp->pg_clima_fd);

   pgmp = pgp->pg_master;

#if a_DBGIF
   su_cs_dict_gut(&pgmp->pgm_gray);

   a_server__wb_reset(pgmp);
   su_cs_dict_gut(&pgmp->pgm_black.pgwb_ca);
   su_cs_dict_gut(&pgmp->pgm_black.pgwb_cname);
   su_cs_dict_gut(&pgmp->pgm_white.pgwb_ca);
   su_cs_dict_gut(&pgmp->pgm_white.pgwb_cname);

   su_FREE(pgmp->pgm_cli_fds);
#endif

   if(su_path_rm(pgmp->pgm_sockpath))
      rv = su_EX_OK;
   else{
      su_log_write(su_LOG_CRIT, _("cannot remove server socket %s/%s: %s"),
         pgp->pg_store_path, pgmp->pgm_sockpath, su_err_doc(-1));
      rv = su_EX_IOERR;
   }

   closelog();

   sigprocmask(SIG_SETMASK, &sso, NIL);

   NYD_OU;
   return rv;
}

static s32
a_server__wb_setup(struct a_pg *pgp, boole reset){
   struct su_avopt avo;
   s32 rv;
   BITENUM_IS(u32,a_pg_avo_flags) f;
   struct a_pg_master *pgmp;
   NYD_IN;

   pgmp = pgp->pg_master;

   if(reset)
      a_server__wb_reset(pgmp);

   su_cs_dict_add_flags(&pgmp->pgm_white.pgwb_ca, su_CS_DICT_FROZEN);
   su_cs_dict_add_flags(&pgmp->pgm_white.pgwb_cname, su_CS_DICT_FROZEN);
   su_cs_dict_add_flags(&pgmp->pgm_black.pgwb_ca, su_CS_DICT_FROZEN);
   su_cs_dict_add_flags(&pgmp->pgm_black.pgwb_cname, su_CS_DICT_FROZEN);

   if(reset){
      a_conf_setup(pgp, a_PG_AVO_RELOAD);
      f = a_PG_AVO_NONE | a_PG_AVO_RELOAD;
   }else
      f = a_PG_AVO_FULL | a_PG_AVO_RELOAD;
jreavo:
   su_avopt_setup(&avo, pgp->pg_argc, C(char const*const*,pgp->pg_argv),
      a_sopts, a_lopts);

   while((rv = su_avopt_parse(&avo)) != su_AVOPT_STATE_DONE)
      switch(rv){
      /* In long-option order */
      case '4': case '6':
      case 'A': case 'a': case 'F': case 'f':
      case 'c': case 'D': case 'd': case 'p':
         case 'G': case 'g': case 'L': case 'l':
      case 'q': case 't':
      case 'R':
      case 's':
      case 'm':
      case 'v':
         if((rv = a_conf__arg(pgp, rv, avo.avo_current_arg, f)) < 0){
            rv = -rv;
            goto jleave;
         }
         break;
      default:
         break;
      }

   if(reset > FAL0){
      reset = TRUM1;
      a_conf_finish(pgp, a_PG_AVO_RELOAD);
      f = a_PG_AVO_FULL | a_PG_AVO_RELOAD;
      goto jreavo;
   }

   su_cs_dict_balance(&pgmp->pgm_white.pgwb_ca);
   su_cs_dict_balance(&pgmp->pgm_white.pgwb_cname);
   su_cs_dict_balance(&pgmp->pgm_black.pgwb_ca);
   su_cs_dict_balance(&pgmp->pgm_black.pgwb_cname);

   if(reset && (pgp->pg_flags & a_PG_F_VV))
      su_log_write(su_LOG_INFO, "reloaded configuration");

   rv = su_EX_OK;
jleave:
   NYD_OU;
   return rv;
}

static void
a_server__wb_reset(struct a_pg_master *pgmp){
   struct a_pg_srch *pgsp;
   NYD_IN;

   su_cs_dict_clear(&pgmp->pgm_black.pgwb_ca);
   su_cs_dict_clear(&pgmp->pgm_black.pgwb_cname);
   su_cs_dict_clear(&pgmp->pgm_white.pgwb_ca);
   su_cs_dict_clear(&pgmp->pgm_white.pgwb_cname);

   while((pgsp = pgmp->pgm_white.pgwb_srch) != NIL){
      pgmp->pgm_white.pgwb_srch = pgsp->pgs_next;
      su_FREE(pgsp);
   }

   NYD_OU;
}
/* }}} */

static s32
a_server__loop(struct a_pg *pgp){ /* {{{ */
   fd_set rfds;
   sigset_t psigset, psigseto;
   union {struct timespec os; struct su_timespec s; struct a_pg_srch *pgsp;} t;
   u32 ograycnt;
   struct a_pg_master *pgmp;
   s32 rv;
   NYD_IN;

   rv = su_EX_OK;
   a_pgm = S(struct a_pg_master ATOMIC*,pgmp = pgp->pg_master);
   ograycnt = su_cs_dict_count(&pgmp->pgm_gray) + a_PG_GRAY_MIN_LIMIT;
   ASSERT(su_cs_dict_flags(&pgmp->pgm_gray) & su_CS_DICT_FROZEN);

   signal(SIGHUP, &a_server__on_sig);
   signal(SIGTERM, &a_server__on_sig);
   signal(SIGUSR1, &a_server__on_sig);
   signal(SIGUSR2, &a_server__on_sig);

   sigemptyset(&psigset);
   sigaddset(&psigset, SIGHUP);
   sigaddset(&psigset, SIGTERM);
   sigaddset(&psigset, SIGUSR1);
   sigaddset(&psigset, SIGUSR2);
   sigprocmask(SIG_BLOCK, &psigset, &psigseto);

   while(a_pgm != NIL){
      u32 i;
      s32 maxfd, x, e;
      struct timespec *tosp;
      fd_set *rfdsp;

      /* Recreate w/b lists? */
      if(UNLIKELY(a_server_hup)){
         a_server_hup = 0;
         if((rv = a_server__wb_setup(pgp, TRU1)) != su_EX_OK)
            goto jleave;
      }

      if(UNLIKELY(a_server_usr2)){
         a_server_usr2 = 0;
         a_server__gray_save(pgp);
      }

      if(UNLIKELY(a_server_usr1)){
         a_server_usr1 = 0;
         a_server__log_stat(pgp);
      }

      FD_ZERO(rfdsp = &rfds);
      tosp = NIL;
      maxfd = -1;

      for(i = 0; i < pgmp->pgm_cli_no; ++i){
         x = pgmp->pgm_cli_fds[i];
         FD_SET(x, rfdsp);
         maxfd = MAX(maxfd, x);
      }

      if(pgp->pg_flags & a_PG_F_MASTER_ACCEPT_SUSPENDED){
         t.os.tv_sec = 2;
         t.os.tv_nsec = 0;
         tosp = &t.os;
         /* Had accept(2) failure, have no clients: only sleep a bit */
         if(maxfd < 0){
            rfdsp = NIL;
            a_DBG2( su_log_write(su_LOG_DEBUG, "select: suspend,sleep"); )
         }else{
            a_DBG2( su_log_write(su_LOG_DEBUG, "select: suspend,maxfd=%d",
               maxfd); )
         }
      }else if(pgmp->pgm_cli_no < pgp->pg_server_queue){
         if(maxfd < 0 && pgp->pg_server_timeout != 0){
            t.os.tv_sec = pgp->pg_server_timeout;
            if(LIKELY(!su_state_has(su_STATE_REPRODUCIBLE)))
               t.os.tv_sec *= su_TIME_MIN_SECS;
            t.os.tv_nsec = 0;
            tosp = &t.os;
         }

         x = pgp->pg_clima_fd;
         FD_SET(x, rfdsp);
         maxfd = MAX(maxfd, x);

         a_DBG2( su_log_write(su_LOG_DEBUG,
            "select: maxfd=%d timeout=%d (%lu)",
            maxfd, (tosp != NIL), (tosp != NIL ? S(ul,tosp->tv_sec) : 0)); )
      }else{
         a_DBG( su_log_write(su_LOG_DEBUG,
            "select: reached server_queue=%d, no accept-waiting", maxfd); )
      }

      /* Poll descriptors interruptable */
      if((x = pselect(maxfd + 1, rfdsp, NIL, NIL, tosp, &psigseto)) == -1){
         if((e = su_err_no_by_errno()) == su_ERR_INTR)
            continue;
         su_log_write(su_LOG_CRIT, _("select(2) failed: %s"), su_err_doc(e));
         rv = su_EX_IOERR;
         goto jleave;
      }else if(x == 0){
         if(pgp->pg_flags & a_PG_F_MASTER_ACCEPT_SUSPENDED){
            pgp->pg_flags &= ~S(uz,a_PG_F_MASTER_ACCEPT_SUSPENDED);
            a_DBG( su_log_write(su_LOG_DEBUG, "select: un-suspend"); )
            continue;
         }

         ASSERT(pgmp->pgm_cli_no == 0);
         a_DBG( su_log_write(su_LOG_DEBUG, "no clients, timeout: bye!"); )
         break;
      }

      /* ..if no DB was loaded */
      pgmp->pgm_epoch = su_timespec_current(&t.s)->ts_sec;
      if(pgmp->pgm_base_epoch == 0){
         pgmp->pgm_base_epoch = pgmp->pgm_epoch;
         i = 0;
      }else{
         /* XXX-MONO */
         s64 be;

         be = pgmp->pgm_base_epoch;
         if(t.s.ts_sec < be){
            pgmp->pgm_base_epoch = t.s.ts_sec;
            be = 0;
         }else
            be = t.s.ts_sec - be;

         /* Suspension excessed datatype storage / --gc-timeout: clear */
         i = S(u32,be /
               (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));
         if(i >= pgp->gc_timeout){
            a_DBG( su_log_write(su_LOG_DEBUG,
               "select(2) suspension >= gc_timeout: clearing gray DB"); )
            /* xxx The balance() could fail to reallocate the base array!
             * xxx Since we handle insertion failures it is ugly but ..ok */
            su_cs_dict_balance(su_cs_dict_clear(&pgmp->pgm_gray));
            pgmp->pgm_base_epoch = pgmp->pgm_epoch;
            i = 0;
         }
         pgmp->pgm_epoch_min = S(s16,i);
      }

      /* */
      for(i = 0; i < pgmp->pgm_cli_no; ++i)
         if(FD_ISSET(pgmp->pgm_cli_fds[i], &rfds)){
            a_server__cli_ready(pgp, i);
            if(a_pgm == NIL)
               goto jleave;
         }

      if(a_pgm == NIL)
         goto jleave;

      /* */
      if(FD_ISSET(pgp->pg_clima_fd, &rfds)){
         if((x = accept(pgp->pg_clima_fd, NIL, NIL)) == -1){
            /* Just skip this mess for now, and pause accept(2) */
            pgp->pg_flags |= a_PG_F_MASTER_ACCEPT_SUSPENDED;
            a_DBG( su_log_write(su_LOG_DEBUG,
               "accept(2): temporarily suspending: %s", su_err_doc(x)); )
         }else{
            pgmp->pgm_cli_fds[pgmp->pgm_cli_no++] = x;
            a_DBG2( su_log_write(su_LOG_DEBUG, "accepted client=%u fd=%d",
               pgmp->pgm_cli_no, x); )
         }
         /* XXX non-empty accept queue MUST cause more select(2) wakes */
      }

      /* Check for DB cleanup; need to recalculate XXX pgm_epoch_min up2date */
      ASSERT(pgmp->pgm_epoch_min ==
         S(u16,(pgmp->pgm_epoch - pgmp->pgm_base_epoch) /
            (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS)));
      i = S(u16,pgmp->pgm_epoch_min);
      if(i >= pgp->pg_gc_timeout >> 1 || (i >= su_TIME_DAY_MINS &&
            su_cs_dict_count(&pgmp->pgm_gray) >= pgp->pg_limit - (
               pgp->pg_limit >> 2)))
         a_server__gray_cleanup(pgp, FAL0);
      /* Otherwise we may need to allow the dict to grow; it is frozen all the
       * time to move expensive growing out of the way of waiting clients.
       * (Of course some may wait now, too.)  Misuse MIN_LIMIT for that! */
      else if(su_cs_dict_count(&pgmp->pgm_gray) > ograycnt){
         ograycnt = su_cs_dict_count(&pgmp->pgm_gray) + a_PG_GRAY_MIN_LIMIT;
         pgmp->pgm_cleanup_cnt = 0;
         su_cs_dict_add_flags(su_cs_dict_balance(&pgmp->pgm_gray),
            su_CS_DICT_FROZEN);
      }
   }

jleave:
   a_server__gray_save(pgp);

   sigprocmask(SIG_SETMASK, &psigseto, NIL);

   /*
   signal(SIGHUP, SIG_DFL);
   signal(SIGTERM, SIG_DFL);
   signal(SIGUSR1, SIG_DFL);
   signal(SIGUSR2, SIG_DFL);
   */

   NYD_OU;
   return rv;
} /* }}} */

static void
a_server__log_stat(struct a_pg *pgp){ /* {{{ */
   struct a_pg_srch *pgsp;
   ul i1, i2;
   enum su_log_level olvl;
   struct a_pg_master *pgmp;
   NYD2_IN;

   olvl = su_log_get_level();
   su_log_set_level(su_LOG_INFO);

   pgmp = pgp->pg_master;

   for(i1 = 0, pgsp = pgmp->pgm_white.pgwb_srch; pgsp != NIL;
         ++i1, pgsp = pgsp->pgs_next){
   }
   for(i2 = 0, pgsp = pgmp->pgm_black.pgwb_srch; pgsp != NIL;
         ++i2, pgsp = pgsp->pgs_next){
   }

   su_log_write(su_LOG_INFO,
      _("clients %lu of %lu\n"
        "white: CA %lu/%lu (fuzzy %lu), CNAME %lu/%lu\n"
        "-hits: CA exact %lu / fuzzy %lu, CNAME exact %lu / fuzzy %lu\n"
        "black: CA %lu/%lu (fuzzy %lu), CNAME %lu/%lu\n"
        "-hits: CA exact %lu / fuzzy %lu, CNAME exact %lu / fuzzy %lu\n"
        "gray: %lu/%lu, gc_cnt %lu; epoch: %lu, now %lu: %lu\n"
        "-hits: new %lu, defer %lu, pass %lu"),
      S(ul,pgmp->pgm_cli_no), S(ul,pgp->pg_server_queue),
      S(ul,su_cs_dict_count(&pgmp->pgm_white.pgwb_ca)),
            S(ul,su_cs_dict_size(&pgmp->pgm_white.pgwb_ca)), i1,
         S(ul,su_cs_dict_count(&pgmp->pgm_white.pgwb_cname)),
            S(ul,su_cs_dict_size(&pgmp->pgm_white.pgwb_cname)),
      pgmp->pgm_cnt_white.pgwbc_ca, pgmp->pgm_cnt_white.pgwbc_ca_fuzzy,
         pgmp->pgm_cnt_white.pgwbc_cname,
            pgmp->pgm_cnt_white.pgwbc_cname_fuzzy,
      S(ul,su_cs_dict_count(&pgmp->pgm_black.pgwb_ca)),
            S(ul,su_cs_dict_size(&pgmp->pgm_black.pgwb_ca)), i2,
         S(ul,su_cs_dict_count(&pgmp->pgm_black.pgwb_cname)),
            S(ul,su_cs_dict_size(&pgmp->pgm_black.pgwb_cname)),
      pgmp->pgm_cnt_black.pgwbc_ca, pgmp->pgm_cnt_black.pgwbc_ca_fuzzy,
         pgmp->pgm_cnt_black.pgwbc_cname,
            pgmp->pgm_cnt_black.pgwbc_cname_fuzzy,
      S(ul,su_cs_dict_count(&pgmp->pgm_gray)),
         S(ul,su_cs_dict_size(&pgmp->pgm_gray)),
         S(ul,pgmp->pgm_cleanup_cnt),
         S(ul,pgmp->pgm_base_epoch),
         S(ul,pgmp->pgm_epoch), S(ul,pgmp->pgm_epoch_min),
      pgmp->pgm_cnt_gray_new, pgmp->pgm_cnt_gray_defer,
         pgmp->pgm_cnt_gray_pass
      );

#if DVLDBGOR(1, 0)
   a_DBG2(
      su_log_write(su_LOG_INFO, "WHITE CA:");
      su_cs_dict_statistics(&pgmp->pgm_white.pgwb_ca);
      su_log_write(su_LOG_INFO, "WHITE CNAME:");
      su_cs_dict_statistics(&pgmp->pgm_white.pgwb_cname);
      su_log_write(su_LOG_INFO, "BLACK CA:");
      su_cs_dict_statistics(&pgmp->pgm_black.pgwb_ca);
      su_log_write(su_LOG_INFO, "BLACK CNAME:");
      su_cs_dict_statistics(&pgmp->pgm_black.pgwb_cname);
      su_log_write(su_LOG_INFO, "GRAY:");
      su_cs_dict_statistics(&pgmp->pgm_gray);
   )
#endif

   su_log_set_level(olvl);

   NYD2_OU;
} /* }}} */

static void
a_server__cli_ready(struct a_pg *pgp, u32 client){ /* {{{ */
   /* xxx should use FIONREAD nonetheless, or O_NONBLOCK.
    * xxx (On the other hand .. clear postfix protocol etc etc) */
   ssize_t all, osx;
   uz rem;
   struct a_pg_master *pgmp;
   NYD_IN;

   pgmp = pgp->pg_master;
   rem = sizeof(pgp->pg_buf);
   all = 0;
jredo:
   osx = read(pgmp->pgm_cli_fds[client], &pgp->pg_buf[S(uz,all)], rem);
   if(osx == -1){
      if(su_err_no_by_errno() == su_ERR_INTR)
         goto jredo;

jcli_err:
      su_log_write(su_LOG_CRIT,
         _("client fd=%d read() failed, dropping client: %s"),
         pgmp->pgm_cli_fds[client], su_err_doc(-1));
      close(pgmp->pgm_cli_fds[client]);
      goto jcli_del;
   }else if(osx == 0){
      a_DBG2( su_log_write(su_LOG_DEBUG,
         "client fd=%d disconnected, %u remain",
         pgmp->pgm_cli_fds[client], pgmp->pgm_cli_no - 1); )
jcli_del:
      close(pgmp->pgm_cli_fds[client]);
      /* _copy() */
      su_mem_move(&pgmp->pgm_cli_fds[client], &pgmp->pgm_cli_fds[client + 1],
         (--pgmp->pgm_cli_no - client) * sizeof(pgmp->pgm_cli_fds[0]));
   }else{
      all += osx;
      rem -= S(uz,osx); /* (always sufficiently spaced */
      if(all < 2 ||
            pgp->pg_buf[all - 1] != '\0' || pgp->pg_buf[all - 2] != '\0')
         goto jredo;

      /* Is it a forced SHUTDOWN request? */
      if(all == 2){
         a_DBG2( su_log_write(su_LOG_DEBUG, "client fd=%d shutdown request",
            pgmp->pgm_cli_fds[client]); )
         a_pgm = NIL;
         goto jleave;
      }

      pgp->pg_buf[0] = a_server__cli_req(pgp, client, S(uz,all));

      for(;;){
         if(write(pgmp->pgm_cli_fds[client], pgp->pg_buf,
               sizeof(pgp->pg_buf[0])) == -1){
            if(su_err_no_by_errno() == su_ERR_INTR)
               continue;
            goto jcli_err;
         }
         break;
      }
   }

jleave:
   NYD_OU;
} /* }}} */

static char
a_server__cli_req(struct a_pg *pgp, u32 client, uz len){ /* {{{ */
   char rv;
   u32 r_l, s_l, ca_l, cn_l;
   struct a_pg_master *pgmp;
   NYD_IN;
   ASSERT(len > 0);
   ASSERT(pgp->pg_buf[len -1] == '\0');
   UNUSED(client);
   UNUSED(len);

   pgmp = pgp->pg_master;

   /* C99 */{
      char *cp;

      cp = pgp->pg_buf;

      pgp->pg_r = cp;
      for(r_l = 0; *cp != '\0'; ++r_l, ++cp){
         ASSERT(cp != &pgp->pg_buf[len -1]);
      }

      pgp->pg_s = ++cp;
      for(s_l = 0; *cp != '\0'; ++s_l, ++cp){
         ASSERT(cp != &pgp->pg_buf[len -1]);
      }

      pgp->pg_ca = ++cp;
      for(ca_l = 0; *cp != '\0'; ++ca_l, ++cp){
         ASSERT(cp != &pgp->pg_buf[len -1]);
      }

      pgp->pg_cname = ++cp;
      for(cn_l = 0; *cp != '\0'; ++cn_l, ++cp){
         ASSERT(cp != &pgp->pg_buf[len -1]);
      }

      ASSERT(cp == &pgp->pg_buf[len -2]);
   }

   if(pgp->pg_flags & a_PG_F_VV)
      su_log_write(su_LOG_INFO,
         "client fd=%d bytes=%lu R=%u<%s> S=%u<%s> CA=%u<%s> CNAME=%u<%s>",
         pgmp->pgm_cli_fds[client], S(ul,len), r_l, pgp->pg_r, s_l, pgp->pg_s,
         ca_l, pgp->pg_ca, cn_l, pgp->pg_cname);

   rv = a_PG_ANSWER_DUNNO;
   if(a_server__cli_lookup(pgp, &pgmp->pgm_white, &pgmp->pgm_cnt_white))
      goto jleave;

   rv = a_PG_ANSWER_REJECT;
   if(a_server__cli_lookup(pgp, &pgmp->pgm_black, &pgmp->pgm_cnt_black))
      goto jleave;

   pgp->pg_s[-1] = '/';
   pgp->pg_ca[-1] = '/';
   rv = a_server__gray_lookup(pgp, pgp->pg_buf);

jleave:
   NYD_OU;
   return rv;
} /* }}} */

static boole
a_server__cli_lookup(struct a_pg *pgp, struct a_pg_wb *pgwbp, /* {{{ */
      struct a_pg_wb_cnt *pgwbcp){
   char const *me;
   boole rv;
   NYD_IN;

   rv = TRU1;
   me = (pgwbp == &pgp->pg_master->pgm_white) ? "allow" : "block";

   /* */
   if(su_cs_dict_has_key(&pgwbp->pgwb_ca, pgp->pg_ca)){
      ++pgwbcp->pgwbc_ca;
      if(pgp->pg_flags & a_PG_F_V)
         su_log_write(su_LOG_INFO, "### %s address: %s", me, pgp->pg_ca);
      goto jleave;
   }

   /* C99 */{
      char const *cp;
      boole first;

      for(first = TRU1, cp = pgp->pg_cname;; first = FAL0){
         union {void *p; up v;} u;

         if((u.p = su_cs_dict_lookup(&pgwbp->pgwb_cname, cp)) != NIL &&
               (first || u.v != TRU1)){
            if(first)
              ++pgwbcp->pgwbc_cname;
            else
              ++pgwbcp->pgwbc_cname_fuzzy;
            if(pgp->pg_flags & a_PG_F_V)
               su_log_write(su_LOG_INFO, "### %s %sdomain: %s",
                  me, (first ? su_empty : _("wildcard ")), cp);
            goto jleave;
         }

         if((cp = su_cs_find_c(cp, '.')) == NIL || *++cp == '\0')
            break;
      }
   }

   /* Fuzzy IP search */{
      union a_pg_srch_ip c_sip;
      struct a_pg_srch *pgsp;
      u32 *c_ip;
      int c_af;

      /* xxx Client had this already, simply binary pass it, too? */
      c_af = (su_cs_find_c(pgp->pg_ca, ':') != NIL) ? AF_INET6 : AF_INET;
      if(inet_pton(c_af, pgp->pg_ca, (c_af == AF_INET ? S(void*,&c_sip.v4)
               : S(void*,&c_sip.v6))) != 1){
         su_log_write(su_LOG_CRIT, _("Cannot re-parse an already "
            "prepared IP address?: "), pgp->pg_ca);
         goto jleave0;
      }
      c_ip = (c_af == AF_INET) ? R(u32*,&c_sip.v4.s_addr)
            : R(u32*,c_sip.v6.s6_addr);

      for(pgsp = pgwbp->pgwb_srch; pgsp != NIL; pgsp = pgsp->pgs_next){
         u32 *ip, max, m, xm, i;

         if(c_af == AF_INET){
            if(!(pgsp->pgs_flags & a_PG_SRCH_IPV4))
               continue;
            ip = R(u32*,&pgsp->pgs_ip.v4.s_addr);
            max = 1;
         }else if(!(pgsp->pgs_flags & a_PG_SRCH_IPV6))
            continue;
         else{
            ip = S(u32*,R(void*,pgsp->pgs_ip.v6.s6_addr));
            max = 4;
         }

         for(m = pgsp->pgs_mask, i = 0;;){
            /* If mask worked, quickshot */
            if(m == 0)
               goto jleave;

            xm = 0xFFFFFFFFu;
            if((i + 1) << 5 >= m){
               if((m &= 31))
                  xm <<= (32 - m);
               m = 0;
            }
            xm = su_boswap_net_32(xm);

            ASSERT((ip[i] & xm) == ip[i]);
            if(ip[i] != (c_ip[i] & xm))
               break;

            if(++i == max){
               ++pgwbcp->pgwbc_ca_fuzzy;
               if(pgp->pg_flags & a_PG_F_V)
                  su_log_write(su_LOG_INFO, "### %s wildcard address: %s",
                     me, pgp->pg_ca);
               goto jleave;
            }
         }
      }
   }

jleave0:
   rv = FAL0;
jleave:
   NYD_OU;
   return rv;
} /* }}} */

static void
a_server__on_sig(int sig){
   if(sig == SIGHUP)
      a_server_hup = 1;
   else if(sig == SIGTERM)
      a_pgm = NIL;
   else if(sig == SIGUSR1)
      a_server_usr1 = 1;
   else if(sig == SIGUSR2)
      a_server_usr2 = 1;
}

/* gray {{{ */
static void
a_server__gray_create(struct a_pg *pgp){
   struct a_pg_master *pgmp;
   NYD_IN;

   pgmp = pgp->pg_master;

   /* Perform the initial allocation without _ERR_PASS so that we panic if we
    * cannot create it, then set _ERR_PASS to handle (ignore) errors */
   su_cs_dict_resize(su_cs_dict_set_min_size(su_cs_dict_set_treshold_shift(
         su_cs_dict_create(&pgmp->pgm_gray, (a_PG_GRAY_FLAGS |
            su_CS_DICT_FROZEN), NIL), a_PG_GRAY_TS), a_PG_GRAY_MIN_LIMIT), 1);

   a_server__gray_load(pgp);

   /* Finally enable automatic memory management, balance as necessary */
   su_cs_dict_add_flags(&pgmp->pgm_gray, su_CS_DICT_ERR_PASS);
   if(su_cs_dict_count(&pgmp->pgm_gray) > a_PG_GRAY_MIN_LIMIT)
      su_cs_dict_add_flags(su_cs_dict_balance(&pgmp->pgm_gray),
         su_CS_DICT_FROZEN);

   NYD_OU;
}

static void
a_server__gray_load(struct a_pg *pgp){ /* {{{ */
   char path[PATH_MAX], *base;
   struct su_timespec ts;
   struct stat st;
   s16 min;
   s32 i;
   union {void *v; char *c;} p;
   void *mbase;
   NYD_IN;

   su_cs_pcopy(su_cs_pcopy(path, pgp->pg_store_path), "/" a_PG_GRAY_DB_NAME);

   /* Obtain a memory map on the DB storage */
   mbase = NIL;

   i = open(path, (O_RDONLY
#ifdef O_NOFOLLOW
         | O_NOFOLLOW
#endif
#ifdef O_NOCTTY
         | O_NOCTTY /* hmm */
#endif
         ));
   if(i == -1){
      if(su_err_no_by_errno() != su_ERR_NOENT)
         su_log_write(su_LOG_ERR, _("cannot load gray DB storage: %s: %s"),
            path, su_err_doc(-1));
      goto jleave;
   }

   p.c = NIL;

   if(fstat(i, &st) == -1)
      su_log_write(su_LOG_ERR, _("cannot fstat(2) gray DB storage: %s: %s"),
         path, su_err_doc(su_err_no_by_errno()));
   else if((p.v = mmap(NIL, S(uz,st.st_size), PROT_READ, MAP_SHARED, i, 0)) == NIL)
      su_log_write(su_LOG_ERR, _("cannot mmap(2) gray DB storage: %s: %s"),
         path, su_err_doc(su_err_no_by_errno()));

   close(i);

   if((mbase = p.v) == NIL)
      goto jleave;

   pgp->pg_master->pgm_base_epoch = su_timespec_current(&ts)->ts_sec;

   /* (Saving DB stops before S32_MAX bytes) */
   for(min = S16_MAX, base = p.c, i = MIN(S32_MAX, S(s32,st.st_size));
         i > 0; ++p.c, --i){
      s64 ibuf;
      union {u32 f; uz z;} u;

      /* Complete a line first */
      if(*p.c != '\n')
         continue;

      if(&base[1] == p.c)
         goto jerr;

      u.f = su_idec(&ibuf, base, P2UZ(p.c - base), 10, 0,
            C(char const**,&base));
      if((u.f & su_IDEC_STATE_EMASK) || UCMP(64, ibuf, >, U32_MAX))
         goto jerr;

      /* The first line is only base epoch */
      if(min == S16_MAX){
         if(*base != '\n')
            goto jerr;

         min = S(s16,(pgp->pg_master->pgm_base_epoch - ibuf) /
               (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));

         if(/*UCMP(16, min, >=, S16_MAX) ||*/ min >= pgp->pg_gc_timeout){
            if(a_DBGIF || (pgp->pg_flags & a_PG_F_V))
               su_log_write(su_LOG_INFO,
                  _("gray DB content timed out, skipping: %s"), path);
            goto jleave;
         }
      }else if(*base++ != ' ')
         goto jerr;
      else if((u.z = P2UZ(p.c - base)) >= a_BUF_SIZE)
         goto jerr;
      else{
         char key[a_BUF_SIZE];
         s16 nmin;
         up d;

         su_mem_copy(key, base, u.z);
         key[u.z] = '\0';

         d = S(up,ibuf);
         nmin = S(s16,d & U16_MAX);
         nmin -= min;

         if(nmin < 0){
            nmin = -nmin;
            if(nmin >= pgp->pg_gc_timeout)
               goto jskip;
            if(!(d & 0x80000000)){
               if(nmin > pgp->pg_delay_max)
                  goto jskip;
            }
            nmin = -nmin;
         }

         d = (d & 0xFFFF0000u) | S(u16,nmin);
         if(su_cs_dict_insert(&pgp->pg_master->pgm_gray, key, R(void*,d)
               ) > su_ERR_NONE){
            su_log_write(su_LOG_ERR,
               _("out of memory while reading gray DB, skipping rest of: %s"),
               path);
            goto jleave;
         }

         a_DBG( su_log_write(su_LOG_DEBUG,
            "load: acc=%d, count=%d min=%hd: %s",
            !!(d & 0x80000000), S(ul,(d & 0x7FFF0000) >> 16), nmin, key); )
      }

jskip:
      base = &p.c[1];
   }

   if(base != p.c)
jerr:
      su_log_write(su_LOG_WARN, _("DB storage had corruptions: %s"), path);

   if(a_DBGIF || (pgp->pg_flags & a_PG_F_V)){
      struct su_timespec ts2;

      su_timespec_sub(su_timespec_current(&ts2), &ts);
      su_log_write(su_LOG_INFO,
         _("loaded %lu gray DB entries in %lu:%lu (sec:nano) from %s"),
         S(ul,su_cs_dict_count(&pgp->pg_master->pgm_gray)),
         S(ul,ts2.ts_sec), S(ul,ts2.ts_nano), path);
   }

jleave:
   if(mbase != NIL)
      munmap(mbase, S(uz,st.st_size));

   NYD_OU;
   return;
} /* }}} */

static void
a_server__gray_save(struct a_pg *pgp){ /* {{{ */
   char path[PATH_MAX], *cp;
   /* Signals are blocked */
   struct su_timespec ts;
   struct su_cs_dict_view dv;
   s16 min;
   uz cnt, xlen;
   s32 fd;
   NYD_IN;

   su_cs_pcopy(su_cs_pcopy(path, pgp->pg_store_path), "/" a_PG_GRAY_DB_NAME);

   fd = open(path, (O_WRONLY | O_CREAT | O_TRUNC
#ifdef O_NOFOLLOW
         | O_NOFOLLOW
#endif
#ifdef O_NOCTTY
         | O_NOCTTY /* hmm, II. */
#endif
         ), S_IRUSR | S_IWUSR);
   if(fd == -1){
      su_log_write(su_LOG_CRIT, _("cannot create gray DB storage: %s: %s"),
         path, su_err_doc(su_err_no_by_errno()));
      goto jleave;
   }

   su_timespec_current(&ts);
   cnt = 0;

   cp = su_ienc_s64(pgp->pg_buf, ts.ts_sec, 10);
   xlen = su_cs_len(cp);
   cp[xlen++] = '\n';
   if(UCMP(z, write(fd, cp, xlen), !=, xlen))
      goto jerr;

   /* XXX-MONO */
   /* C99 */{
      s64 be;

      be = pgp->pg_master->pgm_base_epoch;
      if(ts.ts_sec < be){
         pgp->pg_master->pgm_base_epoch = be;
         be = 0;
      }else
         be = ts.ts_sec - be;
      min = S(s16,be /
            (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));
   }

   su_CS_DICT_FOREACH(&pgp->pg_master->pgm_gray, &dv){
      /* (see cleanup() for comments) */
      uz i, j;
      s16 nmin;
      up d;

      d = R(up,su_cs_dict_view_data(&dv));
      nmin = S(s16,d & U16_MAX);
      nmin -= min;

      if(nmin < 0){
         nmin = -nmin;
         if(nmin >= pgp->pg_gc_timeout)
            continue;
         if(!(d & 0x80000000)){
            if(nmin >= pgp->pg_delay_max)
               continue;
         }
         nmin = -nmin;
      }

      d = (d & 0xFFFF0000u) | S(u16,nmin);

      cp = su_ienc_up(pgp->pg_buf, d, 10);
      i = su_cs_len(cp);
      cp[i++] = ' ';
      j = su_cs_len(su_cs_dict_view_key(&dv));
      su_mem_copy(&cp[i], su_cs_dict_view_key(&dv), j);
      i += j;
      cp[i++] = '\n';

      if(UNLIKELY(S(uz,S32_MAX) - i < xlen)){
         su_log_write(su_LOG_WARN,
            _("gray DB too large, truncating near 2GB size: %s"), path);
         break;
      }

      if(UCMP(z, write(fd, cp, i), !=, i))
         goto jerr;
      xlen += i;
      ++cnt;

      a_DBG( su_log_write(su_LOG_DEBUG,
         "save: acc=%d, count=%d nmin=%hd: %s",
         !!(d & 0x80000000), S(ul,(d & 0x7FFF0000) >> 16), nmin,
         su_cs_dict_view_key(&dv)); )
   }

jclose:
   fsync(fd);
   close(fd);

   if(a_DBGIF || (pgp->pg_flags & a_PG_F_V)){
      struct su_timespec ts2;

      su_timespec_sub(su_timespec_current(&ts2), &ts);
      su_log_write(su_LOG_INFO,
         _("saved %lu gray DB entries in %lu:%lu (sec:nano) to %s"),
         S(ul,cnt), S(ul,ts2.ts_sec), S(ul,ts2.ts_nano), path);
   }

jleave:
   NYD_OU;
   return;

jerr:
   su_log_write(su_LOG_CRIT, _("cannot write gray DB storage: %s: %s"),
      path, su_err_doc(su_err_no_by_errno()));

   if(!su_path_rm(path))
      su_log_write(su_LOG_CRIT,
         _("cannot even unlink corrupted gray DB storage: %s: %s"),
         path, su_err_doc(-1));
   goto jclose;
} /* }}} */

static void
a_server__gray_cleanup(struct a_pg *pgp, boole force){ /* {{{ */
   struct su_timespec ts;
   struct su_cs_dict_view dv;
   struct a_pg_master *pgmp;
   u32 c_75, c_88;
   u16 t, t_75, t_88;
   boole gc_any;
   NYD_IN;

   gc_any = FAL0;
   t = pgp->pg_gc_timeout;

   /* We may need to cleanup more, check some tresholds */
   UNINIT(c_88 = c_75, 0);
   UNINIT(t_88 = t_75, 0);
   if(force){
      force = TRUM1;
      c_88 = c_75 = 0;
      t_88 = t_75 = t;
      t_75 -= t >> 2;
      t_88 -= t >> 3;
   }

   pgmp = pgp->pg_master;

   /* XXX-MONO */
   /* C99 */{
      s64 be;

      be = pgmp->pgm_base_epoch;
      pgmp->pgm_base_epoch =
      pgmp->pgm_epoch = su_timespec_current(&ts)->ts_sec;
      if(ts.ts_sec < be)
         be = 0;
      else
         be = ts.ts_sec - be;
      pgmp->pgm_epoch_min = S(s16,be /
            (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));
   }

   a_DBG( su_log_write(su_LOG_DEBUG, "gc: start%s epoch=%lu min=%d",
      (force ? _(" in force mode") : su_empty),
      S(ul,pgmp->pgm_epoch), pgmp->pgm_epoch_min); )

   ASSERT(su_cs_dict_flags(&pgmp->pgm_gray) & su_CS_DICT_FROZEN);
jredo:
   su_cs_dict_view_setup(&dv, &pgmp->pgm_gray);
   for(su_cs_dict_view_begin(&dv); su_cs_dict_view_is_valid(&dv);){
      s16 nmin;
      up d;

      d = R(up,su_cs_dict_view_data(&dv));
      nmin = S(s16,d & U16_MAX);
      nmin -= pgmp->pgm_epoch_min;

      if(nmin < 0){
         nmin = -nmin;

         /* GC garbage */
         if(nmin >= t){
            a_DBG( su_log_write(su_LOG_DEBUG,
               "gc: del acc >=gc-timeout (force=%d) min=%d: %s",
               -nmin, (force > 0), su_cs_dict_view_key(&dv)); )
            goto jdel;
         }

         /* Not yet accepted entries.. */
         if(!(d & 0x80000000)){
            /* GC things which would count as "new" */
            if(nmin >= pgp->pg_delay_max){
               a_DBG( su_log_write(su_LOG_DEBUG,
                  "gc: del non-acc >=delay-max min=%d: %s",
                  -nmin, su_cs_dict_view_key(&dv)); )
               goto jdel;
            }
         }

         if(force < 0){
            if(nmin >= t_88)
               ++c_88;
            else if(nmin >= t_75)
               ++c_75;
         }

         nmin = -nmin;
      }

      a_DBG( su_log_write(su_LOG_DEBUG,
         "gc: keep: acc=%d, min=%hd: %s",
         !!(d & 0x80000000), nmin, su_cs_dict_view_key(&dv)); )
      d = (d & 0xFFFF0000u) | S(u16,nmin);
      su_cs_dict_view_set_data(&dv, R(void*,d));
      su_cs_dict_view_next(&dv);
      continue;
jdel:
      su_cs_dict_view_remove(&dv);
      gc_any = TRU1;
   }

   /* In force mode try to give back more, if necessary */
   if(force < 0){
      u32 l, c;

      l = pgp->pg_limit - (pgp->pg_limit >> 2);
      c = su_cs_dict_count(&pgmp->pgm_gray);

      if(c > l){
         if(c - c_88 <= l)
            t = t_88;
         else if(c - c_75 <= l)
            t = t_75;
         else
            t >>= 1;
         /* else we cannot help it, really */
         a_DBG( su_log_write(su_LOG_DEBUG,
            "gc: forced and still too large, restart with %s gc-timeout",
            (t == t_88 ? "88%" : (t == t_75) ? "75%" : "50%")); )
         force = TRU1;
         goto jredo;
      }
   }

   if(pgmp->pgm_cleanup_cnt < S16_MAX)
      ++pgmp->pgm_cleanup_cnt;

   /* Do not balance when force mode is on, client is waiting */
   if(gc_any){
      gc_any = FAL0; /* -> "was balanced" */
      if(pgmp->pgm_cleanup_cnt >= pgp->pg_gc_rebalance &&
            pgp->pg_gc_rebalance != 0 && !force){
         su_cs_dict_add_flags(su_cs_dict_balance(&pgmp->pgm_gray),
            su_CS_DICT_FROZEN);
         a_DBG( su_log_write(su_LOG_DEBUG,
            "gc: rebalance after %u: count=%u, new size=%u",
            pgmp->pgm_cleanup_cnt, su_cs_dict_count(&pgmp->pgm_gray),
            su_cs_dict_size(&pgmp->pgm_gray)); )
         pgmp->pgm_cleanup_cnt = 0;
         gc_any = TRU1;
      }
   }

   if(a_DBGIF || (pgp->pg_flags & a_PG_F_V)){
      struct su_timespec ts2;

      su_timespec_sub(su_timespec_current(&ts2), &ts);
      su_log_write(su_LOG_INFO,
         _("gray DB: count=%u: %sGC took %lu:%lu (sec:nano), balanced: %d"),
         su_cs_dict_count(&pgmp->pgm_gray),
         (force == TRU1 ? _("two round ") : su_empty),
         S(ul,ts2.ts_sec), S(ul,ts2.ts_nano), gc_any);
   }

   NYD_OU;
} /* }}} */

static char
a_server__gray_lookup(struct a_pg *pgp, char const *key){ /* {{{ */
   struct su_cs_dict_view dv;
   s16 min, xmin;
   up d;
   u16 cnt;
   struct a_pg_master *pgmp;
   char rv;
   NYD_IN;

   rv = a_PG_ANSWER_DUNNO;
   pgmp = pgp->pg_master;
   cnt = 0;

   /* Key already known, .. or can be added? */
   if(!su_cs_dict_view_find(su_cs_dict_view_setup(&dv, &pgmp->pgm_gray), key)){
      u32 i;

jretry_nent:
      i = su_cs_dict_count(&pgmp->pgm_gray);
      rv = (pgp->pg_limit_delay != 0 && i >= pgp->pg_limit_delay)
            ? a_PG_ANSWER_DEFER_SLEEP : a_PG_ANSWER_DEFER;

      /* New entry may be disallowed */
      if(i < pgp->pg_limit){
         d = (pgp->pg_count == 0) ? 0x80000000u : 0;
         goto jgray_set;
      }

      /* We ran against this wall, try a cleanup if allowed */
      if(UCMP(16, pgmp->pgm_epoch_min, >=, a_DB_CLEANUP_MIN_DELAY)){
         a_server__gray_cleanup(pgp, TRU1);
         goto jretry_nent;
      }

      if(!(pgp->pg_flags & a_PG_F_MASTER_LIMIT_EXCESS_LOGGED)){
         pgp->pg_flags |= a_PG_F_MASTER_LIMIT_EXCESS_LOGGED;
         /*if(pgp->pg_flags & a_PG_F_V)*/
            su_log_write(su_LOG_WARN,
               _("Reached --limit=%lu, excess not handled; "
                  "condition is logged once only"),
               S(ul,pgp->pg_limit));
      }

      /* XXX Make limit excess return configurable? REJECT?? */
      rv = a_PG_ANSWER_DUNNO;
      goto jleave;
   }

   /* Key is known */
   d = R(up,su_cs_dict_view_data(&dv));

   /* If yet accepted, update it quick */
   if(d & 0x80000000u){
      a_DBG( su_log_write(su_LOG_DEBUG, "gray up quick: %s", key); )
      ASSERT(rv == a_PG_ANSWER_DUNNO);
      ASSERT(cnt == 0);
      goto jgray_set;
   }

   min = S(s16,d & U16_MAX);
   cnt = S(u16,(d >> 16) & S16_MAX) + 1;

   xmin = pgmp->pgm_epoch_min - min;

   /* Totally ignore it if not enough time passed */
   if(xmin < (pgp->pg_delay_min *
         (pgp->pg_flags & a_PG_F_MASTER_DELAY_PROGRESSIVE ? cnt : 1))){
      a_DBG( su_log_write(su_LOG_DEBUG, "gray too soon: %s (%lu,%lu,%lu)",
         key, S(ul,min), S(ul,pgmp->pgm_epoch_min), S(ul,xmin)); )
      --cnt; /* (Logging) */
      rv = a_PG_ANSWER_DEFER;
      goto jleave;
   }

   /* If too much time passed, reset: this is a new thing! */
   if(xmin > pgp->pg_delay_max){
      a_DBG( su_log_write(su_LOG_DEBUG, "gray too late: %s (%lu,%lu,%lu)",
         key, S(ul,min), S(ul,pgmp->pgm_epoch_min), S(ul,xmin)); )
      rv = a_PG_ANSWER_DEFER;
      cnt = 0;
   }
   /* If seen often enough wave through! */
   else if(cnt >= pgp->pg_count){
      a_DBG( su_log_write(su_LOG_DEBUG, "gray ok-to-go (%lu): %s",
         S(ul,cnt), key); )
      ASSERT(rv == a_PG_ANSWER_DUNNO);
      cnt = 0; /* (Logging: does no longer matter) */
      d = 0x80000000u;
   }else{
      rv = a_PG_ANSWER_DEFER;
      a_DBG( su_log_write(su_LOG_DEBUG, "gray inc count=%lu: %s",
         S(ul,cnt), key); )
   }

jgray_set:
   d = (d & 0x80000000u) | (S(up,cnt) << 16) | S(u16,pgmp->pgm_epoch_min);
   if(su_cs_dict_view_is_valid(&dv))
      su_cs_dict_view_set_data(&dv, R(void*,d));
   else{
      ++pgmp->pgm_cnt_gray_new;
      a_DBG( su_log_write(su_LOG_DEBUG, "gray new entry: %s", key); )
      ASSERT(rv != a_PG_ANSWER_DUNNO);

      /* Need to handle memory failures */
      while(su_cs_dict_insert(&pgmp->pgm_gray, key, R(void*,d)) > su_ERR_NONE){
         /* We ran against this wall, try a cleanup if allowed */
         if(UCMP(16, pgmp->pgm_epoch_min, >=, a_DB_CLEANUP_MIN_DELAY)){
            a_server__gray_cleanup(pgp, TRU1);
            continue;
         }

         /* XXX What if new pg_limit is ... 0 ? */
         pgp->pg_limit = su_cs_dict_count(&pgmp->pgm_gray);
         if(pgp->pg_limit_delay != 0)
            pgp->pg_limit_delay = pgp->pg_limit - (pgp->pg_limit >> 3);

         if(!(pgp->pg_flags & a_PG_F_MASTER_NOMEM_LOGGED)){
            pgp->pg_flags |= a_PG_F_MASTER_NOMEM_LOGGED;
            /*if(pgp->pg_flags & a_PG_F_V)*/
               su_log_write(su_LOG_WARN,
                  _("out-of-memory, reduced limit to %lu; "
                     "condition is logged once only"),
                  S(ul,pgp->pg_limit));
         }

         /* XXX Make limit excess return configurable? REJECT?? */
         rv = a_PG_ANSWER_DUNNO;
         break;
      }

      if(pgp->pg_count == 0)
         rv = a_PG_ANSWER_DUNNO;
   }

jleave:
   if(rv != a_PG_ANSWER_DUNNO)
      ++pgmp->pgm_cnt_gray_defer;
   else
      ++pgmp->pgm_cnt_gray_pass;
   if(pgp->pg_flags & a_PG_F_V)
      su_log_write(su_LOG_INFO, "### gray (defer=%d, count=%lu): %s",
         (rv != a_PG_ANSWER_DUNNO), S(ul,cnt), key);

   NYD_OU;
   return rv;
} /* }}} */
/* }}} */
/* }}} */

/* conf {{{ */
static void
a_conf_setup(struct a_pg *pgp, BITENUM_IS(u32,a_pg_avo_flags) f){
   NYD2_IN;

   pgp->pg_flags &= ~S(uz,a_PG_F_SETUP_MASK);

   LCTAV(VAL_4_MASK <= 32);
   LCTAV(VAL_6_MASK <= 128);
   pgp->pg_4_mask = U8_MAX;
   pgp->pg_6_mask = U8_MAX;

   LCTAV(VAL_DELAY_MIN <= S16_MAX);
   pgp->pg_delay_min = U16_MAX;
   LCTAV(VAL_DELAY_MAX <= S16_MAX);
   pgp->pg_delay_max = U16_MAX;
   LCTAV(VAL_GC_REBALANCE <= S16_MAX);
   pgp->pg_gc_rebalance = U16_MAX;
   LCTAV(VAL_GC_TIMEOUT <= S16_MAX);
   pgp->pg_gc_timeout = U16_MAX;
   LCTAV(VAL_SERVER_TIMEOUT <= S16_MAX);
   pgp->pg_server_timeout = U16_MAX;

   LCTAV(VAL_COUNT <= S32_MAX);
   pgp->pg_count = U32_MAX;
   LCTAV(VAL_LIMIT <= S32_MAX);
   pgp->pg_limit = U32_MAX;
   LCTAV(VAL_LIMIT_DELAY <= S32_MAX);
   pgp->pg_limit_delay = U32_MAX;

   if(!(f & a_PG_AVO_RELOAD)){
      LCTAV(VAL_SERVER_QUEUE <= S32_MAX);
      pgp->pg_server_queue = U32_MAX;

      pgp->pg_defer_msg = NIL;

      pgp->pg_store_path = NIL;
   }

   NYD2_OU;
}

static void
a_conf_finish(struct a_pg *pgp, BITENUM_IS(u32,a_pg_avo_flags) f){
   NYD2_IN;

   if(pgp->pg_4_mask == U8_MAX)
      pgp->pg_4_mask = VAL_4_MASK;
   if(pgp->pg_6_mask == U8_MAX)
      pgp->pg_6_mask = VAL_6_MASK;

   if(pgp->pg_delay_min == U16_MAX)
      pgp->pg_delay_min = VAL_DELAY_MIN;
   if(pgp->pg_delay_max == U16_MAX)
      pgp->pg_delay_max = VAL_DELAY_MAX;
   if(pgp->pg_gc_rebalance == U16_MAX)
      pgp->pg_gc_rebalance = VAL_GC_REBALANCE;
   if(pgp->pg_gc_timeout == U16_MAX)
      pgp->pg_gc_timeout = VAL_GC_TIMEOUT;
   if(pgp->pg_server_timeout == U16_MAX)
      pgp->pg_server_timeout = VAL_SERVER_TIMEOUT;

   if(pgp->pg_count == U32_MAX)
      pgp->pg_count = VAL_COUNT;
   if(pgp->pg_limit == U32_MAX)
      pgp->pg_limit = VAL_LIMIT;
   if(pgp->pg_limit_delay == U32_MAX)
      pgp->pg_limit_delay = VAL_LIMIT_DELAY;

   if(!(f & a_PG_AVO_RELOAD)){
      if(pgp->pg_server_queue == U32_MAX)
         pgp->pg_server_queue = VAL_SERVER_QUEUE;

      if(pgp->pg_defer_msg == NIL){
         pgp->pg_defer_msg = (VAL_DEFER_MSG != NIL) ? VAL_DEFER_MSG
               : a_DEFER_MSG;
         pgp->pg_flags |= a_PG_F_NOFREE_DEFER_MSG;
      }

      if(pgp->pg_store_path == NIL){
         pgp->pg_store_path = VAL_STORE_PATH;
         pgp->pg_flags |= a_PG_F_NOFREE_STORE_PATH;
      }
   }

   /* */
   /* C99 */{
      char const *em_arr[5], **empp = em_arr;

      if(pgp->pg_delay_min >= pgp->pg_delay_max){
         *empp++ = _("delay-min is >= delay-max\n");
         pgp->pg_delay_min = pgp->pg_delay_max;
      }
      if((pgp->pg_flags & a_PG_F_MASTER_DELAY_PROGRESSIVE) &&
            S(uz,pgp->pg_delay_min) * pgp->pg_count >=
               S(uz,pgp->pg_delay_max)){
         *empp++ = _("delay-min*count is >= delay-max: -delay-progressive\n");
         pgp->pg_flags ^= a_PG_F_MASTER_DELAY_PROGRESSIVE;
      }

      if(pgp->pg_limit_delay >= pgp->pg_limit){
         *empp++ = _("limit-delay is >= limit\n");
         pgp->pg_limit_delay = 0;
      }
      if(pgp->pg_server_queue == 0){
         *empp++ = _("server-queue must be greater than 0\n");
         pgp->pg_server_queue = 1;
      }

      *empp = NIL;

      for(empp = em_arr; *empp != NIL; ++empp)
         a_conf_error(pgp, "%s", V_(*empp));
   }

   NYD2_OU;
}

static void
a_conf_list_values(struct a_pg *pgp){
   /* Note!  Test assumes store-path is last line! */
   NYD2_IN;

   fprintf(stdout,
      "4-mask=%lu\n"
         "6-mask=%lu\n"
      "count=%lu\n"
         "delay-max=%lu\n"
         "delay-min=%lu\n"
         "%s"
         "gc-rebalance=%lu\n"
         "gc-timeout=%lu\n"
         "limit=%lu\n"
         "limit-delay=%lu\n"
      "server-queue=%lu\n"
         "server-timeout=%lu\n"
      "store-path=%s\n"
      "defer-msg=%s\n"
      ,
      S(ul,pgp->pg_4_mask), S(ul,pgp->pg_6_mask),
      S(ul,pgp->pg_count), S(ul,pgp->pg_delay_max), S(ul,pgp->pg_delay_min),
         (pgp->pg_flags & a_PG_F_MASTER_DELAY_PROGRESSIVE
            ? "delay-progressive\n" : su_empty),
         S(ul,pgp->pg_gc_rebalance), S(ul,pgp->pg_gc_timeout),
         S(ul,pgp->pg_limit), S(ul,pgp->pg_limit_delay),
      S(ul,pgp->pg_server_queue), S(ul,pgp->pg_server_timeout),
      pgp->pg_store_path,
      pgp->pg_defer_msg
      );

   NYD2_OU;
}

static s32
a_conf__arg(struct a_pg *pgp, s32 o, char const *arg,
      BITENUM_IS(u32,a_pg_avo_flags) f){
   union {u8 *i8; u16 *i16; u32 *i32;} p;
   NYD2_IN;

   /* In long-option order */
   switch(o){
   case '4':
   case '6':
      if(!(f & a_PG_AVO_FULL)){
         u8 max;

         if(o == '4'){
            p.i8 = &pgp->pg_4_mask;
            max = 32;
         }else{
            p.i8 = &pgp->pg_6_mask;
            max = 128;
         }

         if((su_idec_u8(p.i8, arg, UZ_MAX, 10, NIL
                  ) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
               ) != su_IDEC_STATE_CONSUMED || *p.i8 > max){
            a_conf_error(pgp, _("Invalid IPv%c mask: %s (max: %hhu)\n"),
               o, arg, max);
            o = -su_EX_USAGE;
         }
      }break;

   case 'A':
      if(f & a_PG_AVO_FULL)
         o = a_conf__AB(pgp, arg, ((pgp->pg_flags & a_PG_F_TEST_MODE)
               ? R(struct a_pg_wb*,0x1) : &pgp->pg_master->pgm_white));
      break;
   case 'a':
      if(f & a_PG_AVO_FULL)
         o = a_conf__ab(pgp, C(char*,arg), ((pgp->pg_flags & a_PG_F_TEST_MODE
               ) ? R(struct a_pg_wb*,0x1) : &pgp->pg_master->pgm_white));
      break;

   case 'B':
      if(f & a_PG_AVO_FULL)
         o = a_conf__AB(pgp, arg, ((pgp->pg_flags & a_PG_F_TEST_MODE) ? NIL
               : &pgp->pg_master->pgm_black));
      break;
   case 'b':
      if(f & a_PG_AVO_FULL)
         o = a_conf__ab(pgp, C(char*,arg), ((pgp->pg_flags & a_PG_F_TEST_MODE
               ) ? NIL : &pgp->pg_master->pgm_black));
      break;

   case 'c': p.i32 = &pgp->pg_count; goto ji32;
   case 'D': p.i16 = &pgp->pg_delay_max; goto ji16;
   case 'd': p.i16 = &pgp->pg_delay_min; goto ji16;
   case 'p': pgp->pg_flags |= a_PG_F_MASTER_DELAY_PROGRESSIVE; break;
   case 'G': p.i16 = &pgp->pg_gc_rebalance; goto ji16;
   case 'g': p.i16 = &pgp->pg_gc_timeout; goto ji16;
   case 'L': p.i32 = &pgp->pg_limit; goto ji32;
   case 'l': p.i32 = &pgp->pg_limit_delay; goto ji32;

   case 'q':
      if(f & a_PG_AVO_RELOAD)
         break;
      p.i32 = &pgp->pg_server_queue;
      goto ji32;
   case 't': p.i16 = &pgp->pg_server_timeout; goto ji16;

   case 'R': o = a_conf__R(pgp, arg, f); break;

   case 's':
      if(f & (a_PG_AVO_FULL | a_PG_AVO_RELOAD))
         break;
      if(su_cs_len(arg) + sizeof("/" a_PG_GRAY_DB_NAME) >= PATH_MAX){
         a_conf_error(pgp,
            _("-s / --store-path argument is a path too long: %s\n"),
            su_err_doc(o = su_err_no_by_errno()));
         o = -o;
         goto jleave;
      }
      if(pgp->pg_store_path != NIL)
         su_FREE(UNCONST(char*,pgp->pg_store_path));
      pgp->pg_store_path = su_cs_dup(arg, su_STATE_ERR_NOPASS);
      break;

   case 'm':
      if(f & (a_PG_AVO_FULL | a_PG_AVO_RELOAD))
         break;
      if(pgp->pg_defer_msg != NIL)
         su_FREE(UNCONST(char*,pgp->pg_defer_msg));
      pgp->pg_defer_msg = su_cs_dup(arg, su_STATE_ERR_NOPASS);
      break;

   case 'v':
      if(!(f & a_PG_AVO_FULL)){
         uz i;

         i = ((pgp->pg_flags << 1) | a_PG_F_V) & a_PG_F_V_MASK;
         pgp->pg_flags = (pgp->pg_flags & ~S(uz,a_PG_F_V_MASK)) | i;
      }break;
   }

jleave:
   if(o < 0 && (pgp->pg_flags & a_PG_F_TEST_MODE)){
      pgp->pg_flags |= a_PG_F_TEST_ERRORS;
      o = su_EX_OK;
   }

   NYD2_OU;
   return o;

ji16:
   if((su_idec_u16(p.i16, arg, UZ_MAX, 10, NIL
            ) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
         ) != su_IDEC_STATE_CONSUMED || UCMP(32, *p.i16, >, S16_MAX))
      goto jeiuse;
   goto jleave;

ji32:
   if((su_idec_u32(p.i32, arg, UZ_MAX, 10, NIL
            ) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
         ) != su_IDEC_STATE_CONSUMED || UCMP(32, *p.i32, >, S32_MAX))
      goto jeiuse;
   goto jleave;

jeiuse:
   a_conf_error(pgp, _("Invalid number or limit excess of -%c argument: %s\n"),
      o, arg);
   o = -su_EX_USAGE;
   goto jleave;
}

static s32
a_conf__AB(struct a_pg *pgp, char const *path, struct a_pg_wb *pgwbp){
   char *lnb;
   size_t lnl;
   ssize_t lnr;
   s32 rv;
   FILE *fp;
   NYD2_IN;

   if((fp = fopen(path, "r")) == NIL){
      a_conf_error(pgp, _("Cannot open file %s: %s\n"),
         su_err_doc(su_err_no_by_errno()));
      rv = -su_EX_NOINPUT;
      goto jleave;
   }

   rv = su_EX_OK;

   lnl = 0;
   lnb = NIL;/* XXX lnb+lnl : su_cstr */
   while((lnr = getline(&lnb, &lnl, fp)) != -1){
      while(lnr > 0 && lnb[lnr - 1] == '\n')
         lnb[--lnr] = '\0';

      if((rv = a_conf__ab(pgp, lnb, pgwbp)) != su_EX_OK &&
            !(pgp->pg_flags & a_PG_F_TEST_MODE))
         break;
      rv = su_EX_OK;
   }
   if(rv == su_EX_OK && !feof(fp))
      rv = -su_EX_IOERR;

   if(lnb != NIL)
      free(lnb);

   fclose(fp);

jleave:
   NYD2_OU;
   return rv;
}

static s32
a_conf__ab(struct a_pg *pgp, char *entry, struct a_pg_wb *pgwbp){
   union a_pg_srch_ip sip;
   struct a_pg_srch *pgsp;
   u32 m;
   char c, *cp;
   s32 rv;
   NYD2_IN;

   rv = su_EX_OK;

   /* A bit of cleanup first */
   while((c = *entry) != '\0' && su_cs_is_space(c))
      ++entry;

   if(/*maybe_comment &&*/ c == '#')
      goto jleave;

   for(cp = entry; *cp != '\0'; ++cp){
   }

   while(cp > entry && su_cs_is_space(cp[-1]))
      --cp;
   *cp = '\0';

   if(cp == entry)
      goto jleave;

   /* Domain plus subdomain match */
   if(*entry == '.'){
      ++entry;
      m = 1;
      goto jcname;
   }

   /* A CIDR match? */
   m = U32_MAX;
   if((cp = su_cs_find_c(entry, '/')) != NIL){
      *cp++ = '\0';
      if((su_idec_u32(&m, cp, UZ_MAX, 10, NIL
               ) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
            ) != su_IDEC_STATE_CONSUMED || /* unrecog. otherw. */m == U32_MAX){
         sip.cp = N_("Invalid CIDR mask: %s/%s\n");
         goto jedata;
      }
   }

   if(su_cs_find_c(entry, ':') != NIL){
      if(m != U32_MAX && m > 128){
         sip.cp = N_("Invalid IPv6 mask: %s/%s\n");
         goto jedata;
      }
      rv = AF_INET6;
      goto jca;
   }else if(su_cs_first_not_of(entry, "0123456789.") == UZ_MAX){
      if(m != U32_MAX && m > 32){
         sip.cp = N_("Invalid IPv4 mask: %s/%s\n");
         goto jedata;
      }
      rv = AF_INET;
      goto jca;
   }else if(m != U32_MAX){
      sip.cp = N_("CIDR notation unexpected: %s/%s\n");
      goto jedata;
   }else{
      m = 0;
      goto jcname;
   }

jleave:
   NYD2_OU;
   return rv;

jcname:
   /* So be easy and use the norm_triple normalizer */
   sip.cp = pgp->pg_cname;
   pgp->pg_cname = entry;
   if(a_norm_triple_cname(pgp)){
      cp = pgp->pg_cname;
      pgp->pg_cname = sip.cp;

      if(!(pgp->pg_flags & a_PG_F_TEST_MODE)){
         union {void *p; up v;} u;

         u.v = (m == 0) ? TRU1 : TRU2; /* "is exact" */
         su_cs_dict_insert(&pgwbp->pgwb_cname, cp, u.p);
      }else{
         char const *me;

         me = (pgwbp == NIL) ? "!" : su_empty;
         /* xxx could use C++ dns hostname check */
         fprintf(stdout, "%s%c %s%s\n",
            me, (m == 0 ? '=' : '~'),
            (m == 0 ? su_empty : "{*.,}"), cp);
      }
   }else{
      pgp->pg_cname = sip.cp;

      sip.cp = N_("Invalid domain name: %s\n");
      cp = UNCONST(char*,su_empty);
      goto jedata;
   }
   ASSERT(rv == su_EX_OK);
   goto jleave;

jca:/* C99 */{
   char buf[INET6_ADDRSTRLEN];
   boole exact;
   u8 g_m;

   if(inet_pton(rv, entry,
         (rv == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6))) != 1){
      sip.cp = N_("Invalid internet address: %s\n");
      cp = UNCONST(char*,su_empty);
      goto jedata;
   }

   /* We have the implicit global masks! */
   g_m = (rv == AF_INET) ? pgp->pg_4_mask : pgp->pg_6_mask;
   if(g_m != 0 && m >= g_m){
      m = g_m;
      exact = TRU1;
   }else
      exact = (m == U32_MAX);

   if(m != U32_MAX){
      uz max, i;
      u32 *ip, mask;

      if(rv == AF_INET){
         LCTA(su_FIELD_OFFSETOF(struct in_addr,s_addr) % sizeof(u32) == 0,
            "Alignment constraint of IPv4 address member not satisfied");
         ip = R(u32*,&sip.v4.s_addr);
         max = 1;
      }else{
         LCTA(su_FIELD_OFFSETOF(struct in6_addr,s6_addr) % sizeof(u32) == 0,
            "Alignment constraint of IPv6 address member not satisfied");
         ip = R(u32*,sip.v6.s6_addr);
         max = 4;
      }
      mask = m;

      i = 0;
      do{
         u32 xm;

         if((xm = mask) != 0){
            xm = 0xFFFFFFFFu;
            if((i + 1) << 5 >= mask){
               if((mask &= 31))
                  xm <<= (32 - mask);
               mask = 0;
            }
         }

         ip[i] &= su_boswap_net_32(xm);
      }while(++i != max);
   }

   /* We need to normalize through the system's C library to match it!
    * This only for exact match or test mode, however */
   if((exact || (pgp->pg_flags & a_PG_F_TEST_MODE)) &&
         inet_ntop(rv, (rv == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6)),
            buf, INET6_ADDRSTRLEN) == NIL){
      sip.cp = N_("Invalid internet address: %s\n");
      cp = UNCONST(char*,su_empty);
      goto jedata;
   }

   if(!(pgp->pg_flags & a_PG_F_TEST_MODE)){
      if(exact)
         su_cs_dict_insert(&pgwbp->pgwb_ca, buf, NIL);
      else{
         ASSERT(m != U32_MAX);
         pgsp = su_TALLOC(struct a_pg_srch, 1);
         pgsp->pgs_next = pgwbp->pgwb_srch;
         pgwbp->pgwb_srch = pgsp;
         pgsp->pgs_flags = (rv == AF_INET) ? a_PG_SRCH_IPV4 : a_PG_SRCH_IPV6;
         pgsp->pgs_mask = S(u8,m);
         su_mem_copy(&pgsp->pgs_ip, &sip, sizeof(sip));
      }
   }else{
      char const *me;

      me = (pgwbp == NIL) ? "!" : su_empty;
      if(exact)
         fprintf(stdout, "%s= %s (/%lu)\n", me, buf, S(ul,g_m));
      else
         fprintf(stdout, "%s~ %s/%lu\n", me, buf, S(ul,m));
   }
   rv = su_EX_OK;
   }goto jleave;

jedata:
   a_conf_error(pgp, V_(sip.cp), entry, cp);
   rv = -su_EX_DATAERR;
   goto jleave;
}

static s32
a_conf__R(struct a_pg *pgp, char const *path,
      BITENUM_IS(u32,a_pg_avo_flags) f){
   struct su_avopt avo;
   char *lnb;
   size_t lnl;
   ssize_t lnr;
   s32 mpv;
   FILE *fp;
   NYD2_IN;

   lnl = 0;
   lnb = NIL;/* XXX lnb+lnl : su_cstr */

   if((fp = fopen(path, "r")) == NIL){
      a_conf_error(pgp, _("Cannot open --resource-file %s: %s\n"),
         path, su_err_doc(mpv = su_err_no_by_errno()));
      mpv = -mpv;
      goto jleave;
   }

   su_avopt_setup(&avo, 0, NIL, NIL, a_lopts);

   while((lnr = getline(&lnb, &lnl, fp)) != -1){
      char *cp;

      for(cp = lnb; lnr > 0 && su_cs_is_space(*cp); ++cp, --lnr){
      }

      if(lnr == 0)
         continue;

      /* We do support comments */
      if(*cp == '#')
         continue;

      while(lnr > 0 && su_cs_is_space(cp[lnr - 1]))
         cp[--lnr] = '\0';

      /* Empty lines are ignored */
      if(lnr == 0)
         continue;

      switch((mpv = su_avopt_parse_line(&avo, cp))){
      /* In long-option order */
      case '4': case '6':
      case 'A': case 'a': case 'B': case 'b':
      case 'c': case 'D': case 'd': case 'p':
         case 'G': case 'g': case 'L': case 'l':
      case 'q': case 't':
      case 'R':
      case 's':
      case 'm':
      case 'v':
         if((mpv = a_conf__arg(pgp, mpv, avo.avo_current_arg, f)) < 0 &&
               !(pgp->pg_flags & a_PG_F_TEST_MODE))
            goto jleave;
         break;

      default:
         if(pgp->pg_flags & a_PG_F_TEST_MODE){
            a_conf_error(pgp,
               _("Option unknown or invalid in --resource-file: %s: %s\n"),
               path, cp);
            break;
         }
         mpv = -su_EX_USAGE;
         goto jleave;
      }
   }

   mpv = su_EX_OK;
jleave:
   if(lnb != NIL)
      free(lnb);
   if(fp != NIL)
      fclose(fp);

   NYD2_OU;
   return mpv;
}

static s32
a_conf_chdir_store_path(struct a_pg *pgp){
   s32 rv;
   NYD2_IN;

   if(su_path_chdir(pgp->pg_store_path))
      rv = su_EX_OK;
   else{
      su_log_write(su_LOG_CRIT, _("cannot change directory to %s: %s\n"),
         pgp->pg_store_path, su_err_doc(-1));
      rv = su_EX_NOINPUT;
   }

   NYD2_OU;
   return rv;
}

static void
a_conf_error(struct a_pg *pgp, char const *msg, ...){
   va_list vl;

   va_start(vl, msg);

   if(pgp->pg_flags & a_PG_F_TEST_MODE)
      vfprintf(stderr, msg, vl);
   else
      su_log_vwrite(su_LOG_CRIT, msg, &vl);

   va_end(vl);

   pgp->pg_flags |= a_PG_F_TEST_ERRORS;
}
/* }}} */

/* normalization {{{ */
static boole
a_norm_triple_r(struct a_pg *pgp){ /* XXX-3 should normalize addresses */
   char *r, *cp, *ue, c;
   NYD2_IN;

   r = pgp->pg_r;

   while(su_cs_is_space(*r))
      ++r;

   cp = r;
   cp += su_cs_len(cp);

   while(cp > r && su_cs_is_space(cp[-1]))
      --cp;
   *cp = '\0';

   cp = r;

   /* Skip over local-part */
   for(;; ++cp){
      if((c = *cp) == '\0'){
         r = NIL;
         goto jleave;
      }
      if(c == '@')
         break;
   }

   /* "Normalize" domain */
   ue = cp;
   while((c = *cp) != '\0')
      *cp++ = S(char,su_cs_to_lower(c));

   if(&ue[1] >= cp)
      r = NIL;

jleave:
   pgp->pg_r = r;

   NYD2_OU;
   return (r != NIL);
}

static boole
a_norm_triple_s(struct a_pg *pgp){ /* XXX-3 should normalize addresses */
   char *s, *cp, c, *ue, *d;
   NYD2_IN;

   s = pgp->pg_s;

   while(su_cs_is_space(*s))
      ++s;

   cp = s;
   cp += su_cs_len(cp);

   while(cp > s && su_cs_is_space(cp[-1]))
      --cp;
   *cp = '\0';

   cp = s;
   ue = NIL;

   /* Skip over local-part.
    * XXX-1 We take anything to the first VERP delimiter or start of domain
    * XXX-2 We also assume VERP does things like
    *    dev-commits-src-all+bounces-6241-steffen=sdaoden.eu@FreeBSD.org
    *    owner-source-changes+M161144=steffen=sdaoden.eu@openbsd.org
    * that is, numeric IDs etc after the VERP delimiter: do not care.
    * Note openwall (ezmlm)
    *    oss-security-return-27633-steffen=sdaoden.eu@lists.openwall.com
    * It is not possible to deal with that but on a per-message base.
    */
   for(;; ++cp){
      if((c = *cp) == '\0'){
         s = NIL;
         goto jleave;
      }

      if(c == '@')
         break;
      if(c == '+' || c == '='){
         if(ue == NIL)
            *(ue = cp) = '@';
      }
   }

   /* "Normalize" domain */
   ASSERT(*cp != '\0');
   d = ++cp;
   while((c = *cp) != '\0')
      *cp++ = S(char,su_cs_to_lower(c));

   /* Now fill the hole */
   if(d < cp){
      /* To avoid overzealous fortify implementations, use _move() */
      if(ue != NIL)
         su_mem_move(&ue[1], d, P2UZ(++cp - d));
   }else
      s = NIL;

jleave:
   pgp->pg_s = s;

   NYD2_OU;
   return (s != NIL);
}

static boole
a_norm_triple_ca(struct a_pg *pgp){
   union a_pg_srch_ip a;
   u32 *ip, mask, max, i;
   char *ca, *cp;
   NYD2_IN;

   cp = pgp->pg_ca;

   while(su_cs_is_space(*cp))
      ++cp;

   ca = cp;
   cp += su_cs_len(cp);

   while(cp > ca && su_cs_is_space(cp[-1]))
      --cp;
   *cp = '\0';

   cp = ca;

   if(su_cs_find_c(cp, ':') != NIL){
      if(inet_pton(AF_INET6, cp, &a.v6) != 1){
         ca = NIL;
         goto jleave;
      }
      LCTA(su_FIELD_OFFSETOF(struct in6_addr,s6_addr) % sizeof(u32) == 0,
         "Alignment constraint of IPv6 address member not satisfied");
      ip = R(u32*,a.v6.s6_addr);
      mask = pgp->pg_6_mask;
      max = 4;
   }else{
      if(inet_pton(AF_INET, cp, &a.v4) != 1){
         ca = NIL;
         goto jleave;
      }
      LCTA(su_FIELD_OFFSETOF(struct in_addr,s_addr) % sizeof(u32) == 0,
         "Alignment constraint of IPv4 address member not satisfied");
      ip = R(u32*,&a.v4.s_addr);
      mask = pgp->pg_4_mask;
      max = 1;
   }

   i = 0;
   do{
      u32 m;

      if((m = mask) != 0){
         m = 0xFFFFFFFFu;
         if((i + 1) << 5 >= mask){
            if((mask &= 31))
               m <<= (32 - mask);
            mask = 0;
         }
      }

      ip[i] &= su_boswap_net_32(m);
   }while(++i != max);

   /* XXX As long as we use inet_ntop() .pg_ca needs to have been "allocated"
    * XXX with sufficient room to place INET6_ADDSTRLEN +1! */
   if(inet_ntop((max == 1 ? AF_INET : AF_INET6), ip,
         ca = pgp->pg_ca, INET6_ADDRSTRLEN) == NIL){
      ca = NIL;
      goto jleave;
   }

   /* My preferred style is superfluous here as long as it is normalized
    *for(cp = ca; (a.c = *cp) != '\0'; ++cp)
    *   *cp = su_cs_to_upper(a.c); */

jleave:
   pgp->pg_ca = ca;

   NYD2_OU;
   return (ca != NIL);
}

static boole
a_norm_triple_cname(struct a_pg *pgp){
   /* This bails for the root label . */
   char *cn, *cp, *ds, c;
   NYD2_IN;

   cn = pgp->pg_cname;

   while(su_cs_is_space(*cn))
      ++cn;

   cp = cn;
   cp += su_cs_len(cp);

   while(cp > cn && su_cs_is_space(cp[-1]))
      --cp;
   *cp = '\0';

   cp = cn;

   /* "Normalize" domain */
   ds = cp;
   while((c = *cp) != '\0')
      *cp++ = S(char,su_cs_to_lower(c));

   if(&ds[1] >= cp)
      cn = NIL;

   pgp->pg_cname = cn;

   NYD2_OU;
   return (cn != NIL);
}
/* }}} */

/* misc {{{ */
static void
a_main_log_write(u32 lvl_a_flags, char const *msg, uz len){
   /* We need to deal with CANcelled newlines .. */
   static char xb[1024];
   static uz xl;
   UNUSED(len);

   LCTAV(su_LOG_EMERG == LOG_EMERG && su_LOG_ALERT == LOG_ALERT &&
      su_LOG_CRIT == LOG_CRIT && su_LOG_ERR == LOG_ERR &&
      su_LOG_WARN == LOG_WARNING && su_LOG_NOTICE == LOG_NOTICE &&
      su_LOG_INFO == LOG_INFO && su_LOG_DEBUG == LOG_DEBUG);

   if(len > 0 && msg[len - 1] != '\n'){
      if(sizeof(xb) - 2 - xl > len){
         su_mem_copy(&xb[xl], msg, len);
         xl += len;
         goto jleave;
      }
   }

   if(xl > 0){
      if(len > 0 && msg[len - 1] == '\n')
         --len;
      if(sizeof(xb) - 2 - xl < len)
         len = sizeof(xb) - 2 - xl;
      su_mem_copy(&xb[xl], msg, len);
      xl += len;
      xb[xl++] = '\n';
      xb[xl] = '\0';
      xl = 0;
      msg = xb;
   }

   syslog(S(int,lvl_a_flags & su_LOG_PRIMASK), "%s", msg);
jleave:;
}

static void
a_main_usage(FILE *fp){
   char buf[7];
   uz i;
   NYD2_IN;

   i = (su_program != NIL) ? su_cs_len(su_program) : 0;
   i = MIN(i, sizeof(buf) -1);
   if(i > 0)
      su_mem_set(buf, ' ', i);
   buf[i] = '\0';

   fprintf(fp, _("%s (s-postgray %s): "
      "postfix protocol policy (graylisting) server\n"
      "\n"),
      VAL_NAME, a_VERSION);
   fprintf(fp, _(
         ". Please use --long-help (-H) for option summary\n"
         ". Bugs/Contact via " a_CONTACT "\n"));

   NYD2_OU;
}

static boole
a_main_dump_doc(up cookie, boole has_arg, char const *sopt, char const *lopt,
      char const *doc){
   char const *x1, *x2, *x3;
   NYD2_IN;
   UNUSED(doc);

   /* I18N: separating command line options: opening for short option */
   x2 = (sopt[0] != '\0') ? _(", ") : sopt;

   if(has_arg){
      /* I18N: describing arguments to command line options */
      x1 = _("=ARG");
      x3 = (x2 != sopt) ? _(" ARG") : sopt;
   }else
      x1 = x3 = su_empty;

   /* I18N: long option[=ARG][ short option [ARG]]: doc */
   fprintf(S(FILE*,cookie), _("%s%s%s%s%s: %s\n"),
      lopt, x1, x2, sopt, x3, V_(doc));

   NYD2_OU;
   return TRU1;
}

#if a_DBGIF
static void
a_main_oncrash(int signo){
   char s2ibuf[32], *cp;
   int fd;
   uz i;

   su_nyd_set_disabled(TRU1);

   if((fd = open(a_NYD_FILE, O_WRONLY | O_CREAT | O_EXCL, 0666)) == -1)
      fd = STDERR_FILENO;

# undef _X
# define _X(X) X, sizeof(X) -1

   write(fd, _X("\n\nNYD: program dying due to signal "));

   cp = &s2ibuf[sizeof(s2ibuf) -1];
   *cp = '\0';
   i = signo;
   do{
      *--cp = "0123456789"[i % 10];
      i /= 10;
   }while(i != 0);
   write(fd, cp, P2UZ(&s2ibuf[sizeof(s2ibuf) -1] - cp));

   write(fd, _X(":\n"));

   su_nyd_dump(&a_main_oncrash__dump, S(uz,S(u32,fd)));

   write(fd, _X("-----\nCome up to the lab and see what's on the slab\n"));

   /* C99 */{
      struct sigaction xact;
      sigset_t xset;

      xact.sa_handler = SIG_DFL;
      sigemptyset(&xact.sa_mask);
      xact.sa_flags = 0;
      sigaction(signo, &xact, NIL);

      sigemptyset(&xset);
      sigaddset(&xset, signo);
      sigprocmask(SIG_UNBLOCK, &xset, NIL);

      kill(getpid(), signo);

      for(;;)
         _exit(su_EX_ERR);
   }
}

static void
a_main_oncrash__dump(up cookie, char const *buf, uz blen){
   write(S(int,cookie), buf, blen);
}
#endif /* a_DBGIF */
/* }}} */

int
main(int argc, char *argv[]){ /* {{{ */
   struct su_avopt avo;
   struct a_pg pg;
   BITENUM_IS(u32,a_pg_avo_flags) f;
   s32 mpv;

   mpv = (getenv("SOURCE_DATE_EPOCH") == NIL); /* xxx su_env_get? */
   su_state_create(su_STATE_CREATE_RANDOM, (mpv ? NIL : VAL_NAME),
      (DVLDBGOR(su_LOG_DEBUG, (mpv ? su_LOG_ERR : su_LOG_DEBUG)) |
         DVL( su_STATE_DEBUG | )
         (mpv ? (0 /*| su_STATE_LOG_SHOW_LEVEL | su_STATE_LOG_SHOW_PID*/)
            : (su_STATE_LOG_SHOW_PID | su_STATE_REPRODUCIBLE))),
      su_STATE_ERR_NOPASS);

#if a_DBGIF
   signal(SIGABRT, &a_main_oncrash);
#  ifdef SIGBUS
   signal(SIGBUS, &a_main_oncrash);
#  endif
   signal(SIGFPE, &a_main_oncrash);
   signal(SIGILL, &a_main_oncrash);
   signal(SIGSEGV, &a_main_oncrash);
#endif

   STRUCT_ZERO(struct a_pg, &pg);
   a_conf_setup(&pg, a_PG_AVO_NONE);
   pg.pg_argc = S(u32,(argc > 0) ? --argc : argc);
   pg.pg_argv = ++argv;

   /* To avoid that clients do not parse too much we may have to parse ARGV
    * several times instead */
   f = a_PG_AVO_NONE;
jreavo:
   su_avopt_setup(&avo, pg.pg_argc, C(char const*const*,pg.pg_argv),
      a_sopts, a_lopts);

   while((mpv = su_avopt_parse(&avo)) != su_AVOPT_STATE_DONE){
      char const *emsg;

      /* In long-option order (mostly) */
      switch(mpv){
      case 'o':
         pg.pg_flags |= a_PG_F_CLIENT_ONCE_MODE;
         break;
      case '.':
         pg.pg_flags |= a_PG_F_CLIENT_SHUTDOWN_MODE;
         break;
      case '#':
         pg.pg_flags |= a_PG_F_TEST_MODE;
         break;

      case '4': case '6':
      case 'A': case 'a': case 'B': case 'b':
      case 'c': case 'D': case 'd': case 'p':
         case 'G': case 'g': case 'L': case 'l':
      case 'q': case 't':
      case 'R':
      case 's':
      case 'm':
      case 'v':
         if((mpv = a_conf__arg(&pg, mpv, avo.avo_current_arg, f)) < 0){
            mpv = -mpv;
            goto jleave;
         }
         break;

      case 'H':
      case 'h':
         a_main_usage(stdout);
         if(mpv == 'H'){
            fprintf(stdout, _("\nLong options:\n"));
            (void)su_avopt_dump_doc(&avo, &a_main_dump_doc, R(up,stdout));
         }
         mpv = su_EX_OK;
         goto jleave;

      case su_AVOPT_STATE_ERR_ARG:
         emsg = su_avopt_fmt_err_arg;
         goto jerropt;
      case su_AVOPT_STATE_ERR_OPT:
         emsg = su_avopt_fmt_err_opt;
jerropt:
         if(!(f & a_PG_AVO_FULL))
            fprintf(stderr, V_(emsg), avo.avo_current_err_opt);

         if(pg.pg_flags & a_PG_F_TEST_MODE){
            pg.pg_flags |= a_PG_F_TEST_ERRORS;
            break;
         }
jeusage:
         a_main_usage(stderr);
         mpv = su_EX_USAGE;
         goto jleave;
      }
   }

   if(!(f & a_PG_AVO_FULL)){
      if(avo.avo_argc != 0){
         fprintf(stderr, _("Excess arguments given\n"));
         if(!(pg.pg_flags & a_PG_F_TEST_MODE))
            goto jeusage;
         pg.pg_flags |= a_PG_F_TEST_ERRORS;
      }

      a_conf_finish(&pg, a_PG_AVO_NONE);
   }

   if(!(pg.pg_flags & a_PG_F_TEST_MODE))
      mpv = a_client(&pg);
   else if(!(f & a_PG_AVO_FULL)){
      f = a_PG_AVO_FULL;
      goto jreavo;
   }else{
      fprintf(stdout, "# # #\n");
      a_conf_list_values(&pg);
      mpv = (pg.pg_flags & a_PG_F_TEST_ERRORS) ? su_EX_USAGE : su_EX_OK;
   }

jleave:
   if(!(pg.pg_flags & a_PG_F_NOFREE_DEFER_MSG) && pg.pg_defer_msg != NIL)
      su_FREE(UNCONST(char*,pg.pg_defer_msg));
   if(!(pg.pg_flags & a_PG_F_NOFREE_STORE_PATH) && pg.pg_store_path != NIL)
      su_FREE(C(char*,pg.pg_store_path));

   su_state_gut(mpv == su_EX_OK
      ? su_STATE_GUT_ACT_NORM /*DVL( | su_STATE_GUT_MEM_TRACE )*/
      : su_STATE_GUT_ACT_QUICK);

   return mpv;
} /* }}} */

#include "su/code-ou.h"
#undef su_FILE
/* s-it-mode */
