/*@ Save and load Linux (2.6.0+) entropy.
 *@ Different to "cat XY > /dev/urandom" this increments "entropy_avail".
 *@ NOTE: this will not work correctly if used in conjunction with haveged
 *@ or a similar entropy managing daemon; *unless* it is ensured it loads
 *@ entropy before, and saves entropy after the daemon lifetime!
 *@ Synopsis: entropy-saver save [file]
 *@ Synopsis: entropy-saver load [file]
 *@ "file" defaults to a_RAND_FILE_STORE.
 *@ XXX save: should build [file].new, and link(2) to [file] only on success.
 *
 * 2019 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
 * Public Domain
 */

/* Random device*/
#define a_RAND_DEV "/dev/random"

/* Maximum number of bytes we handle (must be LT INT_MAX/8!) */
#define a_RAND_NO_BYTES 512

/* When saving, the minimum number of entropy_avail we keep in the pool.
 * _This_ is checked after we have read once (512 we test initially).
 * We will refuse to save a dump which offers less than 128 bits. */
#define a_RAND_ENTROPY_COUNT_MIN 1024

/* Default storage */
#define a_RAND_FILE_STORE "/var/lib/misc/random.dat"

#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sysexits.h>
#include <syslog.h>
#include <unistd.h>

#include <linux/random.h>
#include <linux/version.h>

#if KERNEL_VERSION(2,6,0) >= LINUX_VERSION_CODE
# error Linux kernel version and IOCTL usage incompatible.
#endif

static char const a_rand_file_store[] = a_RAND_FILE_STORE;

