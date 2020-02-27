/*@ s-cdda: access digital audio CDs (TOC, MCN, ISRC, CD-TEXT, audio tracks).
 *@ Thanks to Thomas Schmitt (libburnia) for cdrom-cookbook.txt and cdtext.txt.
 *@ According to SCSI Multimedia Commands - 3 (MMC-3, Revision 10g).
 *
 * Copyright (c) 2020 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
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

/* */
#define a_VERSION "0.0.2"
#define a_COPYRIGHT \
   "Copyright (c) 2020 Steffen Nurpmeso <steffen@sdaoden.eu>\n\n"

/* Maximum stack usage (in frames a a_MMC_FRAME_SIZE).
 * linux/drivers/cdrom/cdrom.c mmc_ioctl_cdrom_read_audio() limits this to
 * frames worth a second */
#define a_STACK_FRAMES_MAX 75

/* -- >8 -- 8< -- */

#define su_OS_LINUX 0
#define su_OS_FREEBSD 0

#if 0
#elif defined __linux__ || defined __linux
# undef su_OS_LINUX
# define su_OS_LINUX 1
#else
# error TODO Not ported to this OS yet.
#endif

/* -- >8 -- 8< -- */

#include <sys/ioctl.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#if su_OS_LINUX
# include <linux/cdrom.h>
# include <scsi/sg.h>
# define a_CDROM "/dev/cdrom"
#elif su_OS_FREEBSD
#endif

/* SU compat */
#define FIELD_SIZEOF(T,F) sizeof(((T *)NIL)->F)
#define NELEM(A) (sizeof(A) / sizeof((A)[0]))
#define su_CONCAT(S1,S2) su__CONCAT_1(S1, S2)
#define su__CONCAT_1(S1,S2) S1 ## S2
#define UNINIT(X, Y) X = Y
#define Z_ALIGN(X) (((X) + sizeof(ul)-1) & ~(sizeof(ul) - 1))
#define ul unsigned long int
#define ui unsigned int
#define uz size_t
#define u32 unsigned int
#define u16 unsigned short
#define u8 unsigned char
#define boole u8
#define FAL0 0
#define TRU1 1
#define NIL NULL
#define MAX(A,B) ((A) < (B) ? (B) : (A))
#define MIN(A,B) ((A) < (B) ? (A) : (B))

enum a_actions{
   a_ACT_USAGE,
   a_ACT_TOC = 1u<<0,
   a_ACT_MCN = 1u<<1,
   a_ACT_ISRC = 1u<<2,
   a_ACT_CDTEXT = 1u<<3,
   a_ACT_READ = 1u<<4,

   a_ACT_DEFAULT = a_ACT_TOC,
   a_ACT_QUERY_MASK = a_ACT_TOC | a_ACT_MCN | a_ACT_ISRC | a_ACT_CDTEXT,
   a_ACT_MASK = (a_ACT_QUERY_MASK | a_ACT_READ)
};

enum a_act_rawbuf{
   a_ACT_RAWBUF_TOC,
   a_ACT_RAWBUF_MCN,
   a_ACT_RAWBUF_ISRC,
   a_ACT_RAWBUF_CDTEXT,
   a__ACT_RAWBUF_MAX
};

/* Extending a_actions, all in 8-bit! */
enum a_flags{
   a_F_NO_TOC_DUMP = 1u<<5, /* TOC only queried internally for info */
   a_F_VERBOSE = 1u<<6,
   a_F_NO_CHECKS = 1u<<7
};

/* MMC-3: sizes, limits etc. */
enum a_mmc{
   a_MMC_TRACKS_MAX = 99,
   a_MMC_TRACK_FRAMES_MIN = 300,
   a_MMC_TRACK_LEADOUT = 0xAA,

   /* 4 bytes/Sample * 44100 Samples/second = 176400 bytes/second.
    * 176400 bytes/second / 2352 bytes/frame = 75 frames/second */
   a_MMC_FRAME_SIZE = 2352,
   a_MMC_FRAMES_PER_SEC = 75,
   /* Table 333 - LBA to MSF translation */
   a_MMC_MSF_OFFSET = 2 * a_MMC_FRAMES_PER_SEC,
   a_MMC_MSF_LARGE_M = 90,
   a_MMC_MSF_LARGE_OFFSET = -450150
#define a_MMC_MSF_TO_LBA(M,S,F) \
      ((int)(((u32)(M) * 60  + (S)) * a_MMC_FRAMES_PER_SEC  + (u32)(F)) - \
         ((u32)(M) < a_MMC_MSF_LARGE_M ? a_MMC_MSF_OFFSET \
            : a_MMC_MSF_LARGE_OFFSET))
};

/* MMC-3: Sub-channel Control Field: audio track flags */
enum a_mmc_tflags{
   a_MMC_TF_NONE,
   a_MMC_TF_PREEMPHASIS = 0x01,
   a_MMC_TF_COPY_PERMIT = 0x02,
   a_MMC_TF_DATA_TRACK = 0x04, /* (changes meaning of other bits!) */
   a_MMC_TF_CHANNELS_4 = 0x08
};

enum a_mmc_cmdx{
   a_MMC_CMD_x_BIT_TIME_MSF = 0x2, /* Bit 1 of byte 1 (many) */

   a_MMC_CMD_x42_READ_SUBCHANNEL = 0x42,
      a_MMC_CMD_x42_SUBQ = 0x40,
      a_MMC_CMD_x42_PARAM_MCN = 0x02,
         a_MMC_CMD_x42_ISRC_RESP_BIT_MCVAL = 0x80, /* Bit 7/byte 0: is valid */
      a_MMC_CMD_x42_PARAM_ISRC = 0x03,
         a_MMC_CMD_x42_ISRC_RESP_BIT_TCVAL = 0x80, /* Bit 7/byte 0: is valid */

   a_MMC_CMD_x43_READ_TOC_PMA_ATIP = 0x43,
      a_MMC_CMD_x43_FORMAT_FULLTOC = 0x02,
#define a_MMC_CMD_x43_FULLTOC_RESP_CONTROL_TO_TFLAGS(X) ((X) & 0x0F)
#define a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_FIRST_TRACK(X) ((X) == 0xA0)
#define a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_LAST_TRACK(X) ((X) == 0xA1)
#define a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_LEAD_OUT(X) ((X) == 0xA2)
#define a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_TRACK(X) \
         ((X) >= 0x01 && (X) <= 0x63)

      a_MMC_CMD_x43_FORMAT_CDTEXT = 0x05
};

enum a_cdtext{
   a_CDTEXT_PACK_LEN = 18,
   a_CDTEXT_BLOCK_PACKS_MAX = 255, /* Including! */
   a_CDTEXT_BLOCKS_MAX = 8,
   a_CDTEXT_LEN_MAX = a_CDTEXT_BLOCKS_MAX * a_CDTEXT_BLOCK_PACKS_MAX *
         a_CDTEXT_PACK_LEN,

