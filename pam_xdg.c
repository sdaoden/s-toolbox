/*@ pam_xdg - manage XDG Base Directories (runtime dir life time, environment).
 *@ See pam_xdg.8 for more.
 *@ - According to XDG Base Directory Specification, v0.7.
 *@ - Supports libpam (Linux) and OpenPAM.
 *@ - Requires C preprocessor with __VA_ARGS__ support!
 *@ - Uses "rm -rf" to drop per-user directories. XXX Unroll this?  nftw?
 *
 * Copyright (c) 2021 Steffen Nurpmeso <steffen@sdaoden.eu>.
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

/* For these a leading \1 is replaced with struct passwd::pw_dir.
 * Be aware we use a stack buffer for storage */
#define a_XDG_DATA_HOME_DEF "\1/.local/share"
#define a_XDG_CONFIG_HOME_DEF "\1/.config"
#define a_XDG_CACHE_HOME_DEF "\1/.cache"
/* For porter's sake this */
#define a_XDG_DATA_DIRS_DEF a_STRING(XDG_DATA_DIR_LOCAL) "/share:/usr/share"
#define a_XDG_CONFIG_DIRS_DEF a_STRING(XDG_CONFIG_DIR) "/xdg"

/* We create the outer directories as necessary (stack buffer storage!).
 * This only holds for last component of _OUTER, though. */
#define a_RUNTIME_DIR_OUTER a_STRING(XDG_RUNTIME_DIR_OUTER)
#define a_RUNTIME_DIR_OUTER_MODE 0755
#define a_RUNTIME_DIR_BASE "user"
#define a_RUNTIME_DIR_BASE_MODE 0755 /* 0711? */

/* Note: we manage these relative to the per-user directory!
 * a_LOCK_FILE is only used without "per_user_lock" */
#define a_LOCK_FILE "../." a_XDG ".lck"
#define a_LOCK_TRIES 10

#define a_DAT_FILE "." a_XDG ".dat"

/* >8 -- 8< */

/*
#define _POSIX_C_SOURCE 200809L
#define _ATFILE_SOURCE
*/
#define _GNU_SOURCE /* Always the same mess */

#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <stdint.h> /* xxx not, actually!?! */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <security/pam_appl.h>
#include <security/pam_modules.h>
#ifdef OPENPAM_VERSION
# include <security/openpam.h>
#else
# include <security/pam_ext.h>
#endif

#ifdef OPENPAM_VERSION
#else
# include <syslog.h>
#endif

/* Who are we? */
#define a_XDG "pam_xdg"

/* _XOPEN_PATH_MAX POSIX 2008/Cor 1-2013 */
#ifndef PATH_MAX
# define PATH_MAX 1024
#endif

/* */
#ifdef O_SEARCH
# define a_O_SEARCH O_SEARCH
#elif defined O_PATH
# define a_O_SEARCH O_PATH
#else
  /* Well, hardly, but not in practice so do not #error out */
# define a_O_SEARCH 0
#endif

/* */
#define a_STRING(X) a__STRING(X)
#define a__STRING(X) #X

/* libpam / OpenPAM compat */
#ifdef OPENPAM_VERSION
# define a_LOG(HDL, LVL, ...) ((void)HDL, openpam_log(LVL, __VA_ARGS__))
# define a_LOG_ERR PAM_LOG_ERROR
# define a_LOG_NOTICE PAM_LOG_NOTICE
#else
# define a_LOG(HDL, LVL, ...) pam_syslog(HDL, LVL, __VA_ARGS__)
# define a_LOG_ERR LOG_ERR
# define a_LOG_NOTICE LOG_NOTICE
#endif

/* Just put it all in one big fun, use two exec paths */
static int a_xdg(int isopen, pam_handle_t *pamh, int flags, int argc,
      char const **argv);