int
main(int argc, char **argv){
   enum {a_LOAD, a_SAVE};

   struct{
      struct rand_pool_info rpi;
      char buf[a_RAND_NO_BYTES];
   } x;
   char *rpibuf; /* To make C++ happy: rpi.buf is char[0] */
   ssize_t len;
   char const *store;
   int rv, accu, randfd, storfd, iocarg;

   /* Command line handling */
   if(argc < 2 || argc > 3)
      goto jeuse;

   if(!strcmp(argv[1], "load"))
      accu = a_LOAD;
   else if(!strcmp(argv[1], "save"))
      accu = a_SAVE;
   else{
jeuse:
      fprintf(stderr,
         "Synopsis: entropy-saver save [storage-file]\n"
         "Synopsis: entropy-saver load [storage-file]\n"
         "\n"
         "storage-file defaults to " a_RAND_FILE_STORE "\n"
         "Exit: sysexits.h: EX_USAGE, EX_NOPERM, EX_IOERR, EX_TEMPFAIL\n");
      rv = EX_USAGE;
      goto j_leave;
   }

   openlog("entropy-saver",
#ifdef LOG_PERROR
      LOG_PERROR |
#endif
      LOG_PID, LOG_DAEMON);

   /* Open our two files according to chosen action */
   randfd = open(a_RAND_DEV, (O_RDONLY | O_NONBLOCK));
   if(randfd == -1){
      accu = errno;
      syslog(LOG_ERR, "Failed to open " a_RAND_DEV ": %s\n",
         strerror(accu));
      rv = (accu == EACCES || accu == EPERM) ? EX_NOPERM : EX_IOERR;
      goto jleave;
   }

   store = (argv[2] != NULL) ? argv[2] : a_rand_file_store;
   storfd = open(store, (accu == a_LOAD ? O_RDONLY
         : O_WRONLY | O_CREAT | O_TRUNC), (S_IRUSR | S_IWUSR));
   if(storfd == -1){
      accu = errno;
      syslog(LOG_ERR, "Failed to open %s: %s\n", store, strerror(accu));
      rv = (accu == EACCES || accu == EPERM) ? EX_NOPERM : EX_IOERR;
      goto jerr1;
   }

   /* For at least statistics query entropy count once */
   rv = ioctl(randfd, (int)RNDGETENTCNT, &iocarg);
   if(rv == -1){
      syslog(LOG_ERR, "Failed to query available entropy of " a_RAND_DEV
         ": %s\n", strerror(errno));
      rv = EX_IOERR;
      goto jerr2;
   }
   x.rpi.entropy_count = iocarg;

   rpibuf = (char*)x.rpi.buf;

   if(accu == a_LOAD){
      syslog(LOG_INFO, "%d bits of entropy available at " a_RAND_DEV "\n",
         x.rpi.entropy_count);

      /* INT: entropy bits */
      len = read(storfd, &x.rpi.entropy_count, sizeof x.rpi.entropy_count);
      if(len == -1){
         syslog(LOG_ERR, "Failed to read from %s: %s\n",
            store, strerror(errno));
         rv = EX_IOERR;
         goto jerr2;
      }
      if(len != sizeof x.rpi.entropy_count){
         syslog(LOG_ERR, "Storage %s: seems corrupted (false format)\n",
            store);
         rv = EX_IOERR;
         goto jerr2;
      }
      /* The former because we will refuse to save less than that, the latter
       * rather arbitrary (like the suff as such?) */
      if(x.rpi.entropy_count < 128 || x.rpi.entropy_count > 1000000){
         syslog(LOG_ERR, "Storage %s seems corrupted (%d entropy bits)\n",
            store, x.rpi.entropy_count);
         rv = EX_IOERR;
         goto jerr2;
      }

      /* REST: pool bytes */
      len = read(storfd, rpibuf, sizeof x.buf);
      if(len == -1){
         syslog(LOG_ERR, "Failed to read from %s: %s\n",
            store, strerror(errno));
         rv = EX_IOERR;
         goto jerr2;
      }
      if(len == 0){
         syslog(LOG_ERR, "Storage %s: seems corrupted (no entropy)\n", store);
         rv = EX_TEMPFAIL;
         goto jerr2;
      }
      x.rpi.buf_size = (int)len;

      if(read(storfd, &accu, 1) != 0){
         syslog(LOG_ERR, "Storage %s: seems corrupted (no EOF seen)\n",
            store);
         rv = EX_IOERR;
         goto jerr2;
      }

      syslog(LOG_INFO, "%d bytes / %d bits of entropy read from %s\n",
         x.rpi.buf_size, x.rpi.entropy_count, store);

      accu = ioctl(randfd, RNDADDENTROPY, &x.rpi);
      if(accu == -1){
         syslog(LOG_ERR, "Failed to add %d bits of entropy to " a_RAND_DEV
            ": %s\n", x.rpi.entropy_count, strerror(errno));
         rv = EX_IOERR;
         goto jerr2;
      }

      /* For at least statistics */
      rv = ioctl(randfd, (int)RNDGETENTCNT, &iocarg);
      if(rv != -1)
         syslog(LOG_INFO, "%d bits of entropy are at at " a_RAND_DEV "\n",
            iocarg);
   }else{
      /* Since we are reading in non-blocking mode, and since reading from
       * /dev/random returns not that much in this mode, read in a loop until
       * it no longer serves / the entropy count falls under a _COUNT_MIN */
      size_t rem_size;
      int entrop_cnt, e;

      entrop_cnt = x.rpi.entropy_count;
      syslog(LOG_INFO, "%d bits of entropy available at " a_RAND_DEV "%s\n",
         entrop_cnt, (entrop_cnt <= 512 ? ": temporary failure" : ""));
      if(entrop_cnt <= 512){
         rv = EX_TEMPFAIL;
         goto jerr2;
      }

      x.rpi.buf_size = x.rpi.entropy_count = 0;
      rem_size = sizeof x.buf;
jread_more:
      len = read(randfd, rpibuf, rem_size);
      if(len == -1){
         /* Ignore the EAGAIN that /dev/random reports when it would block
          * (Bernd Petrovitsch (bernd at petrovitsch dot priv dot at)) */
         if((e = errno) == EAGAIN ||
#if defined EWOULDBLOCK && EWOULDBLOCK != EAGAIN /* xxx never true on Linux */
               e == EWOULDBLOCK ||
#endif
               e == EBUSY)
            goto jread_insuff;

         syslog(LOG_ERR, "Failed to read from " a_RAND_DEV ": %s\n",
            strerror(errno));
         rv = EX_IOERR;
         goto jerr2;
      }
      x.rpi.buf_size += (int)len;
      rpibuf += len;
      rem_size -= len;

      rv = ioctl(randfd, (int)RNDGETENTCNT, &iocarg);
      if(rv == -1){
         syslog(LOG_ERR, "Failed to query remaining entropy of " a_RAND_DEV
            ": %s\n", strerror(errno));
         rv = EX_IOERR;
         goto jerr2;
      }
      entrop_cnt -= iocarg;
      x.rpi.entropy_count += entrop_cnt;

      /* Try to read more? */
      if(len > 0 && (entrop_cnt = iocarg) >= a_RAND_ENTROPY_COUNT_MIN &&
            rem_size >= 64)
         goto jread_more;
      syslog(LOG_INFO, "%d bits of entropy remain at " a_RAND_DEV "\n",
         iocarg);

      if(x.rpi.entropy_count <= 128){
jread_insuff:
         syslog(LOG_ERR, "Insufficient entropy to save from " a_RAND_DEV
            " (%d bits)\n", x.rpi.entropy_count);
         rv = EX_TEMPFAIL;
         goto jerr2;
      }

      rpibuf = (char*)x.rpi.buf;
      len = x.rpi.buf_size;
      if((ssize_t)sizeof(x.rpi.entropy_count) != write(storfd,
               &x.rpi.entropy_count, sizeof x.rpi.entropy_count) ||
            len != write(storfd, rpibuf, len)){
         syslog(LOG_ERR, "Failed to write to %s: %s\n",
            store, strerror(errno));
         rv = EX_IOERR;
         goto jerr2;
      }

      syslog(LOG_INFO, "%d bits / %d bytes of entropy saved to %s\n",
         x.rpi.entropy_count, x.rpi.buf_size, store);
   }

   rv = 0;
jerr2:
   if(close(storfd) == -1)
      syslog(LOG_ERR, "Error closing %s: %s\n", store, strerror(errno));
jerr1:
   if(close(randfd) == -1)
      syslog(LOG_ERR, "Error closing " a_RAND_DEV ": %s\n", strerror(errno));
jleave:
   closelog();
j_leave:
   return rv;
}

/* s-it-mode */
