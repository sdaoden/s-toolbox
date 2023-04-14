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
 *@ - May want to make policy return on ENOMEM/limit excess configurable?
 *@ - We do not sleep per policy instance=, but per-question.
 *@   This could add a lot of delay per-message in non-focus-sender mode.
 *@   Restore instance= handling from git history, and sleep only once per
 *@   instance?  The documented "it should be impossible to reach the graylist
 *@   bypass limit" calculation is no longer true then however.
 *@ - We could add a in-between-delay counter, and if more than X messages
 *@   come in before the next delay expires, we could auto-blacklist.
 *@   Just extend the DB format to a 64-bit integer, and use bits 32..48.
 *@   (Adding this feature should work with existing DBs.)
 *
 * Copyright (c) 2022 - 2023 Steffen Nurpmeso <steffen@sdaoden.eu>.
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
#define a_VERSION "0.8.1"
#define a_CONTACT "Steffen Nurpmeso <steffen@sdaoden.eu>"

/* Maximum accept(2) backlog */
#define a_SERVER_LISTEN (VAL_SERVER_QUEUE / 2)

/**/

/* Maximum size of the triple recipient/sender/client_address we look out for,
 * anything beyond is _ANSWER_NODEFER.  RFC 5321 limits:
 *   4.5.3.1.1.  Local-part
 * The maximum total length of a user name or other local-part is 64 octets.
 *   4.5.3.1.2.   Domain
 * The maximum total length of a domain name or number is 255 octets.
 * We also store client_name for configurable domain whitelisting, but be easy and treat that as local+domain, too.
 * And finally we also use the buffer for gray savings and stdio getline(3) replacement (for ditto): add plenty
 * (a_misc_line_get() complains and skips lines longer than that; note: stack buffers!) */
#define a_BUF_SIZE (ALIGN_Z(INET6_ADDRSTRLEN +1) + ((64 + 256 +1) * 3) + 1 + su_IENC_BUFFER_SIZE + 1)

/* Minimum number of minutes in between DB cleanup runs.
 * Together with --limit-delay this forms a barrier against limit excess */
#define a_DB_CLEANUP_MIN_DELAY (1 * su_TIME_HOUR_MINS)

/* The default built-in messages (see manual) */
#define a_MSG_ALLOW "DUNNO" /* "OK" */
#define a_MSG_BLOCK "REJECT" /* "5.7.1 Please go away" */
#define a_MSG_DEFER "DEFER_IF_PERMIT 4.2.0 Service temporarily faded to Gray"
#define a_MSG_NODEFER "DUNNO"

/* When hitting limit, new entries are delayed that long */
#define a_LIMIT_DELAY_SECS 1 /* xxx configurable? */

/**/
#define a_OPENLOG_FLAGS (LOG_NDELAY)
#define a_OPENLOG_FLAGS_LOGGER (LOG_NDELAY)

/* */
#define a_DBGIF 0
# define a_DBG(X)
# define a_DBG2(X)
# define a_NYD_FILE "/tmp/" VAL_NAME ".dat"

/* -- >8 -- 8< -- */

/*
#define _POSIX_C_SOURCE 200809L
#define _ATFILE_SOURCE
*/
#define _GNU_SOURCE /* Always the same mess */

#include <su/code.h>

/* Sandbox may impose the necessity to use a dedicated logger process */
#undef a_HAVE_LOG_FIFO
#undef a_SANDBOX_SIGNAL
#if VAL_OS_SANDBOX > 0
# ifdef HAVE_SANITIZER
#  warning HAVE_SANITIZER, turning off OS sandbox
#  undef VAL_OS_SANDBOX
#  define VAL_OS_SANDBOX 0
# elif su_OS_FREEBSD
#  define a_HAVE_LOG_FIFO
#  define a_SANDBOX_SIGNAL SIGTRAP

#  include <sys/capsicum.h>
#  include <sys/procctl.h>
# elif su_OS_LINUX
#  ifdef __UCLIBC__
#   warning uclibc never tried, turning off OS sandbox
#   undef VAL_OS_SANDBOX
#   define VAL_OS_SANDBOX 0
#  else
#   define a_HAVE_LOG_FIFO
#   define a_SANDBOX_SIGNAL SIGSYS

#   include <linux/filter.h>
#   include <linux/seccomp.h>

#   include <sys/prctl.h>
#   include <sys/syscall.h>
#  endif
# elif su_OS_OPENBSD
# else
#  undef VAL_OS_SANDBOX
#  define VAL_OS_SANDBOX 0
# endif
#endif /* VAL_OS_SANDBOX > 0 */

#if VAL_OS_SANDBOX == 0
# if su_OS_LINUX
#  include <sys/syscall.h> /* __NR_close_range */
# endif
#endif

/* TODO all std or posix, nono */
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/uio.h>

#include <arpa/inet.h>
#include <netinet/in.h>

#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h> /* XXX fmtcodec, then all *printf -> unroll! */
#include <stdlib.h>
#include <syslog.h>
#include <unistd.h>

#include <su/avopt.h>
#include <su/boswap.h>
#include <su/cs.h>
#include <su/cs-dict.h>
#include <su/icodec.h>
#include <su/mem.h>
#include <su/path.h>
#include <su/time.h>

#if a_DBGIF || defined su_HAVE_NYD
/*# define NYDPROF_ENABLE*/
# define NYD_ENABLE
# define NYD2_ENABLE
#endif
#include "su/code-in.h"

/* defines, enums, types, rodata, bss {{{ */

/* Unfortunately pre v0.8 versions had an undocumented problem: in case the server socket was already existing upon
 * startup (server did have not chance to perform cleanup), no server would ever have been started, and a default
 * postfix smtpd_policy_service_default_action would cause trouble.  A "rm -f PG-SOCKET" in a startup-script avoids
 * this, but it was never announced to be necessary.  v0.8 added a "reassurance" lock file to automatize this */
#define a_REA_NAME VAL_NAME ".pid"

/* Dictionary flags.  No need for _CASE since keys are normalized already.  No _AUTO_SHRINK! */
#define a_WB_CA_FLAGS (su_CS_DICT_HEAD_RESORT)
#define a_WB_CNAME_FLAGS (su_CS_DICT_HEAD_RESORT)

/* Gray dictionary; is balanced() after resize; no _ERR_PASS, set later on!
 * Always in FROZEN state to delay resize costs to balance()!
 * MIN_LIMIT is also used to consider whether _this_ balance() is needed */
#define a_GRAY_FLAGS (su_CS_DICT_HEAD_RESORT | su_CS_DICT_STRONG /*| su_CS_DICT_ERR_PASS*/)
#define a_GRAY_TS 4
#define a_GRAY_MIN_LIMIT 1000
#define a_GRAY_DB_NAME VAL_NAME ".db" /* (len LE REA_NAME!) */

/* MIN(sizeof(pg_buf), this) actually used (and never more than 1024-some!) */
#ifdef a_HAVE_LOG_FIFO
# define a_FIFO_NAME VAL_NAME ".log" /* (len LE REA_NAME!) */
# ifdef PIPE_BUF
#  define a_FIFO_IO_MAX PIPE_BUF
# elif defined _POSIX_PIPE_BUF
#  define a_FIFO_IO_MAX _POSIX_PIPE_BUF
# else
#  define a_FIFO_IO_MAX 512 /* POSIX Issue 7 TC2 */
# endif
#endif

/**/
#ifdef O_NOFOLLOW
# define a_O_NOFOLLOW O_NOFOLLOW
#else
# define a_O_NOFOLLOW 0
#endif
#ifdef O_NOCTTY
# define a_O_NOCTTY O_NOCTTY
#else
# define a_O_NOCTTY 0
#endif
#ifdef O_PATH
# define a_O_PATH O_PATH
#else
# define a_O_PATH 0
#endif

/* xxx Low quality effort to close open file descriptors: as we are normally started in a controlled manner not
 * xxx "from within the wild" this seems superfluous even */
#if su_OS_DRAGONFLY || su_OS_NETBSD || su_OS_OPENBSD
# define a_CLOSE_ALL_FDS() (closefrom(STDERR_FILENO + 1) == 0)
#elif su_OS_FREEBSD
# define a_CLOSE_ALL_FDS() (closefrom(STDERR_FILENO + 1), TRU1)
#elif su_OS_LINUX
# ifdef __NR_close_range
#  define a_CLOSE_ALL_FDS() (syscall(__NR_close_range, STDERR_FILENO + 1, ~0u, 0) == 0)
# endif
#endif
#ifndef a_CLOSE_ALL_FDS
# define a_CLOSE_ALL_FDS() (TRU1)
#endif

enum a_flags{
	a_F_NONE,

	/* Setup: command line option and shared persistent flags */
	a_F_MODE_SHUTDOWN = 1u<<1, /* -. (client asks EOT,\0,\0) */
	a_F_MODE_STARTUP = 1u<<2, /* -@ (client asks ENQ,\0,\0) */
	a_F_MODE_STATUS = 1u<<3, /* -% */
	a_F_MODE_TEST = 1u<<4, /* -# */
	a__F_MODE_MASK = a_F_MODE_SHUTDOWN | a_F_MODE_STARTUP | a_F_MODE_STATUS | a_F_MODE_TEST,

	a_F_CLIENT_ONCE = 1u<<5, /* -o */
	a_F_FOCUS_SENDER = 1u<<6, /* -f */
	a_F_UNTAMED = 1u<<7, /* -u */

	a_F_SETUP_MASK = (1u<<12) - 1,

	a_F_DELAY_PROGRESSIVE = 1u<<13, /* -p */
	a_F_V = 1u<<14, /* -v */
	a_F_VV = 1u<<15,
	a_F_V_MASK = a_F_V | a_F_VV,

	/* */
	a_F_TEST_ERRORS = 1u<<16,
	a_F_NOFREE_MSG_ALLOW = 1u<<17,
	a_F_NOFREE_MSG_BLOCK = 1u<<18,
	a_F_NOFREE_MSG_DEFER = 1u<<19,
	a_F_NOFREE_STORE_PATH = 1u<<20,

	/* Client */
	a_F_CLIENT_NONE,

	/* Master (server-only control block) */
	a_F_MASTER_NONE = 0,
	a_F_MASTER_IN_SETUP = 1u<<24, /* First time config evaluation from within server */
	a_F_MASTER_ACCEPT_SUSPENDED = 1u<<25,
	a_F_MASTER_LIMIT_EXCESS_LOGGED = 1u<<26,
	a_F_MASTER_NOMEM_LOGGED = 1u<<27,
	a_F_MASTER_FLAG = 1u<<30 /* It is the master */
};

enum a_avo_flags{
	a_AVO_NONE,
	a_AVO_FULLER = 1u<<0, /* Like _FULL less AaBb */
	a_AVO_FULL = 1u<<1,
	a_AVO_RELOAD = 1u<<2
};

enum a_answer{
	a_ANSWER_ALLOW,
	a_ANSWER_BLOCK,
	a_ANSWER_DEFER_SLEEP,
	a_ANSWER_DEFER,
	a_ANSWER_NODEFER
};

/* Fuzzy search */
enum a_srch_flags{
	a_SRCH_NONE,
	a_SRCH_IPV4 = 1u<<0,
	a_SRCH_IPV6 = 1u<<1
};

union a_srch_ip{
	/* (Let us just place that align thing, ok?  I feel better that way) */
	u64 align;
	struct in_addr v4;
	struct in6_addr v6;
	/* And whatever else is needed to use this */
	char *cp;
};

/* Fuzzy search white/blacklist */
struct a_srch{
	struct a_srch *s_next;
	BITENUM_IS(u8,a_srch_flags) s_flags;
	u8 s_mask; /* SRCH_IP*: CIDR mask */
	u8 s__pad[su_6432(6,2)];
	union a_srch_ip s_ip;
};

struct a_line{
	u32 l_curr;
	u32 l_fill;
	s32 l_err; /* Error; su_ERR_NONE with 0 result: EOF */
	/* First a_BUF_SIZE bytes are "end-user storage" xxx could be optimized */
	char l_buf[MAX(a_BUF_SIZE * 4, su_PAGE_SIZE - 32) - 4];
};
#define a_LINE_SETUP(LP) do{(LP)->l_curr = (LP)->l_fill = 0;}while(0)

struct a_wb{
	struct a_srch *wb_srch; /* ca list, fuzzy */
	struct su_cs_dict wb_ca; /* client_address=, exact */
	struct su_cs_dict wb_cname; /* client_name=, exact + fuzzy */
};

struct a_wb_cnt{
	ul wbc_ca;
	ul wbc_ca_fuzzy;
	ul wbc_cname;
	ul wbc_cname_fuzzy;
};

struct a_master{
	char const *m_sockpath;
	s32 m_reafd; /* Client/Master reassurance fd (locked; server PID storage) */
	su_64( u8 m__pad[4]; )
	s32 *m_cli_fds;
	u32 m_cli_no;
	u16 m_cleanup_cnt;
	s16 m_epoch_min; /* Relative minutes of .m_base_epoch .. .m_epoch */
	s64 m_epoch; /* Of last tick */
	s64 m_base_epoch; /* ..of relative minutes; reset by gray_cleanup() */
	struct a_wb m_white;
	struct a_wb m_black;
	struct su_cs_dict m_gray;
	struct a_wb_cnt m_cnt_white;
	struct a_wb_cnt m_cnt_black;
	ul m_cnt_gray_new;
	ul m_cnt_gray_defer;
	ul m_cnt_gray_pass;
};

struct a_pg{
	BITENUM_IS(uz,a_flags) pg_flags;
	struct a_master *pg_master;
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
	char const *pg_msg_allow;
	char const *pg_msg_block;
	char const *pg_msg_defer;
	char const *pg_store_path;
	/**/
	char **pg_argv;
	u32 pg_argc;
	s32 pg_clima_fd; /* Client/Master comm fd */
#ifdef a_HAVE_LOG_FIFO
	s32 pg_logfd; /* Opened pre-sandbox and kept (:() */
	s32 pg_rootfd; /* FreeBSD: open on / for sandbox openat(2) purposes (LOG_FIFO: unrelated, save pad) */
#endif
#if su_OS_FREEBSD
# ifndef a_HAVE_LOG_FIFO
#  error implerr
# endif
	char const *pg_store_path_real; /* realpath(3) variant */
#endif
	/* Triple data plus client_name, pointing into .pg_buf */
	char *pg_r; /* Ignored with _F_FOCUS_SENDER */
	char *pg_s;
	char *pg_ca;
	char *pg_cname;
	char pg_buf[ALIGN_Z(a_BUF_SIZE)];
};

static char const a_sopts[] = "4:6:" "A:a:B:b:" "c:D:d:pfG:g:L:l:" "m:~:!:" "o" "R:" "q:t:" "s:" "u" "v" ".@%#" "Hh";
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
	"delay-progressive;p;" N_("double delay-min per retry until count is reached"),
	"focus-sender;f;" N_("ignore recipient data (see manual)"),
	"gc-rebalance:;G;" N_("no of GC DB cleanup runs before rebalance"),
	"gc-timeout:;g;" N_("until unused gray DB entry is removed (minutes)"),
	"limit:;L;" N_("DB entries after which new ones are not handled"),
	"limit-delay:;l;" N_("DB entries after which new ones cause sleeps"),

	"msg-allow:;~;" N_("whitelist message (read manual; not SIGHUP)"),
	"msg-block:;!;" N_("blacklist message (\")"),
	"msg-defer:;m;" N_("defer_if_permit message (\")"),

	"once;o;" N_("process only one request per client invocation"),

	"resource-file:;R;" N_("path to configuration file with long options"),

	"server-queue:;q;" N_("number of clients a server supports (not SIGHUP)"),
	"server-timeout:;t;" N_("until client-less server exits (0=never; minutes)"),

	"store-path:;s;" N_("DB and server/client socket directory (not SIGHUP)"),

	"untamed;u;" N_("only setrlimit(2), no further system dependent sandbox"),

	"verbose;v;" N_("increase syslog verbosity (multiply for more verbosity)"),

	/**/
	"shutdown;.;" N_("[*] force running server to exit, synchronize on that"),
	"startup;@;" N_("[*] only startup the server"),
	"status;%;" N_("[*] exit status 0 or 1 state whether server runs; otherwise error"),
	"test-mode;#;" N_("[*] check and list configuration, exit according status"),

	"long-help;H;" N_("[*] this listing"),
	"help;h;" N_("[*] short help"),
	NIL
};

/* What can reside in resource files (and is parsed twice), in long-option order */
#define a_AVOPT_CASES \
	case '4': case '6':\
	case 'A': case 'a': case 'B': case 'b':\
	case 'c': case 'D': case 'd': case 'p': case 'f': case 'G': case 'g': case 'L': case 'l':\
	case '~': case '!': case 'm':\
	case 'o':\
	case 'R':\
	case 'q': case 't':\
	case 's':\
	case 'u':\
	case 'v':

static struct a_pg ATOMIC *a_pg;
#ifdef a_HAVE_LOG_FIFO
static s32 ATOMIC a_server_chld;
#endif
static s32 ATOMIC a_server_hup;
static s32 ATOMIC a_server_usr1;
static s32 ATOMIC a_server_usr2;
/* }}} */

/* protos {{{ */

/* client */
static s32 a_client(struct a_pg *pgp);

static s32 a_client__loop(struct a_pg *pgp);
static s32 a_client__req(struct a_pg *pgp);

/* server */
static s32 a_server(struct a_pg *pgp, char const *sockpath, s32 reafd);

/* (signals blocked in (__logger() and) __setup() path (for __wb_setup() not with reset)) */
#ifdef a_HAVE_LOG_FIFO
static void a_server__logger(struct a_pg *pgp, pid_t srvpid);
#endif
static s32 a_server__setup(struct a_pg *pgp);
static s32 a_server__reset(struct a_pg *pgp);
static s32 a_server__wb_setup(struct a_pg *pgp, boole reset);
static void a_server__wb_reset(struct a_master *mp);
static s32 a_server__loop(struct a_pg *pgp);
static void a_server__log_stat(struct a_pg *pgp);
static void a_server__cli_ready(struct a_pg *pgp, u32 client);
static char a_server__cli_req(struct a_pg *pgp, u32 client, uz len);
static boole a_server__cli_lookup(struct a_pg *pgp, struct a_wb *wbp, struct a_wb_cnt *wbcp);
static void a_server__on_sig(int sig);

static void a_server__gray_create(struct a_pg *pgp);
static void a_server__gray_load(struct a_pg *pgp);
static boole a_server__gray_save(struct a_pg *pgp);
static void a_server__gray_cleanup(struct a_pg *pgp, boole force);
static char a_server__gray_lookup(struct a_pg *pgp, char const *key);

/* conf; _conf__(arg|A|a)() return a negative exit status on error */
static void a_conf_setup(struct a_pg *pgp, BITENUM_IS(u32,a_avo_flags) f);
static void a_conf_finish(struct a_pg *pgp, BITENUM_IS(u32,a_avo_flags) f);
static void a_conf_list_values(struct a_pg *pgp);
static s32 a_conf_arg(struct a_pg *pgp, s32 o, char const *arg, BITENUM_IS(u32,a_avo_flags) f);