   /* Can be joined: "recommended to be less than 160 bytes" */
   a_CDTEXT_PACK_LEN_TEXTDAT = 12,
   a_CDTEXT_PACK_TYPES = 16,

   a_CDTEXT_PACK_T_TITLE = 0x80,
   a_CDTEXT_PACK_T_ARTIST, /* PERFORMER */
   a_CDTEXT_PACK_T_SONGWRITER,
   a_CDTEXT_PACK_T_COMPOSER,
   /* These we ignore */
   a_CDTEXT_PACK_T_ARRANGER,
   a_CDTEXT_PACK_T_MESSAGES,
   a_CDTEXT_PACK_T_DISCID,
   a_CDTEXT_PACK_T_GENRE,
   a_CDTEXT_PACK_T_TOC,
   a_CDTEXT_PACK_T_TOC2,
   /* Universal Product Code UPC aka European Article Number EAN for track[0],
    * International Standard Record Code for rest */
   a_CDTEXT_PACK_T_UPC_EAN_ISRC = 0x8E,
   a_CDTEXT_PACK_T_BLOCKINFO = 0x8F,
#define a_CDTEXT_PACK_T2IDX(T) \
   a_CDTEXT_PACK_T2IDX_RAW(su_CONCAT(a_CDTEXT_PACK_T_, T))
#define a_CDTEXT_PACK_T2IDX_RAW(T) ((T) - 0x80)
#define a_CDTEXT_PACK_IDX2T(T) ((T) + 0x80)

   a_CDTEXT_CHARSET_LATIN1 = 0x00,
   a_CDTEXT_CHARSET_ASCII = 0x01,

   a_CDTEXT_LANG_NONE = 0x00,
   a_CDTEXT_LANG_ENGLISH = 0x09
};

struct a_mmc_cmd{
   u8 cmd[10];
};

struct a_mmc_cmd_x42_resp_data_head{
   u8 reserved;
   u8 audio_status;
   u8 data_length_1;
   u8 data_length_2;
};

struct a_mmc_cmd_x42_mcn_resp{
   u8 x_mcval;
   u8 n1_13_nul[13 +1]; /* zero terminated */
   /* u8 aframe; optional? */
};

struct a_mmc_cmd_x42_isrc_resp{
   u8 x_tcval;
   /* (2x country code, 3x owner code, 2x year of recording, 5x serial no */
   u8 l1_12_nul[12 +1]; /* zero terminated */
   u8 aframe;
   /* u8 reserved; optional? */
};

struct a_mmc_cmd_x43_full_toc_resp{
   u8 session;
   u8 adr_control; /* (Control in bits 0..3: a_mmc_tflags) */
   u8 tno;
   u8 point;
   u8 min;
   u8 sec;
   u8 frame;
   u8 zero; /* (xxx for cdrom) */
   u8 pmin;
   u8 psec;
   u8 pframe;
};

struct a_mmc_cmd_x43_cdtext_resp{
   u8 type;
   u8 xtension_tno;
   u8 seq;
   u8 dbchars_blocknum_charpos;
   u8 text[12];
   /* xxx CRC not tested (but "not mandatory for supporting CD-TEXT data") */
   u8 crc[2];
};

struct a_track{
   u8 t_tflags;
   u8 t_minute; /* MSF style */
   u8 t_second;
   u8 t_frame;
   int t_lba; /* Logical block address */
   char *t_cdtext_dat[a_CDTEXT_PACK_TYPES];
};

struct a_rawbuf{
   u8 *rb_buf;
   uz rb_buflen;
};

struct a_data{
   char const *d_dev;
   int d_fd;
   u8 d_flags; /* a_actions | a_flags */
   u8 d_trackno_start;
   u8 d_trackno_end;
   u8 d_trackno_audio;
   /* Indices of only audio tracks */
   u8 d_track_audio[Z_ALIGN(a_MMC_TRACKS_MAX + 1)]; /* [0] = leadout */
   /* ISRC may exist as duplicates in CD-TEXT.  As this is short living, do not
    * care and try to merge: when dumping CD-TEXT, we fill in missing pieces as
    * appropriate (but not vice versa) */
   char d_mcn[Z_ALIGN( FIELD_SIZEOF(struct a_mmc_cmd_x42_mcn_resp,n1_13_nul))];
   char d_isrc[a_MMC_TRACKS_MAX + 1][Z_ALIGN(
         FIELD_SIZEOF(struct a_mmc_cmd_x42_isrc_resp,l1_12_nul))
         ]; /* [0] = CD */
   /* Note: CD-TEXT data is indexed according to CD-TEXT track information! */
   struct a_track d_track_data[a_MMC_TRACKS_MAX + 1]; /* [0] = leadout/CD */
   char *d_cdtext_text_data; /* Just a huge storage for that stuff */
   struct a_rawbuf d_rawbufs[a__ACT_RAWBUF_MAX];
};

/**/
static void *a_alloc(size_t len);
static int a_open(struct a_data *dp);
static void a_cleanup(struct a_data *dp);

/**/
static int a_act(struct a_data *dp);
static int a_read(struct a_data *dp, u8 tno);

/**/
static int a_parse_toc(struct a_data *dp, u8 *buf, u16 len);
static int a_parse_mcn(struct a_data *dp, u8 *buf, u16 len);
static int a_parse_isrc(struct a_data *dp, u8 tno, u8 *buf, u16 len);
static int a_parse_cdtext(struct a_data *dp, u8 *buf, u16 len);

/**/
static void a_dump_hex(void *vp, u32 len);
static int a_dump_toc(struct a_data *dp);
static int a_dump_mcn(struct a_data *dp);
static int a_dump_isrc(struct a_data *dp);
static int a_dump_cdtext(struct a_data *dp);

/* OS */
static int a_os_mmc(struct a_data *dp, struct a_mmc_cmd *mmccp,
      struct a_rawbuf *rbp);
static int a_os_read(struct a_data *dp, int lbas, int lbae);

