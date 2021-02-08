/*@ pam_xdg - manage XDG Base Directories (runtime dir life time, environment).
 *@ Create /run/user/`id -u` when the first session is opened.
 *@ It also creates according XDG_RUNTIME_DIR etc. environment variables in the
 *@ user sessions, except when given the "runtime" option, in which case it
 *@ only creates XDG_RUNTIME_DIR and not the others.
 *@ Place for example in /etc/pam.d/common-session one of the following:
 *@   session options pam_xdg.so [runtime] [notroot]
 *@ Notes: - according to XDG Base Directory Specification, v0.7.
 *@        - Linux-only (i think).
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

/* */
#define a_XDG "pam_xdg"

#define a_RUNTIME_DIR_OUTER "/run" /* This must exist already */
#define a_RUNTIME_DIR_BASE "user" /* We create this as necessary, thus. */
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
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include <security/pam_modules.h>
#include <security/pam_ext.h>

/* _XOPEN_PATH_MAX POSIX 2008/Cor 1-2013 */
#ifndef PATH_MAX
# define PATH_MAX 1024
#endif

static int a_xdg(int isopen, pam_handle_t *pamh, int flags, int argc,
      const char **argv);

static int
a_xdg(int isopen, pam_handle_t *pamh, int flags, int argc, const char **argv){
   char uidbuf[sizeof "18446744073709551615"],
         wbuf[((sizeof("XDG_RUNTIME_DIR=") + sizeof(a_RUNTIME_DIR_OUTER) +
               sizeof(a_RUNTIME_DIR_BASE) + sizeof("18446744073709551615")) |
            (sizeof("XDG_CONFIG_DIRS=") + PATH_MAX)
            ) +1];
   struct stat st;
   struct passwd *pwp;
   char const *emsg;
   int cwdfd, only_runtime, notroot, res, uidbuflen;
   char const *user;
   (void)flags;

   user = "<unset>";
   cwdfd = -1;
   only_runtime = notroot = 0;

   /* Command line */
   if(isopen){
      for(; argc > 0; ++argv, --argc){
         if(!strcmp(argv[0], "runtime"))
            only_runtime = 1;
         else if(!strcmp(argv[0], "notroot"))
            notroot = 1;
         else if(!(flags & PAM_SILENT)){
            emsg = "command line";
            errno = EINVAL;
            goto jerr;
         }
      }
   }else
      goto jok; /* No longer used, session counting does not work */

   /* We need the user we go for */
   if((res = pam_get_item(pamh, PAM_USER, (void const**)&user)
         ) != PAM_SUCCESS){
      user = "<lookup failed>";
      emsg = "cannot query PAM_USER name";
      goto jepam;
   }

   if((pwp = getpwnam(user)) == NULL){
      emsg = "host machine does not know about user";
      errno = EINVAL;
      goto jerr;
   }

   if(notroot && pwp->pw_uid == 0)
      goto jok;

   /* I admit all this is overly complicated and expensive */
   if((cwdfd = open(a_RUNTIME_DIR_OUTER, (O_PATH | O_DIRECTORY | O_NOFOLLOW))
         ) == -1){
      emsg = "cannot obtain chdir(2) descriptor to " a_RUNTIME_DIR_OUTER;
      goto jerr;
   }

   /* We try create the base directory once as necessary */
   /*if(isopen)*/{
      res = 0;
      while(fstatat(cwdfd, a_RUNTIME_DIR_BASE, &st, AT_SYMLINK_NOFOLLOW
            ) == -1){
         if(res++ != 0 || errno != ENOENT){
            emsg = "base directory " a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE
                  " not accessible";
            goto jerr;
         }

         if(mkdirat(cwdfd, a_RUNTIME_DIR_BASE, a_RUNTIME_DIR_BASE_MODE
               ) == -1 && errno != EEXIST){
            emsg = "cannot create base directory "
                  a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE;
            goto jerr;
         }
      }
      /* Not worth doing S_ISDIR(st.st_mode), O_DIRECTORY will bail next */
   }

   if((res = openat(cwdfd, a_RUNTIME_DIR_BASE,
         (O_PATH | O_DIRECTORY | O_NOFOLLOW))) == -1){
      emsg = "cannot obtain chdir(2) descriptor to " a_RUNTIME_DIR_OUTER "/"
            a_RUNTIME_DIR_BASE;
      goto jerr;
   }
   close(cwdfd);
   cwdfd = res;

   /* Turn to user management */
   uidbuflen = snprintf(uidbuf, sizeof(uidbuf), "%lu",
         (unsigned long)pwp->pw_uid);

   /* We create the per-user directory on isopen time as necessary */
   for(res = 0;; ++res){
      int nfd;

      if((nfd = openat(cwdfd, uidbuf, (O_PATH | O_DIRECTORY | O_NOFOLLOW))
            ) != -1){
         close(cwdfd);
         cwdfd = nfd;
         break;
      }else{
         if(errno == ENOENT){
            if(!isopen)
               goto jok;
            if(res != 0)
               goto jeurd;
         }else{
jeurd:
            emsg = "per user XDG_RUNTIME_DIR not accessible";
            goto jerr;
         }
      }

      if(mkdirat(cwdfd, uidbuf, 0700) == -1 && errno != EEXIST){
         emsg = "cannot create per user XDG_RUNTIME_DIR";
         goto jerr;
      }

      /* Just chown it! */
      if(fchownat(cwdfd, uidbuf, pwp->pw_uid, pwp->pw_gid,
            AT_SYMLINK_NOFOLLOW) == -1){
         emsg = "cannot chown(2) per user XDG_RUNTIME_DIR";
         goto jerr;
      }
   }

   /* When opening, we want to put environment variables, too */
   /*if(isopen)*/{
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
      memcpy(cp, uidbuf, uidbuflen +1);

      if((res = pam_putenv(pamh, wbuf)) != PAM_SUCCESS)
         goto jepam;

      /* And the rest */
      if(!only_runtime){
         struct adir{
            char const *name;
            size_t len;
            char const *defval;
         } const adirs[] = {
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
            {NULL,0,NULL} /* xxx nelem */
         }, *adp;

         char const *src;
         size_t i;

         i = strlen(pwp->pw_dir);

         for(adp = adirs; adp->name != NULL; ++adp){
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
   if(cwdfd != -1)
      close(cwdfd);

   return (res == PAM_SUCCESS) ? PAM_SUCCESS : PAM_SESSION_ERR;

jerr:
   pam_syslog(pamh, LOG_ERR, a_XDG ": user %s: %s: %s\n",
      user, emsg, strerror(errno));
   res = PAM_SESSION_ERR;
   goto jleave;

jepam:
   pam_syslog(pamh, LOG_ERR, a_XDG ": user %s: PAM failure: %s\n",
      user, pam_strerror(pamh, res));
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
   pam_syslog(pamh, LOG_NOTICE, "pam_sm_acct_mgmt not used by " a_XDG);
   return PAM_SERVICE_ERR;
}

int
pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv){
   (void)flags;
   (void)argc;
   (void)argv;
   pam_syslog(pamh, LOG_NOTICE, "pam_sm_setcred not used by " a_XDG);
   return PAM_SERVICE_ERR;
}

int
pam_sm_chauthtok(pam_handle_t *pamh, int flags, int argc, const char **argv){
   (void)flags;
   (void)argc;
   (void)argv;
   pam_syslog(pamh, LOG_NOTICE, "pam_sm_chauthtok not used by " a_XDG);
   return PAM_SERVICE_ERR;
}

/* s-it-mode */
