/*@ pam_xdg - manage XDG Base Directories (runtime dir life time, environment).
 *@ See pam_xdg.8 for more.
 *@ - According to XDG Base Directory Specification, v0.7.
 *@ - Supports libpam (Linux) and *BSD OpenPAM.
 *@ - Requires C preprocessor with __VA_ARGS__ support!
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
#define a_XDG_DATA_DIRS_DEF "/usr/local/share:/usr/share"
#define a_XDG_CONFIG_DIRS_DEF "/etc/xdg/"
#define a_XDG_CACHE_HOME_DEF "\1/.cache"

/* We create the outer directories as necessary (stack buffer storage!) */
#define a_RUNTIME_DIR_OUTER "/run"
#define a_RUNTIME_DIR_OUTER_MODE 0755
#define a_RUNTIME_DIR_BASE "user"
#define a_RUNTIME_DIR_BASE_MODE 0755 /* 0711? */

/* >8 -- 8< */

/*
#define _POSIX_C_SOURCE 200809L
#define _ATFILE_SOURCE
*/
#define _GNU_SOURCE /* Always the same mess */

#include <sys/stat.h>
#include <sys/types.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
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

/* Because of complicated file locking, use one function with two exec paths */
static int a_xdg(int isopen, pam_handle_t *pamh, int flags, int argc,
      const char **argv);

static int
a_xdg(int isopen, pam_handle_t *pamh, int flags, int argc, const char **argv){
   enum a_flags{
      a_NONE,
      /* Options */
      a_RUNTIME = 1u<<0,
      a_NOTROOT = 1u<<1,
#if 0
      a_SESSIONS = 1u<<16,
      a_USER_LOCK = 1u<<17,
#endif
      /* Flags */
      a_MPV = 1u<<29, /* Multi-Purpose-Vehicle */
      a_SKIP_XDG = 1u<<30 /* We shall not act */
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

   char uidbuf[sizeof ".18446744073709551615"],
         wbuf[((sizeof("XDG_RUNTIME_DIR=") + sizeof(a_RUNTIME_DIR_OUTER) +
               sizeof(a_RUNTIME_DIR_BASE) + sizeof(".18446744073709551615")) |
            (sizeof("XDG_CONFIG_DIRS=") + PATH_MAX)
            ) +1];
   struct a_dirtree const *dtp;
   struct passwd *pwp;
   char const *emsg;
   int cwdfd, f, res, uidbuflen;
   char const *user;

   user = "<unset>";
   cwdfd = AT_FDCWD;

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
#if 0
         else if(!strcmp(argv[0], "track_user_sessions"))
            f |= a_SESSIONS;
         else if(!strcmp(argv[0], "per_user_lock"))
            f |= a_USER_LOCK;
#endif
         else if(!(flags & PAM_SILENT)){
            emsg = "command line";
            errno = EINVAL;
            goto jerr;
         }
      }

#if 0
      if((f & a_USER_LOCK) && !(f & a_SESSIONS))
         a_LOG(pamh, a_LOG_NOTICE,
            a_XDG ": \"per_user_lock\" requires \"track_user_sessions\"");
#endif
   }else{
      f = f_saved;

      if(f & a_SKIP_XDG)
         goto jok;
      goto jok; /* No longer used, session counting does not work */
   }

   /* We need the user we go for */
   if((res = pam_get_item(pamh, PAM_USER, (void const**)&user)
         ) != PAM_SUCCESS){
      user = "<lookup failed>";
      emsg = "cannot query PAM_USER name";
      goto jepam;
   }

   if((pwp = getpwnam(user)) == NULL){
      emsg = "host does not know about user";
      errno = EINVAL;
      goto jerr;
   }

   if((f & a_NOTROOT) && pwp->pw_uid == 0){
      f |= a_SKIP_XDG;
      goto jok;
   }

   /* Handle outer directory tree.  On *BSD outermost may not exist! */
   for(/*f &= ~a_MPV,*/ dtp = a_dirtree; dtp->name != NULL;){
      int e;
      gid_t oegid;
      mode_t oumask;

      if((res = openat(cwdfd, dtp->name,
               (a_O_SEARCH | O_DIRECTORY | O_NOFOLLOW))) != -1){
         if(cwdfd != AT_FDCWD)
            close(cwdfd); /* XXX error hdl */
         cwdfd = res;
         f &= ~a_MPV;
         ++dtp;
         continue;
      }

      if(!isopen)
         /* Someone removed the entire directory tree while sessions were open!
          * Silently out!?! */
         goto jok;

      /* We try create the directories once as necessary */
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
   }

   /* Turn to user management; note this is the lockfile */
   uidbuflen = snprintf(uidbuf, sizeof(uidbuf), ".%lu",
         (unsigned long)pwp->pw_uid);

   /* We create the per-user directory on isopen time as necessary */
   for(f &= ~a_MPV;; f |= a_MPV){
      if((res = openat(cwdfd, &uidbuf[1],
            (a_O_SEARCH | O_DIRECTORY | O_NOFOLLOW))) != -1){
         close(cwdfd); /* XXX error hdl */
         cwdfd = res;
         break;
      }else{
         if(errno == ENOENT){
            if(!isopen)
               goto jok;
            if(f & a_MPV)
               goto jeurd;
         }else{
jeurd:
            emsg = "per user XDG_RUNTIME_DIR not accessible";
            goto jerr;
         }
      }

      if(mkdirat(cwdfd, &uidbuf[1], 0700) == -1 && errno != EEXIST){
         emsg = "cannot create per user XDG_RUNTIME_DIR";
         goto jerr;
      }

      /* Just chown it! */
      if(fchownat(cwdfd, &uidbuf[1], pwp->pw_uid, pwp->pw_gid,
            AT_SYMLINK_NOFOLLOW) == -1){
         emsg = "cannot chown(2) per user XDG_RUNTIME_DIR";
         goto jerr;
      }
   }

   /* When opening, we want to put environment variables, too */
   if(isopen){
      char *cp;

      /* XDG_RUNTIME_DIR */
      cp = wbuf;
      memcpy(cp, "XDG_RUNTIME_DIR=", sizeof("XDG_RUNTIME_DIR=") -1);
      cp += sizeof("XDG_RUNTIME_DIR=") -1;
      memcpy(cp, a_RUNTIME_DIR_OUTER, sizeof(a_RUNTIME_DIR_OUTER) -1);
      cp += sizeof(a_RUNTIME_DIR_OUTER) -1;
      *cp++ = '/';
      memcpy(cp, a_RUNTIME_DIR_BASE, sizeof(a_RUNTIME_DIR_BASE) -1);
      cp += sizeof(a_RUNTIME_DIR_BASE) -1;
      *cp++ = '/';
      memcpy(cp, &uidbuf[1], uidbuflen);

      if((res = pam_putenv(pamh, wbuf)) != PAM_SUCCESS)
         goto jepam;

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
            cp = wbuf;
            memcpy(cp, adp->name, adp->len);
            cp += adp->len;
            if(*(src = adp->defval) == '\1'){
               memcpy(cp, pwp->pw_dir, i);
               cp += i;
               ++src;
            }
            memcpy(cp, src, strlen(src) +1);

            if((res = pam_putenv(pamh, wbuf)) != PAM_SUCCESS)
               goto jepam;
         }
      }
   }

jok:
   res = PAM_SUCCESS;
jleave:
   if(cwdfd != -1 && cwdfd != AT_FDCWD) /* >=0, but AT_FDCWD unspecified */
      close(cwdfd);

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