/* MAIN {{{ */
int
main(int argc, char **argv){
   struct a_data d;
   char *ep;
   long int li;
   int rv;
   u8 act;

   memset(&d, 0, sizeof d);

   act = a_ACT_USAGE;
   rv = EX_USAGE;
   UNINIT(li, 0);

   /* (Very primitive arg parser) */
   for(; argc > 1; --argc){
      ++argv;

      if(!strcmp(*argv, "-n") || !strcmp(*argv, "--no-checks"))
         act |= a_F_NO_CHECKS;
      else if(!strcmp(*argv, "-v") || !strcmp(*argv, "--verbose"))
         act |= a_F_VERBOSE;
      else if(!strcmp(*argv, "-d") || !strcmp(*argv, "--dev")){
         if(--argc == 1)
            goto jusage;
         d.d_dev = *++argv;
      }else if(!strcmp(*argv, "-h") || !strcmp(*argv, "--help")){
         rv = EX_OK;
         goto jusage;
      }else if(!strcmp(*argv, "-t") || !strcmp(*argv, "--toc"))
         act |= a_ACT_TOC;
      else if(!strcmp(*argv, "-m") || !strcmp(*argv, "--mcn"))
         act |= a_ACT_MCN;
      else if(!strcmp(*argv, "-i") || !strcmp(*argv, "--isrc"))
         act |= a_ACT_ISRC | a_F_NO_TOC_DUMP;
      else if(!strcmp(*argv, "-x") || !strcmp(*argv, "--cdtext"))
         act |= a_ACT_CDTEXT | a_F_NO_TOC_DUMP;
      else if(!strcmp(*argv, "-a") || !strcmp(*argv, "--all")){
         act |= a_ACT_QUERY_MASK;
      }else if(!strcmp(*argv, "-r") || !strcmp(*argv, "--read")){
         act &= ~a_ACT_MASK;
         act |= a_ACT_TOC | a_ACT_READ;
         if(--argc == 1)
            goto jusage;

         errno = 0;
         li = strtol(*++argv, &ep, 0);
         if(li < 1 || li > a_MMC_TRACKS_MAX || *ep != '\0'){
            fprintf(stderr, "! Invalid track number: %s\n", *argv);
            goto jusage;
         }
      }else{
         fprintf(stderr, "! Unknown argument: %s\n", *argv);
         goto jusage;
      }
   }

   /* Polish flags */
   if((act & a_ACT_MASK) == a_ACT_USAGE)
      act |= a_ACT_TOC;
   else if(act & a_ACT_TOC)
      act &= ~a_F_NO_TOC_DUMP;
   else if(act & a_F_NO_TOC_DUMP)
      act |= a_ACT_TOC;
   d.d_flags = act;

   /* */
   if((rv = a_open(&d)) != EX_OK)
      goto jleave;

   if((rv = a_act(&d)) != EX_OK)
      ;
   else if(d.d_flags & a_ACT_READ)
      rv = a_read(&d, (u8)li);
   else{
      if((d.d_flags & (a_ACT_TOC | a_F_NO_TOC_DUMP)) == a_ACT_TOC)
         a_dump_toc(&d);
      if(d.d_flags & a_ACT_MCN)
         a_dump_mcn(&d);
      if(d.d_flags & a_ACT_ISRC)
         a_dump_isrc(&d);
      if(d.d_flags & a_ACT_CDTEXT)
         a_dump_cdtext(&d);
   }

   a_cleanup(&d);

jleave:
   return rv;

jusage:
   puts(
      "s-cdda (" a_VERSION "): accessing audio CDs (via SCSI MMC-3 aware "
         "cdrom/drivers)\n"
      a_COPYRIGHT
      "Synopsis:\n"
      "  s-cdda -h|--help  this help\n"
      "  s-cdda [-nv] [-d|--dev DEV] [-t|--toc]\n"
      "     Dump the table of (audio) contents\n"
      "  s-cdda [-nv] [-d|--dev DEV] -m|--mcn\n"
      "     Dump Media-Catalog-Number/European-Article-Number "
         "if available/supported\n"
      "  s-cdda [-nv] [-d|--dev DEV] -i|--isrc\n"
      "     Dump International Standard Recording Code (ISRC), "
         "if available/supported\n"
      "  s-cdda [-nv] [-d|--dev DEV] -x|--cd-text\n"
      "     Dump (subset of) CD-TEXT information, if available/supported\n"
      "  s-cdda [-nv] [-d|--dev DEV] -a|--all\n"
      "     All the queries from above\n"
      "  s-cdda [-nv] [-d|--dev DEV] -r|--read NUM\n"
      "     Dump audio of track NUMber to (non-terminal) standard output\n"
      "\n"
      "-d|--dev DEV    Use CD-ROM DEVice; else $CDROM, else " a_CDROM "\n"
      "-v|--verbose    Be more verbose (on standard error)\n"
      "-n|--no-checks  No sanity checks on CD data (\"pampers over errors\")\n"
      "\n"
      "Remarks: with multiple queries errors are ignored but for TOC.\n"
      "-m and -i subject to HW quality: retry on error!  "
         "Exit states from sysexits.h"
      "\n! no option joining (\"-vt\"); untested: mixed mode, multisession"
   );
   goto jleave;
}
/* }}} */

/* UTILS {{{ */
static void *
a_alloc(size_t len){
   void *rv;

   if((rv = malloc(len)) == NIL){
      fprintf(stderr, "! Out of memory\n");
      exit(1);
   }

   return rv;
}

static int
a_open(struct a_data *dp){
   int rv;
   char const *cp;

   if((cp = dp->d_dev) == NIL && (cp = getenv("CDROM")) == NIL)
      cp = a_CDROM;

   if((dp->d_fd = open(dp->d_dev = cp, O_RDONLY | O_NONBLOCK)) == -1){
      fprintf(stderr, "! Cannot open %s: %s\n", cp, strerror(errno));
      rv = EX_OSFILE;
      goto jleave;
   }

   rv = EX_OK;
jleave:
   return rv;
}

static void
a_cleanup(struct a_data *dp){
   uz i;
   char *cp;

   if(dp->d_dev != NIL && dp->d_fd != -1)
      close(dp->d_fd);

   if((cp = dp->d_cdtext_text_data) != NIL)
      free(cp);

   for(i = 0; i < NELEM(dp->d_rawbufs); ++i)
      if((cp = (char*)dp->d_rawbufs[i].rb_buf) != NIL)
         free(cp);
}
/* }}} */