static int
a_xdg(int isopen, pam_handle_t *pamh, int flags, int argc, char const **argv){
   enum a_flags{
      a_NONE,
      /* Options */
      a_RUNTIME = 1u<<0,
      a_NOTROOT = 1u<<1,
      a_SESSIONS = 1u<<2,
      a_USER_LOCK = 1u<<3,

      a_SKIP_XDG = 1u<<15, /* We shall not act */

      a__SAVED_MASK = (a_SKIP_XDG << 1) - 1, /* Bits to restore on !isopen */

      /* Flags */
      a_MPV = 1u<<30 /* Multi-Purpose-Vehicle */
   };

   struct a_dirtree{
      char const *name;
      int mode;
   };

   static struct a_dirtree const a_dirtree[] = {
      {a_RUNTIME_DIR_OUTER, a_RUNTIME_DIR_OUTER_MODE},
      {a_RUNTIME_DIR_BASE, a_RUNTIME_DIR_BASE_MODE},
      {NULL, 0} /* XXX -> nelem/item/countof */
   };
   static int f_saved;

   char uidbuf[sizeof "../.18446744073709551615"],
         xbuf[((sizeof("XDG_RUNTIME_DIR=") + sizeof(a_RUNTIME_DIR_OUTER) +
               sizeof(a_RUNTIME_DIR_BASE) +
               sizeof("../.18446744073709551615")) |
            (sizeof("XDG_CONFIG_DIRS=") + PATH_MAX)
            ) +1];
   struct a_dirtree dt_user;
   struct a_dirtree const *dtp;
   struct passwd *pwp;
   int cwdfd, cntrlfd, datfd, f, res, uidbuflen;
   char const *user, *emsg;

   user = "<unset>";
   cwdfd = AT_FDCWD;
   datfd = cntrlfd = -1;

   /* Command line */
   if(isopen){
      f = a_NONE;

      for(; argc > 0; ++argv, --argc){
         if(!strcmp(argv[0], "runtime"))
            f |= a_RUNTIME;
         else if(!strcmp(argv[0], "rundir")){ /* XXX COMPAT */
            a_LOG(pamh, a_LOG_NOTICE,
               a_XDG ": \"rundir\" was a misdocumentation of \"runtime\", "
               "sorry for this");
            f |= a_RUNTIME;
         }
         else if(!strcmp(argv[0], "notroot"))
            f |= a_NOTROOT;
         else if(!strcmp(argv[0], "track_sessions"))
            f |= a_SESSIONS;
         else if(!strcmp(argv[0], "per_user_lock"))
            f |= a_USER_LOCK;
         else if(!(flags & PAM_SILENT)){
            emsg = "command line";
            errno = EINVAL;
            goto jerr;
         }
      }

      if((f & a_USER_LOCK) && !(f & a_SESSIONS))
         a_LOG(pamh, a_LOG_NOTICE,
            a_XDG ": \"per_user_lock\" requires \"track_sessions\"");
   }else{
      f = f_saved;

      if(f & a_SKIP_XDG)
         goto jok;
   }

   /* We need the user we go for */
   if((res = pam_get_item(pamh, PAM_USER, (void const**)&user)
         ) != PAM_SUCCESS){
      user = "<lookup failed>";
      emsg = "cannot query PAM_USER name";
      goto jepam;
   }

   /* No PAM failure, no PAM_USER_UNKNOWN here: we are no authentificator! */
   if((pwp = getpwnam(user)) == NULL){
      emsg = "host does not know about user";
      errno = EINVAL;
      goto jerr;
   }

   if((f & a_NOTROOT) && pwp->pw_uid == 0){
      f |= a_SKIP_XDG;
      goto jok;
   }

   /* Our lockfile and per-user directory name */
   uidbuflen = snprintf(uidbuf, sizeof(uidbuf), "../.%lu", /* xxx error?? */
         (unsigned long)pwp->pw_uid) - 3;

   dt_user.name = &uidbuf[4];
   dt_user.mode = 0700; /* XDG implied */

   /* Handle tree, go to user runtime.  On *BSD outermost may not exist! */
   for(/*f &= ~a_MPV,*/ dtp = a_dirtree;;){
      int e;
      gid_t oegid;
      mode_t oumask;

      if((res = openat(cwdfd, dtp->name,
               (a_O_SEARCH | O_DIRECTORY | O_NOFOLLOW))) != -1){
         if(cwdfd != AT_FDCWD)
            close(cwdfd); /* XXX error hdl */
         cwdfd = res;

         if(dtp == &dt_user)
            break;
         else if((++dtp)->name == NULL)
            dtp = &dt_user;
         f &= ~a_MPV;
         continue;
      }

      if(!isopen)
         /* XXX Entire directory tree disappeared while sessions were open!
          * XXX Silently out!?! */
         goto jok;

      /* We try creating the directories once as necessary */
      if((f & a_MPV) || errno != ENOENT){
         emsg = "cannot obtain chdir(2) descriptor (within) tree "
               a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE;
         goto jerr;
      }
      f |= a_MPV;

      oumask = umask(0000);
      oegid = getegid();
      setegid(0);
         res = mkdirat(cwdfd, dtp->name, dtp->mode);
         e = (res == -1) ? errno : 0;
      setegid(oegid);
      umask(oumask);

      if(res == -1){
         if(e != EEXIST){
            emsg = "cannot create directory (within) tree "
                  a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE;
            goto jerr;
         }
      }else if(cwdfd == AT_FDCWD)
         a_LOG(pamh, a_LOG_NOTICE,
            a_XDG ": " a_RUNTIME_DIR_OUTER " did not exist, but should be "
            "(a mount point of) volatile storage!");
      /* Just chown it! */
      else if(dtp == &dt_user &&
            fchownat(cwdfd, &uidbuf[4], pwp->pw_uid, pwp->pw_gid,
               AT_SYMLINK_NOFOLLOW) == -1){
         emsg = "cannot chown(2) per user XDG_RUNTIME_DIR";
         goto jerr;
      }
   }

   /* When opening, put environment.  Ignore (but log) putenv() failures, even
    * if session handling is not enabled: very unlikely, and non-critical */
   if(isopen){
      char *cp;

      /* XDG_RUNTIME_DIR */
      cp = xbuf;
      memcpy(cp, "XDG_RUNTIME_DIR=", sizeof("XDG_RUNTIME_DIR=") -1);
      cp += sizeof("XDG_RUNTIME_DIR=") -1;
      memcpy(cp, a_RUNTIME_DIR_OUTER, sizeof(a_RUNTIME_DIR_OUTER) -1);
      cp += sizeof(a_RUNTIME_DIR_OUTER) -1;
      *cp++ = '/';
      memcpy(cp, a_RUNTIME_DIR_BASE, sizeof(a_RUNTIME_DIR_BASE) -1);
      cp += sizeof(a_RUNTIME_DIR_BASE) -1;
      *cp++ = '/';
      memcpy(cp, &uidbuf[4], uidbuflen);

      if(pam_putenv(pamh, xbuf) != PAM_SUCCESS)
         a_LOG(pamh, a_LOG_ERR, a_XDG ": user %s: pam_putenv(): %s\n",
            user, pam_strerror(pamh, res));

      /* And the rest unless disallowed */
      if(!(f & a_RUNTIME)){
         struct a_dir{
            char const *name;
            size_t len;
            char const *defval;
         };

         static struct a_dir const a_dirs[] = {
            {"XDG_DATA_HOME=", sizeof("XDG_DATA_HOME=") -1,
               a_XDG_DATA_HOME_DEF},
            {"XDG_CONFIG_HOME=", sizeof("XDG_CONFIG_HOME=") -1,
               a_XDG_CONFIG_HOME_DEF},
            {"XDG_DATA_DIRS=", sizeof("XDG_DATA_DIRS=") -1,
               a_XDG_DATA_DIRS_DEF},
            {"XDG_CONFIG_DIRS=", sizeof("XDG_CONFIG_DIRS=") -1,
               a_XDG_CONFIG_DIRS_DEF},
            {"XDG_CACHE_HOME=", sizeof("XDG_CACHE_HOME=") -1,
               a_XDG_CACHE_HOME_DEF},
            {NULL,0,NULL} /* XXX -> nelem/item/countof */
         };

         char const *src;
         struct a_dir const *adp;
         size_t i;

         i = strlen(pwp->pw_dir);

         for(adp = a_dirs; adp->name != NULL; ++adp){
            cp = xbuf;
            memcpy(cp, adp->name, adp->len);
            cp += adp->len;
            if(*(src = adp->defval) == '\1'){
               memcpy(cp, pwp->pw_dir, i);
               cp += i;
               ++src;
            }
            memcpy(cp, src, strlen(src) +1);

            if(pam_putenv(pamh, xbuf) != PAM_SUCCESS)
               a_LOG(pamh, a_LOG_ERR, a_XDG ": user %s: pam_putenv(): %s\n",
                  user, pam_strerror(pamh, res));
         }
      }
   }

   /* In session mode we have to manage the counter file */
   if(f & a_SESSIONS){
      unsigned long long int sessions;

      /* Landed in the runtime base dir, obtain our lock */
      if((cntrlfd = openat(cwdfd,
            (f & a_USER_LOCK ? uidbuf : a_LOCK_FILE),
            (O_CREAT | O_WRONLY | O_NOFOLLOW | O_NOCTTY),
            (S_IRUSR | S_IWUSR))) == -1){
         emsg = "cannot open control lock file";
         goto jerr;
      }

      for(res = a_LOCK_TRIES;;){
         struct flock flp;

         memset(&flp, 0, sizeof flp);
         flp.l_type = F_WRLCK;
         flp.l_start = 0;
         flp.l_whence = SEEK_SET;
         flp.l_len = 0;

         if(fcntl(cntrlfd, F_SETLKW, &flp) != -1)
            break;

         /* XXX It may happen we cannot manage the lock and thus not access
          * XXX the session counter, ie this session is zombie to us.
          * XXX Just like counter below, should globally disable sessions!! */
         if(errno != EINTR){
            emsg = "unexpected error obtaining lock on lock control file";
            goto jerr;
         }
         if(--res == 0){
            emsg = "cannot obtain lock on lock control file";
            goto jerr;
         }
      }

      sessions = 0;

      if((datfd = openat(cwdfd, a_DAT_FILE, O_RDONLY)) != -1){
         char *ep;
         ssize_t r;

         while((r = read(datfd, xbuf, sizeof(xbuf) -1)) == -1){
            if(errno != EINTR)
               goto jecnt;
         }

         close(datfd);
         datfd = -1;

         xbuf[(size_t)r] = '\0';
         sessions = strtoull(xbuf, &ep, 10);
         /* Do not log too often for "session counter error"s, as below */
         if(ep == xbuf){
            /* It likely had been actively truncate(2)d below.  If we are
             * opening this session, simply continue without session support,
             * the corresponding log entry had been emitted in the past, so
             * just give the user the environment variables (s)he wants */
            if(isopen){
               f |= a_SKIP_XDG;
               goto jok;
            }
            res = PAM_SESSION_ERR;
            goto jleave;
         }else if(sessions == ULLONG_MAX || ep != &xbuf[(size_t)r])
            goto jecnt;
      }

      if(isopen)
         ++sessions;
      else if(sessions > 0)
         --sessions;

      if(!isopen && sessions == 0){ /* former.. hmmm. */
         /* Ridiculously simple, but everything else would be the opposite.
          * Ie, E[MN]FILE failures, or whatever else */
         char const cmd[] = "rm -rf " a_RUNTIME_DIR_OUTER "/"
               a_RUNTIME_DIR_BASE "/";

         memcpy(xbuf, cmd, sizeof(cmd) -1);
         memcpy(&xbuf[sizeof(cmd) -1], &uidbuf[4], uidbuflen +1);

         res = system(xbuf);
         if(!WIFEXITED(res) || WEXITSTATUS(res) != 0){
            emsg = "unable to rm(1) -rf per user XDG_RUNTIME_DIR";
            errno = EINVAL;
            goto jerr;
         }
         /* This is the end .. */
         goto jok;
      }else{
         /* Write out session counter */
         res = snprintf(xbuf, sizeof xbuf, "%llu", sessions); /* xxx error? */

         if(((datfd = openat(cwdfd, a_DAT_FILE,
                  (O_CREAT | O_TRUNC | O_WRONLY | O_SYNC | O_NOFOLLOW |
                     O_NOCTTY),
                  (S_IRUSR | S_IWUSR))) == -1) ||
               write(datfd, xbuf, res) != res){
jecnt:
            /* Ensure read above fails, so that henceforth session teardown is
             * skipped for this user */
            truncate(a_DAT_FILE, 0); /* xxx that may fail, too!? */
            emsg = "counter file error, disabled session tracking for user";
            goto jerr;
         }
         close(datfd);
         datfd = -1;
      }
   }

jok:
   res = PAM_SUCCESS;
jleave:
   if(datfd != -1)
      close(datfd);
   if(cntrlfd != -1)
      close(cntrlfd);
   if(cwdfd != -1 && cwdfd != AT_FDCWD) /* >=0, but AT_FDCWD unspecified */
      close(cwdfd);

   f &= a__SAVED_MASK;
   f_saved = f;

   return (res == PAM_SUCCESS) ? PAM_SUCCESS : PAM_SESSION_ERR;

jerr:
   a_LOG(pamh, a_LOG_ERR, a_XDG ": user %s: %s: %s\n",
      user, emsg, strerror(errno));
   f |= a_SKIP_XDG;
   res = PAM_SESSION_ERR;
   goto jleave;

jepam:
   a_LOG(pamh, a_LOG_ERR, a_XDG ": user %s: PAM failure: %s\n",
      user, pam_strerror(pamh, res));
   f |= a_SKIP_XDG;
   goto jleave;
}

int
pam_sm_open_session(pam_handle_t *pamh, int flags,
      int argc, const char **argv){
   return a_xdg(1, pamh, flags, argc, argv);
}

int
pam_sm_close_session(pam_handle_t *pamh, int flags,
      int argc, const char **argv){
   return a_xdg(0, pamh, flags, argc, argv);
}

int
pam_sm_acct_mgmt(pam_handle_t *pamh, int flags, int argc, const char **argv){
   (void)flags;
   (void)argc;
   (void)argv;

   a_LOG(pamh, a_LOG_NOTICE, a_XDG ": pam_sm_acct_mgmt not used");

   return PAM_SERVICE_ERR;
}

int
pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv){
   (void)flags;
   (void)argc;
   (void)argv;

   a_LOG(pamh, a_LOG_NOTICE, a_XDG ": pam_sm_setcred not used");

   return PAM_SERVICE_ERR;
}

int
pam_sm_chauthtok(pam_handle_t *pamh, int flags, int argc, const char **argv){
   (void)flags;
   (void)argc;
   (void)argv;

   a_LOG(pamh, a_LOG_NOTICE, a_XDG ": pam_sm_chauthtok not used");

   return PAM_SERVICE_ERR;
}

/* s-it-mode */