static s32 a_conf__AB(struct a_pg *pgp, char const *path, struct a_wb *wbp);
static s32 a_conf__ab(struct a_pg *pgp, char *entry, struct a_wb *wbp);
static s32 a_conf__R(struct a_pg *pgp, char const *path, BITENUM_IS(u32,a_avo_flags) f);
static void a_conf__err(struct a_pg *pgp, char const *msg, ...);

/* normalization; can fail for effectively empty or bogus input!
 * XXX As long as we do not have ip_addr, _ca() uses inet_ntop() that may grow,
 * XXX so ensure .pg_ca has enough room in it! */
static boole a_norm_triple_r(struct a_pg *pgp);
static boole a_norm_triple_s(struct a_pg *pgp);
static boole a_norm_triple_ca(struct a_pg *pgp);
static boole a_norm_triple_cname(struct a_pg *pgp);

/* misc */

/* If err refers to an out of resource error, delay a bit, and return true */
static boole a_misc_os_resource_delay(s32 err);

/* Open RDONLY a (possibly sandbox-enabled) file */
static s32 a_misc_open(struct a_pg *pgp, char const *path);

/* getline(3) replacement (-1, or size of space-normalized and trimmed line) */
static sz a_misc_line_get(struct a_pg *pgp, s32 fd, struct a_line *lp);
static s32 a_misc_line__uflow(s32 fd, struct a_line *lp);

/* init states whether called (from a_client()) for first init: "this does not fail" */
static s32 a_misc_log_open(struct a_pg *pgp, boole client, boole init);
static void a_misc_log_write(u32 lvl_a_flags, char const *msg, uz len);

static void a_misc_usage(FILE *fp);
static boole a_misc_dump_doc(up cookie, boole has_arg, char const *sopt, char const *lopt, char const *doc);

#if a_DBGIF || defined su_HAVE_NYD
static void a_misc_oncrash(int signo);
static void a_misc_oncrash__dump(up cookie, char const *buf, uz blen);
#endif

/* sandbox:
 * setrlimit plus optionally OS-specific, at EOF, after main() */
static void a_sandbox_client(struct a_pg *pgp);
static void a_sandbox_server(struct a_pg *pgp);
/* Some things are more .. hard to handle.  path_reset() is called for configuration reset */
#define a_sandbox_path_check(PGP,P) (P)
#define a_sandbox_path_reset(PGP,ISEXIT) do{}while(0)
#define a_sandbox_open(PGP,SP,P,F,M) open(P, (F | a_O_NOFOLLOW | a_O_NOCTTY), M)
#define a_sandbox_sock_accepted(PGP,SFD) (TRU1)
#if VAL_OS_SANDBOX > 0
  /* On FreeBSD any path may be openat(2)ed relative to / descriptor, so a config-reload can replace all paths.
   * We realpath(3) all paths as we see them, then use &[1] */
# if su_OS_FREEBSD
#  undef a_sandbox_path_check
#  undef a_sandbox_path_reset
#  undef a_sandbox_open
#  undef a_sandbox_sock_accepted
static char const *a_sandbox_path_check(struct a_pg *pgp, char const *path);
static void a_sandbox_path_reset(struct a_pg *pgp, boole isexit);
static int a_sandbox_open(struct a_pg *pgp, boole store_path, char const *path, int flags, int mode);
static boole a_sandbox_sock_accepted(struct a_pg *pgp, s32 sockfd);

  /* On OpenBSD paths are unveil(2)-fixed on startup */
# elif su_OS_OPENBSD
#  undef a_sandbox_path_check
static char const *a_sandbox_path_check(struct a_pg *pgp, char const *path);
#  if a_DBGIF
#   undef a_sandbox_path_reset
static void a_sandbox_path_reset(struct a_pg *pgp, boole isexit);
#  endif
# endif
#endif /* VAL_OS_SANDBOX>0 */
/* }}} */