/* ACTING {{{ */
static int
a_act(struct a_data *dp){
   struct a_mmc_cmd mmcc;
   u16 len;
   struct a_rawbuf *rbp;
   u8 act, relax, myact, isrcno;
   int rv;

   rv = EX_OK;
   act = (dp->d_flags & a_ACT_QUERY_MASK);
   if(!(relax = (dp->d_flags & a_F_NO_CHECKS))){
      myact = act & (a_ACT_QUERY_MASK & ~a_ACT_TOC);
      for(len = 1u << 0; myact != 0; len <<= 1)
         if(myact & len){
            myact ^= len;
            if(relax++)
               break;
         }
      relax = (relax > 1);
   }

   for(isrcno = 0; act != 0;){
      /* len is not counted in returned length: hard-coded below */
      struct a_mmc_resp_head {u16 len; u8 rsrv1; u8 rsrv2;};

      memset(&mmcc, 0, sizeof mmcc);

      if(act & (myact = a_ACT_TOC)){
         rbp = &dp->d_rawbufs[a_ACT_RAWBUF_TOC];
         rbp->rb_buflen = Z_ALIGN(sizeof(struct a_mmc_resp_head) +
               (sizeof(struct a_mmc_cmd_x43_full_toc_resp) *
                  a_MMC_TRACKS_MAX));
         mmcc.cmd[0] = a_MMC_CMD_x43_READ_TOC_PMA_ATIP;
         mmcc.cmd[1] = a_MMC_CMD_x_BIT_TIME_MSF;
         mmcc.cmd[2] = a_MMC_CMD_x43_FORMAT_FULLTOC;
      }else if(act & (myact = a_ACT_MCN)){
         rbp = &dp->d_rawbufs[a_ACT_RAWBUF_MCN];
         rbp->rb_buflen = Z_ALIGN(sizeof(struct a_mmc_resp_head) +
               sizeof(struct a_mmc_cmd_x42_resp_data_head) +
               sizeof(struct a_mmc_cmd_x42_mcn_resp));
         mmcc.cmd[0] = a_MMC_CMD_x42_READ_SUBCHANNEL;
         mmcc.cmd[1] = a_MMC_CMD_x_BIT_TIME_MSF; /* (Ignored) */
         mmcc.cmd[2] = a_MMC_CMD_x42_SUBQ;
         mmcc.cmd[3] = a_MMC_CMD_x42_PARAM_MCN;
      }else if(act & (myact = a_ACT_ISRC)){
         rbp = &dp->d_rawbufs[a_ACT_RAWBUF_ISRC];
         rbp->rb_buflen = Z_ALIGN(sizeof(struct a_mmc_resp_head) +
               sizeof(struct a_mmc_cmd_x42_resp_data_head) +
               sizeof(struct a_mmc_cmd_x42_isrc_resp));
         mmcc.cmd[0] = a_MMC_CMD_x42_READ_SUBCHANNEL;
         mmcc.cmd[1] = a_MMC_CMD_x_BIT_TIME_MSF; /* (Ignored) */
         mmcc.cmd[2] = a_MMC_CMD_x42_SUBQ;
         mmcc.cmd[3] = a_MMC_CMD_x42_PARAM_ISRC;
         if(isrcno == 0)
            isrcno = 1;
         mmcc.cmd[6] = dp->d_track_audio[isrcno];
      }else if(act & (myact = a_ACT_CDTEXT)){
         rbp = &dp->d_rawbufs[a_ACT_RAWBUF_CDTEXT];
         rbp->rb_buflen = Z_ALIGN(sizeof(struct a_mmc_resp_head) +
               a_CDTEXT_LEN_MAX);
         mmcc.cmd[0] = a_MMC_CMD_x43_READ_TOC_PMA_ATIP;
         mmcc.cmd[1] = a_MMC_CMD_x_BIT_TIME_MSF; /* (Ignored) */
         mmcc.cmd[2] = a_MMC_CMD_x43_FORMAT_CDTEXT;
      }else
         exit(42);

      rbp->rb_buf = a_alloc(rbp->rb_buflen);
      mmcc.cmd[7] = ((u16)rbp->rb_buflen >> 8) & 0xFF;
      mmcc.cmd[8] = (u16)rbp->rb_buflen & 0xFF;

      /* We might want to ignore non-crucial errors */
      if((rv = a_os_mmc(dp, &mmcc, rbp)) != EX_OK){
         if(!relax || myact == a_ACT_TOC)
            break;
         dp->d_flags &= ~myact;
         rv = EX_OK;
         goto jtick;
      }

      /* Response: length field not included in overall length;
       * subtract the other two bytes of the shared response header */
      len = rbp->rb_buf[0];
      len <<= 8;
      len |= rbp->rb_buf[1];
      if(len <= 2 * sizeof(u8) ||
            (len -= 2 * sizeof(u8)) + sizeof(struct a_mmc_resp_head)
               > rbp->rb_buflen){
         fprintf(stderr,
            "! SCSI MMC-3 response of unexpected size %u (+%lu) bytes:\n",
            len, (ul)sizeof(struct a_mmc_resp_head));
         a_dump_hex(rbp->rb_buf, len + sizeof(struct a_mmc_resp_head));

         if(!relax || myact == a_ACT_TOC){
            rv = EX_DATAERR;
            break;
         }
         goto jtick;
      }

      if(dp->d_flags & a_F_VERBOSE){
         fprintf(stderr, "* SCSI MMC-3 response with %u (+%lu) bytes:\n",
            len, (ul)sizeof(struct a_mmc_resp_head));
         a_dump_hex(rbp->rb_buf, len + sizeof(struct a_mmc_resp_head));
      }

      switch(myact){
      case a_ACT_TOC:
         rv = a_parse_toc(dp, &rbp->rb_buf[4], len);
         break;
      case a_ACT_MCN:
         rv = a_parse_mcn(dp, &rbp->rb_buf[4], len);
         break;
      case a_ACT_ISRC:
         rv = a_parse_isrc(dp, dp->d_track_audio[isrcno],
               &rbp->rb_buf[4], len);
         if(rv == EX_OK && isrcno++ < dp->d_trackno_audio)
            myact = 0;
         else
            isrcno = 0;
         break;
      case a_ACT_CDTEXT:
         rv = a_parse_cdtext(dp, &rbp->rb_buf[4], len);
         break;
      default:
         break;
      }

      if(rv != EX_OK){
         if(!relax || myact == a_ACT_TOC)
            break;
         dp->d_flags ^= myact;
      }
      rv = EX_OK;

jtick:
      act &= ~myact;
   }

   return rv;
}

static int
a_read(struct a_data *dp, u8 tno){
   int rv, lbas, lbae, len;

   if(isatty(STDOUT_FILENO)){
      fprintf(stderr, "! Cannot dump to a terminal\n");
      rv = EX_IOERR;
      goto jleave;
   }

   if(tno > dp->d_trackno_audio){
      fprintf(stderr, "! Invalid track number: %u (of %u)\n",
         tno, dp->d_trackno_audio);
      rv = EX_DATAERR;
      goto jleave;
   }

   lbas = dp->d_track_data[tno].t_lba;
   lbae = dp->d_track_data[(tno == dp->d_trackno_end) ? 0 : ++tno].t_lba;
   rv = lbae - lbas;
   len = rv * a_MMC_FRAME_SIZE;

   if(dp->d_flags & a_F_VERBOSE)
      fprintf(stderr, "* Reading track %u, LBA start=%d end=%d "
            "(%d frames, %d bytes)\n",
         tno, lbas, lbae, rv, len);

   if((rv = a_os_read(dp, lbas, lbae)) == EX_OK)
      fprintf(stderr, "Read track %u, %d bytes)\n", tno, len);

jleave:
   return rv;
}
/* }}} */

