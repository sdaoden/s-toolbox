/*@ pam_xdg - manage XDG Base Directories (runtime dir life time, environment).
 *@ Create /run/user/`id -u` when the first session is opened, and remove it
 *@ again once the last is closed.
 *@ It also creates according XDG_RUNTIME_DIR etc. environment variables in the
 *@ user sessions, except when given the "runtime" option, in which case it
 *@ only creates XDG_RUNTIME_DIR and not the others.
 *@ Place for example in /etc/pam.d/common-session one of the following:
 *@   session options pam_xdg.so [runtime] [notroot]
 *@ Notes: - effectively needs ISO C99 as it uses strtoull(3).
 *@        - according to XDG Base Directory Specification, v0.7.
 *@        - Linux.
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

#define a_RUNTIME_DIR_OUTER "/run"  /* This must exist already */
#define a_RUNTIME_DIR_BASE "user" /* We create this as necessary, thus. */

#define a_LOCK_FILE "." a_XDG ".lck"
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
#include <stdint.h>
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
         wbuf[(((sizeof("18446744073709551615") -1) * 2) | 
            (sizeof("cd ..;rm -rf ") + sizeof("18446744073709551615")) |
            (sizeof("XDG_RUNTIME_DIR=") + sizeof(a_RUNTIME_DIR_OUTER) +
               sizeof(a_RUNTIME_DIR_BASE) + sizeof("18446744073709551615")) |
            (sizeof("XDG_CONFIG_DIRS=") + PATH_MAX)
            ) +1];
   struct flock flp;
   struct stat st;
   uint64_t sessions;
   struct passwd *pwp;
   char const *emsg;
   int cntrlfd, fd, cwdfd, only_runtime, notroot, res, uidbuflen;
   char const *user;
   (void)flags;

   user = "<unset>";
   cntrlfd = fd = cwdfd = -1;
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
   }

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
   umask(0022);

   if((cwdfd = open(a_RUNTIME_DIR_OUTER, (O_PATH | O_DIRECTORY | O_NOFOLLOW))
         ) == -1){
      emsg = "cannot obtain chdir(2) descriptor to " a_RUNTIME_DIR_OUTER;
      goto jerr;
   }

   /* We try create the base directory once as necessary */
   if(isopen){
      res = 0;
      while(fstatat(cwdfd, a_RUNTIME_DIR_BASE, &st, AT_SYMLINK_NOFOLLOW
            ) == -1){
         if(res++ != 0 || errno != ENOENT){
            emsg = "base directory " a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE
                  " not accessible";
            goto jerr;
         }

         if(mkdirat(cwdfd, a_RUNTIME_DIR_BASE, 0711) == -1){
            emsg = "cannot create base directory "
                  a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE;
            goto jerr;
         }
      }
   }

   if((res = openat(cwdfd, a_RUNTIME_DIR_BASE,
         (O_PATH | O_DIRECTORY | O_NOFOLLOW))) == -1){
      emsg = "cannot obtain chdir(2) descriptor to " a_RUNTIME_DIR_OUTER "/"
            a_RUNTIME_DIR_BASE;
      goto jerr;
   }
   close(cwdfd);
   cwdfd = res;

   /* Landed in the runtime base dir, obtain our lock */
   if((cntrlfd = openat(cwdfd, a_LOCK_FILE,
         (O_CREAT | O_WRONLY | O_NOFOLLOW | O_NOCTTY),
         (S_IRUSR | S_IWUSR))) == -1){
      emsg = "cannot open control lock file";
      goto jerr;
   }

   for(res = a_LOCK_TRIES;;){
      memset(&flp, 0, sizeof flp);
      flp.l_type = F_WRLCK;
      flp.l_start = 0;
      flp.l_whence = SEEK_SET;
      flp.l_len = 0;

      if(fcntl(cntrlfd, F_SETLKW, &flp) != -1)
         break;

      if(errno != EINTR){
         emsg = "unexpected error obtaining lock on control lock file";
         goto jerr;
      }
      if(--res == 0){
         emsg = "cannot obtain lock on control lock file";
         goto jerr;
      }
   }

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

      if(mkdirat(cwdfd, uidbuf, 0700) == -1){
         emsg = "cannot create per user XDG_RUNTIME_DIR";
         goto jerr;
      }
      if(fchownat(cwdfd, uidbuf, pwp->pw_uid, pwp->pw_gid, AT_SYMLINK_NOFOLLOW
            ) == -1){
         emsg = "cannot chown(2) per user XDG_RUNTIME_DIR";
         goto jerr;
      }
   }

   /* Read session counter; be simple and assume 0 if non-existent, this should
    * not happen in practice */
   sessions = 0;
   if((fd = openat(cwdfd, a_DAT_FILE, O_RDONLY)) != -1){
      char *ep;
      ssize_t r;

      while((r = read(fd, wbuf, sizeof(wbuf) -1)) == -1){
         if(errno != EINTR){
            emsg = "I/O error while reading session counter";
            goto jerr;
         }
      }

      /* We have written this as a valid POSIX text file, then, so chop tail */
      if(r < 1 || (size_t)r >= (sizeof(wbuf) -1) / 2){
jecnt:
         emsg = "session counter corrupted, ask administrator to remove "
               a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE "/YOUR-UID/"
               a_DAT_FILE;
         goto jerr;
      }
      for(;;){
         char c;

         c = wbuf[(size_t)r - 1];
         if(c == '\0' || c == '\n'){
            if(--r == 0)
               goto jecnt;
         }else
            break;
      }
      wbuf[(size_t)r] = '\0';

      sessions = strtoull(wbuf, &ep, 10);
      if(sessions == ULLONG_MAX || ep == wbuf || *ep != '\0')
         goto jecnt;

      close(fd);
      fd = -1;
   }

   if(isopen)
      ++sessions;
   /* == 0 should never happen, but just handled it easily */
   else if(sessions == 0 || --sessions == 0){
      /* This is ridiculously simple, but everything else would be opposite */
      char const cmd[] = "rm -rf " a_RUNTIME_DIR_OUTER "/"
            a_RUNTIME_DIR_BASE "/";

      memcpy(wbuf, cmd, sizeof(cmd) -1);
      memcpy(&wbuf[sizeof(cmd) -1], uidbuf, uidbuflen +1);
      res = system(wbuf);
      if(!WIFEXITED(res) || WEXITSTATUS(res) != 0){
         emsg = "unable to rm(1) -rf per user XDG_RUNTIME_DIR";
         errno = EINVAL;
         goto jerr;
      }
      goto jok;
   }

   /* Write out session counter (as a valid POSIX text file) */
   res = snprintf(wbuf, sizeof wbuf, "%llu\n", (unsigned long long)sessions);

   if(((fd = openat(cwdfd, a_DAT_FILE,
         (O_CREAT | O_TRUNC | O_WRONLY | O_SYNC | O_NOFOLLOW | O_NOCTTY),
         (S_IRUSR | S_IWUSR))) == -1) || write(fd, wbuf, res) != res){
      emsg = "cannot write session counter, ask administrator to remove "
            a_RUNTIME_DIR_OUTER "/" a_RUNTIME_DIR_BASE "/YOUR-UID/"
            a_DAT_FILE;
      goto jerr;
   }
   close(fd);
   fd = -1;

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
   if(fd != -1)
      close(fd);
   if(cntrlfd != -1)
      close(cntrlfd);
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