/* client {{{ */
static s32
a_client(struct a_pg *pgp){
	struct sockaddr_un soaun;
	boole isstartup, islock;
	s32 rv, reafd;
	NYD_IN;

	/* Best-effort only */
	while(!a_CLOSE_ALL_FDS()){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			continue;
		if(rv != su_ERR_BADF){
			a_DBG(write(STDERR_FILENO, "CLOSE_ALL_FDS()\n", sizeof("CLOSE_ALL_FDS()\n") -1);)
		}
		break;
	}

	(void)a_misc_log_open(pgp, TRU1, TRU1);

	if(!su_path_chdir(pgp->pg_store_path)){
		su_log_write(su_LOG_CRIT, _("cannot change directory to %s: %s"), pgp->pg_store_path, V_(su_err_doc(-1)));
		rv = su_EX_NOINPUT;
		goto j_leave;
	}

	isstartup = FAL0;
	rv = su_EX_OK;/* xxx uninit? */
	if(0){
jretry_all:
		close(pgp->pg_clima_fd);
		close(reafd);
	}

	pgp->pg_clima_fd = reafd = -1;

	while((reafd = open(a_REA_NAME, O_WRONLY | O_CREAT | a_O_NOFOLLOW | a_O_NOCTTY, 0644)) == -1){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			continue;
		if(a_misc_os_resource_delay(rv))
			continue;
		su_log_write(su_LOG_CRIT, _("cannot create/open client/server reassurance lock %s/%s: %s"),
			pgp->pg_store_path, a_REA_NAME, V_(su_err_doc(rv)));
		rv = su_EX_CANTCREAT;
		goto jleave;
	}

	/* If we can grap a write lock no server exists */
	islock = TRU1;
	while(flock(reafd, LOCK_EX | LOCK_NB) == -1){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			continue;
		if(LIKELY(rv == su_ERR_WOULDBLOCK)){
			if(pgp->pg_flags & a_F_MODE_STATUS){
				rv = su_EX_OK;
				goto jleave;
			}
			if(!isstartup && (pgp->pg_flags & a_F_MODE_STARTUP)){
				a_DBG(su_log_write(su_LOG_DEBUG, "--startup could not acquire write lock: server running");)
				rv = su_EX_TEMPFAIL;
				goto jleave;
			}
			islock = FAL0;
			break;
		}else if(rv == su_ERR_NOLCK){
			a_DBG(su_log_write(su_LOG_DEBUG, "out of OS resources, cannot flock(2), waiting a bit");)
			su_time_msleep(250, TRU1);
		}else{
			su_log_write(su_LOG_CRIT, _("error handling client/server reassurance lock %s/%s: %s"),
				pgp->pg_store_path, a_REA_NAME, V_(su_err_doc(rv)));
			rv = su_EX_OSERR;
			goto jleave;
		}
	}

	/* In status/shutdown mode a taken lock means we are done */
	if(islock){
		if(pgp->pg_flags & a_F_MODE_STATUS){
			rv = su_EX_ERR;
			goto jleave;
		}
		if(pgp->pg_flags & a_F_MODE_SHUTDOWN){
			a_DBG(su_log_write(su_LOG_DEBUG, "--shutdown could acquire write lock: no server");)
			rv = su_EX_TEMPFAIL;
			goto jleave;
		}
	}

	STRUCT_ZERO(struct sockaddr_un, &soaun);
	soaun.sun_family = AF_UNIX;
	LCTAV(FIELD_SIZEOF(struct sockaddr_un,sun_path) >= sizeof(VAL_NAME ".socket"));
	su_mem_copy(soaun.sun_path, VAL_NAME ".socket", sizeof(VAL_NAME ".socket"));

	while((pgp->pg_clima_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			continue;
		if(a_misc_os_resource_delay(rv))
			continue;
		su_log_write(su_LOG_CRIT, _("cannot open client/server socket %s/%s: %s"),
			pgp->pg_store_path, soaun.sun_path, V_(su_err_doc(su_err_by_errno())));
		rv = su_EX_NOINPUT;
		goto jleave;
	}

jretry_bind:
	if(bind(pgp->pg_clima_fd, R(struct sockaddr const*,&soaun), sizeof(soaun))){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			goto jretry_bind;
		if(rv == su_ERR_NOBUFS/*hm*/ || rv == su_ERR_NOMEM){
			a_DBG(su_log_write(su_LOG_DEBUG, "out of OS resources, bind(2) failed, waiting a bit");)
			su_time_msleep(250, TRU1);
			goto jretry_bind;
		}
		/* The server may be running yet */
		if(rv != su_ERR_ADDRINUSE){
			su_log_write(su_LOG_CRIT, _("cannot bind() socket %s/%s: %s"),
				pgp->pg_store_path, soaun.sun_path, V_(su_err_doc(-1)));
			rv = su_EX_IOERR;
			goto jleave;
		}

		/* ADDRINUSE with taken write lock: former server not properly shutdown (hard power cycle?) */
		if(islock){
			struct su_pathinfo pi;
			char const *emsg;

			a_DBG(su_log_write(su_LOG_DEBUG, "bind(2) ADDRINUSE with acquired write lock: no server");)

			emsg = NIL;
			if(!su_pathinfo_lstat(&pi, soaun.sun_path)){
			}else if(!su_pathinfo_is_sock(&pi))
				emsg = _("refused removing non-socket");
			else if(!su_path_rm(soaun.sun_path)){
			}else
				goto jretry_bind;

			if(emsg == NIL)
				emsg = V_(su_err_doc(-1));
			su_log_write(su_LOG_CRIT, _("cannot remove stale socket %s/%s: %s"),
				pgp->pg_store_path, soaun.sun_path, emsg);
			rv = su_EX_SOFTWARE;
			goto jleave;
		}
	}else{
		ASSERT(!(pgp->pg_flags & a_F_MODE_SHUTDOWN));
		/* If we were here already something is borked, fail fast, leave even cleanup to next invocation */
		if(isstartup){
			rv = su_EX_SOFTWARE;
			goto jleave;
		}
		if((rv = a_server(pgp, soaun.sun_path, reafd)) != su_EX_OK)
			goto jleave;
		isstartup = ((pgp->pg_flags & a_F_MODE_STARTUP) != 0);
		goto jretry_all;
	}

	/* */
	while(connect(pgp->pg_clima_fd, R(struct sockaddr const*,&soaun), sizeof(soaun))){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			continue;

		a_DBG(su_log_write(su_LOG_DEBUG, "out of OS resources, connect(2) failed, waiting a bit");)
		su_time_msleep(250, TRU1);

		if(rv == su_ERR_AGAIN || rv == su_ERR_TIMEDOUT)
			continue;
		if(rv == su_ERR_CONNREFUSED){
			a_DBG(su_log_write(su_LOG_DEBUG, "connect(2) CONNREFUSED, restart");)
			goto jretry_all;
		}
		su_log_write(su_LOG_CRIT, _("cannot connect client socket %s/%s: %s"),
			pgp->pg_store_path, soaun.sun_path, V_(su_err_doc(rv)));
		rv = su_EX_IOERR;
		goto jleave;
	}

	if(pgp->pg_flags & (a_F_MODE_STARTUP | a_F_MODE_SHUTDOWN))
		goto jstartup_shutdown;

	close(reafd);
	reafd = -1;

	rv = a_client__loop(pgp);
	if(rv < 0){
		/* After connect(2) succeeded once we may not restart from scratch since likely some circumstance
		 * beyond our horizon exists XXX if not we need a flag to continue working on current block!
		 *goto jretry_socket;*/
		rv = -rv;
	}

jleave:
	if(pgp->pg_clima_fd != -1)
		close(pgp->pg_clima_fd);
	if(reafd != -1)
		close(reafd);

j_leave:
	NYD_OU;
	return rv;

jstartup_shutdown:/* C99 */{
	char xb[3];
	ssize_t xl;

	(void)a_misc_log_open(pgp, TRU1, FAL0);
	a_sandbox_client(pgp); /* (sec overkill) */

	xb[1] = xb[2] = '\0';
	xb[0] = (pgp->pg_flags & a_F_MODE_STARTUP) ? '\05' : '\04';
	xl = 0;
	do{
		ssize_t y;

		if((y = write(pgp->pg_clima_fd, &xb[xl], 3lu - S(uz,xl))) == -1){
			if(su_err_by_errno() == su_ERR_INTR)
				continue;
			rv = su_EX_IOERR;
			goto jleave;
		}
		xl += y;
	}while(xl != 3);

	/* Blocks until descriptor goes away, or reads ENQ again (xxx check?) */
	for(;;){
		if(read(pgp->pg_clima_fd, &soaun, 1) == -1){
			if(su_err_by_errno() == su_ERR_INTR)
				continue;
			rv = su_EX_IOERR;
			goto jleave;
		}
		break;
	}

	rv = su_EX_OK;
	}goto jleave;
}

static s32
a_client__loop(struct a_pg *pgp){
	struct a_line line;
	char *bp;
	ssize_t lnr;
	boole use_this, seen_any;
	s32 rv;
	NYD_IN;

	/* Ignore signals that may happen (beside a possible SIGCHLD that is ignored per se) */
	signal(SIGHUP, SIG_IGN);
	signal(SIGUSR1, SIG_IGN);
	signal(SIGUSR2, SIG_IGN);

	if((rv = a_misc_log_open(pgp, TRU1, FAL0)) != su_EX_OK)
		goto jleave;
	a_sandbox_client(pgp);

	/* Main loop: while we receive policy queries, collect the triple(s) we are looking for, ask our server what he
	 * thinks about that, act accordingly */
	a_LINE_SETUP(&line);
jblock:
	bp = pgp->pg_buf;
	pgp->pg_r = pgp->pg_s = pgp->pg_ca = pgp->pg_cname = NIL;
	use_this = TRU1;
	seen_any = FAL0;

	while((lnr = a_misc_line_get(pgp, STDIN_FILENO, &line)) != -1){
		/* Until an empty line ends one block, collect data */
		if(lnr == 0){
			/* Query complete?  Normalize data and ask server about triple */
			if(use_this && ((pgp->pg_flags & a_F_FOCUS_SENDER) || pgp->pg_r != NIL) &&
					pgp->pg_s != NIL && pgp->pg_ca != NIL && pgp->pg_cname != NIL){
				if((rv = a_client__req(pgp)) != su_EX_OK)
					break;
			}else if(seen_any){
				if(fputs("action=" a_MSG_NODEFER "\n\n", stdout) == EOF || fflush(stdout) == EOF){
					rv = su_EX_IOERR;
					break;
				}
			}

			if(pgp->pg_flags & a_F_CLIENT_ONCE)
				break;
			goto jblock;
		}else{
			/* We assume no WS at BOL and EOL, nor in between key, =, and value.  We use the first value
			 * shall an attribute appear multiple times; this also aids in bp handling simplicity */
			uz i;
			char *cp, *xcp;

			seen_any = TRU1;

			if(!use_this)
				continue;

			cp = line.l_buf;

			if((xcp = su_cs_find_c(cp, '=')) == NIL){
				rv = su_EX_PROTOCOL;
				break;
			}

			i = P2UZ(xcp++ - cp);
			lnr -= i + 1;

			if(lnr == 0)
				continue;

			if(i == sizeof("request") -1 && !su_mem_cmp(cp, "request", sizeof("request") -1)){
				if(lnr != sizeof("smtpd_access_policy") -1 || su_mem_cmp(xcp, "smtpd_access_policy",
							sizeof("smtpd_access_policy") -1)){
					/* We are the wrong policy server for this -- log? */
					a_DBG(su_log_write(su_LOG_DEBUG, "client got wrong request=%s (=DUNNO)", xcp);)
					use_this = FAL0;
					continue;
				}
			}else if(i == sizeof("recipient") -1 && !(pgp->pg_flags & a_F_FOCUS_SENDER) &&
					!su_mem_cmp(cp, "recipient", sizeof("recipient") -1)){
				if(pgp->pg_r != NIL)
					continue;
				pgp->pg_r = bp;
			}else if(i == sizeof("sender") -1 && !su_mem_cmp(cp, "sender", sizeof("sender") -1)){
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
			if(UCMP(z, lnr, >=, P2UZ(&pgp->pg_buf[sizeof(pgp->pg_buf) - ALIGN_Z(INET6_ADDRSTRLEN+1) -1] - bp))){
				a_DBG(su_log_write(su_LOG_DEBUG, "client buffer too small!!!");)
				use_this = FAL0;
			}else{
				char *top;

				top = (pgp->pg_ca == bp) ? &bp[ALIGN_Z(INET6_ADDRSTRLEN +1)] : NIL;
				bp = &su_cs_pcopy(bp, xcp)[1];
				if(top != NIL){
					ASSERT(bp <= top);
					bp = top;
				}
			}
		}
	}
	if(rv == su_EX_OK && line.l_err != su_ERR_NONE && !(pgp->pg_flags & a_F_CLIENT_ONCE))
		rv = su_EX_IOERR;

jleave:
	NYD_OU;
	return rv;
}

static s32
a_client__req(struct a_pg *pgp){
	struct iovec iov[5], *iovp;
	char const *cp;
	u8 resp;
	ssize_t srvx;
	s32 rv, c;
	NYD_IN;

	rv = su_EX_OK;

	if(!(pgp->pg_flags & a_F_FOCUS_SENDER) && !a_norm_triple_r(pgp))
		goto jex_nodefer;
	if(!a_norm_triple_s(pgp))
		goto jex_nodefer;
	if(!a_norm_triple_ca(pgp))
		goto jex_nodefer;
	if(!a_norm_triple_cname(pgp))
		goto jex_nodefer;

	/* Requests are terminated with \0\0 */
	if(pgp->pg_flags & a_F_FOCUS_SENDER){
		iov[0].iov_base = UNCONST(char*,su_empty);
		iov[0].iov_len = sizeof(su_empty[0]);
	}else
		iov[0].iov_len = su_cs_len(iov[0].iov_base = pgp->pg_r) +1;
	iov[1].iov_len = su_cs_len(iov[1].iov_base = pgp->pg_s) +1;
	iov[2].iov_len = su_cs_len(iov[2].iov_base = pgp->pg_ca) +1;
	iov[3].iov_len = su_cs_len(iov[3].iov_base = pgp->pg_cname) +1;
	iov[4].iov_base = UNCONST(char*,su_empty);
	iov[4].iov_len = sizeof(su_empty[0]);

	if(pgp->pg_flags & a_F_VV)
		su_log_write(su_LOG_INFO, "asking R=%u<%s> S=%u<%s> CA=%u<%s> CNAME=%u<%s>",
			iov[0].iov_len -1, iov[0].iov_base, iov[1].iov_len -1, iov[1].iov_base,
			iov[2].iov_len -1, iov[2].iov_base, iov[3].iov_len -1, iov[3].iov_base);

	iovp = iov;
	c = NELEM(iov);
jredo_write:
	srvx = writev(pgp->pg_clima_fd, iovp, c);
	if(srvx == -1){
		if((rv = su_err_by_errno()) == su_ERR_INTR)/* XXX no more in client */
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
		if((rv = su_err_by_errno()) == su_ERR_INTR)/* XXX no more in client */
			goto jredo_read;
jioerr:
		su_log_write(su_LOG_ERR, _("I/O error in server communication: %s"), V_(su_err_doc(rv)));
		/* If the server is gone, then restart cycle from our point of view */
		rv = (rv == su_ERR_PIPE) ? -su_EX_IOERR : su_EX_IOERR;
		goto jex_nodefer;
	}else if(UCMP(z, srvx, !=, sizeof(resp))){
		/* This cannot happen here */
		rv = su_ERR_AGAIN;
		goto jioerr;
	}

	rv = su_EX_OK;

	switch(resp){
	case a_ANSWER_ALLOW:
		cp = pgp->pg_msg_allow;
		break;
	case a_ANSWER_BLOCK:
		cp = pgp->pg_msg_block;
		break;
	case a_ANSWER_DEFER_SLEEP:
		su_time_msleep(a_LIMIT_DELAY_SECS * su_TIMESPEC_SEC_MILLIS, TRU1);
		FALLTHRU
	case a_ANSWER_DEFER:
		cp = pgp->pg_msg_defer;
		break;
	default:
	case a_ANSWER_NODEFER:
jex_nodefer:
		cp = a_MSG_NODEFER;
		break;
	}

	a_DBG(su_log_write(su_LOG_DEBUG, "answer %s", cp);)
	c = snprintf(pgp->pg_buf, FIELD_SIZEOF(struct a_pg,pg_buf), "action=%s\n\n", cp);
	while(c > 0){
		srvx = write(STDOUT_FILENO, pgp->pg_buf, S(u32,c));
		if(srvx == -1){
			if(su_err_by_errno() == su_ERR_INTR)/* XXX no more in client */
				continue;
			rv = su_EX_IOERR;
			break;
		}
		c -= srvx;
	}

	NYD_OU;
	return rv;
}
/* }}} */

/* server {{{ */
static s32
a_server(struct a_pg *pgp, char const *sockpath, s32 reafd){
	enum a__f {a_NONE, a_SIGBLOCK = 1u<<0, a_NEED_EXIT = 1u<<1, a_FIFO_PATH = 1u<<2, a_FIFO_FD = 1u<<3};

	struct a_master m;
	sigset_t ssn, sso;
	s32 rv;
	BITENUM_IS(u32,a__f) f;
	NYD_IN;

	STRUCT_ZERO(struct a_master, &m);

	f = a_NONE;

	/* We listen(2) before we fork(2) the server so the client can connect(2)
	 * race-free without getting ECONNREFUSED */
	if(listen(pgp->pg_clima_fd, a_SERVER_LISTEN)){
		su_log_write(su_LOG_CRIT, _("cannot listen on server socket %s/%s: %s"),
			pgp->pg_store_path, sockpath, V_(su_err_doc(su_err_by_errno())));
		rv = su_EX_IOERR;
		goto jerr;
	}

	/* Dependent upon sandbox approach we need a log FIFO.  Also prepare this first */
#ifdef a_HAVE_LOG_FIFO
	if(!(pgp->pg_flags & a_F_UNTAMED)){
		while(mkfifo(a_FIFO_NAME, S_IWUSR | S_IRUSR) == -1){
			if((rv = su_err_by_errno()) == su_ERR_INTR)
				continue;
			if(rv == su_ERR_EXIST){
				struct su_pathinfo pi;

				if(!su_pathinfo_lstat(&pi, a_FIFO_NAME))
					rv = -1;
				else if(su_pathinfo_is_fifo(&pi))
					break;
				else
					rv = su_ERR_INVAL;

				su_log_write(su_LOG_CRIT, _("will not remove invalid non-\"fifo\" myself %s/%s: %s"),
					pgp->pg_store_path, a_FIFO_NAME, su_err_doc(rv));
			}else
				su_log_write(su_LOG_CRIT, _("cannot create privsep log fifo %s/%s: %s"),
					pgp->pg_store_path, a_FIFO_NAME, V_(su_err_doc(rv)));
			rv = su_EX_SOFTWARE;
			goto jerr;
		}

		f |= a_FIFO_PATH;
	}
#endif /* a_HAVE_LOG_FIFO */

	/* xxx Rather random placement of SIG_BLOCK start */
	sigfillset(&ssn);
	sigprocmask(SIG_BLOCK, &ssn, &sso);
	f |= a_SIGBLOCK;

	switch(fork()){
	case -1: /* Error */
#ifdef a_HAVE_LOG_FIFO
jefork:
#endif
		su_log_write(su_LOG_CRIT, _("cannot start server process: %s"), V_(su_err_doc(su_err_by_errno())));
		rv = su_EX_OSERR;
jerr:
#ifdef a_HAVE_LOG_FIFO
		if(f & a_FIFO_FD)
			close(pgp->pg_logfd);
		if((f & a_FIFO_PATH) && !su_path_rm(a_FIFO_NAME))
			su_log_write(su_LOG_CRIT, _("cannot remove privsep log fifo: %s"), V_(su_err_doc(-1)));
#endif

		if(!su_path_rm(sockpath))
			su_log_write(su_LOG_CRIT, _("cannot remove socket %s/%s: %s"),
				pgp->pg_store_path, sockpath, V_(su_err_doc(-1)));

		if(f & a_NEED_EXIT)
			_exit(rv);
		break;
	default: /* Parent (client) */
		rv = su_EX_OK;
		break;
	case 0: /* Child (server) */
		goto jserver;
	}

	ASSERT(!(f & a_NEED_EXIT));
	if(f & a_SIGBLOCK)
		sigprocmask(SIG_SETMASK, &sso, NIL);

	NYD_OU;
	return rv;

jserver:
	su_program = VAL_NAME ": server";
	f |= a_NEED_EXIT;
	pgp->pg_flags |= a_F_MASTER_FLAG;
	pgp->pg_master = &m;

	m.m_sockpath = sockpath;
	m.m_reafd = reafd;

	/* Close the channels postfix(8)s spawn(8) opened for us; in test mode keep STDERR open */
	close(STDIN_FILENO);
	close(STDOUT_FILENO);

	setsid();

	/* In HAVE_LOG_FIFO sandbox mode we fork again, and use the first level for only logging.
	 * Like this the log process can gracefully synchronize on the SIGCHLD of the "real server" */
#ifdef a_HAVE_LOG_FIFO
	if(!(pgp->pg_flags & a_F_UNTAMED)){
		pid_t srvpid;

		/* So to avoid fork if log process will not work out */
		while((pgp->pg_logfd = open(a_FIFO_NAME, O_RDONLY | a_O_NOFOLLOW | a_O_NOCTTY)) == -1){
			if((rv = su_err_by_errno()) == su_ERR_INTR)
				continue;
			if(a_misc_os_resource_delay(rv))
				continue;
			su_log_write(su_LOG_CRIT, _("cannot open privsep log fifo for reading %s/%s: %s"),
				pgp->pg_store_path, a_FIFO_NAME, V_(su_err_doc(rv)));
			rv = su_EX_SOFTWARE;
			goto jerr;
		}
		f |= a_FIFO_FD;

		switch((srvpid = fork())){
		case -1: goto jefork;
		default: /* Parent (logger); does not return */ a_server__logger(pgp, srvpid); break;
		case 0: /* Child (server) */ break;
		}

		close(pgp->pg_logfd);
		pgp->pg_logfd = -1;
		f &= ~S(u32,a_FIFO_PATH | a_FIFO_FD);
	}
#endif /* HAVE_LOG_FIFO */

	if((rv = a_misc_log_open(pgp, FAL0, FAL0)) != su_EX_OK)
		goto jerr;

	if((rv = a_server__setup(pgp)) == su_EX_OK){
		sigprocmask(SIG_SETMASK, &sso, NIL);
		rv = a_server__loop(pgp);
	}

	/* C99 */{
		s32 xrv;

		xrv = a_server__reset(pgp);
		if(rv == su_EX_OK)
			rv = xrv;
	}

	su_state_gut(rv == su_EX_OK ? su_STATE_GUT_ACT_NORM /*DVL(| su_STATE_GUT_MEM_TRACE)*/ : su_STATE_GUT_ACT_QUICK);
	exit(rv);
}

#ifdef a_HAVE_LOG_FIFO /* {{{ */
static void
a_server__logger(struct a_pg *pgp, pid_t srvpid){
	/* Cannot use ASSERT or any other thing that could log */
	sigset_t ssn;
	uz i;
	s32 rv;
	NYD_IN;

	su_program = VAL_NAME;
	su_state_clear(su_STATE_LOG_SHOW_PID);
	rv = su_EX_OK;

	/* The logger shall die only when the "real server" terminates.  Keep reafd open ourselves */
	signal(SIGCHLD, &a_server__on_sig);
	sigemptyset(&ssn);
	sigaddset(&ssn, SIGCHLD);
# if defined a_SANDBOX_SIGNAL && VAL_OS_SANDBOX > 1
	sigaddset(&ssn, a_SANDBOX_SIGNAL);
# endif
	sigprocmask(SIG_UNBLOCK, &ssn, NIL);

	if(LIKELY(!su_state_has(su_STATE_REPRODUCIBLE))){
		closelog();
		openlog(su_program, a_OPENLOG_FLAGS_LOGGER, LOG_MAIL);
	}

	while(!a_server_chld){
		boole sync;
		char c;
		ssize_t ra, r;

		/* The message is [0]=1(server)|2(client), [1]=log prio, [3,4]=length (11 bit).
		 * If that is not what there is, read bytewise until we synchronized.
		 * The length is always smaller than what a pipe can serve atomically */
		ra = 0;
jsynced:
		do if((r = read(pgp->pg_logfd, &pgp->pg_buf[S(uz,ra)], 4 - S(uz,ra))) <= 0){
			if(r == 0 || a_server_chld)
				goto jeio;
			if(su_err_by_errno() != su_ERR_INTR)
				goto jeio;
			goto jsynced;
		}while((ra += r) != 4);

		if(((c = pgp->pg_buf[0]) == '\01' || c == '\02') &&
				(C2UZ(pgp->pg_buf[1]) & ~S(uz,su_LOG_PRIMASK)) == 0){
			sync = TRU1;
			i = C2UZ(pgp->pg_buf[2]) | (C2UZ(pgp->pg_buf[3]) << 8u);
			if(i >= sizeof(pgp->pg_buf) - (4+1 +1)) /* (see misc_log_write()) */
				goto jneedsync;
			i -= 4;
		}else{
			for(ra = 1; ra < 4; ++ra){
				if((c = pgp->pg_buf[S(uz,ra)]) == '\01' || c == '\02'){
					su_mem_move(pgp->pg_buf, &pgp->pg_buf[ra], 4 - S(uz,ra));
					goto jsynced;
				}
			}
jneedsync:
			sync = FAL0;
			ra = 0;
			i = 1;
		}

		do{
			r = read(pgp->pg_logfd, &pgp->pg_buf[S(uz,ra)], i);
			if(r <= 0){
				if(r == 0 || a_server_chld)
					goto jeio;
				if(su_err_by_errno() != su_ERR_INTR)
					goto jeio;
				continue;
			}
			ra += r;
			i -= S(uz,r);
		}while(i != 0);

		if(!sync){
			if((c = pgp->pg_buf[0]) == '\01' || c == '\02'){
				ra = 1;
				goto jsynced;
			}
			goto jneedsync;
		}

		/* No matter what, this is a single message for us now. */
		if(ra <= (4 +1))
			continue;
		/* xxx We could normalize again, like misc_log_write() yet did? */
		pgp->pg_buf[S(uz,ra) - 1] = '\0'; /* should be yet */

		if(LIKELY(!su_state_has(su_STATE_REPRODUCIBLE)))
			syslog(S(int,pgp->pg_buf[1]), "%s", &pgp->pg_buf[4]);
		else
			write(STDERR_FILENO, &pgp->pg_buf[4], S(uz,ra) - 4 -1);
	}

	/* If we have some real I/O error (what could that be?) we have to terminate the real server */
jeio:
	for(i = 0; !a_server_chld; ++i){
		kill((i == 10 ? SIGKILL : SIGTERM), srvpid);
		su_time_msleep(100u * i, TRU1);
	}

	close(pgp->pg_logfd);
	if(!su_path_rm(a_FIFO_NAME)){
		/*su_log_write(su_LOG_CRIT, _("cannot remove privsep log fifo: %s"), V_(su_err_doc(-1)));*/
		rv = su_EX_OSERR;
	}

	/* Goes home with exit close(m.m_reafd);*/

	su_state_gut(rv == su_EX_OK ? su_STATE_GUT_ACT_NORM /*DVL(| su_STATE_GUT_MEM_TRACE)*/ : su_STATE_GUT_ACT_QUICK);
	NYD_OU;
	exit(rv);
}
#endif /* a_HAVE_LOG_FIFO }}} */

/* __(wb_)?(setup|reset)?() {{{ */
static s32
a_server__setup(struct a_pg *pgp){
	/* Signals blocked xxx _INTR thus no longer happens.. */
	struct a_master *mp;
	s32 rv;
	NYD_IN;

#if su_OS_FREEBSD /* XXX */
	if((pgp->pg_store_path_real = realpath(pgp->pg_store_path, NIL)) == NIL){
		rv = su_err_by_errno();
		su_log_write(su_LOG_CRIT, _("cannot get realpath(3) of %s: %s"),
			pgp->pg_store_path, V_(su_err_doc(rv)));
		rv = su_EX_IOERR;
		goto jleave;
	}
#endif

	mp = pgp->pg_master;

	while(ftruncate(mp->m_reafd, 0) == -1){
		if((rv = su_err_by_errno()) != su_ERR_INTR)
			goto jepid;
	}
	/* C99 */{
		uz i;

		pgp->pg_r = su_ienc_sz(pgp->pg_buf, S(sz,getpid()), 10);
		i = su_cs_len(pgp->pg_r);
		pgp->pg_r[i++] = '\n';
		pgp->pg_r[i] = '\0';

		while(i > 0){
			ssize_t j;

			j = write(mp->m_reafd, pgp->pg_r, 1);
			if(j == -1 && (rv = su_err_by_errno()) != su_ERR_INTR)
				goto jepid;
			pgp->pg_r += S(uz,j);
			i -= S(uz,j);
		}
	}

	mp->m_cli_fds = su_TALLOC(s32, pgp->pg_server_queue);

	su_cs_dict_create(&mp->m_white.wb_ca, a_WB_CA_FLAGS, NIL);
	su_cs_dict_create(&mp->m_white.wb_cname, a_WB_CNAME_FLAGS, NIL);
	su_cs_dict_create(&mp->m_black.wb_ca, a_WB_CA_FLAGS, NIL);
	su_cs_dict_create(&mp->m_black.wb_cname, a_WB_CNAME_FLAGS, NIL);
	if((rv = a_server__wb_setup(pgp, FAL0)) != su_EX_OK)
		goto jleave;

	a_server__gray_create(pgp);

jleave:
	NYD_OU;
	return rv;

jepid:
	su_log_write(su_LOG_CRIT, _("cannot update server PID to reassurance lock %s/%s: %s"),
		pgp->pg_store_path, a_REA_NAME, V_(su_err_doc(rv)));
	rv = su_EX_IOERR;
	goto jleave;
}

static s32
a_server__reset(struct a_pg *pgp){
	sigset_t ssn, sso;
	struct a_master *mp;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;

	sigfillset(&ssn);
#if defined a_SANDBOX_SIGNAL && VAL_OS_SANDBOX > 1
	sigdelset(&ssn, a_SANDBOX_SIGNAL);
#endif
	sigprocmask(SIG_BLOCK, &ssn, &sso);

	close(pgp->pg_clima_fd);

	mp = pgp->pg_master;

#if a_DBGIF
	su_cs_dict_gut(&mp->m_gray);

	a_server__wb_reset(mp);
	su_cs_dict_gut(&mp->m_black.wb_ca);
	su_cs_dict_gut(&mp->m_black.wb_cname);
	su_cs_dict_gut(&mp->m_white.wb_ca);
	su_cs_dict_gut(&mp->m_white.wb_cname);

	su_FREE(mp->m_cli_fds);
#endif

	if(su_path_rm_at(
#if su_OS_FREEBSD
			pgp->pg_rootfd
#else
			su_PATH_AT_FDCWD
#endif
			, mp->m_sockpath, su_IOPF_AT_NONE))
		rv = su_EX_OK;
	else{
		su_log_write(su_LOG_CRIT, _("cannot remove client/server socket %s/%s: %s"),
			pgp->pg_store_path, mp->m_sockpath, V_(su_err_doc(-1)));
		rv = su_EX_OSERR;
	}

#if a_DBGIF
# if su_OS_FREEBSD /* XXX */
	free(pgp->pg_store_path_real);
# endif

	a_sandbox_path_reset(pgp, TRU1);
#endif

	/* Reassurance lock FD last. */
	close(mp->m_reafd);

	sigprocmask(SIG_SETMASK, &sso, NIL);

	NYD_OU;
	return rv;
}

static s32
a_server__wb_setup(struct a_pg *pgp, boole reset){
	sigset_t ssn, sso;
	struct su_avopt avo;
	s32 rv;
	BITENUM_IS(u32,a_avo_flags) f;
	struct a_master *mp;
	NYD_IN;

	mp = pgp->pg_master;

	if(reset){
		sigfillset(&ssn);
#if defined a_SANDBOX_SIGNAL && VAL_OS_SANDBOX > 1
		sigdelset(&ssn, a_SANDBOX_SIGNAL);
#endif
		sigprocmask(SIG_BLOCK, &ssn, &sso);

		a_sandbox_path_reset(pgp, FAL0);
		a_server__wb_reset(mp);
	}

	su_cs_dict_add_flags(&mp->m_white.wb_ca, su_CS_DICT_FROZEN);
	su_cs_dict_add_flags(&mp->m_white.wb_cname, su_CS_DICT_FROZEN);
	su_cs_dict_add_flags(&mp->m_black.wb_ca, su_CS_DICT_FROZEN);
	su_cs_dict_add_flags(&mp->m_black.wb_cname, su_CS_DICT_FROZEN);

	if(reset){
		a_conf_setup(pgp, a_AVO_RELOAD);
		f = a_AVO_NONE | a_AVO_RELOAD;
	}else{
		pgp->pg_flags |= a_F_MASTER_IN_SETUP;
jreavo:
		f = a_AVO_FULL | a_AVO_RELOAD;
	}
	su_avopt_setup(&avo, pgp->pg_argc, C(char const*const*,pgp->pg_argv), a_sopts, a_lopts);

	while((rv = su_avopt_parse(&avo)) != su_AVOPT_STATE_DONE){
		switch(rv){
		a_AVOPT_CASES
			if((rv = a_conf_arg(pgp, rv, avo.avo_current_arg, f)) < 0){
				rv = -rv;
				goto jleave;
			}
			break;
		default:
			break;
		}
	}

	if(reset > FAL0){
		reset = TRUM1;
		a_conf_finish(pgp, a_AVO_RELOAD);
		goto jreavo;
	}

	if(pgp->pg_flags & a_F_MODE_STARTUP){
		a_DBG(su_log_write(su_LOG_DEBUG, "--startup server, setting --server-timeout=0");)
		pgp->pg_server_timeout = 0;
	}

	su_cs_dict_balance(&mp->m_white.wb_ca);
	su_cs_dict_balance(&mp->m_white.wb_cname);
	su_cs_dict_balance(&mp->m_black.wb_ca);
	su_cs_dict_balance(&mp->m_black.wb_cname);

	if(reset && (pgp->pg_flags & a_F_VV))
		su_log_write(su_LOG_INFO, "reloaded configuration");

	rv = su_EX_OK;
jleave:
	pgp->pg_flags &= ~S(uz,a_F_MASTER_IN_SETUP);

	if(reset)
		sigprocmask(SIG_SETMASK, &sso, NIL);

	NYD_OU;
	return rv;
}

static void
a_server__wb_reset(struct a_master *mp){
	struct a_srch *pgsp;
	NYD_IN;

	su_cs_dict_clear(&mp->m_black.wb_ca);
	su_cs_dict_clear(&mp->m_black.wb_cname);
	su_cs_dict_clear(&mp->m_white.wb_ca);
	su_cs_dict_clear(&mp->m_white.wb_cname);

	while((pgsp = mp->m_white.wb_srch) != NIL){
		mp->m_white.wb_srch = pgsp->s_next;
		su_FREE(pgsp);
	}

	NYD_OU;
}
/* }}} */

static s32
a_server__loop(struct a_pg *pgp){ /* {{{ */
	fd_set rfds;
	sigset_t psigset, psigseto;
	union {struct timespec os; struct su_timespec s; struct a_srch *pgsp;} t;
	u32 ograycnt;
	struct a_master *mp;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;
	mp = pgp->pg_master;
	ograycnt = su_cs_dict_count(&mp->m_gray) + a_GRAY_MIN_LIMIT;
	ASSERT(su_cs_dict_flags(&mp->m_gray) & su_CS_DICT_FROZEN);

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

	a_sandbox_server(pgp);

	while(a_pg != NIL){
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

		for(i = 0; i < mp->m_cli_no; ++i){
			x = mp->m_cli_fds[i];
			FD_SET(x, rfdsp);
			maxfd = MAX(maxfd, x);
		}

		if(pgp->pg_flags & a_F_MASTER_ACCEPT_SUSPENDED){
			t.os.tv_sec = 2;
			t.os.tv_nsec = 0;
			tosp = &t.os;
			/* Had accept(2) failure, have no clients: only sleep a bit */
			if(maxfd < 0){
				rfdsp = NIL;
				a_DBG2(su_log_write(su_LOG_DEBUG, "select: suspend,sleep");)
			}else{
				a_DBG2(su_log_write(su_LOG_DEBUG, "select: suspend,maxfd=%d", maxfd);)
			}
		}else if(mp->m_cli_no < pgp->pg_server_queue){
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

			a_DBG2(su_log_write(su_LOG_DEBUG, "select: maxfd=%d timeout=%d (%lu)",
				maxfd, (tosp != NIL), (tosp != NIL ? S(ul,tosp->tv_sec) : 0));)
		}else{
			a_DBG(su_log_write(su_LOG_DEBUG, "select(2): reached server_queue=%d, no accept-waiting", maxfd);)
		}

		/* Poll descriptors interruptable */
		if((x = pselect(maxfd + 1, rfdsp, NIL, NIL, tosp, &psigseto)) == -1){
			if((e = su_err_by_errno()) == su_ERR_INTR)
				continue;
			su_log_write(su_LOG_CRIT, _("select(2) failed: %s"), V_(su_err_doc(e)));
			rv = su_EX_IOERR;
			goto jleave;
		}else if(x == 0){
			if(pgp->pg_flags & a_F_MASTER_ACCEPT_SUSPENDED){
				pgp->pg_flags &= ~S(uz,a_F_MASTER_ACCEPT_SUSPENDED);
				a_DBG(su_log_write(su_LOG_DEBUG, "select(2): un-suspend");)
				continue;
			}

			ASSERT(mp->m_cli_no == 0);
			a_DBG(su_log_write(su_LOG_DEBUG, "no clients, timeout: bye!");)
			break;
		}

		/* ..if no DB was loaded */
		mp->m_epoch = su_timespec_current(&t.s)->ts_sec;
		if(mp->m_base_epoch == 0)
			mp->m_base_epoch = mp->m_epoch;
		else{
			/* XXX-MONO */
			s64 be;

			be = mp->m_base_epoch;
			if(t.s.ts_sec < be){
				mp->m_base_epoch = t.s.ts_sec;
				be = 0;
			}else
				be = t.s.ts_sec - be;

			/* Suspension excessed datatype storage / --gc-timeout: clear */
			i = S(u32,be / (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));
			if(i >= pgp->pg_gc_timeout){
				a_DBG(su_log_write(su_LOG_DEBUG, "select(2) timeout >= gc_timeout: clearing gray DB");)
				/* xxx The balance() could fail to reallocate the base array!
				 * xxx Since we handle insertion failures it is ugly but ..ok */
				su_cs_dict_balance(su_cs_dict_clear(&mp->m_gray));
				mp->m_base_epoch = mp->m_epoch;
				i = 0;
			}
			mp->m_epoch_min = S(s16,i);
		}

		/* */
		for(i = 0; i < mp->m_cli_no; ++i)
			if(FD_ISSET(mp->m_cli_fds[i], &rfds)){
				a_server__cli_ready(pgp, i);
				if(a_pg == NIL)
					goto jleave;
			}

		if(a_pg == NIL)
			goto jleave;

		/* */
		if(FD_ISSET(pgp->pg_clima_fd, &rfds)){
			if((x = accept(pgp->pg_clima_fd, NIL, NIL)) == -1){
				/* Just skip this mess for now, and pause accept(2) */
				pgp->pg_flags |= a_F_MASTER_ACCEPT_SUSPENDED;
				a_DBG(su_log_write(su_LOG_DEBUG, "accept(2): suspending for a bit: %s", V_(su_err_doc(x)));)
			}else if(!a_sandbox_sock_accepted(pgp, x)){
				rv = su_EX_OSERR;
				goto jleave;
			}else{
				mp->m_cli_fds[mp->m_cli_no++] = x;
				a_DBG2(su_log_write(su_LOG_DEBUG, "accept(2)ed client=%u fd=%d", mp->m_cli_no, x);)
			}
			/* XXX non-empty accept queue MUST cause more select(2) wakes */
		}

		/* Check for DB cleanup; need to recalculate XXX m_epoch_min up2date */
		ASSERT(mp->m_epoch_min == S(u16,(mp->m_epoch - mp->m_base_epoch) /
				(su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS)));
		i = S(u16,mp->m_epoch_min);
		if(i >= pgp->pg_gc_timeout >> 1 || (i >= su_TIME_DAY_MINS &&
				su_cs_dict_count(&mp->m_gray) >= pgp->pg_limit - (pgp->pg_limit >> 2)))
			a_server__gray_cleanup(pgp, FAL0);
		/* Otherwise we may need to allow the dict to grow; it is frozen all the
		 * time to move expensive growing out of the way of waiting clients.
		 * (Of course some may wait now, too.)  Misuse MIN_LIMIT for that! */
		else if(su_cs_dict_count(&mp->m_gray) > ograycnt){
			ograycnt = su_cs_dict_count(&mp->m_gray) + a_GRAY_MIN_LIMIT;
			mp->m_cleanup_cnt = 0;
			su_cs_dict_add_flags(su_cs_dict_balance(&mp->m_gray), su_CS_DICT_FROZEN);
		}
	}

jleave:
	if(!a_server__gray_save(pgp) && rv == su_EX_OK)
		rv = su_EX_CANTCREAT;

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
	struct a_srch *pgsp;
	ul i1, i2;
	enum su_log_level olvl;
	struct a_master *mp;
	NYD2_IN;

	olvl = su_log_get_level();
	su_log_set_level(su_LOG_INFO);

	mp = pgp->pg_master;

	for(i1 = 0, pgsp = mp->m_white.wb_srch; pgsp != NIL; ++i1, pgsp = pgsp->s_next){
	}
	for(i2 = 0, pgsp = mp->m_black.wb_srch; pgsp != NIL; ++i2, pgsp = pgsp->s_next){
	}

	su_log_write(su_LOG_INFO,
		_("clients %lu of %lu; in following: exact/wildcard counts [(size)]\n"
		  "white: CA %lu (%lu) / %lu, CNAME %lu (%lu) [/?]\n"
		  "-hits: CA %lu/%lu, CNAME %lu/%lu\n"
		  "black: CA %lu (%lu) / %lu, CNAME %lu (%lu) [/?]\n"
		  "-hits: CA %lu/%lu, CNAME %lu/%lu\n"
		  "gray: %lu (%lu), gc_cnt %lu; epoch: base %lu, now %lu, minutes %lu\n"
		  "-hits: new %lu, defer %lu, pass %lu"),
		S(ul,mp->m_cli_no), S(ul,pgp->pg_server_queue),
		S(ul,su_cs_dict_count(&mp->m_white.wb_ca)), S(ul,su_cs_dict_size(&mp->m_white.wb_ca)), i1,
				S(ul,su_cs_dict_count(&mp->m_white.wb_cname)),
					S(ul,su_cs_dict_size(&mp->m_white.wb_cname)),
			mp->m_cnt_white.wbc_ca, mp->m_cnt_white.wbc_ca_fuzzy,
				mp->m_cnt_white.wbc_cname, mp->m_cnt_white.wbc_cname_fuzzy,
		S(ul,su_cs_dict_count(&mp->m_black.wb_ca)), S(ul,su_cs_dict_size(&mp->m_black.wb_ca)), i2,
				S(ul,su_cs_dict_count(&mp->m_black.wb_cname)),
					S(ul,su_cs_dict_size(&mp->m_black.wb_cname)),
			mp->m_cnt_black.wbc_ca, mp->m_cnt_black.wbc_ca_fuzzy,
				mp->m_cnt_black.wbc_cname, mp->m_cnt_black.wbc_cname_fuzzy,
		S(ul,su_cs_dict_count(&mp->m_gray)), S(ul,su_cs_dict_size(&mp->m_gray)),
			S(ul,mp->m_cleanup_cnt), S(ul,mp->m_base_epoch), S(ul,mp->m_epoch),
			S(ul,mp->m_epoch_min),
		mp->m_cnt_gray_new, mp->m_cnt_gray_defer, mp->m_cnt_gray_pass
		);

#if DVLDBGOR(1, 0)
	a_DBG2(
		su_log_write(su_LOG_INFO, "WHITE CA:");
		su_cs_dict_statistics(&mp->m_white.wb_ca);
		su_log_write(su_LOG_INFO, "WHITE CNAME:");
		su_cs_dict_statistics(&mp->m_white.wb_cname);
		su_log_write(su_LOG_INFO, "BLACK CA:");
		su_cs_dict_statistics(&mp->m_black.wb_ca);
		su_log_write(su_LOG_INFO, "BLACK CNAME:");
		su_cs_dict_statistics(&mp->m_black.wb_cname);
		su_log_write(su_LOG_INFO, "GRAY:");
		su_cs_dict_statistics(&mp->m_gray);
	)
#endif

	su_log_set_level(olvl);

	NYD2_OU;
} /* }}} */

static void
a_server__cli_ready(struct a_pg *pgp, u32 client){ /* {{{ */
	/* xxx should use FIONREAD nonetheless, or O_NONBLOCK. (On the other hand .. clear postfix protocol etc etc) */
	ssize_t all, osx;
	uz rem;
	struct a_master *mp;
	NYD_IN;

	mp = pgp->pg_master;
	rem = sizeof(pgp->pg_buf);
	all = 0;
jredo:
	osx = read(mp->m_cli_fds[client], &pgp->pg_buf[S(uz,all)], rem);
	if(osx == -1){
		if(su_err_by_errno() == su_ERR_INTR)
			goto jredo;

jcli_err:
		su_log_write(su_LOG_CRIT, _("client fd=%d read() failed, dropping client: %s"),
			mp->m_cli_fds[client], V_(su_err_doc(-1)));
		close(mp->m_cli_fds[client]);
		goto jcli_del;
	}else if(osx == 0){
		a_DBG2(su_log_write(su_LOG_DEBUG, "client fd=%d disconnected, %u remain",
			mp->m_cli_fds[client], mp->m_cli_no - 1);)
jcli_del:
		close(mp->m_cli_fds[client]);
		/* _copy() */
		su_mem_move(&mp->m_cli_fds[client], &mp->m_cli_fds[client + 1],
			(--mp->m_cli_no - client) * sizeof(mp->m_cli_fds[0]));
	}else{
		all += osx;
		rem -= S(uz,osx);

		/* Buffer is always sufficiently spaced, unless bogus */
		if(rem == 0){
			su_err_set(su_ERR_MSGSIZE);
			goto jcli_err;
		}

		/* Client requests are terminated with \0\0, at least one byte payload */
		if(all < 3 || pgp->pg_buf[all - 1] != '\0' || pgp->pg_buf[all - 2] != '\0')
			goto jredo;

		/* Is it a special payload? */
		if(all == 3){
			/* ENQ: startup acknowledge, EOT: shutdown request */
			ASSERT(pgp->pg_buf[0] == '\05' || pgp->pg_buf[0] == '\04');
			if(pgp->pg_buf[0] == '\05'){
				a_DBG2(su_log_write(su_LOG_DEBUG, "client fd=%d startup acknowledge request",
					mp->m_cli_fds[client]);)
			}else{
				a_DBG2(su_log_write(su_LOG_DEBUG, "client fd=%d shutdown request",
					mp->m_cli_fds[client]);)
				a_pg = NIL;
				goto jleave;
			}
		}else
			pgp->pg_buf[0] = a_server__cli_req(pgp, client, S(uz,all));

		for(;;){
			if(write(mp->m_cli_fds[client], pgp->pg_buf, sizeof(pgp->pg_buf[0])) == -1){
				if(su_err_by_errno() == su_ERR_INTR)
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
	struct a_master *mp;
	NYD_IN;
	ASSERT(len > 0);
	ASSERT(pgp->pg_buf[len -1] == '\0');
	UNUSED(client);
	UNUSED(len);

	mp = pgp->pg_master;

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

	if(pgp->pg_flags & a_F_VV)
		su_log_write(su_LOG_INFO, "client fd=%d bytes=%lu R=%u<%s> S=%u<%s> CA=%u<%s> CNAME=%u<%s>",
			mp->m_cli_fds[client], S(ul,len), r_l, pgp->pg_r, s_l, pgp->pg_s,
			ca_l, pgp->pg_ca, cn_l, pgp->pg_cname);

	rv = a_ANSWER_ALLOW;
	if(a_server__cli_lookup(pgp, &mp->m_white, &mp->m_cnt_white))
		goto jleave;

	rv = a_ANSWER_BLOCK;
	if(a_server__cli_lookup(pgp, &mp->m_black, &mp->m_cnt_black))
		goto jleave;

	pgp->pg_s[-1] = '/';
	pgp->pg_ca[-1] = '/';
	rv = a_server__gray_lookup(pgp, pgp->pg_buf);

jleave:
	NYD_OU;
	return rv;
} /* }}} */

static boole
a_server__cli_lookup(struct a_pg *pgp, struct a_wb *wbp, struct a_wb_cnt *wbcp){ /* {{{ */
	char const *me;
	boole rv;
	NYD_IN;

	rv = TRU1;
	me = (wbp == &pgp->pg_master->m_white) ? "allow" : "block";

	/* */
	if(su_cs_dict_has_key(&wbp->wb_ca, pgp->pg_ca)){
		++wbcp->wbc_ca;
		if(pgp->pg_flags & a_F_V)
			su_log_write(su_LOG_INFO, "### %s address: %s", me, pgp->pg_ca);
		goto jleave;
	}

	/* C99 */{
		char const *cp;
		boole first;

		for(first = TRU1, cp = pgp->pg_cname;; first = FAL0){
			union {void *p; up v;} u;

			if((u.p = su_cs_dict_lookup(&wbp->wb_cname, cp)) != NIL && (first || u.v != TRU1)){
				if(first)
				  ++wbcp->wbc_cname;
				else
				  ++wbcp->wbc_cname_fuzzy;
				if(pgp->pg_flags & a_F_V)
					su_log_write(su_LOG_INFO, "### %s %sdomain: %s",
						me, (first ? su_empty : _("wildcard ")), cp);
				goto jleave;
			}

			if((cp = su_cs_find_c(cp, '.')) == NIL || *++cp == '\0')
				break;
		}
	}

	/* Fuzzy IP search */{
		union a_srch_ip c_sip;
		struct a_srch *pgsp;
		u32 *c_ip;
		int c_af;

		/* xxx Client had this already, simply binary pass it, too? */
		c_af = (su_cs_find_c(pgp->pg_ca, ':') != NIL) ? AF_INET6 : AF_INET;
		if(inet_pton(c_af, pgp->pg_ca, (c_af == AF_INET ? S(void*,&c_sip.v4) : S(void*,&c_sip.v6))) != 1){
			su_log_write(su_LOG_CRIT, _("Cannot re-parse an already prepared IP address?: "), pgp->pg_ca);
			goto jleave0;
		}
		c_ip = (c_af == AF_INET) ? R(u32*,&c_sip.v4.s_addr) : R(u32*,c_sip.v6.s6_addr);

		for(pgsp = wbp->wb_srch; pgsp != NIL; pgsp = pgsp->s_next){
			u32 *ip, max, m, xm, i;

			if(c_af == AF_INET){
				if(!(pgsp->s_flags & a_SRCH_IPV4))
					continue;
				ip = R(u32*,&pgsp->s_ip.v4.s_addr);
				max = 1;
			}else if(!(pgsp->s_flags & a_SRCH_IPV6))
				continue;
			else{
				ip = S(u32*,R(void*,pgsp->s_ip.v6.s6_addr));
				max = 4;
			}

			for(m = pgsp->s_mask, i = 0;;){
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
					++wbcp->wbc_ca_fuzzy;
					if(pgp->pg_flags & a_F_V)
						su_log_write(su_LOG_INFO, "### %s wildcard address: %s", me, pgp->pg_ca);
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
#ifdef a_HAVE_LOG_FIFO
	if(sig == SIGCHLD)
		a_server_chld = 1;
	else
#endif
	     if(sig == SIGHUP)
		a_server_hup = 1;
	else if(sig == SIGTERM)
		a_pg = NIL;
	else if(sig == SIGUSR1)
		a_server_usr1 = 1;
	else if(sig == SIGUSR2)
		a_server_usr2 = 1;
}

/* gray {{{ */
static void
a_server__gray_create(struct a_pg *pgp){
	struct a_master *mp;
	NYD_IN;

	mp = pgp->pg_master;

	/* Perform the initial allocation without _ERR_PASS so that we panic if we
	 * cannot create it, then set _ERR_PASS to handle (ignore) errors */
	su_cs_dict_resize(su_cs_dict_set_min_size(su_cs_dict_set_threshold_shift(
				su_cs_dict_create(&mp->m_gray, (a_GRAY_FLAGS | su_CS_DICT_FROZEN), NIL),
			a_GRAY_TS), a_GRAY_MIN_LIMIT), 1);

	a_server__gray_load(pgp);

	/* Finally enable automatic memory management, balance as necessary */
	su_cs_dict_add_flags(&mp->m_gray, su_CS_DICT_ERR_PASS);
	if(su_cs_dict_count(&mp->m_gray) > a_GRAY_MIN_LIMIT)
		su_cs_dict_add_flags(su_cs_dict_balance(&mp->m_gray), su_CS_DICT_FROZEN);

	NYD_OU;
}

static void
a_server__gray_load(struct a_pg *pgp){ /* {{{ */
	struct su_pathinfo pi;
	struct su_timespec ts;
	char *base;
	s16 min;
	s32 i;
	union {sz l; void *v; char *c;} p;
	void *mbase;
	NYD_IN;

	/* Obtain a memory map on the DB storage (only called once on server startup, note: pre-sandbox!) */
	mbase = NIL;

	while((i = a_sandbox_open(pgp, TRU1, a_GRAY_DB_NAME, O_RDONLY, 0)) == -1){
		if((i = su_err_by_errno()) == su_ERR_INTR)
			continue;
		if(a_misc_os_resource_delay(i))
			continue;
		if(i != su_ERR_NOENT)
			su_log_write(su_LOG_ERR, _("cannot load gray DB in %s: %s"), pgp->pg_store_path, V_(su_err_doc(-1)));
		goto jleave;
	}

	if(!su_pathinfo_fstat(&pi, i)){
		su_log_write(su_LOG_ERR, _("cannot fstat(2) gray DB in %s: %s"), pgp->pg_store_path, V_(su_err_doc(-1)));
		p.l = -1;
	}else{
		p.v = mmap(NIL, S(uz,pi.pi_size)/* (max 2GB) */, PROT_READ, MAP_SHARED, i, 0);
		if(p.l == -1)
			su_log_write(su_LOG_ERR, _("cannot mmap(2) gray DB in %s: %s"),
				pgp->pg_store_path, V_(su_err_doc(su_err_by_errno())));
	}

	close(i);

	if(p.l == -1)
		goto jleave;
	mbase = p.v;

	pgp->pg_master->m_base_epoch = su_timespec_current(&ts)->ts_sec;

	/* (Saving DB stops before S32_MAX bytes, but .. do) */
	for(min = S16_MAX, base = p.c, i = MIN(S32_MAX, S(s32,pi.pi_size)); i > 0; ++p.c, --i){
		s64 ibuf;
		union {u32 f; uz z;} u;

		/* Complete a line first */
		if(*p.c != '\n')
			continue;

		if(&base[2] >= p.c)
			goto jerr;

		u.f = su_idec(&ibuf, base, P2UZ(p.c - base), 10, 0, C(char const**,&base));
		if((u.f & su_IDEC_STATE_EMASK) || UCMP(64, ibuf, >, U32_MAX))
			goto jerr;

		/* The first line is only base epoch */
		if(min == S16_MAX){
			if(*base != '\n')
				goto jerr;

			min = S(s16,(pgp->pg_master->m_base_epoch - ibuf) /
					(su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));

			if(/*UCMP(16, min, >=, S16_MAX) ||*/ min >= pgp->pg_gc_timeout){
				if(a_DBGIF || (pgp->pg_flags & a_F_V))
					su_log_write(su_LOG_INFO, _("skipping timed out gray DB content in %s"),
						pgp->pg_store_path);
				goto jleave;
			}
		}else if(*base++ != ' ')
			goto jerr;
		/* [no recipient]/s[ender]/c[lient address] */
		else if((u.z = P2UZ(p.c - base)) >= a_BUF_SIZE || u.z <= 2+2)
			goto jerr;
		else{
			char key[a_BUF_SIZE];
			s32 insrv;
			s16 nmin;
			up d;

			if(pgp->pg_flags & a_F_FOCUS_SENDER){
				while(*base != '/'){
					if(--u.z == 0)
						goto jerr;
					++base;
				}
			}
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
			insrv = su_cs_dict_insert(&pgp->pg_master->m_gray, key, R(void*,d));
			if(insrv > su_ERR_NONE){
				su_log_write(su_LOG_ERR, _("after out of memory skipping rest of gray DB in %s"),
					pgp->pg_store_path);
				goto jleave;
			}
			a_DBG(su_log_write(su_LOG_DEBUG, "load%s: acc=%d, count=%d min=%hd: %s",
				(insrv == -1 ? " -> replace" : su_empty),
				!!(d & 0x80000000), S(ul,(d & 0x7FFF0000) >> 16), nmin, key);)
		}

jskip:
		base = &p.c[1];
	}

	if(base != p.c)
jerr:
		su_log_write(su_LOG_WARN, _("corrupt gray DB in %s"), pgp->pg_store_path);

	if(a_DBGIF || (pgp->pg_flags & a_F_V)){
		struct su_timespec ts2;

		su_timespec_sub(su_timespec_current(&ts2), &ts);
		su_log_write(su_LOG_INFO, _("loaded %lu entries in %lu:%09lu seconds from gray DB in %s"),
			S(ul,su_cs_dict_count(&pgp->pg_master->m_gray)),
			S(ul,ts2.ts_sec), S(ul,ts2.ts_nano), pgp->pg_store_path);
	}

jleave:
	if(mbase != NIL)
		munmap(mbase, S(uz,pi.pi_size));

	NYD_OU;
	return;
} /* }}} */

static boole
a_server__gray_save(struct a_pg *pgp){ /* {{{ */
	/* Signals are blocked */
	struct su_timespec ts;
	struct su_cs_dict_view dv;
	s16 min;
	char *cp;
	uz cnt, xlen;
	s32 fd;
	boole rv;
	NYD_IN;

	rv = TRU1;

	while((fd = a_sandbox_open(pgp, TRU1, a_GRAY_DB_NAME, (O_WRONLY | O_CREAT | O_TRUNC),
			S_IRUSR | S_IWUSR)) == -1){
		if((fd = su_err_by_errno()) == su_ERR_INTR)
			continue;
		if(a_misc_os_resource_delay(fd))
			continue;
		su_log_write(su_LOG_CRIT, _("cannot create gray DB in %s: %s"),
			pgp->pg_store_path, V_(su_err_doc(su_err_by_errno())));
		rv = FAL0;
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

		be = pgp->pg_master->m_base_epoch;
		if(ts.ts_sec < be){
			pgp->pg_master->m_base_epoch = be;
			be = 0;
		}else
			be = ts.ts_sec - be;
		min = S(s16,be / (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));
	}

	su_CS_DICT_FOREACH(&pgp->pg_master->m_gray, &dv){
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

		/* (setrlimit(2) sandbox up to that size(, too)) */
		if(UNLIKELY(S(uz,S32_MAX) - i < xlen)){
			su_log_write(su_LOG_WARN, _("truncating gray DB near 2GB size in: %s"), pgp->pg_store_path);
			break;
		}

		if(UCMP(z, write(fd, cp, i), !=, i))
			goto jerr;
		xlen += i;
		++cnt;

		a_DBG(su_log_write(su_LOG_DEBUG, "save: acc=%d, count=%d nmin=%hd: %s",
			!!(d & 0x80000000), S(ul,(d & 0x7FFF0000) >> 16), nmin, su_cs_dict_view_key(&dv));)
	}

jclose:
	fsync(fd);
	close(fd);

	if(a_DBGIF || (pgp->pg_flags & a_F_V)){
		struct su_timespec ts2;

		su_timespec_sub(su_timespec_current(&ts2), &ts);
		su_log_write(su_LOG_INFO, _("saved %lu entries in %lu:%09lu seconds to gray DB in %s"),
			S(ul,cnt), S(ul,ts2.ts_sec), S(ul,ts2.ts_nano), pgp->pg_store_path);
	}

jleave:
	NYD_OU;
	return rv;

jerr:
	su_log_write(su_LOG_CRIT, _("cannot write gray DB in %s: %s"),
		pgp->pg_store_path, V_(su_err_doc(su_err_by_errno())));

	if(!su_path_rm(a_GRAY_DB_NAME))
		su_log_write(su_LOG_CRIT, _("cannot even unlink corrupt gray DB in %s: %s"),
			pgp->pg_store_path, V_(su_err_doc(-1)));

	rv = FAL0;
	goto jclose;
} /* }}} */

static void
a_server__gray_cleanup(struct a_pg *pgp, boole force){ /* {{{ */
	struct su_timespec ts;
	struct su_cs_dict_view dv;
	struct a_master *mp;
	u32 c_75, c_88;
	u16 t, t_75, t_88;
	boole gc_any;
	NYD_IN;

	gc_any = FAL0;
	t = pgp->pg_gc_timeout;

	/* We may need to cleanup more, check some thresholds (avoid "uninit" warnings) */
	c_88 = c_75 = 0;
	t_88 = t_75 = t;
	if(force){
		force = TRUM1;
		t_75 -= t >> 2;
		t_88 -= t >> 3;
	}

	mp = pgp->pg_master;

	/* XXX-MONO */
	/* C99 */{
		s64 be;

		be = mp->m_base_epoch;
		mp->m_base_epoch =
		mp->m_epoch = su_timespec_current(&ts)->ts_sec;
		if(ts.ts_sec < be)
			be = 0;
		else
			be = ts.ts_sec - be;
		mp->m_epoch_min = S(s16,be / (su_state_has(su_STATE_REPRODUCIBLE) ? 1 : su_TIME_MIN_SECS));
	}

	a_DBG(su_log_write(su_LOG_DEBUG, "gc: start%s epoch=%lu min=%d",
		(force ? _(" in force mode") : su_empty), S(ul,mp->m_epoch), mp->m_epoch_min);)

	ASSERT(su_cs_dict_flags(&mp->m_gray) & su_CS_DICT_FROZEN);
jredo:
	su_cs_dict_view_setup(&dv, &mp->m_gray);
	for(su_cs_dict_view_begin(&dv); su_cs_dict_view_is_valid(&dv);){
		s16 nmin;
		up d;

		d = R(up,su_cs_dict_view_data(&dv));
		nmin = S(s16,d & U16_MAX);
		nmin -= mp->m_epoch_min;

		if(nmin < 0){
			nmin = -nmin;

			/* GC garbage */
			if(nmin >= t){
				a_DBG(su_log_write(su_LOG_DEBUG, "gc: del acc >=gc-timeout (force=%d) min=%d: %s",
					-nmin, (force > 0), su_cs_dict_view_key(&dv));)
				goto jdel;
			}

			/* Not yet accepted entries.. */
			if(!(d & 0x80000000)){
				/* GC things which would count as "new" */
				if(nmin >= pgp->pg_delay_max){
					a_DBG(su_log_write(su_LOG_DEBUG, "gc: del non-acc >=delay-max min=%d: %s",
						-nmin, su_cs_dict_view_key(&dv));)
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

		a_DBG(su_log_write(su_LOG_DEBUG, "gc: keep: acc=%d, min=%hd: %s",
			!!(d & 0x80000000), nmin, su_cs_dict_view_key(&dv));)
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
		c = su_cs_dict_count(&mp->m_gray);

		if(c > l){
			if(c - c_88 <= l)
				t = t_88;
			else if(c - c_75 <= l)
				t = t_75;
			else
				t >>= 1;
			/* else we cannot help it, really */
			a_DBG(su_log_write(su_LOG_DEBUG, "gc: forced and still too large, restart with %s gc-timeout",
				(t == t_88 ? "88%" : (t == t_75) ? "75%" : "50%"));)
			force = TRU1;
			goto jredo;
		}
	}

	if(mp->m_cleanup_cnt < S16_MAX)
		++mp->m_cleanup_cnt;

	/* Do not balance when force mode is on, client is waiting */
	if(gc_any){
		gc_any = FAL0; /* -> "was balanced" */
		if(!force && mp->m_cleanup_cnt >= pgp->pg_gc_rebalance && pgp->pg_gc_rebalance != 0){
			su_cs_dict_add_flags(su_cs_dict_balance(&mp->m_gray), su_CS_DICT_FROZEN);
			a_DBG(su_log_write(su_LOG_DEBUG, "gc: rebalance after %u: count=%u, new size=%u",
				mp->m_cleanup_cnt, su_cs_dict_count(&mp->m_gray), su_cs_dict_size(&mp->m_gray));)
			mp->m_cleanup_cnt = 0;
			gc_any = TRU1;
		}
	}

	if(a_DBGIF || (pgp->pg_flags & a_F_V)){
		struct su_timespec ts2;

		su_timespec_sub(su_timespec_current(&ts2), &ts);
		su_log_write(su_LOG_INFO, _("gray DB: count=%u: %sGC in %lu:%09lu seconds, balanced: %d"),
			su_cs_dict_count(&mp->m_gray), (force == TRU1 ? _("two round ") : su_empty),
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
	struct a_master *mp;
	char rv;
	NYD_IN;

	rv = a_ANSWER_NODEFER;
	mp = pgp->pg_master;
	cnt = 0;

	/* Key already known, .. or can be added? */
	if(!su_cs_dict_view_find(su_cs_dict_view_setup(&dv, &mp->m_gray), key)){
		u32 i;

jretry_nent:
		i = su_cs_dict_count(&mp->m_gray);
		rv = (pgp->pg_limit_delay != 0 && i >= pgp->pg_limit_delay) ? a_ANSWER_DEFER_SLEEP : a_ANSWER_DEFER;

		/* New entry may be disallowed */
		if(i < pgp->pg_limit){
			d = (pgp->pg_count == 0) ? 0x80000000u : 0;
			goto jgray_set;
		}

		/* We ran against this wall, try a cleanup if allowed */
		if(UCMP(16, mp->m_epoch_min, >=, a_DB_CLEANUP_MIN_DELAY)){
			a_server__gray_cleanup(pgp, TRU1);
			goto jretry_nent;
		}

		if(!(pgp->pg_flags & a_F_MASTER_LIMIT_EXCESS_LOGGED)){
			pgp->pg_flags |= a_F_MASTER_LIMIT_EXCESS_LOGGED;
			/*if(pgp->pg_flags & a_F_V)*/
				su_log_write(su_LOG_WARN, _("Reached --limit=%lu, excess not handled; "
						"condition is logged once only"), S(ul,pgp->pg_limit));
		}

		/* XXX Make limit excess return configurable? REJECT?? */
		rv = a_ANSWER_NODEFER;
		goto jleave;
	}

	/* Key is known */
	d = R(up,su_cs_dict_view_data(&dv));

	/* If yet accepted, update it quick */
	if(d & 0x80000000u){
		a_DBG(su_log_write(su_LOG_DEBUG, "gray up quick: %s", key);)
		ASSERT(rv == a_ANSWER_NODEFER);
		ASSERT(cnt == 0);
		goto jgray_set;
	}

	min = S(s16,d & U16_MAX);
	cnt = S(u16,(d >> 16) & S16_MAX) + 1;

	xmin = mp->m_epoch_min - min;

	/* Totally ignore it if not enough time passed */
	if(xmin < (pgp->pg_delay_min * (pgp->pg_flags & a_F_DELAY_PROGRESSIVE ? cnt : 1))){
		a_DBG(su_log_write(su_LOG_DEBUG, "gray too soon: %s (%lu,%lu,%lu)",
			key, S(ul,min), S(ul,mp->m_epoch_min), S(ul,xmin));)
		--cnt; /* (Logging) */
		rv = a_ANSWER_DEFER;
		goto jleave;
	}

	/* If too much time passed, reset: this is a new thing! */
	if(xmin > pgp->pg_delay_max){
		a_DBG(su_log_write(su_LOG_DEBUG, "gray too late: %s (%lu,%lu,%lu)",
			key, S(ul,min), S(ul,mp->m_epoch_min), S(ul,xmin));)
		rv = a_ANSWER_DEFER;
		cnt = 0;
	}
	/* If seen often enough wave through! */
	else if(cnt >= pgp->pg_count){
		a_DBG(su_log_write(su_LOG_DEBUG, "gray ok-to-go (%lu): %s", S(ul,cnt), key);)
		ASSERT(rv == a_ANSWER_NODEFER);
		cnt = 0; /* (Logging: does no longer matter) */
		d = 0x80000000u;
	}else{
		rv = a_ANSWER_DEFER;
		a_DBG(su_log_write(su_LOG_DEBUG, "gray inc count=%lu: %s", S(ul,cnt), key);)
	}

jgray_set:
	d = (d & 0x80000000u) | (S(up,cnt) << 16) | S(u16,mp->m_epoch_min);
	if(su_cs_dict_view_is_valid(&dv))
		su_cs_dict_view_set_data(&dv, R(void*,d));
	else{
		++mp->m_cnt_gray_new;
		a_DBG(su_log_write(su_LOG_DEBUG, "gray new entry: %s", key);)
		ASSERT(rv != a_ANSWER_NODEFER);

		/* Need to handle memory failures */
		while(su_cs_dict_insert(&mp->m_gray, key, R(void*,d)) > su_ERR_NONE){
			/* We ran against this wall, try a cleanup if allowed */
			if(UCMP(16, mp->m_epoch_min, >=, a_DB_CLEANUP_MIN_DELAY)){
				a_server__gray_cleanup(pgp, TRU1);
				continue;
			}

			/* XXX What if new pg_limit is ... 0 ? */
			pgp->pg_limit = su_cs_dict_count(&mp->m_gray);
			if(pgp->pg_limit_delay != 0)
				pgp->pg_limit_delay = pgp->pg_limit - (pgp->pg_limit >> 3);

			if(!(pgp->pg_flags & a_F_MASTER_NOMEM_LOGGED)){
				pgp->pg_flags |= a_F_MASTER_NOMEM_LOGGED;
				/*if(pgp->pg_flags & a_F_V)*/
					su_log_write(su_LOG_WARN,
						_("out-of-memory, reduced limit to %lu; condition is logged once only"),
						S(ul,pgp->pg_limit));
			}

			/* XXX Make limit excess return configurable? REJECT?? */
			rv = a_ANSWER_NODEFER;
			break;
		}

		if(pgp->pg_count == 0)
			rv = a_ANSWER_NODEFER;
	}

jleave:
	if(rv != a_ANSWER_NODEFER)
		++mp->m_cnt_gray_defer;
	else
		++mp->m_cnt_gray_pass;
	if(pgp->pg_flags & a_F_V)
		su_log_write(su_LOG_INFO, "### gray (defer=%d [and count=%lu]): %s",
			(rv != a_ANSWER_NODEFER), S(ul,cnt), key);

	NYD_OU;
	return rv;
} /* }}} */
/* }}} */
/* }}} */

/* conf {{{ */
static void
a_conf_setup(struct a_pg *pgp, BITENUM_IS(u32,a_avo_flags) f){
	NYD2_IN;

	pgp->pg_flags &= ~S(uz,a_F_SETUP_MASK);

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

	if(!(f & a_AVO_RELOAD)){
		LCTAV(VAL_SERVER_QUEUE <= S32_MAX);
		pgp->pg_server_queue = U32_MAX;

		pgp->pg_msg_allow = pgp->pg_msg_block = pgp->pg_msg_defer = NIL;
		pgp->pg_store_path = NIL;
	}

	NYD2_OU;
}

static void
a_conf_finish(struct a_pg *pgp, BITENUM_IS(u32,a_avo_flags) f){
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

	if(!(f & a_AVO_RELOAD)){
		if(pgp->pg_server_queue == U32_MAX)
			pgp->pg_server_queue = VAL_SERVER_QUEUE;

		if(pgp->pg_msg_allow == NIL){
			char const * const ccp = VAL_MSG_ALLOW;
			pgp->pg_msg_allow = (ccp != NIL) ? VAL_MSG_ALLOW : a_MSG_ALLOW;
			pgp->pg_flags |= a_F_NOFREE_MSG_ALLOW;
		}
		if(pgp->pg_msg_block == NIL){
			char const * const ccp = VAL_MSG_BLOCK;
			pgp->pg_msg_block = (ccp != NIL) ? VAL_MSG_BLOCK : a_MSG_BLOCK;
			pgp->pg_flags |= a_F_NOFREE_MSG_BLOCK;
		}
		if(pgp->pg_msg_defer == NIL){
			char const * const ccp = VAL_MSG_DEFER;
			pgp->pg_msg_defer = (ccp != NIL) ? VAL_MSG_DEFER : a_MSG_DEFER;
			pgp->pg_flags |= a_F_NOFREE_MSG_DEFER;
		}

		if(pgp->pg_store_path == NIL){
			pgp->pg_store_path = VAL_STORE_PATH;
			pgp->pg_flags |= a_F_NOFREE_STORE_PATH;
		}
	}

	/* */
	/* C99 */{
		char const *em_arr[5], **empp = em_arr;

		if(pgp->pg_delay_min >= pgp->pg_delay_max){
			*empp++ = _("delay-min is >= delay-max\n");
			pgp->pg_delay_min = pgp->pg_delay_max;
		}
		if((pgp->pg_flags & a_F_DELAY_PROGRESSIVE) &&
				S(uz,pgp->pg_delay_min) * pgp->pg_count >= S(uz,pgp->pg_delay_max)){
			*empp++ = _("delay-min*count is >= delay-max: -delay-progressive\n");
			pgp->pg_flags ^= a_F_DELAY_PROGRESSIVE;
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
			a_conf__err(pgp, "%s", V_(*empp));
	}

	NYD2_OU;
}

static void
a_conf_list_values(struct a_pg *pgp){
	NYD2_IN;

	/* NOTE!  For the test the four last fields must be msg-*, then store-path! */
	fprintf(stdout,
		"4-mask %lu\n"
			"6-mask %lu\n"
		"count %lu\n"
			"delay-max %lu\n"
			"delay-min %lu\n"
			"%s"
			"%s"
			"gc-rebalance %lu\n"
			"gc-timeout %lu\n"
			"limit %lu\n"
			"limit-delay %lu\n"
		"%s"
		"server-queue %lu\n"
			"server-timeout %lu\n"
		"%s"
		"%s""%s"
		"msg-allow %s\n"
			"msg-block %s\n"
			"msg-defer %s\n"
		"store-path %s\n"
		,
		S(ul,pgp->pg_4_mask), S(ul,pgp->pg_6_mask),
		S(ul,pgp->pg_count), S(ul,pgp->pg_delay_max), S(ul,pgp->pg_delay_min),
			(pgp->pg_flags & a_F_DELAY_PROGRESSIVE ? "delay-progressive\n" : su_empty),
			(pgp->pg_flags & a_F_FOCUS_SENDER ? "focus-sender\n" : su_empty),
			S(ul,pgp->pg_gc_rebalance), S(ul,pgp->pg_gc_timeout),
			S(ul,pgp->pg_limit), S(ul,pgp->pg_limit_delay),
		(pgp->pg_flags & a_F_CLIENT_ONCE ? "once\n" : su_empty),
		S(ul,pgp->pg_server_queue), S(ul,pgp->pg_server_timeout),
		(pgp->pg_flags & a_F_UNTAMED ? "untamed\n" : su_empty),
		(pgp->pg_flags & a_F_V ? "verbose\n" : su_empty),
			(pgp->pg_flags & a_F_VV ? "verbose\n" : su_empty),
		pgp->pg_msg_allow, pgp->pg_msg_block, pgp->pg_msg_defer,
		pgp->pg_store_path
		);

	NYD2_OU;
}

static s32
a_conf_arg(struct a_pg *pgp, s32 o, char const *arg, BITENUM_IS(u32,a_avo_flags) f){
	union {u8 *i8; u16 *i16; u32 *i32; char const *cp; char const **cpp;} p;
	NYD2_IN;

	/* In long-option order */
	switch(o){
	case '4':
	case '6':
		if(!(f & a_AVO_FULL)){
			u8 max;

			if(o == '4'){
				p.i8 = &pgp->pg_4_mask;
				max = 32;
			}else{
				p.i8 = &pgp->pg_6_mask;
				max = 128;
			}

			if((su_idec_u8(p.i8, arg, UZ_MAX, 10, NIL) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
					) != su_IDEC_STATE_CONSUMED || *p.i8 > max){
				a_conf__err(pgp, _("Invalid IPv%c mask: %s (max: %hhu)\n"), o, arg, max);
				o = -su_EX_DATAERR;
			}
		}break;

	case 'A':
		if(f & a_AVO_FULL){
			if((p.cp = a_sandbox_path_check(pgp, arg)) == NIL)
				goto jepath;
			o = a_conf__AB(pgp, p.cp, ((pgp->pg_flags & a_F_MODE_TEST
					) ? R(struct a_wb*,0x1) : &pgp->pg_master->m_white));
		}
		break;
	case 'a':
		if(f & a_AVO_FULL)
			o = a_conf__ab(pgp, C(char*,arg), ((pgp->pg_flags & a_F_MODE_TEST
					) ? R(struct a_wb*,0x1) : &pgp->pg_master->m_white));
		break;

	case 'B':
		if(f & a_AVO_FULL){
			if((p.cp = a_sandbox_path_check(pgp, arg)) == NIL)
				goto jepath;
			o = a_conf__AB(pgp, p.cp, ((pgp->pg_flags & a_F_MODE_TEST
					) ? NIL : &pgp->pg_master->m_black));
		}
		break;
	case 'b':
		if(f & a_AVO_FULL)
			o = a_conf__ab(pgp, C(char*,arg), ((pgp->pg_flags & a_F_MODE_TEST
					) ? NIL : &pgp->pg_master->m_black));
		break;

	case 'c': p.i32 = &pgp->pg_count; goto ji32;
	case 'D': p.i16 = &pgp->pg_delay_max; goto ji16;
	case 'd': p.i16 = &pgp->pg_delay_min; goto ji16;
	case 'p': pgp->pg_flags |= a_F_DELAY_PROGRESSIVE; break;
	case 'f': pgp->pg_flags |= a_F_FOCUS_SENDER; break;
	case 'G': p.i16 = &pgp->pg_gc_rebalance; goto ji16;
	case 'g': p.i16 = &pgp->pg_gc_timeout; goto ji16;
	case 'L': p.i32 = &pgp->pg_limit; goto ji32;
	case 'l': p.i32 = &pgp->pg_limit_delay; goto ji32;

	case 'm': p.cpp = &pgp->pg_msg_defer; goto jmsg;
	case '~': p.cpp = &pgp->pg_msg_allow; goto jmsg;
	case '!': p.cpp = &pgp->pg_msg_block; goto jmsg;

	case 'o': pgp->pg_flags |= a_F_CLIENT_ONCE; break;

	case 'R':
		p.cp = arg;
		if((f & a_AVO_FULL) && (p.cp = a_sandbox_path_check(pgp, arg)) == NIL)
			goto jepath;
		o = a_conf__R(pgp, p.cp, f);
		break;

	case 'q':
		if(f & a_AVO_RELOAD)
			break;
		p.i32 = &pgp->pg_server_queue;
		goto ji32;
	case 't': p.i16 = &pgp->pg_server_timeout; goto ji16;

	case 's':
		if(f & (a_AVO_FULL | a_AVO_RELOAD))
			break;
		if(su_cs_len(arg) + sizeof("/" a_REA_NAME) >= PATH_MAX){
			o = su_err_by_errno();
			a_conf__err(pgp, _("--store-path is a path too long: %s\n"), V_(su_err_doc(o)));
			o = -o;
			goto jleave;
		}else{
			struct su_pathinfo pi;

			if(!su_pathinfo_stat(&pi, arg) || !su_pathinfo_is_dir(&pi)){
				a_conf__err(pgp, _("--store-path is not a directory\n"));
				o = -su_ERR_NOTDIR;
				goto jleave;
			}
		}
		if(pgp->pg_store_path != NIL)
			su_FREE(UNCONST(char*,pgp->pg_store_path));
		pgp->pg_store_path = su_cs_dup(arg, su_STATE_ERR_NOPASS);
		break;

	case 'u': pgp->pg_flags |= a_F_UNTAMED; break;

	case 'v':
		if(!(f & a_AVO_FULL)){
			uz i;

			i = pgp->pg_flags;
#if DVLDBGOR(0, 1)
			if(!(i & a_F_V))
				su_log_set_level(su_LOG_INFO);
#endif
			i = ((i << 1) | a_F_V) & a_F_V_MASK;
			pgp->pg_flags = (pgp->pg_flags & ~S(uz,a_F_V_MASK)) | i;
		}break;
	}

jleave:
	if(o < 0 && (pgp->pg_flags & a_F_MODE_TEST)){
		pgp->pg_flags |= a_F_TEST_ERRORS;
		o = su_EX_OK;
	}

	NYD2_OU;
	return o;

ji16:
	if((su_idec_u16(p.i16, arg, UZ_MAX, 10, NIL) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
			) != su_IDEC_STATE_CONSUMED || UCMP(32, *p.i16, >, S16_MAX))
		goto jeiuse;
	goto jleave;

ji32:
	if((su_idec_u32(p.i32, arg, UZ_MAX, 10, NIL) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
			) != su_IDEC_STATE_CONSUMED || UCMP(32, *p.i32, >, S32_MAX))
		goto jeiuse;
	goto jleave;

jeiuse:
	a_conf__err(pgp, _("Invalid number or limit excess of -%c argument: %s\n"), o, arg);
	o = -su_EX_DATAERR;
	goto jleave;

jepath:
	a_conf__err(pgp, _("Invalid path argument to -%c argument: %s: %s\n"), o, arg, V_(su_err_doc(-1)));
	o = -su_EX_DATAERR;
	goto jleave;

jmsg:
	if(f & (a_AVO_FULL | a_AVO_RELOAD))
		goto jleave;
	if(*p.cpp != NIL)
		su_FREE(UNCONST(char*,*p.cpp));
	*p.cpp = su_cs_dup(arg, su_STATE_ERR_NOPASS);
	goto jleave;
}

static s32
a_conf__AB(struct a_pg *pgp, char const *path, struct a_wb *wbp){
	struct a_line line;
	sz lnr;
	s32 fd, rv;
	NYD2_IN;

	if((fd = a_misc_open(pgp, path)) == -1){
		rv = su_err();
		a_conf__err(pgp, _("Cannot open --allow or --block file %s: %s\n"), path, V_(su_err_doc(rv)));
		rv = -rv;
		goto jleave;
	}

	a_LINE_SETUP(&line);
	rv = su_EX_OK;
	while((lnr = a_misc_line_get(pgp, fd, &line)) != -1){
		if(lnr != 0 && (rv = a_conf__ab(pgp, line.l_buf, wbp)) != su_EX_OK){
			if(!(pgp->pg_flags & a_F_MODE_TEST))
				break;
			rv = su_EX_OK;
		}
	}
	if(rv == su_EX_OK && line.l_err != su_ERR_NONE)
		rv = -su_EX_IOERR;

	close(fd);

jleave:
	NYD2_OU;
	return rv;
}

static s32
a_conf__ab(struct a_pg *pgp, char *entry, struct a_wb *wbp){ /* {{{ */
	union a_srch_ip sip;
	struct a_srch *pgsp;
	u32 m;
	char c, *cp;
	s32 rv;
	NYD2_IN;

	rv = su_EX_OK;

	/* A bit of cleanup first */
	while((c = *entry) != '\0' && su_cs_is_space(c))
		++entry;

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
		if((su_idec_u32(&m, cp, UZ_MAX, 10, NIL) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
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

		if(!(pgp->pg_flags & a_F_MODE_TEST)){
			union {void *p; up v;} u;

			u.v = (m == 0) ? TRU1 : TRU2; /* "is exact" */
			su_cs_dict_insert(&wbp->wb_cname, cp, u.p);
		}else{
			char const *me;

			/* xxx could use C++ dns hostname check, too */
			me = (wbp != NIL) ? "allow" : "block";
			fprintf(stdout, "%s %s%s\n", me, (m == 0 ? su_empty : "."), cp);
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

	if(inet_pton(rv, entry, (rv == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6))) != 1){
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
	if((exact || (pgp->pg_flags & a_F_MODE_TEST)) &&
			inet_ntop(rv, (rv == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6)), buf, INET6_ADDRSTRLEN
				) == NIL){
		sip.cp = N_("Invalid internet address: %s\n");
		cp = UNCONST(char*,su_empty);
		goto jedata;
	}

	if(!(pgp->pg_flags & a_F_MODE_TEST)){
		if(exact)
			su_cs_dict_insert(&wbp->wb_ca, buf, NIL);
		else{
			ASSERT(m != U32_MAX);
			pgsp = su_TALLOC(struct a_srch, 1);
			pgsp->s_next = wbp->wb_srch;
			wbp->wb_srch = pgsp;
			pgsp->s_flags = (rv == AF_INET) ? a_SRCH_IPV4 : a_SRCH_IPV6;
			pgsp->s_mask = S(u8,m);
			su_mem_copy(&pgsp->s_ip, &sip, sizeof(sip));
		}
	}else{
		char const *me;

		me = (wbp != NIL) ? "allow" : "block";
		if(exact)
			fprintf(stdout, "%s %s\n", me, buf);
		else
			fprintf(stdout, "%s %s/%lu\n", me, buf, S(ul,m));
	}
	rv = su_EX_OK;
	}goto jleave;

jedata:
	a_conf__err(pgp, V_(sip.cp), entry, cp);
	rv = -su_EX_DATAERR;
	goto jleave;
} /* }}} */

static s32
a_conf__R(struct a_pg *pgp, char const *path, BITENUM_IS(u32,a_avo_flags) f){
	struct a_line line;
	struct su_avopt avo;
	sz lnr;
	s32 fd, mpv;
	NYD2_IN;

	if((fd = a_misc_open(pgp, path)) == -1){
		mpv = su_err();
jerrno:
		a_conf__err(pgp, _("Cannot handle --resource-file %s: %s\n"), path, V_(su_err_doc(mpv)));
		mpv = -mpv;
		goto jleave;
	}

	su_avopt_setup(&avo, 0, NIL, NIL, a_lopts);

	a_LINE_SETUP(&line);
	while((lnr = a_misc_line_get(pgp, fd, &line)) != -1){
		/* Empty lines are ignored */
		if(lnr == 0)
			continue;

		switch((mpv = su_avopt_parse_line(&avo, line.l_buf))){
		a_AVOPT_CASES
			if((mpv = a_conf_arg(pgp, mpv, avo.avo_current_arg, f)) < 0 &&
					!(pgp->pg_flags & a_F_MODE_TEST))
				goto jleave;
			break;

		default:
			if(pgp->pg_flags & a_F_MODE_TEST){
				a_conf__err(pgp, _("Option unknown or invalid in --resource-file: %s: %s\n"),
					path, line.l_buf);
				break;
			}
			mpv = -su_EX_USAGE;
			goto jleave;
		}
	}
	if((mpv = line.l_err) != su_ERR_NONE)
		goto jerrno;

	mpv = su_EX_OK;
jleave:
	if(fd != -1)
		close(fd);

	NYD2_OU;
	return mpv;
}

static void
a_conf__err(struct a_pg *pgp, char const *msg, ...){
	va_list vl;

	va_start(vl, msg);

	if(pgp->pg_flags & a_F_MODE_TEST)
		vfprintf(stderr, msg, vl);
	else
		su_log_vwrite(su_LOG_CRIT, msg, &vl);

	va_end(vl);

	pgp->pg_flags |= a_F_TEST_ERRORS;
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
	 *   dev-commits-src-all+bounces-6241-steffen=sdaoden.eu@FreeBSD.org
	 *   owner-source-changes+M161144=steffen=sdaoden.eu@openbsd.org
	 * that is, numeric IDs etc after the VERP delimiter: do not care.
	 * Note openwall (ezmlm)
	 *   oss-security-return-27633-steffen=sdaoden.eu@lists.openwall.com
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
	union a_srch_ip a;
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
	if(inet_ntop((max == 1 ? AF_INET : AF_INET6), ip, ca = pgp->pg_ca, INET6_ADDRSTRLEN) == NIL){
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
static boole
a_misc_os_resource_delay(s32 err){
	boole rv;
	NYD_IN;

	rv = (err == su_ERR_MFILE || err == su_ERR_NFILE || err == su_ERR_NOBUFS/*hm*/ || err == su_ERR_NOMEM);

	if(rv){
		a_DBG(su_log_write(su_LOG_DEBUG, "out of OS resources while creating file descriptor, waiting a bit");)
		su_time_msleep(250, TRU1);
	}

	NYD_OU;
	return rv;
}

static s32
a_misc_open(struct a_pg *pgp, char const *path){
	s32 fd;
	NYD_IN;
	UNUSED(pgp);

	for(;;){
		fd = a_sandbox_open(pgp, FAL0, path, O_RDONLY, 0);
		if(fd == -1){
			if((fd = su_err_by_errno()) == su_ERR_INTR)
				continue;
			if(a_misc_os_resource_delay(fd))
				continue;
			break;
		}else{
			/* Ensure regular file */
			struct su_pathinfo pi;

			if(!su_pathinfo_fstat(&pi, fd)){
			}else if(!su_pathinfo_is_reg(&pi))
				su_err_set(su_ERR_INVAL);
			else
				break;

			close(fd);
			fd = -1;
		}
		break;
	}

	NYD_OU;
	return fd;
}

static sz
a_misc_line_get(struct a_pg *pgp, s32 fd, struct a_line *lp){
	/* XXX a_LINE_GETC(): tremendous optimization possible! */
#define a_LINE_GETC(LP,FD) ((LP)->l_curr < (LP)->l_fill ? (LP)->l_buf[(LP)->l_curr++] : a_misc_line__uflow(FD, LP))
	sz rv;
	char *cp, *top, cx;
	NYD_IN;
	UNUSED(pgp);

jredo:
	cp = lp->l_buf;
	top = &cp[a_BUF_SIZE - 1];
	cx = '\0';

	for(;;){
		s32 c;

		if((c = a_LINE_GETC(lp, fd)) == -1){
			if(cp != lp->l_buf && lp->l_err == su_ERR_NONE)
				goto jfakenl;
			rv = -1;
			break;
		}

		if(c == '\n'){
jfakenl:
			rv = S(sz,P2UZ(cp - lp->l_buf));
			if(rv > 0 && su_cs_is_space(cp[-1])){
				--cp;
				--rv;
				ASSERT(rv == 0 || !su_cs_is_space(cp[-1]));
			}
			*cp = '\0';
			break;
		}else if(c == '#' && cx == '\0')
			goto jskip;
		else if(su_cs_is_space(c) && (cx == '\0' || su_cs_is_space(cx)))
			continue;
		else if(cp == top)
			goto jelong;
		else
			*cp++ = cx = S(char,c);
	}

jleave:
	NYD_OU;
	return rv;

jelong:
	*cp = '\0';
	su_log_write(su_LOG_ERR, _("line too long, skip: %s"), cp);
jskip:
	for(;;){
		s32 c;

		if((c = a_LINE_GETC(lp, fd)) == -1){
			rv = -1;
			goto jleave;
		}else if(c == '\n')
			goto jredo;
	}
#undef a_LINE_GETC
}

static s32
a_misc_line__uflow(s32 fd, struct a_line *lp){
	s32 rv;
	NYD_IN;

	for(;;){
		ssize_t r;

		if((r = read(fd, &lp->l_buf[a_BUF_SIZE + 1], FIELD_SIZEOF(struct a_line,l_buf) - a_BUF_SIZE - 2)) == -1){
			if((rv = su_err_by_errno()) == su_ERR_INTR)
				continue;
			lp->l_err = rv;
			rv = -1;
		}else{
			lp->l_err = su_ERR_NONE;

			if(r == 0){
				a_DBG2(lp->l_curr = lp->l_fill = 0;)
				rv = -1;
			}else{
				rv = lp->l_buf[a_BUF_SIZE + 1];
				lp->l_curr = a_BUF_SIZE + 1 + 1;
				lp->l_fill = a_BUF_SIZE + 1 + S(u32,r);
			}
		}
		break;
	}

	NYD_OU;
	return rv;
}

static s32
a_misc_log_open(struct a_pg *pgp, boole client, boole init){
	boole repro;
	s32 rv;
	NYD2_IN;
	ASSERT(!init || client);
	UNUSED(pgp);

	rv = su_EX_OK;
	repro = su_state_has(su_STATE_REPRODUCIBLE);

	if(init){
		if(LIKELY(!repro))
			openlog(VAL_NAME, a_OPENLOG_FLAGS, LOG_MAIL);
		su_log_set_write_fun(&a_misc_log_write);
#ifdef a_HAVE_LOG_FIFO
	}else if(!(pgp->pg_flags & a_F_UNTAMED)){
		while((pgp->pg_logfd = open(a_FIFO_NAME, O_WRONLY | a_O_NOFOLLOW | a_O_NOCTTY)) == -1){
			if((rv = su_err_by_errno()) == su_ERR_INTR){
				rv = su_EX_OK;
				continue;
			}
			if(a_misc_os_resource_delay(rv)){
				rv = su_EX_OK;
				continue;
			}
			su_log_write(su_LOG_CRIT, _("cannot open privsep log fifo for writing %s/%s: %s"),
				pgp->pg_store_path, a_FIFO_NAME, V_(su_err_doc(rv)));
			rv = su_EX_IOERR;
			break;
		}

		if(LIKELY(!repro) && rv == su_EX_OK)
			closelog();

#endif /* HAVE_LOG_FIFO */
	}else if(!client && LIKELY(!repro)){
		closelog();
		openlog(VAL_NAME, a_OPENLOG_FLAGS, LOG_MAIL);
	}

#if VAL_OS_SANDBOX < 2
	if(!repro && !init && rv == su_EX_OK)
		close(STDERR_FILENO);
#endif

	su_program = client ? "client" : "server";

	NYD2_OU;
	return rv;
}

static void
a_misc_log_write(u32 lvl_a_flags, char const *msg, uz len){
	/* We need to deal with CANcelled newlines .. */
	static char xb[1024];
	static uz xl;

	LCTAV(su_LOG_EMERG == LOG_EMERG && su_LOG_ALERT == LOG_ALERT && su_LOG_CRIT == LOG_CRIT &&
		su_LOG_ERR == LOG_ERR && su_LOG_WARN == LOG_WARNING && su_LOG_NOTICE == LOG_NOTICE &&
		su_LOG_INFO == LOG_INFO && su_LOG_DEBUG == LOG_DEBUG);
	LCTAV(su_LOG_PRIMASK < (1u << 6));

#ifdef a_HAVE_LOG_FIFO
	if(xl == 0 && a_pg != NIL && C(struct a_pg*,a_pg)->pg_logfd != -1){
		xb[0] = (C(struct a_pg*,a_pg)->pg_flags & a_F_MASTER_FLAG) ? '\01' : '\02';
		xb[1] = S(char,lvl_a_flags & su_LOG_PRIMASK);
		xl = 4;
	}
#endif

	if(len > 0 && msg[len - 1] != '\n'){
		if(sizeof(xb) - (4+1 +1) - xl > len){
			su_mem_copy(&xb[xl], msg, len);
			xl += len;
			goto jleave;
		}
	}

	if(xl > 0){
		if(len > 0 && msg[len - 1] == '\n')
			--len;
		if(sizeof(xb) - (4+1 +1) - xl < len)
			len = sizeof(xb) - (4+1 +1) - xl;
		if(len > 0){
			su_mem_copy(&xb[xl], msg, len);
			xl += len;
		}
		xb[xl++] = '\n';
		xb[xl++] = '\0';
		len = xl;
		xl = 0;
		msg = xb;
	}

#ifdef a_HAVE_LOG_FIFO
	/* In the sandbox, not after termination request xxx wrong: --untamed would be ok! */
	if(a_pg == NIL)
		goto jleave;

	if(C(struct a_pg*,a_pg)->pg_logfd != -1){
		ASSERT(msg == xb);
		len = MIN(len, MIN(sizeof(C(struct a_pg*,a_pg)->pg_buf), MIN(1024u, S(uz,a_FIFO_IO_MAX))) - (4+1 +1));
		xb[2] = S(char,len & 0x00FFu);
		xb[3] = S(char,(len >> 8) & 0x07u);

		/* Normalize content (xxx total overkill) */
		if(len > 6){
			char *cp, *cpmax;

			cpmax = cp = xb;
			cp += 4;
			cpmax += len - 2;
			for(; cp < cpmax; ++cp)
				if(!su_cs_is_print(*cp) && !su_cs_is_blank(*cp))
					*cp = '?';
		}

		for(;;){
			ssize_t w;

			w = write(C(struct a_pg*,a_pg)->pg_logfd, msg, len);
			if(w == -1){
				if(su_err_by_errno() != su_ERR_INTR)
					_exit(su_EX_IOERR);
				continue;
			}
			len -= S(uz,w);
			if(len == 0)
				break;
			msg += w;
		}
	}else
#endif
	      if(UNLIKELY(su_state_has(su_STATE_REPRODUCIBLE)))
		write(STDERR_FILENO, msg, len);
	else
		/* Restrict to < 1024 so no memory allocator kicks in! */
		syslog(S(int,lvl_a_flags & su_LOG_PRIMASK), "%.950s", msg);

jleave:;
}

static void
a_misc_usage(FILE *fp){
	static char const a_u[] = N_(
"%s (s-postgray %s): postfix RFC 6647 (graylisting) policy server\n"
"\n"
". Please use --long-help (-H) for option summary\n"
"  (Options marked [*] cannot be placed in a resource file.)\n"
". Bugs/Contact via %s\n");
	NYD2_IN;

	fprintf(fp, V_(a_u), VAL_NAME, a_VERSION, a_CONTACT);

	NYD2_OU;
}

static boole
a_misc_dump_doc(up cookie, boole has_arg, char const *sopt, char const *lopt, char const *doc){
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
	fprintf(S(FILE*,cookie), _("%s%s%s%s%s: %s\n"), lopt, x1, x2, sopt, x3, V_(doc));

	NYD2_OU;
	return TRU1;
}

#if a_DBGIF || defined su_HAVE_NYD /* {{{ */
static void
a_misc_oncrash(int signo){
	char s2ibuf[32], *cp;
	int fd;
	uz i;

	su_nyd_set_disabled(TRU1);

	if((fd = a_sandbox_open(C(struct a_pg*,a_pg), FAL0, a_NYD_FILE, O_WRONLY | O_CREAT | O_EXCL, 0666)) == -1)
		fd = STDERR_FILENO;

# undef _X
# define _X(X) X, sizeof(X) -1

	write(fd, _X("\n\nNYD: program dying due to signal "));

	cp = &s2ibuf[sizeof(s2ibuf) -1];
	*cp = '\0';
	i = S(uz,signo);
	do{
		*--cp = "0123456789"[i % 10];
		i /= 10;
	}while(i != 0);
	write(fd, cp, P2UZ(&s2ibuf[sizeof(s2ibuf) -1] - cp));

	write(fd, _X(":\n"));

	su_nyd_dump(&a_misc_oncrash__dump, S(uz,S(u32,fd)));

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
a_misc_oncrash__dump(up cookie, char const *buf, uz blen){
	write(S(int,cookie), buf, blen);
}
#endif /* a_DBGIF || defined su_HAVE_NYD }}} */
/* }}} */

int
main(int argc, char *argv[]){ /* {{{ */
	struct su_avopt avo;
	struct a_pg pg;
	BITENUM_IS(u32,a_avo_flags) f;
	s32 mpv;

	mpv = (getenv("SOURCE_DATE_EPOCH") == NIL); /* xxx su_env_get? */
	su_state_create(su_STATE_CREATE_RANDOM, (mpv ? NIL : VAL_NAME),
		(DVLDBGOR(su_LOG_DEBUG, (mpv ? su_LOG_ERR : su_LOG_DEBUG)) | DVL(su_STATE_DEBUG |)
			(mpv ? (0 | su_STATE_LOG_SHOW_LEVEL | su_STATE_LOG_SHOW_PID)
				: (su_STATE_LOG_SHOW_LEVEL | su_STATE_LOG_SHOW_PID | su_STATE_REPRODUCIBLE))),
		su_STATE_ERR_NOPASS);

#if a_DBGIF || defined su_HAVE_NYD
	signal(SIGABRT, &a_misc_oncrash);
# ifdef SIGBUS
	signal(SIGBUS, &a_misc_oncrash);
# endif
	signal(SIGFPE, &a_misc_oncrash);
	signal(SIGILL, &a_misc_oncrash);
	signal(SIGSEGV, &a_misc_oncrash);
#endif

	STRUCT_ZERO(struct a_pg, &pg);
	a_pg = S(struct a_pg ATOMIC*,&pg);
#ifdef a_HAVE_LOG_FIFO
	pg.pg_logfd = pg.pg_rootfd = -1;
#endif
	a_conf_setup(&pg, a_AVO_NONE);
	pg.pg_argc = S(u32,(argc > 0) ? --argc : argc);
	pg.pg_argv = ++argv;

	/* To avoid that clients do not parse too much we may have to parse ARGV several times instead */
	f = a_AVO_NONE;
jreavo:
	su_avopt_setup(&avo, pg.pg_argc, C(char const*const*,pg.pg_argv), a_sopts, a_lopts);

	while((mpv = su_avopt_parse(&avo)) != su_AVOPT_STATE_DONE){
		char const *emsg;

		/* In long-option order (mostly) */
		switch(mpv){
		case '.': pg.pg_flags |= a_F_MODE_SHUTDOWN; break;
		case '@': pg.pg_flags |= a_F_MODE_STARTUP; break;
		case '%': pg.pg_flags |= a_F_MODE_STATUS; break;
		case '#': pg.pg_flags |= a_F_MODE_TEST; break;

		a_AVOPT_CASES
			if((mpv = a_conf_arg(&pg, mpv, avo.avo_current_arg, f)) < 0){
				mpv = -mpv;
				goto jleave;
			}
			break;

		case 'H':
		case 'h':
			a_misc_usage(stdout);
			if(mpv == 'H'){
				fprintf(stdout, _("\nLong options:\n"));
				(void)su_avopt_dump_doc(&avo, &a_misc_dump_doc, R(up,stdout));
			}
			mpv = su_EX_OK;
			goto jleave;

		case su_AVOPT_STATE_ERR_ARG:
			emsg = su_avopt_fmt_err_arg;
			goto jerropt;
		case su_AVOPT_STATE_ERR_OPT:
			emsg = su_avopt_fmt_err_opt;
jerropt:
			if(!(f & a_AVO_FULL))
				fprintf(stderr, V_(emsg), avo.avo_current_err_opt);

			if(pg.pg_flags & a_F_MODE_TEST){
				pg.pg_flags |= a_F_TEST_ERRORS;
				break;
			}
jeusage:
			a_misc_usage(stderr);
			mpv = su_EX_USAGE;
			goto jleave;
		}
	}

	if(!(f & a_AVO_FULL)){
		switch(pg.pg_flags & a__F_MODE_MASK){
		case 0:
		case a_F_MODE_SHUTDOWN:
		case a_F_MODE_STARTUP:
		case a_F_MODE_STATUS:
		case a_F_MODE_TEST:
			break;
		default:
			fprintf(stderr, _("Only none or one of --shutdown, --startup, --status, --test-mode\n"));
			if(!(pg.pg_flags & a_F_MODE_TEST))
				goto jeusage;
			pg.pg_flags |= a_F_TEST_ERRORS;
			break;
		}

		if(avo.avo_argc != 0){
			fprintf(stderr, _("Excess arguments given\n"));
			if(!(pg.pg_flags & a_F_MODE_TEST))
				goto jeusage;
			pg.pg_flags |= a_F_TEST_ERRORS;
		}

		a_conf_finish(&pg, a_AVO_NONE);
	}

	if(!(pg.pg_flags & a_F_MODE_TEST))
		mpv = a_client(&pg);
	else if(!(f & a_AVO_FULL)){
		f = a_AVO_FULL;
		goto jreavo;
	}else{
		fprintf(stdout, _("# Configuration (evaluated first!) #\n"));
		a_conf_list_values(&pg);
		mpv = (pg.pg_flags & a_F_TEST_ERRORS) ? su_EX_USAGE : su_EX_OK;
	}

jleave:
	if(!(pg.pg_flags & a_F_NOFREE_MSG_ALLOW) && pg.pg_msg_allow != NIL)
		su_FREE(UNCONST(char*,pg.pg_msg_allow));
	if(!(pg.pg_flags & a_F_NOFREE_MSG_BLOCK) && pg.pg_msg_block != NIL)
		su_FREE(UNCONST(char*,pg.pg_msg_block));
	if(!(pg.pg_flags & a_F_NOFREE_MSG_DEFER) && pg.pg_msg_defer != NIL)
		su_FREE(UNCONST(char*,pg.pg_msg_defer));

	if(!(pg.pg_flags & a_F_NOFREE_STORE_PATH) && pg.pg_store_path != NIL)
		su_FREE(C(char*,pg.pg_store_path));

	su_state_gut(mpv == su_EX_OK
		? su_STATE_GUT_ACT_NORM /*DVL( | su_STATE_GUT_MEM_TRACE )*/
		: su_STATE_GUT_ACT_QUICK);

	return mpv;
} /* }}} */

/* sandbox {{{ */
/* VAL_OS_SANDBOX is only >0 if we support anything */

/* 0:err_no_by_errno, -1.. */
#if !defined HAVE_SANITIZER || VAL_OS_SANDBOX > 0
static void a_sandbox__err(char const *emsg, char const *arg, s32 err);
#endif

#ifndef HAVE_SANITIZER
static void a_sandbox__rlimit(struct a_pg *pgp, boole server);
#endif

#if VAL_OS_SANDBOX > 0
static void a_sandbox__os(struct a_pg *pgp, boole server);
#endif

#if !defined HAVE_SANITIZER || VAL_OS_SANDBOX > 0
static void
a_sandbox__err(char const *emsg, char const *arg, s32 err){
	if(err == 0)
		err = su_err_by_errno();

	su_log_write(su_LOG_EMERG, "%s failed: %s: %s", V_(emsg), arg, V_(su_err_doc(err)));
}
#endif

#ifndef HAVE_SANITIZER /* {{{ */
static void
a_sandbox__rlimit(struct a_pg *pgp, boole server){
	struct rlimit rl;
	NYD_IN;
	UNUSED(pgp);

	rl.rlim_cur = rl.rlim_max = 0;

	if(setrlimit(RLIMIT_NPROC, &rl) == -1)
		a_sandbox__err("setrlimit", "NPROC", 0);

	if(!server){
# if !(a_DBGIF || defined su_HAVE_NYD)
		if(setrlimit(RLIMIT_NOFILE, &rl) == -1)
			a_sandbox__err("setrlimit", "NOFILE", 0);
# endif

		rl.rlim_cur = rl.rlim_max = ALIGN_Z(a_BUF_SIZE);
	}else{
		rlim_t const xxl = (S(u64,S(rlim_t,-1)) - 1 > S(u64,S32_MAX)) ? S(rlim_t,S32_MAX) : S(rlim_t,-1) - 1;
		u64 xl;

		LCTAV(U64_MAX / a_BUF_SIZE > U32_MAX);
		xl = S(u64,pgp->pg_limit) * ALIGN_Z(a_BUF_SIZE);
		rl.rlim_cur = rl.rlim_max = (S(u64,xxl) <= xl) ? xxl : S(rlim_t,xl);
	}
	if(LIKELY(!su_state_has(su_STATE_REPRODUCIBLE))){
		if(server && (pgp->pg_flags & a_F_VV))
			su_log_write(su_LOG_INFO, "setrlimit(2) RLIMIT_FSIZE %" PRIu64, S(u64,rl.rlim_max));
		if(setrlimit(RLIMIT_FSIZE, &rl) == -1)
			a_sandbox__err("setrlimit", "FSIZE", 0);
	}

	NYD_OU;
}
#endif /* !HAVE_SANITIZER }}} */

#if VAL_OS_SANDBOX > 0 && su_OS_FREEBSD /* {{{ */
static char **a_sandbox__paths; /* TODO su_vector */
static uz a_sandbox__paths_cnt;
static uz a_sandbox__paths_size;

static void
a_sandbox__os(struct a_pg *pgp, boole server){
# if VAL_OS_SANDBOX > 1
	struct sigaction sa;
# endif
	cap_rights_t rights;
	s32 e;
	pid_t pid;
	NYD_IN;

	pid = getpid();

#ifdef PROC_NO_NEW_PRIVS_ENABLE
	e = PROC_NO_NEW_PRIVS_ENABLE;
	if(procctl(P_PID, pid, PROC_NO_NEW_PRIVS_CTL, &e) == -1)
		a_sandbox__err("procctl", "PROC_NO_NEW_PRIVS_CTL->PROC_NO_NEW_PRIVS_ENABLE", 0);
#endif

	if(server
# if a_DBGIF || defined su_HAVE_NYD
		|| TRU1
# endif
	){
		while((pgp->pg_rootfd = open("/", a_O_PATH | O_DIRECTORY)) == -1 &&
				(e = su_err_by_errno()) != su_ERR_INTR)
			a_sandbox__err("open", "/ O_PATH for capsicum(4) openat(2) support", e);

		cap_rights_init(&rights, CAP_FSYNC, CAP_READ, CAP_WRITE, CAP_LOOKUP, CAP_FSTAT, CAP_FTRUNCATE,
			CAP_CREATE);
		if(cap_rights_limit(pgp->pg_rootfd, &rights) == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
			a_sandbox__err("cap_rights_limit", "/ root directory, for openat(2)", e);
	}

	if(!server){
		cap_rights_init(&rights, CAP_READ);
		if(cap_rights_limit(STDIN_FILENO, &rights) == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
			a_sandbox__err("cap_rights_limit", "STDIN", e);

		cap_rights_init(&rights, CAP_READ, CAP_WRITE);
		if(cap_rights_limit(pgp->pg_clima_fd, &rights) == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
			a_sandbox__err("cap_rights_limit", "client socket", e);
	}else{
		cap_rights_init(&rights);
		if(cap_rights_limit(pgp->pg_master->m_reafd, &rights) == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
			a_sandbox__err("cap_rights_limit", "reassurance FD", e);

		cap_rights_init(&rights, CAP_ACCEPT, CAP_EVENT, CAP_READ, CAP_WRITE);
		if(cap_rights_limit(pgp->pg_clima_fd, &rights) == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
			a_sandbox__err("cap_rights_limit", "server socket", e);
	}

	cap_rights_init(&rights, CAP_FSYNC, CAP_WRITE);
	if(!server){
		if(cap_rights_limit(STDOUT_FILENO, &rights) == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
			a_sandbox__err("cap_rights_limit", "STOUT", e);
	}
	if(cap_rights_limit(pgp->pg_logfd, &rights) == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
		a_sandbox__err("cap_rights_limit", "logger FD", e);
	/* STDERR depends */
	if(su_state_has(su_STATE_REPRODUCIBLE) && cap_rights_limit(STDERR_FILENO, &rights) == -1 &&
			(e = su_err_by_errno()) != su_ERR_NOSYS)
		a_sandbox__err("cap_rights_limit", "STDERR", e);

	if(cap_enter() == -1 && (e = su_err_by_errno()) != su_ERR_NOSYS)
		a_sandbox__err("cap_enter", "", e);

	NYD_OU;
}

static char const *
a_sandbox_path_check(struct a_pg *pgp, char const *path){
	char const *rv;
	NYD_IN;
	UNUSED(pgp);

	if(pgp->pg_flags & (a_F_MODE_TEST | a_F_UNTAMED))
		rv = path;
	/* XXX Actually we can simply return path for as long as we are not sandboxed, instead */
	else if(pgp->pg_flags & a_F_MASTER_IN_SETUP){
		char *rpath;

		if((rv = rpath = realpath(path, NIL)) != NIL){
			if(a_sandbox__paths_cnt + 2 >= a_sandbox__paths_size){
				a_sandbox__paths_size += 8;
				a_sandbox__paths = su_TREALLOC(char*, a_sandbox__paths, a_sandbox__paths_size);
			}
			a_sandbox__paths[a_sandbox__paths_cnt++] = su_cs_dup(path, su_STATE_ERR_NOPASS);
			rv = a_sandbox__paths[a_sandbox__paths_cnt++] = su_cs_dup(rpath, su_STATE_ERR_NOPASS);

			free(rpath);
		}
	}else{
		uz i;

		rv = NIL;
		for(i = 0; i < a_sandbox__paths_cnt; i += 2)
			if(!su_cs_cmp(path, a_sandbox__paths[i])){
				rv = a_sandbox__paths[++i];
				break;
			}
	}

	NYD_OU;
	return rv;
}

static void
a_sandbox_path_reset(struct a_pg *pgp, boole isexit){
	uz i;
	NYD_IN;
	UNUSED(pgp);
	UNUSED(isexit);

	if(isexit && a_sandbox__paths_cnt > 0){
		for(i = 0; i < a_sandbox__paths_cnt; ++i)
			su_FREE(a_sandbox__paths[i]);
		su_FREE(a_sandbox__paths);

		a_sandbox__paths = NIL;
		a_sandbox__paths_cnt = a_sandbox__paths_size = 0;
	}

	NYD_OU;
}

static int
a_sandbox_open(struct a_pg *pgp, boole store_path, char const *path, int flags, int mode){
	int rv;
	NYD_IN;

	flags |= a_O_NOFOLLOW | a_O_NOCTTY;

	/* Heavy if in sandbox */
	if(/*(pgp->pg_flags & a_F_UNTAMED) ||*/ pgp->pg_rootfd == -1)
		rv = open(path, flags, mode);
	else{
		char pathbuf[PATH_MAX]; /* (it was ensured that --store-path/REA_NAME fits xxx) */

		if(!store_path){
			if(path[0] != '/'){
				uz i;

				for(i = 0; i < a_sandbox__paths_cnt; i += 2)
					if(!su_cs_cmp(path, a_sandbox__paths[i])){
						path = a_sandbox__paths[++i];
						break;
					}
			}
		}else{
			char *cp;

			ASSERT(!su_cs_cmp(path, a_GRAY_DB_NAME));
			cp = su_cs_pcopy(pathbuf, pgp->pg_store_path_real);
			*cp++ = su_PATH_SEP_C;
			su_cs_pcopy(cp, a_GRAY_DB_NAME);
			path = pathbuf;
		}

		ASSERT(path[0] == '/');
		++path;
		while((rv = openat(pgp->pg_rootfd, path, flags, mode)) == -1 && su_err_by_errno() == su_ERR_INTR){
		}

		if(rv != -1){
			cap_rights_t rights;

			if(flags & O_WRONLY)
				cap_rights_init(&rights, CAP_FSTAT, CAP_FSYNC, CAP_WRITE);
			else if(flags & O_RDWR)
				cap_rights_init(&rights, CAP_FSTAT, CAP_FSYNC, CAP_READ, CAP_WRITE);
			else
				cap_rights_init(&rights, CAP_FSTAT, CAP_READ);

			if(cap_rights_limit(rv, &rights) == -1 && (mode = su_err_by_errno()) != su_ERR_NOSYS){
				close(rv);
				a_sandbox__err("cap_rights_limit", path, mode);
				rv = -1;
			}
		}
	}

	NYD_OU;
	return rv;
}

static boole
a_sandbox_sock_accepted(struct a_pg *pgp, s32 sockfd){
	cap_rights_t rights;
	s32 e;
	NYD_IN;

	e = su_ERR_NONE;

	if(!(pgp->pg_flags & a_F_UNTAMED)){
		cap_rights_init(&rights, CAP_EVENT, CAP_READ, CAP_WRITE);
		if(cap_rights_limit(sockfd, &rights) == -1){
			if((e = su_err_by_errno()) == su_ERR_NOSYS)
				e = su_ERR_NONE;
		}
	}

	NYD_OU;
	return (e == su_ERR_NONE);
}
#endif /* }}} VAL_OS_SANDBOX>0 && su_OS_FREEBSD */

#if VAL_OS_SANDBOX > 0 && su_OS_LINUX /* {{{ */
# define a_LOAD_SYSNR BPF_STMT(BPF_LD | BPF_W | BPF_ABS, FIELD_OFFSETOF(struct seccomp_data,nr))
# define a_ALLOW BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW)
# if VAL_OS_SANDBOX > 1
#  define a_FAIL BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRAP)
# else
#  ifdef SECCOMP_RET_KILL_PROCESS
#   define a_FAIL BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS)
#  else
#   define a_FAIL BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL)
#  endif
# endif

  /* Always 64-bit */
# ifndef su_CC_BOM
#  error SU does not offer CC_BOM via compiler (should come from su/code.h)
# endif
# if su_BOM_IS_LITTLE()
#  define a_ARG_LO_OFF 0
#  define a_ARG_HI_OFF sizeof(u32)
# else
#  define a_ARG_LO_OFF sizeof(u32)
#  define a_ARG_HI_OFF 0
# endif

# define a_Y(SYSNO) BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYSNO, 0, 1), a_ALLOW

# define a_EXIT_GROUP
# define a_NEWFSTATAT
# define a_FSTATAT64
# define a_OPENAT
# ifdef __NR_exit_group
#  undef a_EXIT_GROUP
#  define a_EXIT_GROUP a_Y(__NR_exit_group),
# endif
# ifdef __NR_newfstatat
#  undef a_NEWFSTATAT
#  define a_NEWFSTATAT a_Y(__NR_newfstatat),
# endif
# ifdef __NR_fstatat64
#  undef a_FSTATAT64
#  define a_FSTATAT64 a_Y(__NR_fstatat64),
# endif
# ifdef __NR_openat
#  undef a_OPENAT
#  define a_OPENAT a_Y(__NR_openat),
# endif

  /* GLibC, musl */
# ifdef __GLIBC__
#  define a_G(X) X
#  define a_M(X)
# else
#  define a_G(X)
#  define a_M(X) X
# endif

/* __NR_futex? */
# define a_SHARED \
	/* futex C lib? */\
	\
	a_Y(__NR_close),\
	a_Y(__NR_exit),a_EXIT_GROUP \
	a_Y(__NR_fstat),a_FSTATAT64 a_NEWFSTATAT \
	a_Y(__NR_getpid),\
	a_Y(__NR_open),a_OPENAT \
	a_Y(__NR_read),\
	a_Y(__NR_write),\
	a_Y(__NR_writev),\
	\
	a_FAIL

static struct sock_filter const a_sandbox__client_flt[] = {
	/* See seccomp(2).  Load syscall number into accu */
	a_LOAD_SYSNR,
# ifdef VAL_OS_SANDBOX_CLIENT_RULES
	VAL_OS_SANDBOX_CLIENT_RULES
# else
	a_M(a_Y(__NR_ioctl) su_COMMA)
# endif
	a_SHARED
};

static struct sock_filter const a_sandbox__server_flt[] = {
	a_LOAD_SYSNR,
# ifdef VAL_OS_SANDBOX_SERVER_RULES
	VAL_OS_SANDBOX_SERVER_RULES
# else
	a_Y(__NR_accept),
	a_Y(__NR_clock_gettime),
#  ifdef __NR_clock_nanosleep
	a_Y(__NR_clock_nanosleep),
#  endif
#  ifdef __NR_nanosleep
		a_Y(__NR_nanosleep),
#  endif
	a_Y(__NR_fcntl),
	a_Y(__NR_fsync),
	a_Y(__NR_pselect6),
#  ifdef __NR_rt_sigaction
	a_Y(__NR_rt_sigaction),
#  endif
#  ifdef __NR_sigaction
		a_Y(__NR_sigaction),
#  endif
#  ifdef __NR_rt_sigprocmask
	a_Y(__NR_rt_sigprocmask),
#  endif
#  ifdef __NR_sigprocmask
		a_Y(__NR_sigprocmask),
#  endif
#  ifdef __NR_rt_sigreturn
	a_Y(__NR_rt_sigreturn),
#  endif
#  ifdef __NR_sigreturn
		a_Y(__NR_sigreturn),
#  endif
	a_Y(__NR_unlink),
	/*a_Y(__NR_openat), in a_SHARED:syslog */

	a_Y(__NR_brk),
	a_Y(__NR_munmap),
	a_Y(__NR_madvise),
	/* mmap: only PROT_READ except memory alloc, so write, too */
	BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_mmap, 0, 7),
	BPF_STMT(BPF_LD | BPF_W | BPF_ABS, FIELD_OFFSETOF(struct seccomp_data,args[2]) + a_ARG_LO_OFF),
	BPF_STMT(BPF_ALU | BPF_AND | BPF_K, ~S(u32,PROT_READ | PROT_WRITE)),
	BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 0, 0, 3),
	BPF_STMT(BPF_LD | BPF_W | BPF_ABS, FIELD_OFFSETOF(struct seccomp_data,args[2]) + a_ARG_HI_OFF),
	BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, 0, 0, 1),
	a_ALLOW,
	a_LOAD_SYSNR,

# endif /* !VAL_OS_SANDBOX_SERVER_RULES */
	a_SHARED
};

# undef a_LOAD_SYSNR
# undef a_ALLOW
# undef a_FAIL
# undef a_ARG_LO_OFF
# undef a_ARG_HI_OFF
# undef a_Y
# undef a_EXIT_GROUP
# undef a_NEWFSTATAT
# undef a_STATAT64
# undef a_OPENAT
# undef a_G
# undef a_M
# undef a_SHARED

static struct sock_fprog const a_sandbox__client_prg = {
	FIELD_INITN(len) S(us,NELEM(a_sandbox__client_flt)),
	FIELD_INITN(filter) C(struct sock_filter*,a_sandbox__client_flt)
};

static struct sock_fprog const a_sandbox__server_prg = {
	FIELD_INITN(len) S(us,NELEM(a_sandbox__server_flt)),
	FIELD_INITN(filter) C(struct sock_filter*,a_sandbox__server_flt)
};

# if VAL_OS_SANDBOX > 1
static void a_sandbox__osdeath(int no, siginfo_t *sip, void *vp);
# endif

# if VAL_OS_SANDBOX > 1
static void
a_sandbox__osdeath(int no, siginfo_t *sip, void *vp){
	char msg[80];
	int i;
	UNUSED(no);
	UNUSED(vp);

	i = snprintf(msg, sizeof(msg),
			VAL_NAME ": seccomp(2) violation (syscall %d); please report this bug\n",
			sip->si_syscall);
	write(STDERR_FILENO, msg, i);

	_exit(1);
}
# endif /* VAL_OS_SANDBOX>1 */

static void
a_sandbox__os(struct a_pg *pgp, boole server){
# if VAL_OS_SANDBOX > 1
	struct sigaction sa;
# endif
	NYD_IN;
	UNUSED(pgp);

	/* (Avoid ptrace) */
# if defined PR_SET_DUMPABLE && !defined HAVE_SANITIZER
	if(prctl(PR_SET_DUMPABLE, 0) == -1)
		a_sandbox__err("prctl", "SET_DUMPABLE=0", 0);
# endif

	/* Prepare seccomp */
# ifdef PR_SET_NO_NEW_PRIVS
	if(prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == -1)
		a_sandbox__err("prctl", "SET_NO_NEW_PRIVS", 0);
# endif

	/**/
# if VAL_OS_SANDBOX > 1
	STRUCT_ZERO(struct sigaction,&sa);
	sa.sa_sigaction = &a_sandbox__osdeath;
	sa.sa_flags = SA_SIGINFO;
	sigaction(a_SANDBOX_SIGNAL, &sa, NIL);
# endif

	if(prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, (server ? &a_sandbox__server_prg : &a_sandbox__client_prg)) == -1)
		a_sandbox__err("prctl", "SET_SECCOMP", 0);

	NYD_OU;
}
#endif /* }}} VAL_OS_SANDBOX>0 && su_OS_LINUX */

#if VAL_OS_SANDBOX > 0 && su_OS_OPENBSD /* {{{ */
static char **a_sandbox__paths; /* TODO su_vector */
static uz a_sandbox__paths_cnt;
static uz a_sandbox__paths_size;

static void
a_sandbox__os(struct a_pg *pgp, boole server){
	NYD_IN;

	if(!server){
		if(unveil(".", "r") == -1) /* (Need at least one real) */
			a_sandbox__err("unveil", ".", 0);

		if(pledge("stdio", "") == -1)
			a_sandbox__err("pledge", "stdio", 0);
	}else{
		uz i;

		setproctitle("server");

		if(unveil(pgp->pg_master->m_sockpath, "c") == -1)
			a_sandbox__err("unveil", pgp->pg_master->m_sockpath, 0);
		if(unveil(a_GRAY_DB_NAME, "rwc") == -1)
			a_sandbox__err("unveil", a_GRAY_DB_NAME, 0);
# if a_DBGIF
		unveil(a_NYD_FILE, "w");
# endif

		for(i = 0; i < a_sandbox__paths_cnt; ++i)
			if(unveil(a_sandbox__paths[i], "r") == -1)
				a_sandbox__err("unveil", a_sandbox__paths[i], 0);

		if(pledge("stdio inet rpath wpath cpath", "") == -1)
			a_sandbox__err("pledge", "stdio inet rpath wpath cpath", 0);
	}

	NYD_OU;
}

static char const *
a_sandbox_path_check(struct a_pg *pgp, char const *path){
	char const *rv;
	NYD_IN;

	if(pgp->pg_flags & (a_F_MODE_TEST | a_F_UNTAMED))
		rv = path;
	else if(pgp->pg_flags & a_F_MASTER_IN_SETUP){
		if(a_sandbox__paths_cnt + 1 >= a_sandbox__paths_size){
			a_sandbox__paths_size += 8;
			a_sandbox__paths = su_TREALLOC(char*, a_sandbox__paths, a_sandbox__paths_size);
		}
		rv = a_sandbox__paths[a_sandbox__paths_cnt++] = su_cs_dup(path, su_STATE_ERR_NOPASS);
	}else{
		uz i;

		rv = NIL;
		for(i = 0; i < a_sandbox__paths_cnt; ++i)
			if(!su_cs_cmp(path, a_sandbox__paths[i])){
				rv = a_sandbox__paths[i];
				break;
			}
	}

	NYD_OU;
	return rv;
}

# if a_DBGIF
static void
a_sandbox_path_reset(struct a_pg *pgp, boole isexit){
	NYD_IN;
	UNUSED(pgp);

	if(isexit && a_sandbox__paths_cnt > 0){
		uz i;

		for(i = 0; i < a_sandbox__paths_cnt; ++i)
			su_FREE(a_sandbox__paths[i]);
		su_FREE(a_sandbox__paths);

		a_sandbox__paths = NIL;
		a_sandbox__paths_cnt = a_sandbox__paths_size = 0;
	}

	NYD_OU;
}
# endif /* a_DBGIF */
#endif /* }}} VAL_OS_SANDBOX>0 && su_OS_OPENBSD */

static void
a_sandbox_client(struct a_pg *pgp){
	NYD_IN;
	UNUSED(pgp);

#ifndef HAVE_SANITIZER
	a_sandbox__rlimit(pgp, FAL0);
#endif

#if VAL_OS_SANDBOX > 0
	if(!(pgp->pg_flags & a_F_UNTAMED))
		a_sandbox__os(pgp, FAL0);
#endif

	NYD_OU;
}

static void
a_sandbox_server(struct a_pg *pgp){
	NYD_IN;
	UNUSED(pgp);

#ifndef HAVE_SANITIZER
	a_sandbox__rlimit(pgp, TRU1);
#endif

#if VAL_OS_SANDBOX > 0
	if(!(pgp->pg_flags & a_F_UNTAMED))
		a_sandbox__os(pgp, TRU1);
#endif

	NYD_OU;
}
/* sandbox }}} */

#include "su/code-ou.h"
#undef su_FILE
/* s-itt-mode */