/* PARSERS {{{ */
static int
a_parse_toc(struct a_data *dp, u8 *buf, u16 len){
   boole had_leadout;
   u8 tmin, tmax, taudio;
   struct a_mmc_cmd_x43_full_toc_resp *ftrp;
   int rv;

   if(len % sizeof(*ftrp)){
      fprintf(stderr, "! Invalid buffer size\n");
      rv = EX_DATAERR;
      goto jleave;
   }
   len /= sizeof(*ftrp);

   ftrp = (struct a_mmc_cmd_x43_full_toc_resp*)buf;
   tmin = 0xFF;
   tmax = taudio = 0;
   had_leadout = FAL0;

   for(; len > 0; ++ftrp, --len){
      struct a_track *tp;

      if(!a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_TRACK(ftrp->point)){
         char const *msg;

         if(a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_FIRST_TRACK(ftrp->point)){
            tmin = MIN(tmin, ftrp->pmin);
            msg = "first track number";
         }else if(a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_LAST_TRACK(ftrp->point)){
            tmax = MAX(tmax, ftrp->pmin);
            msg = "last track number";
         }else if(a_MMC_CMD_x43_FULLTOC_RESP_POINT_IS_LEAD_OUT(ftrp->point)){
            ftrp->point = 0;
            had_leadout = TRU1;
            goto jset;
         }else
            msg = "ignored";

         if(dp->d_flags & a_F_VERBOSE)
            fprintf(stderr, "* TOC packet 0x%02X (%s)\n", ftrp->point, msg);
         continue;
      }

      if(ftrp->point > a_MMC_TRACKS_MAX){
         fprintf(stderr, "! TOC data specifies invalid track number\n");
         if(dp->d_flags & a_F_NO_CHECKS)
            continue;
         rv = EX_DATAERR;
         goto jleave;
      }

jset:
      tp = &dp->d_track_data[ftrp->point];
      tp->t_tflags = a_MMC_CMD_x43_FULLTOC_RESP_CONTROL_TO_TFLAGS(
            ftrp->adr_control);
      tp->t_minute = ftrp->pmin;
      tp->t_second = ftrp->psec;
      tp->t_frame = ftrp->pframe;
      tp->t_lba = a_MMC_MSF_TO_LBA(tp->t_minute, tp->t_second, tp->t_frame);

      if(ftrp->point != 0 && !(tp->t_tflags & a_MMC_TF_DATA_TRACK))
         dp->d_track_audio[++taudio] = ftrp->point;

      if(dp->d_flags & a_F_VERBOSE)
         fprintf(stderr,
            "* TOC Track=%02u m=%02u s=%02u f=%02u lba=%-6u audio=%d\n",
            ftrp->point, tp->t_minute, tp->t_second, tp->t_frame,
            tp->t_lba, !(tp->t_tflags & a_MMC_TF_DATA_TRACK));
   }

   if(dp->d_flags & a_F_VERBOSE)
      fprintf(stderr, "* Tracks: start=%02u end=%02u audio-tracks=%u\n",
         tmin, tmax, taudio);

   if(tmin > tmax || tmin < 1 || tmax > a_MMC_TRACKS_MAX){
      fprintf(stderr, "! Invalid table-of-contents (track start/end)\n");
      rv = EX_DATAERR;
      if(!(dp->d_flags & a_F_NO_CHECKS))
         goto jleave;
   }

   if(taudio == 0){
      fprintf(stderr, "! No audio tracks found\n");
      rv = EX_NOINPUT;
   }else if(!had_leadout){
      fprintf(stderr, "! No lead-out session data reported\n");
      rv = EX_DATAERR;
   }else{
      dp->d_trackno_start = tmin;
      dp->d_trackno_end = tmax;
      dp->d_trackno_audio = taudio;
      rv = EX_OK;
   }
jleave:
   return rv;
}

static int
a_parse_mcn(struct a_data *dp, u8 *buf, u16 len){
   int rv;
   struct a_mmc_cmd_x42_mcn_resp *mrp;

   /* C99 */{
      struct a_mmc_cmd_x42_resp_data_head *dhp;

      dhp = (struct a_mmc_cmd_x42_resp_data_head*)buf;
      buf += sizeof(*dhp);
      len -= sizeof(*dhp);
   }
   mrp = (struct a_mmc_cmd_x42_mcn_resp*)buf;

   if(len != sizeof(*mrp)){
      fprintf(stderr, "! Invalid size of MCN packet\n");
      rv = EX_DATAERR;
   }else if(mrp->x_mcval & a_MMC_CMD_x42_ISRC_RESP_BIT_MCVAL){
      memcpy(dp->d_mcn, mrp->n1_13_nul, sizeof(mrp->n1_13_nul));
      if(dp->d_flags & a_F_VERBOSE)
         fprintf(stderr, "* MCN: %s\n", dp->d_mcn);
      rv = EX_OK;
   }else{
      fprintf(stderr, "! No valid MediaCatalogNumber / EuropeanArticleNumber "
         "present\n");
      rv = EX_NOINPUT;
   }

   return rv;
}

static int
a_parse_isrc(struct a_data *dp, u8 tno, u8 *buf, u16 len){
   int rv;
   struct a_mmc_cmd_x42_isrc_resp *irp;

   /* C99 */{
      struct a_mmc_cmd_x42_resp_data_head *dhp;

      dhp = (struct a_mmc_cmd_x42_resp_data_head*)buf;
      buf += sizeof(*dhp);
      len -= sizeof(*dhp);
   }
   irp = (struct a_mmc_cmd_x42_isrc_resp*)buf;

   if(len != sizeof(*irp)){
      fprintf(stderr, "! Invalid size of ISRC packet\n");
      rv = EX_DATAERR;
   }else if(irp->x_tcval & a_MMC_CMD_x42_ISRC_RESP_BIT_TCVAL){
      char *cp;

      cp = dp->d_isrc[tno];
      if(*cp != '\0' && (dp->d_flags & a_F_VERBOSE))
         fprintf(stderr, "* ISRC track %lu: duplicate entry\n", (ul)tno);
      memcpy(cp, irp->l1_12_nul, sizeof(irp->l1_12_nul));
      if(dp->d_flags & a_F_VERBOSE)
         fprintf(stderr, "* ISRC track %u: %s\n", tno, cp);
      rv = EX_OK;
   }else{
      fprintf(stderr, "! No valid InternationalStandardRecordingCode for "
         "track %lu\n", (ul)tno);
      rv = EX_NOINPUT;
   }

   return rv;
}

static int
a_parse_cdtext(struct a_data *dp, u8 *buf, u16 len){ /* {{{ */
   struct a_cdtext_block_info{
      u8 bi_charcode;
      u8 bi_first_track;
      u8 bi_last_track;
      u8 bi_copyright;
      u8 bi_packs[a_CDTEXT_PACK_TYPES]; /* pack count for type */
      u8 bi_lastseq[a_CDTEXT_BLOCKS_MAX]; /* for block 0..BLOCKS_MAX-1 */
      u8 bi_langcode[a_CDTEXT_BLOCKS_MAX];
   };

   struct a_cdtext_block_info cdbi;
   char *tcp, *cp_for_tab_ind;
   u8 seq, block, j, tno;
   u16 i;
   char const *emsg, *cpcontig;
   struct a_mmc_cmd_x43_cdtext_resp *crp, *crpx;
   int rv;

   if(len > a_CDTEXT_LEN_MAX){
      /* Should not fit there, so what is that? Just bail */
      emsg = "data buffer too large";
      goto jedat;
   }

   /* xxx In fact we could very well test for >3*? */
   if(len < sizeof(*crp) || len % sizeof(*crp)){
      emsg = "invalid buffer length";
      goto jedat;
   }

   crp = (struct a_mmc_cmd_x43_cdtext_resp*)buf;

   /* Allocate buffers large enough to hold the maximum string length, and
    * a work pool for the packets (just do it like that) */
   len /= sizeof(*crp);
   dp->d_cdtext_text_data = tcp = a_alloc(len * (a_CDTEXT_PACK_LEN_TEXTDAT+1));

   /* Update the CD-TEXT packets to our needs */
   for(crpx = crp, i = len; i > 0; ++crpx, --i){
      crpx->type = a_CDTEXT_PACK_T2IDX_RAW(crpx->type);
      /* Use p_crc[0] for "has this packet been seen yet" state machine! */
      crpx->crc[0] = FAL0;
   }

   /* Text crosses packet boundaries (let me dream of simple [TYPE[LEN]DATA]
    * style blobs), use emsg as indication whether one is not satisfied yet */
   cpcontig = cp_for_tab_ind = NIL;
   for(seq = 0, block = 0xFF; len > 0; ++seq, ++crp, --len){
      /* When encountering a new block, scan forward for the three T_BLOCKINFO
       * packs which must be contained therein in order to detect character set
       * and language information */
      if(block != (j = (crp->dbchars_blocknum_charpos >> 4) & 0x07) ||
            seq != crp->seq){
         /* XXX We should do more sanity checks */
         if(cpcontig != NIL){
            if(!(dp->d_flags & a_F_NO_CHECKS))
               goto jetxtopen;
            cpcontig = NIL;
         }
         cp_for_tab_ind = NIL; /* XXX can TAB stuff cross blocks?? */

         if((block = j) >= a_CDTEXT_BLOCKS_MAX){
            emsg = "too many data blocks";
            fprintf(stderr, "! CD-TEXT: %s\n", emsg);
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
            if(!(dp->d_flags & a_F_NO_CHECKS))
               goto jedat;
            block = a_CDTEXT_BLOCKS_MAX;
         }

         seq = 0;
         memset(&cdbi, 0, sizeof cdbi);

         for(crpx = crp, i = 0; i < len; ++crpx, ++i){
            if(crpx->type != a_CDTEXT_PACK_T2IDX(BLOCKINFO))
               continue;
            switch(crpx->xtension_tno & 0x7F){
            case 0:
               cdbi.bi_charcode = crpx->text[0];
               cdbi.bi_first_track = crpx->text[1];
               cdbi.bi_last_track = crpx->text[2];
               cdbi.bi_copyright = crpx->text[3];
               memcpy(&cdbi.bi_packs[0], &crpx->text[4],
                  a_CDTEXT_PACK_TYPES / 2);
               break;
            case 1:
               memcpy(&cdbi.bi_packs[a_CDTEXT_PACK_TYPES / 2],
                  &crpx->text[0], a_CDTEXT_PACK_TYPES / 2);
               memcpy(&cdbi.bi_lastseq[0],
                  &crpx->text[a_CDTEXT_PACK_TYPES / 2],
                  a_CDTEXT_BLOCKS_MAX / 2);
               break;
            case 2:
               memcpy(&cdbi.bi_lastseq[a_CDTEXT_BLOCKS_MAX / 2],
                  &crpx->text[0], a_CDTEXT_BLOCKS_MAX / 2);
               memcpy(&cdbi.bi_langcode[0], &crpx->text[4],
                  a_CDTEXT_BLOCKS_MAX);
               break;
            }
         }

         /* XXX more sanity checks */
         if(cdbi.bi_packs[a_CDTEXT_PACK_TYPES - 1] != 3 &&
               !(dp->d_flags & a_F_NO_CHECKS)){
            emsg = "block without valid block information encountered";
            goto jedat;
         }

         if(dp->d_flags & a_F_VERBOSE){
            fprintf(stderr,
               "* CD-TEXT: INFO BLOCK %d: charcode=%u tracks=%u-%u "
                  "copyright=%u\n"
               "*   packs of: title=%u artist=%u songwriter=%u "
                  "composer=%u arranger=%u\n"
               "*             discid=%u genre=%u toc=%u toc2=%u upc/isrc=%u\n"
               "*   lastseq=%u/%u/%u/%u/ %u/%u/%u/%u\n"
               "*   langcode=0x%02X/0x%02X/0x%02X/0x%02X/ "
                  "0x%02X/0x%02X/0x%02X/0x%02X\n",
               block, cdbi.bi_charcode,
                  cdbi.bi_first_track, cdbi.bi_last_track, cdbi.bi_copyright,
               cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(TITLE)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(ARTIST)],
                cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(SONGWRITER)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(COMPOSER)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(ARRANGER)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(DISCID)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(GENRE)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(TOC)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(TOC2)],
                  cdbi.bi_packs[a_CDTEXT_PACK_T2IDX(UPC_EAN_ISRC)],
               cdbi.bi_lastseq[0], cdbi.bi_lastseq[1], cdbi.bi_lastseq[2],
                  cdbi.bi_lastseq[3], cdbi.bi_lastseq[4], cdbi.bi_lastseq[5],
                  cdbi.bi_lastseq[6], cdbi.bi_lastseq[7],
               cdbi.bi_langcode[0], cdbi.bi_langcode[1], cdbi.bi_langcode[2],
                  cdbi.bi_langcode[3], cdbi.bi_langcode[4],
                  cdbi.bi_langcode[5], cdbi.bi_langcode[6],
                  cdbi.bi_langcode[7]);
         }
      }

      switch(cdbi.bi_charcode){
      case a_CDTEXT_CHARSET_LATIN1:
      case a_CDTEXT_CHARSET_ASCII:
         break;
      default:
         /* XXX ignoring unsupported encoding */
         if(dp->d_flags & a_F_VERBOSE){
            fprintf(stderr,
               "* CD-TEXT: ignoring packet in block with unsupported "
                  "character encoding %u\n",
               cdbi.bi_charcode);
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
         }
         continue;
      }

      switch(cdbi.bi_langcode[block]){
      case a_CDTEXT_LANG_NONE:
      case a_CDTEXT_LANG_ENGLISH:
         break;
      default:
         /* XXX ignoring unsupported language */
         if(dp->d_flags & a_F_VERBOSE){
            fprintf(stderr,
               "* CD-TEXT: ignoring packet in block with unsupported "
                  "language code %u\n",
               cdbi.bi_charcode);
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
         }
         continue;
      }

      if(crp->dbchars_blocknum_charpos & (1u << 7)){
         /* xxx Now, that would be an error for ASCII/LATIN1? */
         if(dp->d_flags & a_F_VERBOSE){
            fprintf(stderr, "* CD-TEXT: ignoring packet with unsupported "
               "double byte characters\n");
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
         }
         continue;
      }

      if(crp->xtension_tno & (1u << 7)){
          if(dp->d_flags & a_F_VERBOSE){
            fprintf(stderr, "* CD-TEXT: ignoring packet which announces "
               "extensions\n");
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
         }
         continue;
      }

      if(dp->d_flags & a_F_VERBOSE){
         fprintf(stderr, "* CD-TEXT: packet track=%u seq=%u type=0x%02X:\n",
            crp->xtension_tno & 0x7F, crp->seq,
            a_CDTEXT_PACK_IDX2T(crp->type));
         a_dump_hex(crp, a_CDTEXT_PACK_LEN);
      }

jredo_packet:
      tno = crp->xtension_tno & 0x7F;

      if(tno > a_MMC_TRACKS_MAX || tno > cdbi.bi_last_track){
         emsg = "invalid track number";
         fprintf(stderr, "! CD-TEXT: %s\n", emsg);
         a_dump_hex(crp, a_CDTEXT_PACK_LEN);
         if(!(dp->d_flags & a_F_NO_CHECKS))
            goto jedat;
         tno = cdbi.bi_last_track;
      }

      switch(crp->type){
      case a_CDTEXT_PACK_T2IDX(GENRE):
         if(cpcontig != NIL){
            emsg = "text unfinished, block boundary crossed";
            fprintf(stderr, "! CD-TEXT: %s\n", emsg);
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
            if(!(dp->d_flags & a_F_NO_CHECKS))
               goto jedat;
            cpcontig = NIL;
         }
         crp->text[0] = crp->text[1] = '\0'; /* make txt-parsable */
         /* FALLTHRU */
      case a_CDTEXT_PACK_T2IDX(TITLE):
      case a_CDTEXT_PACK_T2IDX(ARTIST):
      case a_CDTEXT_PACK_T2IDX(SONGWRITER):
      case a_CDTEXT_PACK_T2IDX(COMPOSER):
      case a_CDTEXT_PACK_T2IDX(ARRANGER):
      case a_CDTEXT_PACK_T2IDX(MESSAGES):
      case a_CDTEXT_PACK_T2IDX(UPC_EAN_ISRC):{
         struct a_track *tp;
         char **cpp, *cp;

         tp = &dp->d_track_data[tno];

         if((cp = *(cpp = &tp->t_cdtext_dat[crp->type])) == NIL)
            *cpp = cp = tcp;
         else{
            while(*cp != '\0')
               ++cp;
            if(cp != tcp){
               emsg = "text packet continuation out of sequence";
               fprintf(stderr, "! CD-TEXT: %s\n", emsg);
               a_dump_hex(crp, a_CDTEXT_PACK_LEN);
               if(!(dp->d_flags & a_F_NO_CHECKS))
                  goto jedat;
               *cpp = cp = tcp;
            }
         }

         /* We may have worked parts of this text already */
         i = 0;
         if(crp->crc[0]){
            while(crp->text[i] == '\0'){
               if(++i >= a_CDTEXT_PACK_LEN_TEXTDAT){
                  emsg = "text packet without text";
                  fprintf(stderr, "! CD-TEXT: %s\n", emsg);
                  a_dump_hex(crp, a_CDTEXT_PACK_LEN);
                  if(!(dp->d_flags & a_F_NO_CHECKS))
                     goto jedat;
                  break;
               }
            }
         }

         while((*cp++ = (char)crp->text[i++]) != '\0' &&
               i < FIELD_SIZEOF(struct a_mmc_cmd_x43_cdtext_resp, text))
            ;
         if(cp[-1] != '\0'){
            *cp = '\0'; /* (For sanity checks around) */
            cpcontig = cp;
         }else{
            cpcontig = NIL;
            /* The "Tab indicator" is used for consecutive equal strings; it
             * indicates that the last completed string shall be used */
            if(i == 2 && cp[-2] == '\x09'){
               if(cp_for_tab_ind == NIL){
                  emsg = "invalid \"Tab indicator\" to repeat former text";
                  fprintf(stderr, "! CD-TEXT: %s\n", emsg);
                  a_dump_hex(crp, a_CDTEXT_PACK_LEN);
                  if(!(dp->d_flags & a_F_NO_CHECKS))
                     goto jedat;
                  cp[-2] = '\0';
               }else
                  *cpp = cp_for_tab_ind;
            }else
               cp_for_tab_ind = *cpp;
         }
         tcp = cp;

         /* The payload can contain text for multiple tracks, and zero-filling
          * seems to be used otherwise */
         if(i < a_CDTEXT_PACK_LEN_TEXTDAT && crp->text[i] != '\0'){
            memset(&crp->text[0], 0, i);
            crp->crc[0] = TRU1;
            crp->xtension_tno = ++tno;
            goto jredo_packet;
         }
         }break;

      case a_CDTEXT_PACK_T2IDX(DISCID): /* xxx verify */
      default:
         if(dp->d_flags & a_F_VERBOSE){
            fprintf(stderr, "* CD-TEXT: ignoring packet of type 0x%02X\n",
               a_CDTEXT_PACK_IDX2T(crp->type));
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
         }
         /* FALLTHRU */
      case a_CDTEXT_PACK_T2IDX(BLOCKINFO):
         /* These were handled above already */
         if(cpcontig != NIL){
            emsg = "text unfinished, block boundary crossed";
            fprintf(stderr, "! CD-TEXT: %s\n", emsg);
            a_dump_hex(crp, a_CDTEXT_PACK_LEN);
            if(!(dp->d_flags & a_F_NO_CHECKS))
               goto jedat;
            cpcontig = NIL;
         }
         break;
      }
   }
   if(cpcontig != NIL && !(dp->d_flags & a_F_NO_CHECKS))
      goto jetxtopen;

   rv = EX_OK;
jleave:
   return rv;

jetxtopen:
   emsg = "text unfinished, block boundary crossed";
jedat:
   fprintf(stderr, "! CD-TEXT: %s\n", emsg);
   rv = EX_DATAERR;
   goto jleave;
} /* }}} */
/* }}} */

/* DUMPERS {{{ */
static void
a_dump_hex(void *vp, u32 len){
   u32 i, j;
   u8 *buf;

   buf = vp;

   for(j = i = 0; i < len; ++i){
      u8 b;

      if(j == 0){
         fputs("  |", stderr);
         j = 3;
      }
      if((b = buf[i]) >= 0x20 && b < 0x7F){ /* XXX ASCII magic */
         fputc(b, stderr);
         ++j;
      }else{
         fprintf(stderr, "\\x%02X", b);
         j += 4;
      }
      if(j >= 72){
         fputs("|\n", stderr);
         j = 0;
      }
   }
   if(j > 0)
      fputs("|\n", stderr);
}

static int
a_dump_toc(struct a_data *dp){
   struct a_track *tp;
   u8 i;

   for(i = 0; ++i <= dp->d_trackno_audio;){
      tp = &dp->d_track_data[dp->d_track_audio[i]];
      printf("track=%-2u t%u_msf=%02u:%02u.%02u t%u_lba=%-6d "
            "t%u_channels=%u t%u_preemphasis=%u t%u_copy=%u\n",
         i, i, tp->t_minute, tp->t_second, tp->t_frame,
         i, tp->t_lba,
         i, (tp->t_tflags & a_MMC_TF_CHANNELS_4 ? 4 : 2),
         i, (tp->t_tflags & a_MMC_TF_PREEMPHASIS),
         i, (tp->t_tflags & a_MMC_TF_COPY_PERMIT));
   }

   tp = &dp->d_track_data[dp->d_track_audio[0]];
   printf("track=0  t0_msf=%02u:%02u.%02u t0_lba=%-6d track_count=%u\n",
      tp->t_minute, tp->t_second, tp->t_frame, tp->t_lba, dp->d_trackno_audio);

   return ferror(stdout) ? EX_IOERR : EX_OK;
}

static int
a_dump_mcn(struct a_data *dp){
   printf("mcn=%s\n", dp->d_mcn);

   return ferror(stdout) ? EX_IOERR : EX_OK;
}

static int
a_dump_isrc(struct a_data *dp){
   char *cp;
   u8 i;
   int rv;

   rv = EX_OK;

   for(i = 0; ++i <= dp->d_trackno_audio;)
      if(*(cp = dp->d_isrc[dp->d_track_audio[i]]) != '\0' &&
            printf("t%u_isrc=%s\n", i, cp) < 0){
         rv = EX_IOERR;
         break;
      }

   return rv;
}

static int
a_dump_cdtext(struct a_data *dp){
   /* Dump as shell comment .. */
   boole any;
   char *cp;
   struct a_track *tp;
   u8 i, j;

   tp = &dp->d_track_data[0];

   any = FAL0;
   if(*(cp = dp->d_mcn) != '\0'){
      any = TRU1;
      printf("#[CDDB]\n#MCN = %s\n", cp);
   }
   if((cp = tp->t_cdtext_dat[a_CDTEXT_PACK_T2IDX(UPC_EAN_ISRC)]) != NIL){
      if(!any)
         puts("#[CDDB]");
      any = TRU1;
      printf("#UPC_EAN = %s\n", cp);
   }

   puts("#[ALBUM]");
   printf("#TRACKCOUNT = %u\n", dp->d_trackno_audio);
   if((cp = tp->t_cdtext_dat[a_CDTEXT_PACK_T2IDX(TITLE)]) != NIL)
      printf("#TITLE = %s\n", cp);

   any = FAL0;
   if((cp = tp->t_cdtext_dat[a_CDTEXT_PACK_T2IDX(ARTIST)]) != NIL){
      any = TRU1;
      printf("#[CAST]\n#ARTIST = %s\n", cp);
   }
   if((cp = tp->t_cdtext_dat[a_CDTEXT_PACK_T2IDX(SONGWRITER)]) != NIL){
      if(!any)
         puts("#[CAST]");
      any = TRU1;
      printf("#SONGWRITER = %s\n", cp);
   }
   if((cp = tp->t_cdtext_dat[a_CDTEXT_PACK_T2IDX(COMPOSER)]) != NIL){
      if(!any)
         puts("#[CAST]");
      any = TRU1;
      printf("#COMPOSER = %s\n", cp);
   }

   /* Indexed in CD-TEXT order! */
   for(i = 1; i <= a_MMC_TRACKS_MAX; ++i){
      tp = &dp->d_track_data[i];
      for(any = FAL0, j = 0; j < a_CDTEXT_PACK_TYPES; ++j){
         if((cp = tp->t_cdtext_dat[j]) == NIL &&
               j == a_CDTEXT_PACK_T2IDX(UPC_EAN_ISRC) &&
               *(cp = dp->d_isrc[dp->d_track_audio[i]]) == '\0')
            cp = NIL;

         if(cp != NIL){
            char const *pre;

            if(!any){
               any = TRU1;
               printf("#[TRACK]\n#NUMBER = %u\n", dp->d_track_audio[i]);
            }

            if(j == a_CDTEXT_PACK_T2IDX(TITLE))
               pre = "TITLE";
            else if(j == a_CDTEXT_PACK_T2IDX(ARTIST))
               pre = "ARTIST";
            else if(j == a_CDTEXT_PACK_T2IDX(SONGWRITER))
               pre = "SONGWRITER";
            else if(j == a_CDTEXT_PACK_T2IDX(COMPOSER))
               pre = "COMPOSER";
            else if(j == a_CDTEXT_PACK_T2IDX(UPC_EAN_ISRC))
               pre = "ISRC";
            else
               continue;

            printf("#%s = %s\n", pre, cp);
         }
      }
   }

   return ferror(stdout) ? EX_IOERR : EX_OK;
}
/* }}} */

#if su_OS_LINUX /* {{{ */
static int
a_os_mmc(struct a_data *dp, struct a_mmc_cmd *mmccp, struct a_rawbuf *rbp){
   struct{
      struct cdrom_generic_command cgc;
      struct request_sense rs;
   } x;
   int rv;

   memset(&x, 0, sizeof x);

   memcpy(x.cgc.cmd, mmccp, sizeof *mmccp);
   x.cgc.buffer = rbp->rb_buf;
   x.cgc.buflen = (ui)rbp->rb_buflen;
   x.cgc.sense = &x.rs;
   x.cgc.data_direction = CGC_DATA_READ;
   x.cgc.quiet = ((dp->d_flags & a_F_VERBOSE) == 0);
   x.cgc.timeout = 20u * 1000; /* Arbitrary */

   if(ioctl(dp->d_fd, CDROM_SEND_PACKET, &x.cgc) != -1)
      rv = EX_OK;
   else{
      fprintf(stderr, "! ioctl CDROM_SEND_PACKET: %s\n", strerror(errno));
      rv = EX_IOERR;
   }

   return rv;
}

static int
a_os_read(struct a_data *dp, int lbas, int lbae){
   u8 buf[a_STACK_FRAMES_MAX * a_MMC_FRAME_SIZE];
   struct cdrom_read_audio cdra;
   int i;
   char const *emsg;

   while(lbas < lbae){
      cdra.addr.lba = lbas;
      cdra.addr_format = CDROM_LBA;
      i = lbae - lbas;
      if(i > a_STACK_FRAMES_MAX)
         i = a_STACK_FRAMES_MAX;
      cdra.nframes = i;
      cdra.buf = buf;

      if(dp->d_flags & a_F_VERBOSE)
         fprintf(stderr, "* reading %d frames at LBA %d\n", i, lbas);

      if(ioctl(dp->d_fd, CDROMREADAUDIO, &cdra) == -1){
         emsg = "ioctl CDROMREADAUDIO";
         goto jeno;
      }
      lbas += i;

      for(i *= a_MMC_FRAME_SIZE; i > 0;){
         ssize_t w;

         w = write(STDOUT_FILENO, cdra.buf, (size_t)i);
         if(w == -1){
            emsg = "Writing audio data to standard output";
            goto jeno;
         }
         cdra.buf += w;
         i -= w;
      }
   }

   i = EX_OK;
jleave:
   return i;

jeno:
   fprintf(stderr, "! %s: %s\n", emsg, strerror(errno));
   i = EX_IOERR;
   goto jleave;
}
#endif /* }}} su_OS_LINUX */

#if su_OS_FREEBSD /* {{{ */
#endif /* }}} su_OS_FREEBSD */

/* s-it-mode */
