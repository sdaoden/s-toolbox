/*@ s-dkim-sign(8) - [postfix-only] RFC 6376/[8301]/8463 DKIM sign-only milter.
 *@ - OpenSSL must be 1.1.0 or above.
 *@ - TODO --remove could support user free form header removal (all or nothing; not any a_AUTO_RMs).
 *@ - TODO Invalid messages (eg no From:) should not only be pass but also reject'- or quarantine'able.
 *@ - TODO DKIM-I i= DKIM value (optional additional --sign arg).
 *@ - TODO Make somehow addressable postfix's "(may be forged)":
 *@	s-dkim-sign: [15506][info]: start.gursama.com [185.28.39.97] (may be forged): no --client's match: "pass, ."
 *@ - TODO Would like to have "sender localhost && rcpt localhost && pass".
 *@ - TODO internationalized selectors are missing (a_key.k_sel).
 *@ - TODO server mode missing -- must be started by spawn(8); then no more postfix-only.
 *@ - We have some excessively spaced base64 buffers.
 *@ - xxx With multiple keys, cannot include elder generated D-S in newer ones.
 *@ - Assumes header "name" values do not end with whitespace (search @HVALWS).
 *@   (Header body values are trimmed.)
 */
#define a_VERSION "0.6.3"
#define a_CONTACT "Steffen Nurpmeso <steffen@sdaoden.eu>"
#define a_COPYRIGHT \
	VAL_NAME a__COPYRIGHT_X "\n" \
	"\tCopyright (c) 2024 - 2025 " a_CONTACT ".\n" \
	"\tSPDX-License-Identifier: ISC\n"
/*
 * Copyright (c) 2024 - 2025 Steffen Nurpmeso <steffen@sdaoden.eu>.
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
#define su_FILE s_dkim_sign

/* --sign max selectors (<> manual) */
#define a_SIGN_MAX_SELECTORS 5

/* Whether we remove a_rm_head_names[(a_RM_HEAD_USER_MAX..a_RM_HEAD_MAX) -1] *always* (but for "pass" actions)? */
#define a_AUTO_RM 1

/**/
#define a_OPENLOG_FLAGS (LOG_NDELAY)

/* xxx except for NYD almost unused here; DBGIF: su_STATE_GUT_MEM_TRACE (needs SANITIZER=y for test) */
#define a_DBGIF 0
# define a_DBG(X)
# define a_DBG2(X)
# define a_NYD_FILE "/tmp/" VAL_NAME ".dat"

/* -- >8 -- 8< -- */

#if VAL_NAME_IS_MYNAME
# define a__COPYRIGHT_X
#else
# define a__COPYRIGHT_X " (S-dkim-sign)"
#endif

/*
#define _POSIX_C_SOURCE 200809L
#define _ATFILE_SOURCE
*/
#ifndef _GNU_SOURCE
# define _GNU_SOURCE /* Always the same mess */
#endif
/* SunOS/Solaris (fdopen()) */
#ifndef __EXTENSIONS__
# define __EXTENSIONS__
#endif

/* 'Want to have the short memory macros */
#define su_MEM_BAG_SELF (membp)
#include <su/code.h>

#if su_OS_LINUX
# include <sys/syscall.h> /* __NR_close_range */
#endif

/* TODO all std or posix, nonono */
#include <sys/select.h>
#include <sys/socket.h>

#include <arpa/inet.h>
#include <netinet/in.h>

#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h> /* XXX fmtcodec, then all *printf -> unroll! */
#include <stdlib.h>
#include <syslog.h>
#include <unistd.h>

#ifdef su_NYD_ENABLE
# include <signal.h>
#endif

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/opensslv.h>
#include <openssl/pem.h>

#include <su/avopt.h>
#include <su/bits.h>
#include <su/boswap.h>
#include <su/cs.h>
#include <su/cs-dict.h>
#include <su/icodec.h>
#include <su/imf.h>
#include <su/mem.h>
#include <su/mem-bag.h>
#include <su/path.h>
#include <su/sort.h>
#include <su/time.h>

#ifdef su_NYD_ENABLE
/*# define NYDPROF_ENABLE*/
# define NYD_ENABLE
# define NYD_ENABLE
#endif
#include "su/code-in.h"

NSPC_USE(su)

/* We assume it initializes itself (maybe more) */
#if !defined OPENSSL_VERSION_NUMBER || OPENSSL_VERSION_NUMBER + 0 < 0x10100000L
# error This SSL library is not supported it seems.  OpenSSL >= 1.1.0 it must be.
#elif !defined LIBRESSL_VERSION_NUMBER && OPENSSL_VERSION_NUMBER + 0 >= 0x30000000L
# define a_MD_FETCH
# define a_PKEY_GET_SIZE(X) EVP_PKEY_get_size(X)
#else
# undef a_MD_FETCH
# define a_PKEY_GET_SIZE(X) EVP_PKEY_size(X)
#endif

/* milter-protocol.txt {{{ */
/* $Id: milter-protocol.txt,v 1.6 2004/08/04 16:27:50 tvierling Exp $
 * _______________________________________
 * THE SENDMAIL MILTER PROTOCOL, VERSION 2
 *
 * **
 *
 * The Sendmail and "libmilter" implementations of the protocol described
 * herein are:
 *
 *     Copyright (c) 1999-2002 Sendmail, Inc. and its suppliers.
 *     All rights reserved.
 *
 * This document is:
 *
 *     Copyright (c) 2002-2003, Todd Vierling <tv@pobox.com> <tv@duh.org>
 *     All rights reserved.
 *
 * Permission is granted to copy or reproduce this document in its entirety
 * in any medium without charge, provided that the copy or reproduction is
 * without modification and includes the above copyright notice(s).
 *
 * ________
 * OVERVIEW
 *
 * The date of this document is contained within the "Id" symbolic CVS/RCS
 * tag present at the top of this document.
 *
 * This document describes the Sendmail "milter" mail filtering and
 * MTA-level mail manipulation protocol, version 2, based on the publicly
 * available C-language source code to Sendmail, version 8.11.6.
 *
 * As of this writing, this protocol document is based on the
 * implementation of milter in Sendmail 8.11, but has been verified
 * compatible with Sendmail 8.12.  Some Sendmail 8.12 extensions,
 * determined by flags sent with the SMFIC_OPTNEG command, are not yet
 * described here.
 *
 * Technical terms describing mail transport are used throughout.  A reader
 * should have ample understanding of RFCs 821, 822, 2821, and their
 * successors, and (for Sendmail MTAs) a cursory understanding of Sendmail
 * configuration procedures.
 *
 * ______
 * LEGEND
 *
 * All integers are assumed to be in network (big-endian) byte order.
 * Data items are aligned to a byte boundary, and are not forced to any
 * larger alignment.
 *
 * This document makes use of a mnemonic representation of data structures
 * as transmitted over a communications endpoint to and from a milter
 * program.  A structure may be represented like the following:
 *
 * 'W'	SMFIC_HWORLD	Hello world packet
 * uint16	len		Length of string
 * char	str[len]	Text value
 *
 * This structure contains a single byte with the ASCII representation 'W',
 * a 16-bit network byte order integer, and a character array with the
 * length given by the "len" integer.  Character arrays described in this
 * fashion are an exact number of bytes, and are not assumed to be NUL
 * terminated.
 *
 * A special data type representation is used here to indicate strings and
 * arrays of strings using C-language semantics of NUL termination.
 *
 * char	str[]		String, NUL terminated
 * char	array[][]	Array of strings, NUL terminated
 *
 * Here, "str" is a NUL-terminated string, and subsequent data items are
 * assumed to be located immediately following the NUL byte.  "array" is a
 * stream of NUL-terminated strings, located immediately following each
 * other in the stream, leading up to the end of the data structure
 * (determined by the data packet's size).
 *
 * ____________________
 * LINK/PACKET PROTOCOL
 *
 * The MTA makes a connection to a milter by connecting to an IPC endpoint
 * (socket), via a stream-based protocol.  TCPv4, TCPv6, and "Unix
 * filesystem" sockets can be used for connection to a milter.
 * (Configuration of Sendmail to make use of these different endpoint
 * addressing methods is not described here.)
 *
 * Data is transmitted in both directions using a structured packet
 * protocol.  Each packets is comprised of:
 *
 * uint32	len		Size of data to follow
 * char	cmd		Command/response code
 * char	data[len-1]	Code-specific data (may be empty)
 *
 * The connection can be closed at any time by either side.  If closed by
 * the MTA, the milter program should release all state information for the
 * previously established connection.  If closed by the milter program
 * without first sending an accept or reject action message, the MTA will
 * take the default action for any message in progress (configurable to
 * ignore the milter program, or reject with a 4xx or 5xx error).
 *
 * [Header continuation lines are separated with LF, and milters SHOULD NOT
 * use CRLF but only LF for these, too: it is up to the MTA to adjust that.]
 *
 * _____________________________
 * A TYPICAL MILTER CONVERSATION
 *
 * The MTA drives the milter conversation.  The milter program sends
 * responses when (and only when) specified by the particular command code
 * sent by the MTA.  It is an error for a milter either to send a response
 * packet when not requested, or fail to send a response packet when
 * requested.  The MTA may have limits on the time allowed for a response
 * packet to be sent.
 *
 * The typical lifetime of a milter connection can be viewed as follows:
 *
 * MTA			Milter
 *
 * SMFIC_OPTNEG
 * 			SMFIC_OPTNEG
 * SMFIC_MACRO:'C'
 * SMFIC_CONNECT
 * 			Accept/reject action
 * SMFIC_MACRO:'H'
 * SMFIC_HELO
 * 			Accept/reject action
 * SMFIC_MACRO:'M'
 * SMFIC_MAIL
 * 			Accept/reject action
 * SMFIC_MACRO:'R'
 * SMFIC_RCPT
 * 			Accept/reject action
 * SMFIC_HEADER (multiple)
 * 			Accept/reject action (per SMFIC_HEADER)
 * SMFIC_EOH
 * 			Accept/reject action
 * SMFIC_BODY (multiple)
 * 			Accept/reject action (per SMFIC_BODY)
 * SMFIC_BODYEOB
 * 			Modification action (multiple, may be none)
 * 			Accept/reject action
 *
 * 			(Reset state to before SMFIC_MAIL and continue,
 * 			 unless connection is dropped by MTA)
 *
 * Several of these MTA/milter steps can be skipped if requested by the
 * SMFIC_OPTNEG response packet; see below.
 *
 * ____________________
 * PROTOCOL NEGOTIATION
 *
 * Milters can perform several actions on a SMTP transaction.  The following is
 * a bitmask of possible actions, which may be set by the milter in the
 * "actions" field of the SMFIC_OPTNEG response packet.  (Any action which MAY
 * be performed by the milter MUST be included in this field.)
 *
 * 0x01	SMFIF_ADDHDRS		Add headers (SMFIR_ADDHEADER)
 * 0x02	SMFIF_CHGBODY		Change body chunks (SMFIR_REPLBODY)
 * 0x04	SMFIF_ADDRCPT		Add recipients (SMFIR_ADDRCPT)
 * 0x08	SMFIF_DELRCPT		Remove recipients (SMFIR_DELRCPT)
 * 0x10	SMFIF_CHGHDRS		Change or delete headers (SMFIR_CHGHEADER)
 * 0x20	SMFIF_QUARANTINE	Quarantine message (SMFIR_QUARANTINE)
 * [0x40 SMFIF_CHGFROM		Change envelope from (SMFIR_CHGFROM)]
 *
 * (XXX: SMFIF_DELRCPT has an impact on how address rewriting affects
 * addresses sent in the SMFIC_RCPT phase.  This will be described in a
 * future revision of this document.)
 *
 * Protocol content can contain only selected parts of the SMTP
 * transaction.  To mask out unwanted parts (saving on "over-the-wire" data
 * churn), the following can be set in the "protocol" field of the
 * SMFIC_OPTNEG response packet.
 *
 * 0x01	SMFIP_NOCONNECT		Skip SMFIC_CONNECT
 * 0x02	SMFIP_NOHELO		Skip SMFIC_HELO
 * 0x04	SMFIP_NOMAIL		Skip SMFIC_MAIL
 * 0x08	SMFIP_NORCPT		Skip SMFIC_RCPT
 * 0x10	SMFIP_NOBODY		Skip SMFIC_BODY
 * 0x20	SMFIP_NOHDRS		Skip SMFIC_HEADER
 * 0x40	SMFIP_NOEOH		Skip SMFIC_EOH
 *
 * For backwards-compatible milters, the milter should pay attention to the
 * "actions" and "protocol" fields of the SMFIC_OPTNEG packet, and mask out
 * any bits that are not part of the offered protocol content.  The MTA may
 * reject the milter program if any action or protocol bit appears outside
 * the MTA's offered bitmask.
 *
 * _____________
 * COMMAND CODES
 *
 * The following are commands transmitted from the MTA to the milter
 * program.  The data structures represented occupy the "cmd" and "data"
 * fields of the packets described above in LINK/PACKET PROTOCOL.  (In
 * other words, the data structures below take up exactly "len" bytes,
 * including the "cmd" byte.)
 *
 * **
 *
 * 'A'	SMFIC_ABORT	Abort current filter checks
 * 			Expected response:  NONE
 *
 * (Resets internal state of milter program to before SMFIC_HELO, but keeps
 * the connection open.)
 *
 * **
 *
 * 'B'	SMFIC_BODY	Body chunk
 * 			Expected response:  Accept/reject action
 *
 * char	buf[]		Up to MILTER_CHUNK_SIZE (65535) bytes
 *
 * The buffer is not NUL-terminated.
 *
 * The body SHOULD be encoded with CRLF line endings, as if it was being
 * transmitted over SMTP. In practice existing MTAs and milter clients
 * will probably accept bare LFs, although at least some will convert CRLF
 * sequences to LFs.
 *
 * (These body chunks can be buffered by the milter for later replacement
 * via SMFIR_REPLBODY during the SMFIC_BODYEOB phase.)
 *
 * **
 *
 * 'C'	SMFIC_CONNECT	SMTP connection information
 * 			Expected response:  Accept/reject action
 *
 * char	hostname[]	Hostname, NUL terminated
 * char	family		Protocol family (see below)
 * uint16	port		Port number (SMFIA_INET or SMFIA_INET6 only)
 * char	address[]	IP address (ASCII) or unix socket path, NUL terminated
 *
 * (Sendmail invoked via the command line or via "-bs" will report the
 * connection as the "Unknown" protocol family.)
 *
 * Protocol families used with SMFIC_CONNECT in the "family" field:
 *
 * 'U'	SMFIA_UNKNOWN	Unknown (NOTE: Omits "port" and "host" fields entirely)
 * 'L'	SMFIA_UNIX	Unix (AF_UNIX/AF_LOCAL) socket ("port" is 0)
 * '4'	SMFIA_INET	TCPv4 connection
 * '6'	SMFIA_INET6	TCPv6 connection
 *
 * **
 *
 * 'D'	SMFIC_MACRO	Define macros
 * 			Expected response:  NONE
 *
 * char	cmdcode		Command for which these macros apply
 * char	nameval[][]	Array of NUL-terminated strings, alternating
 * 			between name of macro and value of macro.
 *
 * SMFIC_MACRO appears as a packet just before the corresponding "cmdcode"
 * (here), which is the same identifier as the following command.  The
 * names correspond to Sendmail macros, omitting the "$" identifier
 * character.
 *
 * Types of macros, and some commonly supplied macro names, used with
 * SMFIC_MACRO are as follows, organized by "cmdcode" value.
 * Implementations SHOULD NOT assume that any of these macros will be
 * present on a given connection.  In particular, communications protocol
 * information may not be present on the "Unknown" protocol type.
 *
 * 'C'	SMFIC_CONNECT	$_ $j ${daemon_name} ${if_name} ${if_addr}
 *
 * 'H'	SMFIC_HELO	${tls_version} ${cipher} ${cipher_bits}
 * 			${cert_subject} ${cert_issuer}
 *
 * 'M'	SMFIC_MAIL	$i ${auth_type} ${auth_authen} ${auth_ssf}
 * 			${auth_author} ${mail_mailer} ${mail_host}
 * 			${mail_addr}
 *
 * 'R'	SMFIC_RCPT	${rcpt_mailer} ${rcpt_host} ${rcpt_addr}
 *
 * For future compatibility, implementations MUST allow SMFIC_MACRO at any
 * time, but the handling of unspecified command codes, or SMFIC_MACRO not
 * appearing before its specified command, is currently undefined.
 *
 * **
 *
 * 'E'	SMFIC_BODYEOB	End of body marker
 * 			Expected response:  Zero or more modification
 * 			actions, then accept/reject action
 *
 * **
 *
 * 'H'	SMFIC_HELO	HELO/EHLO name
 * 			Expected response:  Accept/reject action
 *
 * char	helo[]		HELO string, NUL terminated
 *
 * **
 *
 * 'L'	SMFIC_HEADER	Mail header
 * 			Expected response:  Accept/reject action
 *
 * char	name[]		Name of header, NUL terminated
 * char	value[]		Value of header, NUL terminated
 *
 * **
 *
 * 'M'	SMFIC_MAIL	MAIL FROM: information
 * 			Expected response:  Accept/reject action
 *
 * char	args[][]	Array of strings, NUL terminated (address at index 0).
 * 			args[0] is sender, with <> qualification.
 * 			args[1] and beyond are ESMTP arguments, if any.
 *
 * **
 *
 * 'N'	SMFIC_EOH	End of headers marker
 * 			Expected response:  Accept/reject action
 *
 * **
 *
 * 'O'	SMFIC_OPTNEG	Option negotiation
 * 			Expected response:  SMFIC_OPTNEG packet
 *
 * uint32	version		SMFI_VERSION (2)
 * uint32	actions		Bitmask of allowed actions from SMFIF_*
 * uint32	protocol	Bitmask of possible protocol content from SMFIP_*
 *
 * **
 *
 * 'R'	SMFIC_RCPT	RCPT TO: information
 * 			Expected response:  Accept/reject action
 *
 * char	args[][]	Array of strings, NUL terminated (address at index 0).
 * 			args[0] is recipient, with <> qualification.
 * 			args[1] and beyond are ESMTP arguments, if any.
 *
 * **
 *
 * 'Q'	SMFIC_QUIT	Quit milter communication
 * 			Expected response:  Close milter connection
 *
 * ______________
 * RESPONSE CODES
 *
 * The following are commands transmitted from the milter program to the
 * MTA, in response to the appropriate type of command packet.  The data
 * structures represented occupy the "cmd" and "data" fields of the packets
 * described above in LINK/PACKET PROTOCOL.  (In other words, the data
 * structures below take up exactly "len" bytes, including the "cmd" byte.)
 *
 * **
 *
 * Response codes:
 *
 * '+'	SMFIR_ADDRCPT	Add recipient (modification action)
 *
 * char	rcpt[]		New recipient, NUL terminated
 *
 * **
 *
 * '-'	SMFIR_DELRCPT	Remove recipient (modification action)
 *
 * char	rcpt[]		Recipient to remove, NUL terminated
 * 			(string must match the one in SMFIC_RCPT exactly)
 *
 * **
 *
 * 'a'	SMFIR_ACCEPT	Accept message completely (accept/reject action)
 *
 * (This will skip to the end of the milter sequence, and recycle back to
 * the state before SMFIC_MAIL.  The MTA may, instead, close the connection
 * at that point.)
 *
 * **
 *
 * 'b'	SMFIR_REPLBODY	Replace body (modification action)
 *
 * char	buf[]		A portion of the body to be replaced
 *
 * The buffer is not NUL-terminated.
 *
 * As with SMFIC_BODY, the body SHOULD be encoded with CRLF line endings.
 * Sendmail will convert CRLFs to bare LFs as it receives SMFIR_REPLBODY
 * responses (even if the CR and LF are split across two responses); the
 * behavior of other MTAs has not been investigated.
 *
 * A milter that uses SMFIR_REPLBODY must replace the entire body, but
 * it may split the new replacement body across multiple SMFIR_REPLBODY
 * responses and it may make each response as small as it wants (and
 * they do not need to correspond one to one with SMFIC_BODY messages).
 * There is no explicit end of body marker; this role is filled by
 * whatever accept/reject response the milter finishes with.
 *
 * **
 *
 * 'c'	SMFIR_CONTINUE	Accept and keep processing (accept/reject action)
 *
 * (If issued at the end of the milter conversation, functions the same as
 * SMFIR_ACCEPT.)
 *
 * **
 *
 * 'd'	SMFIR_DISCARD	Set discard flag for entire message (accept/reject action)
 *
 * (Note that message processing MAY continue afterwards, but the mail will
 * not be delivered even if accepted with SMFIR_ACCEPT.)
 *
 * **
 *
 *[ 'e'	SMFIR_CHGFROM	Change MAIL FROM:<> envelope
 *
 * char	args[][]	Array of strings, NUL terminated (address at index 0).
 * 			args[0] is new MAIL envelope from.
 * 			args[1] and beyond are ESMTP arguments, if any.]
 *
 * **
 *
 * 'h'	SMFIR_ADDHEADER	Add header (modification action)
 *
 * char	name[]		Name of header, NUL terminated
 * char	value[]		Value of header, NUL terminated
 *
 * **
 *
 * 'm'	SMFIR_CHGHEADER	Change header (modification action)
 *
 * uint32	index		Index of the occurrence of this header
 * char	name[]		Name of header, NUL terminated
 * char	value[]		Value of header, NUL terminated
 *
 * (Note that the "index" above is per-name--i.e. a 3 in this field
 * indicates that the modification is to be applied to the third such
 * header matching the supplied "name" field.  A zero length string for
 * "value", leaving only a single NUL byte, indicates that the header
 * should be deleted entirely.)
 *
 * **
 *
 * 'p'	SMFIR_PROGRESS	Progress (asynchronous action)
 *
 * This is an asynchronous response which is sent to the MTA to reset the
 * communications timer during long operations.  The MTA should consume
 * as many of these responses as are sent, waiting for the real response
 * for the issued command.
 *
 * **
 *
 * 'q'	SMFIR_QUARANTINE Quarantine message (modification action)
 * char	reason[]	Reason for quarantine, NUL terminated
 *
 * This quarantines the message into a holding pool defined by the MTA.
 * (First implemented in Sendmail in version 8.13; offered to the milter by
 * the SMFIF_QUARANTINE flag in "actions" of SMFIC_OPTNEG.)
 *
 * **
 *
 * 'r'	SMFIR_REJECT	Reject command/recipient with a 5xx (accept/reject action)
 *
 * **
 *
 * 't'	SMFIR_TEMPFAIL	Reject command/recipient with a 4xx (accept/reject action)
 *
 * **
 *
 * 'y'	SMFIR_REPLYCODE	Send specific Nxx reply message (accept/reject action)
 *
 * char	smtpcode[3]	Nxx code (ASCII), not NUL terminated
 * char	space		' '
 * char	text[]		Text of reply message, NUL terminated
 *
 * ('%' characters present in "text" must be doubled to prevent problems
 * with printf-style formatting that may be used by the MTA.)
 *
 * **
 *
 * 'O'	SMFIC_OPTNEG	Option negotiation (in response to SMFIC_OPTNEG)
 *
 * uint32	version		SMFI_VERSION (2)
 * uint32	actions		Bitmask of requested actions from SMFIF_*
 * uint32	protocol	Bitmask of undesired protocol content from SMFIP_*
 *
 * _______
 * CREDITS
 *
 * Sendmail, Inc. - for the Sendmail program itself
 *
 * The anti-spam community - for making e-mail a usable medium again
 *
 * The spam community - for convincing me that it's time to really do
 * somthing to quell the inflow of their crap
 *
 * ___
 * EOF */
/* }}} */

/* defines, enums, types, rodata, bss {{{ */

/* xxx Low quality effort to close open file descriptors: as we are normally started in a controlled manner not
 * xxx "from within the wild" this seems superfluous even */
#undef a_BASE_FD
#define a_BASE_FD STDERR_FILENO /* xxX STDOUT open for no reason; dup2(STDERR, STDOUT)? */

#if su_OS_DRAGONFLY || su_OS_NETBSD || su_OS_OPENBSD
# define a_CLOSE_ALL_FDS() (closefrom(a_BASE_FD + 1) == 0)
#elif su_OS_FREEBSD
# define a_CLOSE_ALL_FDS() (closefrom(a_BASE_FD + 1), TRU1)
#elif su_OS_LINUX
# ifdef __NR_close_range
#  define a_CLOSE_ALL_FDS() (syscall(__NR_close_range, a_BASE_FD + 1, ~0u, 0) == 0)
# endif
#endif
#ifndef a_CLOSE_ALL_FDS
# define a_CLOSE_ALL_FDS() (TRU1)
#endif

/* Milter protocol: constants, commands and responses, collected and merged from all over the place {{{ */
/* Maximal (body) chunk size (XXX but see a_SMFIP_MDS_256K, a_SMFIP_MDS_1M); the latter is for tests.. */
#define a_MILTER_STD_CHUNK_SIZE 65535
#define a_MILTER_CHUNK_SIZE a_MILTER_STD_CHUNK_SIZE

/* Server commands */
enum a_smfic{
	a_SMFIC_ABORT = 'A', /* abort */
	a_SMFIC_BODY = 'B', /* body chunk */
	a_SMFIC_BODYEOB = 'E', /* final body chunk (End) */
	a_SMFIC_CONNECT = 'C', /* connection information */
	a_SMFIC_DATA = 'T', /* DATA (since Sendmail 8.13) */
	a_SMFIC_EOH = 'N', /* end of headers */
	a_SMFIC_HEADER = 'L', /* header */
	a_SMFIC_HELO = 'H', /* HELO/EHLO */
	a_SMFIC_MACRO = 'D', /* define macro */
	a_SMFIC_MAIL = 'M', /* MAIL from */
	a_SMFIC_OPTNEG = 'O', /* option negotiation */
	a_SMFIC_QUIT = 'Q', /* QUIT */
	a_SMFIC_QUIT_NC = 'K', /* QUIT but new connection follows (since Sendmail 8.14) */
	a_SMFIC_RCPT = 'R', /* RCPT to */
	a_SMFIC_UNKNOWN = 'U' /* any unknown command */
};

/* Milter responses */
enum a_smfir{
	a_SMFIR_ACCEPT = 'a', /* accept */
	a_SMFIR_ADDHEADER = 'h', /* add header */
	a_SMFIR_ADDRCPT = '+', /* add recipient */
	a_SMFIR_ADDRCPT_PAR = '2', /* add recipient (incl. ESMTP args) */
	a_SMFIR_CHGFROM = 'e', /* change envelope sender (from) */
	a_SMFIR_CHGHEADER = 'm', /* change header */
	a_SMFIR_CONN_FAIL = 'f', /* cause a connection failure */
	a_SMFIR_CONTINUE = 'c', /* continue */
	a_SMFIR_DELRCPT = '-', /* remove recipient */
	a_SMFIR_DISCARD = 'd', /* discard */
	a_SMFIR_INSHEADER = 'i', /* insert header (since Sendmail 8.13.0) */
	a_SMFIR_PROGRESS = 'p', /* progress */
	a_SMFIR_QUARANTINE = 'q', /* quarantine */
	a_SMFIR_REJECT = 'r', /* reject */
	a_SMFIR_REPLBODY = 'b', /* replace body (chunk) */
	a_SMFIR_REPLYCODE = 'y', /* reply code etc */
	a_SMFIR_SETSYMLIST = 'l', /* set list of symbols (macros) */
	a_SMFIR_SHUTDOWN = '4', /* 421: shutdown (internal to MTA) */
	a_SMFIR_SKIP = 's', /* skip rest of BODY (since Sendmail 8.14) */
	a_SMFIR_TEMPFAIL = 't' /* tempfail */
};

/* Announced and desired protocol parts (SMFIC_OPTNEG "protocol") */
enum a_smfip{
	a_SMFIP_NOCONNECT = 1u<<0, /* MTA should not send connect info */
	a_SMFIP_NOHELO = 1u<<1, /* .. HELO info */
	a_SMFIP_NOMAIL = 1u<<2, /* .. MAIL info */
	a_SMFIP_NORCPT = 1u<<3, /* .. RCPT info */
	a_SMFIP_NOBODY = 1u<<4, /* .. body */
	a_SMFIP_NOHDRS = 1u<<5, /* .. headers */
	a_SMFIP_NOEOH = 1u<<6, /* .. EOH */
	a_SMFIP_NR_HDR = 1u<<7, /* milter no-reply for headers (since Sendmail 8.14) */
	a_SMFIP_NOHREPL = a_SMFIP_NR_HDR, /* (since Sendmail 8.13) */
	a_SMFIP_NOUNKNOWN = 1u<<8, /* MTA should not send unknown commands */
	a_SMFIP_NODATA = 1u<<9, /* .. DATA */
	a_SMFIP_SKIP = 1u<<10, /* MTA understands SMFIR_SKIP */
	a_SMFIP_RCPT_REJ = 1u<<11, /* MTA should also send rejected RCPTs */
	a_SMFIP_NR_CONN = 1u<<12, /* milter no-reply for connect */
	a_SMFIP_NR_HELO = 1u<<13, /* .. HELO */
	a_SMFIP_NR_MAIL = 1u<<14, /* .. MAIL */
	a_SMFIP_NR_RCPT = 1u<<15, /* .. RCPT */
	a_SMFIP_NR_DATA = 1u<<16, /* .. DATA */
	a_SMFIP_NR_UNKN = 1u<<17, /* .. UNKNOWN commands */
	a_SMFIP_NR_EOH = 1u<<18, /* .. EOH */
	a_SMFIP_NR_BODY = 1u<<19, /* .. body chunk */
	a_SMFIP_HDR_LEADSPC = 1u<<20, /* header value has leading space(s) */
	/* not postfix */
	a_SMFIP_MDS_256K = 1u<<28, /* MILTER_MAX_DATA_SIZE=256K */
	a_SMFIP_MDS_1M = 1u<<29, /* MILTER_MAX_DATA_SIZE=1M */

	a_SMFIP_MASK_NOSEND = a_SMFIP_NOCONNECT | a_SMFIP_NOHELO | a_SMFIP_NOMAIL | a_SMFIP_NORCPT | a_SMFIP_NOBODY |
			a_SMFIP_NOHDRS | a_SMFIP_NOEOH | a_SMFIP_NOUNKNOWN | a_SMFIP_NODATA,
	a_SMFIP_MASK_NOREPLY = a_SMFIP_NR_HDR | a_SMFIP_NR_CONN | a_SMFIP_NR_HELO | a_SMFIP_NR_MAIL | a_SMFIP_NR_RCPT |
			a_SMFIP_NR_DATA | a_SMFIP_NR_UNKN | a_SMFIP_NR_EOH | a_SMFIP_NR_BODY,
	a_SMFIP_MASK_UNUSED = a_SMFIP_SKIP | a_SMFIP_RCPT_REJ | a_SMFIP_HDR_LEADSPC | a_SMFIP_MDS_256K | a_SMFIP_MDS_1M
};

/* Milter desire flags (SMFIC_OPTNEG "actions") */
enum a_smfif{
	a_SMFIF_ADDHDRS = 1u<<0, /* milter may SMFIR_ADDHEADER */
	a_SMFIF_CHGBODY = 1u<<1, /* .. SMFIR_REPLBODY */
	a_SMFIF_ADDRCPT = 1u<<2, /* .. SMFIR_ADDRCPT */
	a_SMFIF_DELRCPT = 1u<<3, /* .. SMFIR_DELRCPT */
	a_SMFIF_CHGHDRS = 1u<<4, /* .. SMFIR_CHGHEADER */
	a_SMFIF_QUARANTINE = 1u<<5, /* .. SMFIR_QUARANTINE */
	a_SMFIF_CHGFROM = 1u<<6, /* .. SMFIR_CHGFROM */
	a_SMFIF_ADDRCPT_PAR = 1u<<7, /* .. SMFIR_ADDRCPT_PAR */
	a_SMFIF_SETSYMLIST = 1u<<8, /* .. SMFIR_SETSYMLIST */

	a_SMFIF_MASK = a_SMFIF_ADDHDRS | a_SMFIF_CHGBODY | a_SMFIF_ADDRCPT | a_SMFIF_DELRCPT | a_SMFIF_CHGHDRS |
			a_SMFIF_QUARANTINE | a_SMFIF_CHGFROM | a_SMFIF_ADDRCPT_PAR | a_SMFIF_SETSYMLIST,
	a_SMFIF_MASK_4US = a_SMFIF_ADDHDRS | a_SMFIF_CHGHDRS
};
/* }}} */

enum a_flags{
	a_F_NONE,

	/* Setup: command line option and shared persistent flags */
	a_F_MODE_TEST = 1u<<1, /* -# */
	a__F_MODE_MASK = a_F_MODE_TEST,
	a_F_REPRO = 1u<<2,

	a_F_SETUP_MASK = (1u<<4) - 1,
	a_F_TEST_ERRORS = 1u<<4,

	a_F_DBG = 1u<<5, /* -d */
	a_F_V = 1u<<6, /* -v */
	a_F_VV = 1u<<7,
	a_F_VVV = 1u<<8,
	a_F_V_MASK = a_F_V | a_F_VV | a_F_VVV,

	/* for remove= <> enum a_rm_head_type inv/any fast triggers (< a_RM_HEAD_USER_MAX) */
	a_F_RM_ANY = 1u<<9, /* *Any* --remove */
#define a_RM_HEAD_TYPE_TO_INV_FLAG(RMT) (1u << (10u + S(uz,RMT)))
	a_F_RM_A_R_INV = 1u<<10, /* a-r: invalid */
	a_F_RM_MO_A_R_INV = 1u<<11,
	a_F_RM_A_A_R_INV = 1u<<12,
	a_F_RM_A_M_S_INV = 1u<<13,
	a_F_RM_A_S_INV = 1u<<14,
	a_F_RM_DKIM_INV = 1u<<15,
	a_F_RM_MO_DKIM_INV = 1u<<16,
#define a_RM_HEAD_TYPE_TO_ANY_FLAG(RMT) (1u << (17u + S(uz,RMT)))
	a_F_RM_A_R_ANY = 1u<<17, /* a-r: . wildcard */
	a_F_RM_MO_A_R_ANY = 1u<<18,
	a_F_RM_A_A_R_ANY = 1u<<19,
	a_F_RM_A_M_S_ANY = 1u<<20,
	a_F_RM_A_S_ANY = 1u<<21,
	a_F_RM_DKIM_ANY = 1u<<22,
	a_F_RM_MO_DKIM_ANY = 1u<<23,
	a_F_RM_MASK = a_F_RM_ANY |
			a_F_RM_A_R_INV | a_F_RM_MO_A_R_INV |
				a_F_RM_A_A_R_INV | a_F_RM_A_M_S_INV | a_F_RM_A_S_INV |
				a_F_RM_DKIM_INV | a_F_RM_MO_DKIM_INV |
			a_F_RM_A_R_ANY | a_F_RM_MO_A_R_ANY |
				a_F_RM_A_A_R_ANY | a_F_RM_A_M_S_ANY | a_F_RM_A_S_ANY |
				a_F_RM_DKIM_ANY | a_F_RM_MO_DKIM_ANY,

	/**/
	a_F_CLI_DOMAINS = 1u<<24, /* --client: any domain names, */
	a_F_CLI_DOMAIN_WILDCARDS = 1u<<25, /* with wildcards, */
	a_F_CLI_IPS = 1u<<26, /* ^ any IP addresses (shared dictionary) */
	a_F_SIGN_WILDCARDS = 1u<<27, /* Any --sign with wildcards, */
	a_F_SIGN_LOCAL_PARTS = 1u<<28 /* with a local-part */
};

enum a_cli_action{
	a_CLI_ACT_NONE,
	a_CLI_ACT_ERR, /* protocol error */
	a_CLI_ACT_PASS,
	a_CLI_ACT_SIGN,
	a_CLI_ACT_VERIFY
};

enum a_md_type{
	a_MD_NONE,
	a_MD_SHA256,
	a_MD_SHA1
};

enum a_pkey_type{
	/* EVP_PKEY_* always defined (1.0-3.1) so no #ifdef effort */
	a_PKEY_NONE,
	a_PKEY_BIG_ED = EVP_PKEY_ED25519,
	a_PKEY_ADAED25519 = -EVP_PKEY_ED25519,
	a_PKEY_RSA = EVP_PKEY_RSA
};

enum a_rm_head_type{
	/* Exact name match, content parsed and matched */
	a_RM_HEAD_A_R, /* authentication-results: */
	a_RM_HEAD_MO_A_R, /* x-mailman-original-authentication-results */
	a_RM_HEAD_A_A_R, /* arc-authentication-results */

	a_RM_HEAD_TOP_TOKEN_MATCH = a_RM_HEAD_A_A_R,

	a_RM_HEAD_A_M_S, /* arc-message-signature */
	a_RM_HEAD_A_S, /* arc-seal */
	a_RM_HEAD_DKIM, /* -signature */
	a_RM_HEAD_MO_DKIM, /* x-mailman-original-dkim-signature */

	a_RM_HEAD_TOP_D_SEARCH = a_RM_HEAD_MO_DKIM, /* Search for d= */
	a_RM_HEAD_TOP_MATCHED = a_RM_HEAD_TOP_D_SEARCH,

	/* Exact header name match, on or off */
	a_RM_HEAD_AUCY, /* autocrypt */
	a_RM_HEAD_IP, /* ironport */

	a_RM_HEAD_TOP_CMP = a_RM_HEAD_IP, /* Maximum exact match */
	a_RM_HEAD_USER_MAX,

	/* a_AUTO_RM range: no a_F_RM_* bits, no entry in a_rm_head_ids[] */
	a_RM_HEAD_DKIM_STORE = a_RM_HEAD_USER_MAX,

	a_RM_HEAD_TOP_AUTO = a_RM_HEAD_DKIM_STORE,
	a_RM_HEAD_MAX = a_AUTO_RM ? a_RM_HEAD_TOP_AUTO + 1 : a_RM_HEAD_USER_MAX
};

enum a_srch_type{
	a_SRCH_NONE,
	a_SRCH_SET = 1u<<0, /* (so dict_lookup() return NIL has meaning) */
	a_SRCH_IPV4 = 1u<<1,
	a_SRCH_IPV6 = 1u<<2,
	a_SRCH_EXACT = 1u<<3, /* Not wildcard or CIDR */
	a_SRCH_VERIFY = 1u<<4, /* Verify action */
	a_SRCH_PASS = 1u<<5 /* No action, pass */
};

/**/
struct a_line{
	u32 l_curr;
	u32 l_fill;
	s32 l_err; /* Error; su_ERR_NONE with 0 result: EOF */
	/* First a_LINE_BUF_SIZE bytes are "end-user storage" xxx could be optimized */
#define a_LINE_BUF_SIZE (su_PAGE_SIZE - 512)
	char l_buf[ALIGN_PAGE(a_LINE_BUF_SIZE) * 2 - 32 - 4];
};
#define a_LINE_SETUP(LP) do{(LP)->l_curr = (LP)->l_fill = 0;}while(0)

struct a_rm_head{
	u32 rmh_cnt; /* ..of used bits in rmh_bits */
	u32 rmh_top; /* maximum bit (.rmh_bits array size) */
	uz rmh_bits[VFIELD_SIZE(0)]; /* Bit set if header shall be removed; bit 0: any set at all */
};

struct a_milter{
	s32 mi_sock;
	u32 mi_len; /* Payload in .pd_buf */
	struct a_pd *mi_pdp;
	struct a_dkim *mi_dkim;
	char const *mi_log_id; /* queue id (macro i) or whatever ID we yet have */
	char const *mi_macro_j;
	struct a_rm_head *mi_rm_head[a_RM_HEAD_MAX]; /* (a_rm_head_names[]) */
#define a_MILTER_CLEANUP_ZERO(MIP) STRUCT_ZERO_FROM_UNTIL(struct a_milter, MIP, mi_rm_head, mi_bag)
	struct su_mem_bag mi_bag;
	char mi_log_buf[64]; /* Per-connection storage (pre-queue id) */
	char mi_buf[ALIGN_Z(a_MILTER_STD_CHUNK_SIZE + 2 +1)]; /* +CRLF +NUL; aligned for u32 */
};

/**/
struct a_dkim_res{
	struct a_dkim_res *dr_next;
	u32 dr_name_len;
	u32 dr_len;
	char dr_dat[VFIELD_SIZE(0)]; /* Prepared DKIM header */
};

struct a_head{
	struct a_head *h_next; /* Creation-ordered list, unique entries */
	struct a_head *h_same_older; /* In the entry's slot (newest first), list of same-headers */
	struct a_head *h_same_newer;
	u32 h_nlen; /* (Note: these are only for ease of calculation) */
	u32 h_dlen;
	char *h_dat;
	char h_name[VFIELD_SIZE(0)]; /* name\0dat\0 */
};

struct a_md_ctx{
	struct a_md_ctx *mdc_next;
	struct a_md *mdc_md;
	EVP_MD_CTX *mdc_md_ctx; /* First used body digest once, afterwards for header digests */
	u32 mdc_b_diglen; /* Prepared base64 body digest len */
	char mdc_b_digdat[(EVP_MAX_MD_SIZE * 4) / 3  +1]; /* XXX excessive -> pdp->pd_key_md_maxsize_b64 */
};

struct a_dkim{
	struct a_pd *d_pdp;
	char const *d_log_id; /* assigned log ID */
	struct a_md_ctx *d_sign_mdctxs;
	char const *d_sign_from_domain; /* What is effectively used for DKIM's d= */
	struct a_sign *d_sign; /* From: sign relation, or NIL */
	uz d_sign_head_totlen; /* Total length of all .d_sign_head's upon non-normalized creation */
	struct a_head *d_sign_head; /* List that matched --header-sign */
	struct a_head **d_sign_htail; /* (We keep that in seen-first order for whatever reason) */
	u32 d_sign_body_f; /* digesting: flags */
	u32 d_sign_body_eln; /* ": on-the-fly empty line count */
	struct a_dkim_res *d_sign_res;
};

/* */
struct a_key_algo_tuple{
	enum a_pkey_type kat_pkey; /* (assumed 32-bit) */
	ZIPENUM(u8,enum a_md_type) kat_md;
	boole kat_obs_pkey;
	boole kat_obs_md;
	boole kat_sign_md; /* DigestSign() takes MD (XXX *SSL gives us no accessible property to automatize this) */
	boole kat_extern_md; /* DigestSign() must be passed prepared MD TODO only because of RFC 8463 */
	char kat_name[11]; /* "our pkey name" */
	char kat_pkey_name[12];
	char kat_md_name[8];
};

struct a_md{
	struct a_md *md_next;
	EVP_MD const *md_md;
	struct a_key_algo_tuple const *md_katp;
};

struct a_key{
	struct a_key *k_next;
	struct a_md *k_md;
	EVP_PKEY *k_key;
	char *k_sel; /* points into .k_file */
	uz k_sel_len;
	struct a_key_algo_tuple const *k_katp;
	char k_file[VFIELD_SIZE(0)];
};

struct a_sign{ /* Stored in dictionary */
	union{char *name; struct a_key *key;} s_sel[a_SIGN_MAX_SELECTORS]; /* key only after conf_finish() */
	u32 s_spec_dom_off; /* */
	boole s_wildcard;
	boole s_anykey; /* Has any keys */
	char s_dom[VFIELD_SIZE(3)]; /* d= value if given (else From:'s address domain) */
};

union a_srch_ip{
	/* (Let us just place that align thing, ok?  I feel better that way) */
	u64 align;
	struct in_addr v4;
	struct in6_addr v6;
	/* And whatever else is needed to use this */
	char const *cp;
	uz f;
	void *vp;
};

struct a_srch{
	struct a_srch *s_next;
	BITENUM(u32,a_srch_type) s_type;
	u32 s_mask; /* CIDR mask */
	union a_srch_ip s_ip;
};

struct a_pd{
	BITENUM(u32,a_flags) pd_flags;
	u32 pd_argc;
	char **pd_argv;
	s64 pd_source_date_epoch; /* a_F_REPRO mode */
	/* Configuration */
	char *pd_domain_name; /* --domain-name */
	char *pd_header_sign; /* --header-sign: NIL: a_HEADER_SIGSEA_OFF_SIGN */
	char *pd_header_seal; /* --header-seal: NIL: none */
	char *pd_mima_sign; /* name\0[:val\0:]\0 */
	char *pd_mima_verify;
	/* --remove a-r etc. (\0|:val\0:)\0; entries NOT lowercased (for -# mode)!
	 * (Below we go for NELEM(>pd_rm) not RM_HEAD_USER_MAX!) */
	char *pd_rm[a_RM_HEAD_USER_MAX];
	struct a_key *pd_keys; /* --key */
	u32 pd_key_md_maxsize; /* MAX() across all EVP_PKEY_get_size() and MDs, */
	u32 pd_key_md_maxsize_b64; /* ..ditto, as base64 (including pad, NUL, etc), */
	uz pd_key_sel_len_max; /* ..ditto, longest selector */
	struct a_md *pd_mds; /* MDs needed (may be able to share MDs in between keys) */
	u32 pd_dkim_sig_ttl; /* --ttl */
	u32 pd_sign_longest_domain; /* Longest (--sign) --domain-name, for buffer alloc purposes */
	struct a_srch *pd_cli_ip; /* --client CIDR list */
	struct a_srch **pd_cli_ip_tail;
	struct su_cs_dict pd_cli; /* --client; IPs end with ACK U+0006 +NUL so names and IPs have diff namespace */
	struct su_cs_dict pd_sign; /* --sign */
};

/* This array is our sole availability shim, everything else should adapt automatically!  Adjust manual! */
static struct a_key_algo_tuple const a_kata[] = {
#ifndef OPENSSL_NO_SHA256
# ifndef OPENSSL_NO_ECX
	{a_PKEY_ADAED25519, a_MD_SHA256, FAL0, FAL0, FAL0, FAL0, "adaed25519\0", "adaed25519\0", "sha256\0"},
	{a_PKEY_BIG_ED, a_MD_SHA256, FAL0, FAL0, FAL0, TRU1, "big_ed", "ed25519", "sha256"},
# endif
# ifndef OPENSSL_NO_RSA
	{a_PKEY_RSA, a_MD_SHA256, FAL0, FAL0, TRU1, FAL0, "rsa", "rsa", "sha256"},
# endif
#endif
#ifndef OPENSSL_NO_SHA1
# ifndef OPENSSL_NO_RSA
	{a_PKEY_RSA, a_MD_SHA1, FAL0, TRU1, TRU1, FAL0, "rsa", "rsa", "sha1"}
# endif
#endif
};

/* RFC 6376, 5.4.1 (in order; EXT: extensions); remains are senseless.
 * (We need to go a bit 'round the corner to be able to detect alloc size via sizeof()) */
#define a_HEADER_SIGSEA__BASE \
	"author\0"/* EXT RFC9057 */ "from\0" /*"reply-to\0" below*/ "subject\0" "date\0" "to\0" "cc\0" \
	"resent-author\0"/* EXT */ "resent-date\0" "resent-from\0" "resent-sender\0"/* EXT */ \
		"resent-to\0" "resent-cc\0" "resent-reply-to\0"/* EXT */ "resent-message-id\0"/* EXT */\
	"in-reply-to\0" "references\0"
#define a_HEADER_SIGSEA__ML \
	"list-id\0" \
	"list-help\0" "list-subscribe\0" "list-unsubscribe\0" \
	"list-post\0" "list-owner\0" "list-archive\0"
#define a_HEADER_SIGSEA__MIME \
	"mime-version\0" "content-type\0" "content-transfer-encoding\0" \
	"content-disposition\0"/* "EXT" */ \
	/* EXT: these not in main mail header, *normally* */ "content-id\0" "content-description\0"
#define a_HEADER_SIGSEA__EXT "message-id\0" "mail-followup-to\0" "openpgp\0"

#define a_HEADER_SIGSEA_SIGN \
	"reply-to\0" a_HEADER_SIGSEA__BASE a_HEADER_SIGSEA__ML ""
#define a_HEADER_SIGSEA_SIGN_EXT \
	"reply-to\0" a_HEADER_SIGSEA__BASE a_HEADER_SIGSEA__ML a_HEADER_SIGSEA__MIME a_HEADER_SIGSEA__EXT ""
#define a_HEADER_SIGSEA_SEAL \
	/*"reply-to\0"*/ a_HEADER_SIGSEA__BASE ""
#define a_HEADER_SIGSEA_SEAL_EXT \
	/*"reply-to\0"*/ a_HEADER_SIGSEA__BASE a_HEADER_SIGSEA__MIME a_HEADER_SIGSEA__EXT ""
#define a_HEADER_SIGSEA_SEAL_EXT_ML \
	a_HEADER_SIGSEA__BASE a_HEADER_SIGSEA__MIME a_HEADER_SIGSEA__EXT "reply-to\0" a_HEADER_SIGSEA__ML ""

#define a_HEADER_SIGSEA_MAX MAX(sizeof(a_HEADER_SIGSEA_SIGN_EXT), sizeof(a_HEADER_SIGSEA_SEAL_EXT_ML))
static char const * const a_header_sigsea[5] = {
	a_HEADER_SIGSEA_SIGN, a_HEADER_SIGSEA_SIGN_EXT,
	a_HEADER_SIGSEA_SEAL, a_HEADER_SIGSEA_SEAL_EXT, a_HEADER_SIGSEA_SEAL_EXT_ML
};
enum{a_HEADER_SIGSEA_OFF_SIGN = 0, a_HEADER_SIGSEA_OFF_SEAL = 2}; /* (base + EXT) */

/**/
static char const a_milter_log_defid[] = "<unknown>: ";
static char const a_localhost[] = "localhost";

static char const a_rm_head_names[a_RM_HEAD_MAX][sizeof("X-Mailman-Original-Authentication-Results")] = {
	/* matchables, token */
	FII(a_RM_HEAD_A_R) "authentication-results",
		FII(a_RM_HEAD_MO_A_R) "x-mailman-original-authentication-results",
		FII(a_RM_HEAD_A_A_R) "arc-authentication-results",
		/* matchables d= search */
		FII(a_RM_HEAD_A_M_S) "arc-message-signature", FII(a_RM_HEAD_A_S) "arc-seal",
		FII(a_RM_HEAD_DKIM) "dkim-signature", FII(a_RM_HEAD_MO_DKIM) "x-mailman-original-dkim-signature",
	/* non-matchables */
	FII(a_RM_HEAD_AUCY) "autocrypt",
		FII(a_RM_HEAD_IP) "ironport"
	/* automatics */
#if a_AUTO_RM
	, FII(a_RM_HEAD_DKIM_STORE) "dkim-store"
#endif
}, a_rm_head_ids[a_RM_HEAD_USER_MAX][8] = {
	FII(a_RM_HEAD_A_R) "a-r", FII(a_RM_HEAD_MO_A_R) "mo-a-r",
		FII(a_RM_HEAD_A_A_R) "a-a-r", FII(a_RM_HEAD_A_M_S) "a-m-s", FII(a_RM_HEAD_A_S) "a-s",
		FII(a_RM_HEAD_DKIM) "dkim", FII(a_RM_HEAD_MO_DKIM) "mo-dkim",
	FII(a_RM_HEAD_AUCY) "aucy", FII(a_RM_HEAD_IP) "ip",
};
CTAV(a_RM_HEAD_A_R == 0 &&
	a_RM_HEAD_MO_A_R == 1 &&
	a_RM_HEAD_A_A_R == 2 &&
	a_RM_HEAD_A_M_S == 3 && a_RM_HEAD_A_S == 4 &&
	a_RM_HEAD_DKIM == 5 && a_RM_HEAD_MO_DKIM == 6 &&
	a_RM_HEAD_AUCY == 7 && a_RM_HEAD_IP == 8 &&
	(!a_AUTO_RM || (a_RM_HEAD_DKIM_STORE == 9)));

static char const a_sopts[] = "A:C:c:" "d:" "~:!:" "k:" "M:" "R:" "r:" "S:s:" "t:" "#" "Hh";
static char const * const a_lopts[] = {
	/* long option order */
	"client:;C;" N_("assign action [(sign|pass),] to domain or address"),
	"client-file:;c;" N_("[action,]file: like --client for all lines of file"),

	"domain-name:;d;" N_("set signature-announced domain name (default)"),

	"header-sign:;~;" N_("comma-separated header list to sign"),
	"header-sign-show;-1;" N_("[*] show default --header-sign lists, exit"),
	"header-seal:;!;" N_("comma-separated header list to (over)sign/seal"),
	"header-seal-show;-2;" N_("[*] show default --header-seal lists, exit"),

	"key:;k;" N_("add key via algo-digest,selector,private-key-pem-file"),

	"milter-macro:;M;" N_("pass unless server announces action,macro[:,value:]"),

	"remove:;r;" N_("remove header of type[:,spec:]"),

	"resource-file:;R;" N_("path to configuration file with long options"),

	"sign:;S;" N_("add sign relation via spec[,domain[:,selector:]]"),
	"sign-file:;s;" N_("like --sign for all lines of file"),

	"ttl:;t;" N_("impose time-to-live on signatures, in seconds"),

	/* verify:;V; */
	/* verify-file:;v; */

	/**/
	"debug;-3;" N_("debug mode: sandbox mode, no real actions, only log"),
	"verbose;-4;" N_("increase syslog verbosity (2x for more verbosity)"),

	/**/
	"test-mode;#;" N_("[*] check and list configuration, exit according status"),

	"copyright;-42;" N_("[*] show copyright"),
	"long-help;H;" N_("[*] this listing"),
	"help;h;" N_("[*] short help"),
	NIL
};

/* What can reside in resource files, in long-option order */
#define a_AVOPT_CASES \
	case 'A':\
	case 'C': case 'c':\
	case 'd':\
	case '~':\
	case '!':\
	case 'k':\
	case 'M':\
	case 'R':\
	case 'r':\
	case 'S': case 's':\
	case 't':\
	/*case 'V': case 'v':*/\
	/**/\
	case -3:\
	case -4:
/* }}} */

/* protos {{{ */

/* server */
static s32 a_server(struct a_pd *pdp);

/* milter */
static s32 a_milter(struct a_pd *pdp, s32 sock);

/* __read() returns -EX_IOERR on connection break */
static void a_milter__cleanup(struct a_milter *mip);
static s32 a_milter__loop(struct a_milter *mip);
static s32 a_milter__read(struct a_milter *mip);
/* .mi_buf .. */
static s32 a_milter__write(struct a_milter *mip, uz len);

/* _ macro */
static enum a_cli_action a_milter__macro_parse_(struct a_milter *mip, char *dp, uz dl, boole bltin);

static enum a_cli_action a_milter__macro_mima(struct a_milter *mip, char *bp, uz bl, char *dp, uz dl);

/**/
static s32 a_milter__rm_parse(struct a_milter *mip, ZIPENUM(u8,enum a_rm_head_type) rmt, char *dp);

static s32 a_milter__verify(struct a_milter *mip);
static s32 a_milter__sign(struct a_milter *mip);
static s32 a_milter__rm_heads(struct a_milter *mip, boole only_autos);

/* post_eoh must be >TRU1 if there was no !pre_eoh; !post_eoh only ensures _cleanup() can be called */
static boole a_dkim_setup(struct a_dkim *dkp, boole post_eoh, struct a_pd *pdp, struct su_mem_bag *membp,
		char const *log_id);
static void a_dkim_cleanup(struct a_dkim *dkp);

/**/
static enum a_cli_action a_dkim_push_header(struct a_dkim *dkp, char const *name, char const *dat,
		struct su_mem_bag *membp);
static enum a_cli_action a_dkim__parse_from(struct a_dkim *dkp, char *store, char const *dat, struct su_mem_bag *membp);

/* Body chunk processing.  dl==0/dp==NIL denotes "no more body data to be expected" */
static boole a_dkim_push_body(struct a_dkim *dkp, char *dp, uz dl, struct su_mem_bag *membp);

/* After collecting all the data, create signature(s); mibuf is of MILTER_CHUNK_SIZE bytes! */
static boole a_dkim_sign(struct a_dkim *dkp, char *mibuf, struct su_mem_bag *membp);

/* advances *mibuf over */
static void a_dkim__head_prep(struct a_dkim *dkp, char const *np, char const *dp, char **mibuf, boole trail_crlf);

/**/
static void a_conf_setup(struct a_pd *pdp, boole init);
static s32 a_conf_finish(struct a_pd *pdp);
#if DVLOR(DBGXOR(1, 0), 0)
static void a_conf_cleanup(struct a_pd *pdp);
#endif

static s32 a_conf_list_values(struct a_pd *pdp);
static void a_conf__list_cpxarr(char const *name, char const *name2_or_nil, char const *cp, boole comma_sep);

static s32 a_conf_arg(struct a_pd *pdp, s32 o, char *arg);
static s32 a_conf__C(struct a_pd *pdp, char *arg, char const *act_or_nil);
static s32 a_conf__c(struct a_pd *pdp, char *arg);
static s32 a_conf__header_sigsea(struct a_pd *pdp, char *arg, boole sign);
static s32 a_conf__k(struct a_pd *pdp, char *arg);
static s32 a_conf__M(struct a_pd *pdp, char *arg);
static s32 a_conf__R(struct a_pd *pdp, char *path);
static s32 a_conf__r(struct a_pd *pdp, char *arg);
static s32 a_conf__S(struct a_pd *pdp, char *arg);
static s32 a_conf__s(struct a_pd *pdp, char *arg);
static void a_conf__err(struct a_pd *pdp, char const *msg, ...);

/* misc */

/* NUL string is not! */
static boole a_misc_is_rfc5321_domain(char const *dom);

static boole a_misc_resource_delay(s32 err);
static s32 a_misc_open(struct a_pd *pdp, char const *path);

static s32 a_misc_log_open(boole isrepro);
static void a_misc_log_write(u32 lvl_a_flags, char const *msg, uz len);

/* getline(3) replacement (-1, or size of space-normalized and trimmed line) */
static sz a_misc_line_get(struct a_pd *pdp, s32 fd, struct a_line *lp);
static s32 a_misc_line__uflow(s32 fd, struct a_line *lp);

static void a_misc_usage(FILE *fp);
static boole a_misc_dump_doc(up cookie, boole has_arg, char const *sopt, char const *lopt, char const *doc);

#ifdef su_NYD_ENABLE
static void a_misc_oncrash(int signo);
static void a_misc_oncrash__dump(up cookie, char const *buf, uz blen);
#endif
/* }}} */

/* server {{{ */
static s32
a_server(struct a_pd *pdp){ /* xxx effectively a stub */
	s32 rv;
	NYD_IN;

	/* In non-test mode, set su_program so that STATE_LOG_SHOW_PID is honoured */
	su_program = su_empty;

	/* Best-effort only */
	while(!a_CLOSE_ALL_FDS()){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			continue;
		if(rv != su_ERR_BADF){
			a_DBG(write(STDERR_FILENO, "CLOSE_ALL_FDS()\n", sizeof("CLOSE_ALL_FDS()\n") -1);)
		}
		break;
	}

	rv = a_milter(pdp, STDIN_FILENO);

	NYD_OU;
	return rv;
}
/* }}} */

/* milter {{{ */
static s32
a_milter(struct a_pd *pdp, s32 sock){
	struct a_dkim dkim;
	struct a_milter *mip;
	s32 rv;
	NYD_IN;

	mip = su_TALLOC(struct a_milter, 1);
	a_MILTER_CLEANUP_ZERO(mip);
	mip->mi_sock = sock;
	mip->mi_pdp = pdp;
	mip->mi_dkim = &dkim;
	mip->mi_log_id = a_milter_log_defid;
	mip->mi_macro_j = a_localhost;
	su_mem_bag_create(&mip->mi_bag, su_PAGE_SIZE * 4); /* xxx pretty arbitrary, and too much */
	mip->mi_log_buf[0] = '\0';

	rv = a_milter__loop(mip);
	if(rv < 0)
		rv = -rv;

	DVL(
		a_milter__cleanup(mip);
		su_mem_bag_gut(&mip->mi_bag);
		DVL(DBG(su_FREE(mip)));
	)

	NYD_OU;
	return rv;
}

static void
a_milter__cleanup(struct a_milter *mip){
	NYD_IN;

	mip->mi_log_id = a_milter_log_defid;
	mip->mi_macro_j = a_localhost;
	a_MILTER_CLEANUP_ZERO(mip);

	a_dkim_cleanup(mip->mi_dkim);

	su_mem_bag_reset(&mip->mi_bag);

	DVL(su_mem_set_conf(su_MEM_CONF_LINGER_FREE_RELEASE, 0);)

	NYD_OU;
}

static s32
a_milter__loop(struct a_milter *mip){ /* XXX too big: split up {{{ */
	enum{ /* {{{ */
		a_NONE,
		a_REPRO = 1u<<0, /* reproducible */
		a_DBG = 1u<<1,
		a_V = 1u<<2,
		a_VV = 1u<<3,
		a_VVV = 1u<<4,

		a_RESP_CONN = 1u<<5, /* Need to respond to connection requests */
		a_RESP_HDR = 1u<<6, /* Need to respond to headers */

		a_RM_MASK = 1u<<7, /* Any --remove */

		a_SMFIC_OPTNEG_MASK = a_REPRO | a_DBG | a_V | a_VV | a_VVV | a_RESP_CONN | a_RESP_HDR | a_RM_MASK,

		/* Action after connection setup is saved into fb */
		a_B_ACT_DUNNO = 1u<<9,
		a_B_ACT_SIGN = 1u<<10,
		a_B_ACT_VERIFY = 1u<<11,
		a_B_ACT_PASS = 1u<<12,
		a_B_ACT_MASK = a_B_ACT_DUNNO | a_B_ACT_SIGN | a_B_ACT_VERIFY | a_B_ACT_PASS,

		a_MIMA = 1u<<16, /* --milter-macro */
		a_CLI = 1u<<17, /* --client's */
		a_SMFIC_CONNECT_MASK = a_MIMA | a_CLI,

		a_FROM = 1u<<18, /* Have seen From: header */
		a_SMFIC_HEADER_MASK = a_FROM,

		/* Only fx */

		/*a_SEEN_SMFIC_CONNECT,*/
		a_SEEN_SMFIC_HEADER = 1u<<19, /* ever seen.. */
		a_SEEN_SMFIC_BODY = 1u<<20,
		/*a_SEEN_SMFIC_BODY_EOB,*/

		a_SETUP = 1u<<23, /* ..in a message cycle, DKIM setup performed pre-EOH, */
		a_SETUP_EOH = 1u<<24, /* ..post EOH */

		a_LOG_ID = 1u<<25,
		a_MYHOSTNAME = 1u<<26,

		a_ACT_SHIFTER = 18u,
		a_ACT_DUNNO = a_B_ACT_DUNNO << a_ACT_SHIFTER,
		a_ACT_SIGN = a_B_ACT_SIGN << a_ACT_SHIFTER,
		a_ACT_VERIFY = a_B_ACT_VERIFY << a_ACT_SHIFTER,
		a_ACT_PASS = a_B_ACT_PASS << a_ACT_SHIFTER,
		a_ACT_MASK = a_B_ACT_MASK << a_ACT_SHIFTER
	}; /* }}} */

	struct {u32 version; u32 actions; u32 protocol;} optneg;
	u32 fb, fx;
	s32 rv;
	struct a_pd *pdp;
	NYD_IN;

	pdp = mip->mi_pdp;

	/* Because we may call milter__cleanup() that calls dkim_cleanup() without ever being a_SETUP, this */
	a_dkim_setup(mip->mi_dkim, FAL0, pdp, &mip->mi_bag, su_empty);

	fb = a_NONE;
	if(pdp->pd_flags & a_F_DBG)
		fb |= a_DBG;
	if(pdp->pd_flags & a_F_V)
		fb |= a_V;
	if(pdp->pd_flags & a_F_VV)
		fb |= a_VV;
	if(pdp->pd_flags & a_F_VVV)
		fb |= a_VVV;
	if(pdp->pd_flags & a_F_REPRO)
		fb |= a_REPRO;

	/* --milter-macro and --client apply restrictions upon connection time */
	if(pdp->pd_mima_sign != NIL || pdp->pd_mima_verify != NIL)
		fb |= a_RESP_CONN | a_MIMA;

	if(pdp->pd_cli_ip != NIL || (pdp->pd_flags & (a_F_CLI_DOMAINS | a_F_CLI_IPS)))
		fb |= a_RESP_CONN | a_CLI;

	/* --sign table may apply restrictions once we see the From: header; and we need a match to act! */
	if(su_cs_dict_count(&pdp->pd_sign) > 0)
		fb |= a_RESP_HDR;

	if(pdp->pd_flags & a_F_RM_ANY)
		fb |= a_RM_MASK;

	for(fx = a_ACT_DUNNO /* UNINIT(fx,a_ACT_DUNNO)? */;;){
		rv = a_milter__read(mip);
		if(rv != su_EX_OK){
			if(rv == -su_EX_IOERR){
				if(fb & a_VVV)
					su_log_write(su_LOG_INFO, "%sconnection shutdown, good bye",
						mip->mi_log_id);
				rv = su_EX_OK;
			}
			goto jleave;
		}

		if(UNLIKELY(fb & a_VVV))
			su_log_write(su_LOG_INFO, "%sCMD %c/%d, %zu data bytes",
				mip->mi_log_id, mip->mi_buf[0], mip->mi_buf[0], mip->mi_len);

		switch(mip->mi_buf[0]){
		case a_SMFIC_QUIT:
			ASSERT(rv == su_EX_OK);
			goto jleave;
		case a_SMFIC_QUIT_NC:
			a_milter__cleanup(mip);
			mip->mi_log_buf[0] = '\0';
			fb &= a_SMFIC_OPTNEG_MASK;
			fx &= a_SMFIC_OPTNEG_MASK;
			fx |= a_ACT_DUNNO;
			break;
		case a_SMFIC_ABORT:
			a_milter__cleanup(mip);
			if(mip->mi_log_buf[0] != '\0')
				mip->mi_log_id = mip->mi_log_buf; /* same connection */
			/* Normally in SMFIC_CONNECT or later, but which we may not have seen XXX */
			if(!(fb & a_B_ACT_MASK)){
				fb |= (fx & a_ACT_MASK) >> a_ACT_SHIFTER;
				a_DBG(su_log_write(su_LOG_DEBUG, "SMFIC_ABORT sets base mask %u", fb & a_B_ACT_MASK);)
			}
			fx &= a_SMFIC_OPTNEG_MASK | a_SMFIC_CONNECT_MASK;
			fx |= (fb & a_B_ACT_MASK) << a_ACT_SHIFTER;
			break;

		case a_SMFIC_OPTNEG: /* {{{ */
			if(mip->mi_len != 13){
				rv = su_EX_SOFTWARE;
				goto jleave;
			}

			su_mem_copy(&optneg, &mip->mi_buf[1], sizeof(optneg));
			optneg.version = su_boswap_net_32(optneg.version);
			optneg.actions = su_boswap_net_32(optneg.actions);
			optneg.protocol = su_boswap_net_32(optneg.protocol);
			if(UNLIKELY(fb & a_VVV))
				su_log_write(su_LOG_INFO, "optneg server: version=0x%X actions=0x%X protocol=0x%X",
					optneg.version, optneg.actions, optneg.protocol);

			/* Use LOG_CRIT in order to surely enter log */
			if(optneg.version < 6){
				su_log_write(su_LOG_CRIT, _("Mail server milter protocol version too low, bailing out"));
				rv = su_EX_UNAVAILABLE;
				goto jleave;
			}
			optneg.version = 6;

			if((optneg.actions & a_SMFIF_MASK_4US) != a_SMFIF_MASK_4US){
				su_log_write(su_LOG_CRIT, _("Mail server cannot add/change mail headers, bailing out"));
				rv = su_EX_UNAVAILABLE;
				goto jleave;
			}
			optneg.actions = (a_AUTO_RM || (fb & a_RM_MASK)) ? a_SMFIF_MASK_4US : a_SMFIF_ADDHDRS;

			if((optneg.protocol & a_SMFIP_MASK_NOSEND) != a_SMFIP_MASK_NOSEND ||
					 (optneg.protocol & a_SMFIP_MASK_NOREPLY) != a_SMFIP_MASK_NOREPLY){
				/* XXX We could deal with non-desired-protocol restrictions, if we would! */
				su_log_write(su_LOG_CRIT,
					_("Mail server cannot restrict milter protocol the needed way, bailing out"));
				rv = su_EX_UNAVAILABLE;
				goto jleave;
			}

			fx = (a_SMFIP_MASK_NOSEND & ~(a_SMFIP_NOBODY | a_SMFIP_NOHDRS)) |
					(a_SMFIP_MASK_NOREPLY /*& ~(a_SMFIP_NR_BODY)*/);
			if(fb & a_RESP_CONN)
				fx &= ~(a_SMFIP_NOCONNECT | a_SMFIP_NR_CONN);
			if(fb & a_RESP_HDR)
				fx &= ~(a_SMFIP_NR_HDR);
			optneg.protocol &= fx;

			if(UNLIKELY(fb & a_VVV))
				su_log_write(su_LOG_INFO, "optneg response: version=0x%X actions=0x%X protocol=0x%X",
					optneg.version, optneg.actions, optneg.protocol);
			optneg.version = su_boswap_net_32(optneg.version);
			optneg.actions = su_boswap_net_32(optneg.actions);
			optneg.protocol = su_boswap_net_32(optneg.protocol);
			mip->mi_buf[0] = a_SMFIC_OPTNEG;
			su_mem_copy(&mip->mi_buf[1], &optneg, sizeof(optneg));
			if(LIKELY(!(fb & a_REPRO))){
				rv = a_milter__write(mip, 1 + sizeof(optneg));
				if(rv != su_EX_OK)
					goto jleave;
			}else
				fprintf(stdout, "OPTNEG NR_CONN=%d NR_HDR=%d\n",
					!!(fb & a_RESP_CONN), !!(fb & a_RESP_HDR));

			fx = fb & a_SMFIC_OPTNEG_MASK;
			fx |= a_ACT_DUNNO;
			break; /* }}} */

		case a_SMFIC_MACRO:{ /* {{{ */
			/* We get macros even for ignored commands */
			uz l, nl, dl;
			char cmd, *bp;

			cmd = mip->mi_buf[1];

			/* We are only interested in some macros */
			if(UNLIKELY(fb & a_VVV))
				su_log_write(su_LOG_INFO, "%smacros for cmd %c/%d: %u bytes",
					mip->mi_log_id, cmd, cmd, mip->mi_len);
			else if(cmd != a_SMFIC_CONNECT && (fx & (a_LOG_ID | a_MYHOSTNAME)) == (a_LOG_ID | a_MYHOSTNAME))
				break;

			for(bp = &mip->mi_buf[2], l = mip->mi_len - 2; l > 0; bp += nl + dl){
				nl = su_cs_len(bp) +1;
				l -= nl;
				if(UNLIKELY(l == 0))
					goto jeproto;
				dl = su_cs_len(&bp[nl]) +1;
				if(UNLIKELY(dl > l))
					goto jeproto;
				l -= dl;

				if(UNLIKELY(fb & a_VVV))
					su_log_write(su_LOG_INFO, "%smacro %lu<%s> %lu<%s>",
						mip->mi_log_id, S(ul,nl) -1, bp, S(ul,dl), &bp[nl]);

				/* Set log ID regardless of state: queue ID it shall be asap as for postfix itself */
				if(!(fx & a_LOG_ID) && nl == 1 +1 && bp[0] == 'i'){
					char *cp;
					struct su_mem_bag *membp;

					fx |= a_LOG_ID;
					membp = &mip->mi_bag;
					mip->mi_log_id = cp = su_LOFI_TALLOC(char, dl + 2);
					cp = su_cs_pcopy(cp, &bp[2]);
					cp[0] = ':'; cp[1] = ' '; cp[2] = '\0';
					continue;
				}

				if(fx & a_ACT_PASS){
					if(!LIKELY(!(fb & a_VVV)))
						break;
					continue;
				}

				if(cmd != a_SMFIC_CONNECT)
					continue;

				if(nl == 1 +1 && bp[0] == '_'){ /* {{{ */
					char *cp;

					/* xxx copying _ macro data assumes it is 7-bit clean */
					if(!(fx & a_LOG_ID)){ /* xxx never though */
						mip->mi_log_id = mip->mi_log_buf;
						cp = su_cs_pcopy_n(mip->mi_log_buf, &bp[2], sizeof(mip->mi_log_buf) -1);
						if(cp == NIL){
							cp = &mip->mi_log_buf[sizeof(mip->mi_log_buf) -3];
							cp[-1] = '.'; cp[-2] = '.';
						}
						cp[0] = ':'; cp[1] = ' '; cp[2] = '\0';
					}

					/* Only if it still matters */
					if(fx & a_ACT_PASS)
						continue;

					switch(a_milter__macro_parse_(mip, &bp[2], dl, ((fb & a_CLI) == 0))){/*(logs)*/
					default:
					case a_CLI_ACT_NONE: FALLTHRU
					case a_CLI_ACT_ERR:
						goto jeproto;
					case a_CLI_ACT_PASS:
						fx &= ~a_ACT_MASK;
						fx |= a_ACT_PASS;
						break;
					case a_CLI_ACT_VERIFY:
						if(LIKELY(!(fx & a_ACT_SIGN))){
							fx &= ~a_ACT_MASK;
							fx |= a_ACT_VERIFY;
						}else{
							fx &= ~a_ACT_MASK;
							fx |= a_ACT_PASS;
							if(UNLIKELY((fb & a_V)))
								su_log_write(su_LOG_INFO,
									"%sclient opposed DKIM=sign->pass",
									mip->mi_log_id);
						}
						break;
					case a_CLI_ACT_SIGN:
						if(LIKELY(!(fx & a_ACT_VERIFY))){
							fx &= ~a_ACT_MASK;
							fx |= a_ACT_SIGN;
						}else{
							fx &= ~a_ACT_MASK;
							fx |= a_ACT_PASS;
							if(UNLIKELY((fb & a_V)))
								su_log_write(su_LOG_INFO,
									"%sclient opposed DKIM=verify->pass",
									mip->mi_log_id);
						}
						break;
					}

					if(fb & a_CLI)
						fx |= a_CLI;
				} /* }}} */
				else if(nl == 1 +1 && bp[0] == 'j'){
					struct su_mem_bag *membp;
					char *cp, c;

					for(cp = &bp[2]; (c = *cp) != '\0'; ++cp)
						*cp = su_cs_to_lower(c);

					membp = &mip->mi_bag;
					mip->mi_macro_j = cp = su_LOFI_TALLOC(char, dl +1);
					su_cs_pcopy(cp, &bp[2])[1] = '\0'; /* used as \0\0 list! */
					fx |= a_MYHOSTNAME;
				}

				if((fb & a_MIMA) && !(fx & a_MIMA)){ /* {{{ */
					switch(a_milter__macro_mima(mip, bp, nl -1, &bp[nl], dl -1)){/*(logs)*/
					default:
					case a_CLI_ACT_NONE: FALLTHRU
					case a_CLI_ACT_ERR:
						break;
					case a_CLI_ACT_PASS:
						fx &= ~a_ACT_MASK;
						fx |= a_MIMA | a_ACT_PASS;
						break;
					case a_CLI_ACT_VERIFY:
						if(LIKELY(!(fx & a_ACT_SIGN))){
							fx &= ~a_ACT_MASK;
							fx |= a_MIMA | a_ACT_VERIFY;
						}else{
							fx &= ~a_ACT_MASK;
							fx |= a_MIMA | a_ACT_PASS;
							if(UNLIKELY((fb & a_V)))
								su_log_write(su_LOG_INFO,
									"%milter-macro opposed DKIM=sign->pass",
									mip->mi_log_id);
						}
						break;
					case a_CLI_ACT_SIGN:
						if(LIKELY(!(fx & a_ACT_VERIFY))){
							fx &= ~a_ACT_MASK;
							fx |= a_MIMA | a_ACT_SIGN;
						}else{
							fx &= ~a_ACT_MASK;
							fx |= a_MIMA | a_ACT_PASS;
							if(UNLIKELY((fb & a_V)))
								su_log_write(su_LOG_INFO,
									"%smilter-macro opposed DKIM=verify->pass",
									mip->mi_log_id);
						}
						break;
					}
				} /* }}} */
			}

			if(LIKELY(cmd == a_SMFIC_CONNECT)){
				if((fb & a_MIMA) && !(fx & a_MIMA)){
					if(UNLIKELY((fb & a_V)))
						su_log_write(su_LOG_INFO, "%smilter-macro mismatch DKIM=pass",
							mip->mi_log_id);
					fx &= ~a_ACT_MASK;
					fx |= a_ACT_PASS;
				}

				if(UNLIKELY(fb & a_REPRO)){
					if(fb & a_MIMA)
						puts((fx & a_MIMA) ? "--milter-macro OK" : "--milter-macro BAD");
					if(fb & a_CLI)
						puts((fx & a_CLI) ? "--client OK" : "--client BAD");
					ASSERT(((fx & a_SMFIC_CONNECT_MASK) == (fb & a_SMFIC_CONNECT_MASK)) ||
						(fx & a_ACT_PASS));
					ASSERT(((fx & a_SMFIC_CONNECT_MASK) != (fb & a_SMFIC_CONNECT_MASK)) ||
						!(fx & a_ACT_PASS));
				}
			}
			}break; /* }}} */

		case a_SMFIC_CONNECT: /* {{{ */
			if(UNLIKELY(fb & a_VVV))
				su_log_write(su_LOG_INFO, "%sconnection established", mip->mi_log_id);

			if(!(fb & a_B_ACT_MASK)){
				fb |= (fx & a_ACT_MASK) >> a_ACT_SHIFTER;
				a_DBG(su_log_write(su_LOG_DEBUG, "SMFIC_CONNECT sets base mask %u", fb & a_B_ACT_MASK);)
			}

			if(fx & a_ACT_PASS)
				goto jaccept;

			if((fx & a_SMFIC_CONNECT_MASK) != (fb & a_SMFIC_CONNECT_MASK)){
				if(UNLIKELY(fb & a_VV))
					su_log_write(su_LOG_INFO, "%sconditions not met DKIM=X->pass", mip->mi_log_id);
				fx &= ~a_ACT_MASK;
				fx |= a_ACT_PASS;
				goto jaccept;
			}

			if(!(fx & a_RESP_CONN)) /* XXX ??? */
				break;
			if(LIKELY(!(fb & a_REPRO))){
				mip->mi_buf[0] = a_SMFIR_CONTINUE;
				rv = a_milter__write(mip, 1);
				if(rv != su_EX_OK)
					goto jleave;
			}else
				puts("SMFIC_CONNECT SMFIR_CONTINUE");
			break; /* }}} */

		case a_SMFIC_HEADER:{ /* {{{ */
			enum {a_FH_NONE, a_FH_SIGN = 1u<<0, a_FH_RM = 1u<<1, a_FH_RM_AUTO = 1u<<2};

			uz i;
			u8 fh, rmt;
			char const *hname;

			UNINIT(rmt, 0);

			if(UNLIKELY(fb & a_VVV))
				su_log_write(su_LOG_INFO, "%sprocessing header <%s>", mip->mi_log_id, &mip->mi_buf[1]);

			if(!(fb & a_B_ACT_MASK)){
				fb |= (fx & a_ACT_MASK) >> a_ACT_SHIFTER;
				a_DBG(su_log_write(su_LOG_DEBUG, "SMFIC_HEADER sets base mask %u", fb & a_B_ACT_MASK);)
			}

			if(fx & a_ACT_PASS)
				goto jaccept;

			if(!(fx & a_SEEN_SMFIC_HEADER)){
				/* XXX should never trigger here, then -> SMFIC_CONNECT! */
				if((fx & a_SMFIC_CONNECT_MASK) != (fb & a_SMFIC_CONNECT_MASK)){
					goto jaccept;
				}
			}
			fx |= a_SEEN_SMFIC_HEADER;

			UNINIT(hname, NIL);
			fh = a_FH_NONE;

#if a_AUTO_RM
			/* These cannot be signed/verified, they are always removed */
			for(rmt = a_RM_HEAD_USER_MAX; rmt < a_RM_HEAD_MAX; ++rmt)
				if(!su_cs_cmp_case(a_rm_head_names[rmt], &mip->mi_buf[1])){
					fh |= a_FH_RM_AUTO;
					goto jheader_step;
				}
#endif

			if(fx & (a_ACT_DUNNO | a_ACT_SIGN)){
				hname = pdp->pd_header_sign;
				if(hname == NIL)
					hname = a_header_sigsea[a_HEADER_SIGSEA_OFF_SIGN];
				for(;;){
					if(!su_cs_cmp_case(hname, &mip->mi_buf[1])){ /* @HVALWS */
						fh |= a_FH_SIGN;
						break;
					}
					hname += su_cs_len(hname) +1;
					if(*hname == '\0'){
						if(UNLIKELY(fb & a_VVV))
							su_log_write(su_LOG_INFO, "%sheader-sign mismatch %s",
								mip->mi_log_id, &mip->mi_buf[1]);
						break;
					}
				}
			}

			if(fx & (a_ACT_DUNNO | a_ACT_VERIFY)){
				if(fb & a_RM_MASK){
					for(rmt = 0; rmt < a_RM_HEAD_USER_MAX; ++rmt)
						if(!su_cs_cmp_case(a_rm_head_names[rmt], &mip->mi_buf[1])){
							fh |= a_FH_RM;
							break;
						}
				}
			}

			if(fh == a_FH_NONE)
				goto jheader_done;
#if a_AUTO_RM
jheader_step:
#endif
			if(!(fx & a_SETUP) && !a_dkim_setup(mip->mi_dkim, FAL0, pdp, &mip->mi_bag, mip->mi_log_id)){
				/* xxx does not happen */
				rv = su_EX_UNAVAILABLE;
				goto jleave;
			}
			fx |= a_SETUP;

			i = 1 + su_cs_len(&mip->mi_buf[1]) +1;
			if(UNLIKELY(fb & a_VVV))
				su_log_write(su_LOG_INFO, "%s%s: %s", mip->mi_log_id, &mip->mi_buf[1], &mip->mi_buf[i]);

			if(fh & a_FH_SIGN){
				ASSERT((fx & (a_ACT_DUNNO | a_ACT_SIGN)) &&
					!((fx & a_ACT_MASK) & ~(a_ACT_DUNNO | a_ACT_SIGN)));
				ASSERT(hname != NIL);
				/* May give action hint for From: (and logs) */
				switch(a_dkim_push_header(mip->mi_dkim, hname, &mip->mi_buf[i], &mip->mi_bag)){
				default:
				case a_CLI_ACT_NONE:
					/* Not From: */
					break;
				case a_CLI_ACT_SIGN:
					fx &= ~a_ACT_MASK;
					fx |= a_FROM | a_ACT_SIGN;
					fh &= ~a_FH_RM;
					break;
				case a_CLI_ACT_VERIFY:
					FALLTHRU
				case a_CLI_ACT_PASS:
					if(UNLIKELY((fx & a_ACT_SIGN) && (fb & a_V)))
						su_log_write(su_LOG_INFO, "%ssign/From: opposed DKIM=sign->pass",
							mip->mi_log_id);
					FALLTHRU
				case a_CLI_ACT_ERR:
					fx &= ~a_ACT_MASK;
					fx |= a_FROM | a_ACT_PASS;
					goto jaccept;
				}
			}

			if(fh & (a_FH_RM | a_FH_RM_AUTO)){
				ASSERT(!(fh & a_FH_RM) ||
					((fx & (a_ACT_DUNNO | a_ACT_VERIFY)) &&
					!((fx & a_ACT_MASK) & ~(a_ACT_DUNNO | a_ACT_VERIFY))));
				rv = a_milter__rm_parse(mip, rmt, &mip->mi_buf[i]);
				if(rv != su_EX_OK){
					fx &= ~a_ACT_MASK;
					fx |= a_ACT_PASS;
					goto jaccept;
				}
			}

jheader_done:
			if(fb & a_RESP_HDR){
				if(fx & a_ACT_PASS)
					goto jaccept;
				if(LIKELY(!(fb & a_REPRO))){
					mip->mi_buf[0] = a_SMFIR_CONTINUE;
					rv = a_milter__write(mip, 1);
					if(rv != su_EX_OK)
						goto jleave;
				}else
					puts("SMFIC_HEADER SMFIR_CONTINUE");
			}
			}break; /* }}} */

		case a_SMFIC_BODY:/* {{{ */
			if(fb & a_VVV)
				su_log_write(su_LOG_INFO, "%sbody chunk %lu bytes",
					mip->mi_log_id, S(ul,mip->mi_len - 1));

			if(fx & a_ACT_PASS)
				goto jaccept;

			if(!(fx & a_SEEN_SMFIC_BODY)){
				if((fx & a_ACT_SIGN) && (fx & (a_SETUP | a_FROM)) != (a_SETUP | a_FROM))
					goto jenofrom;
				/* XXX should never trigger here, then -> SMFIC_CONNECT! */
				if((fx & a_SMFIC_CONNECT_MASK) != (fb & a_SMFIC_CONNECT_MASK)){
					fx &= ~a_ACT_MASK;
					fx |= a_ACT_PASS;
					goto jaccept;
				}
			}
			ASSERT(fb & a_B_ACT_MASK);
			fx |= a_SEEN_SMFIC_BODY;

			if(mip->mi_len == 1)
				break;

			if(!(fx & a_SETUP_EOH)){
				if(!a_dkim_setup(mip->mi_dkim, (TRU1 + !(fx & a_SETUP)), pdp, &mip->mi_bag,
						mip->mi_log_id)){
					rv = su_EX_UNAVAILABLE;
					goto jleave;
				}
				fx |= a_SETUP | a_SETUP_EOH;
			}

			ASSERT(mip->mi_len > 1);
			if(fx & a_ACT_SIGN){
				if(!a_dkim_push_body(mip->mi_dkim, &mip->mi_buf[1], mip->mi_len - 1, &mip->mi_bag)){
					rv = su_EX_TEMPFAIL;
					goto jleave;
				}
			}
			break; /* }}} */

		case a_SMFIC_BODYEOB:/* {{{ */
			if(fb & a_VVV)
				su_log_write(su_LOG_INFO, "%smessage completely received", mip->mi_log_id);

			if(fx & a_ACT_PASS)
				goto jaccept;
			if(!(fx & a_SETUP)){
				if(UNLIKELY(fb & a_V))
					su_log_write(su_LOG_INFO, "%smessage did not trigger DKIM=pass",
						mip->mi_log_id);
				fx &= ~a_ACT_MASK;
				fx |= a_ACT_PASS;
				goto jaccept;
			}
			ASSERT(fb & a_B_ACT_MASK);

			if(!(fx & a_SEEN_SMFIC_BODY)){
				if((fx & (a_ACT_SIGN | a_FROM)) == a_ACT_SIGN){
jenofrom:
					su_log_write(su_LOG_CRIT, _("%smessage without From: header DKIM=pass"),
						mip->mi_log_id);
					fx &= ~a_ACT_MASK;
					fx |= a_ACT_PASS;
					goto jaccept;
				}
				/* XXX should never trigger here, then -> SMFIC_CONNECT! */
				if((fx & a_SMFIC_CONNECT_MASK) != (fb & a_SMFIC_CONNECT_MASK)){
					fx &= ~a_ACT_MASK;
					fx |= a_ACT_PASS;
					goto jaccept;
				}
			}DVL(else if(fx & a_ACT_SIGN) ASSERT(mip->mi_dkim->d_sign_from_domain != NIL);)
			fx |= a_SEEN_SMFIC_BODY;

			if(!(fx & a_SETUP_EOH)){
				if(!a_dkim_setup(mip->mi_dkim, TRU1, pdp, &mip->mi_bag, mip->mi_log_id)){
					rv = su_EX_UNAVAILABLE;
					goto jleave;
				}
				fx |= a_SETUP_EOH;
			}

			if(fx & a_ACT_VERIFY)
				rv = a_milter__verify(mip);
			else{
				ASSERT(fx & a_ACT_SIGN);
				rv = a_milter__sign(mip);
			}
			if(rv != su_EX_OK)
				goto jleave;

jaccept:
			if(UNLIKELY(fb & a_VVV))
				su_log_write(su_LOG_INFO, "%smessage processing complete", mip->mi_log_id);
			if(LIKELY(!(fb & a_REPRO))){
				mip->mi_buf[0] = a_SMFIR_ACCEPT;
				rv = a_milter__write(mip, 1);
				if(rv != su_EX_OK)
					goto jleave;
			}else
				puts("SMFIC_BODYEOB SMFIR_ACCEPT");
			fx |= a_ACT_PASS;
			break; /* }}} */

		default:
			su_log_write(su_LOG_CRIT, _("Received undesired/-handled milter command: %d"), mip->mi_buf[0]);
			rv = su_EX_SOFTWARE;
			goto jleave;
		}
	}

	rv = su_EX_OK;
jleave:
	NYD_OU;
	return rv;

jeproto:
	su_log_write(su_LOG_CRIT, _("Mail server sent invalid data, false lengths, or whatever"));
	rv = su_EX_SOFTWARE;
	goto jleave;
} /* }}} */

static s32
a_milter__read(struct a_milter *mip){ /* {{{ xxx optimize: FIONREAD? single big-as-possible read, split as necessary? */
	fd_set rfds;
	ssize_t br;
	s32 rv;
	u32 l, yet;
	NYD_IN;

	mip->mi_len = yet = 0;
	l = sizeof(u32);
jselect:
	FD_ZERO(&rfds);
	FD_SET(mip->mi_sock, &rfds);

	if(select(mip->mi_sock + 1, &rfds, NIL, NIL, NIL) == -1){
		if((rv = su_err_by_errno()) == su_ERR_INTR)
			goto jselect;
		su_log_write(su_LOG_CRIT, _("%sselect(2) failed: %s"), mip->mi_log_id, V_(su_err_doc(rv)));
		rv = su_EX_IOERR;
		goto jleave;
	}

jread:
	br = read(mip->mi_sock, &mip->mi_buf[yet], l);
	if(br == -1){
		rv = su_err_by_errno();
		if(rv == su_ERR_INTR)
			goto jread;
		su_log_write(su_LOG_CRIT, _("%sread(2) failed: %s"), mip->mi_log_id, V_(su_err_doc(rv)));
		rv = su_EX_IOERR;
		goto jleave;
	}
	if(br == 0){
		if(yet == 0){
			rv = -su_EX_IOERR;
			goto jleave;
		}
		/* Is this really happening? */
		su_time_msleep(250,FAL0);
		goto jselect;
	}
	/* We do not test that br fits in U32_MAX because of milter I/O restrictions */

	yet += S(u32,br);
	l -= S(u32,br);
	if(l > 0)
		goto jread;

	/* Was this u32 length or payload? */
	if(mip->mi_len == 0){
		l = *R(u32*,mip->mi_buf);
		mip->mi_len = l = su_boswap_net_32(l);
		if(l > 0){
			yet = 0;
			goto jread;
		}
	}

	rv = su_EX_OK;
jleave:
	NYD_OU;
	return rv;
} /* }}} */

static s32
a_milter__write(struct a_milter *mip, uz len){ /* {{{ XXX screams for writev */
	s32 rv;
	ssize_t bw;
	char *bp;
	u32 l, lb, yet;
	NYD_IN;

	l = S(u32,len);
	lb = su_boswap_net_32(l);
	bp = R(char*,&lb);
	yet = 0;
	l = sizeof(lb);
jwrite:
	bw = write(mip->mi_sock, &bp[yet], l);
	if(bw == -1){
		rv = su_err_by_errno();
		if(rv == su_ERR_INTR)
			goto jwrite;
		su_log_write(su_LOG_CRIT, _("%swrite(2) failed: %s"), mip->mi_log_id, V_(su_err_doc(rv)));
		rv = su_EX_IOERR;
		goto jleave;
	}
	if(bw == 0){
		su_time_msleep(250, FAL0); /* XXX select this? */
		goto jwrite;
	}
	yet += S(u32,bw);
	l -= S(u32,bw);
	if(l > 0)
		goto jwrite;

	/* Was this u32 length or payload? */
	if(bp == R(char*,&lb)){
		l = S(u32,len);
		if(l > 0){
			bp = &mip->mi_buf[0];
			yet = 0;
			goto jwrite;
		}
	}

	rv = su_EX_OK;
jleave:
	NYD_OU;
	return rv;
} /* }}} */

static enum a_cli_action
a_milter__macro_parse_(struct a_milter *mip, char *dp, uz dl, boole bltin){ /* {{{ */
	union a_srch_ip sip, sip_x;
	struct a_srch *sp;
	int af;
	char *addr, buf[INET6_ADDRSTRLEN + 1];
	enum a_cli_action rv;
	NYD_IN;

	rv = a_CLI_ACT_ERR;

	/* "localhost [127.0.0.1]" (plus optional additional data): isolate fields */
	addr = S(char*,su_mem_find(dp, '[', dl));
	if(addr == NIL)
		goto jleave;
	else{
		char *x, c;

		x = addr;
		while(x > dp && su_cs_is_space(*x))
			--x;
		*x = *addr++ = '\0';

		dl -= P2UZ(addr - dp);
		x = S(char*,su_mem_find(addr, ']', dl));
		if(x == NIL || x == addr)
			goto jleave;
		*x = '\0';

		/* Normalize domains */
		for(x = dp; (c = *x) != '\0' && !su_cs_is_space(c); ++x)
			*x = S(char,su_cs_to_lower(c));
		*x = '\0';
	}

	/* Without --client use defaults */
	if(bltin){
		char const *msg;

		ASSERT(su_cs_dict_count(&mip->mi_pdp->pd_cli) == 0 && mip->mi_pdp->pd_cli_ip == NIL);
		if(!su_cs_cmp(dp, a_localhost)){
			msg = "signing ";
			rv = a_CLI_ACT_SIGN;
		}else{
			msg = "verifying non-";
			rv = a_CLI_ACT_VERIFY;
		}
		if(mip->mi_pdp->pd_flags & a_F_V)
			su_log_write(su_LOG_INFO, "%sno client configured, %slocalhost", mip->mi_log_id, msg);
		goto jleave;
	}

	/* Domain name */
	if(mip->mi_pdp->pd_flags & a_F_CLI_DOMAINS){
		boole any, first;

		for(any = FAL0, first = TRU1;; first = FAL0){
			sip.vp = su_cs_dict_lookup(&mip->mi_pdp->pd_cli, dp);

			if(sip.vp != NIL && (first || !(sip.f & a_SRCH_EXACT))){
				char const *act;

				if(sip.f & a_SRCH_VERIFY){
					act = "verify";
					rv = a_CLI_ACT_VERIFY;
				}else if(sip.f & a_SRCH_PASS){
					act = "pass";
					rv = a_CLI_ACT_PASS;
				}else{
					act = "sign";
					rv = a_CLI_ACT_SIGN;
				}
				if(mip->mi_pdp->pd_flags & a_F_V)
					/* (original name was logged by callee, then) */
					su_log_write(su_LOG_INFO, "%sclient %s match domain name, DKIM=%s: %s",
						mip->mi_log_id, (first ? "exact" : "wildcard"), act, (any ? "." : dp));
				goto jleave;
			}

			if(any || !(mip->mi_pdp->pd_flags & a_F_CLI_DOMAIN_WILDCARDS))
				break;
			dp = su_cs_find_c(dp, '.');
			if(dp == NIL || *++dp == '\0'){
				any = TRU1;
				dp = UNCONST(char*,su_empty);
			}
		}
	}

	if(!(mip->mi_pdp->pd_flags & a_F_CLI_IPS) && mip->mi_pdp->pd_cli_ip == NIL)
		goto jdefault;

	/* We need to normalize through the system's C library to match IP addresses */
	af = (su_cs_find_c(addr, ':') == NIL) ? AF_INET : AF_INET6;
	if(inet_pton(af, addr, (af == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6))) != 1)
		goto jleave;
	/* (xxx could avoid ntop but for .pd_cli or DBG|VV) */
	if(inet_ntop(af, (af == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6)), buf, sizeof(buf)) == NIL)
		goto jleave;

	if(mip->mi_pdp->pd_flags & a_F_CLI_IPS){
		uz i;

		i = su_cs_len(buf);
		buf[i] = '\06';
		buf[i +1] = '\0';
		sip_x.vp = su_cs_dict_lookup(&mip->mi_pdp->pd_cli, buf);
		buf[i] = '\0';

		if(sip_x.vp != NIL){
			char const *act;

			if(sip.f & a_SRCH_VERIFY){
				act = "verify";
				rv = a_CLI_ACT_VERIFY;
			}else if(sip.f & a_SRCH_PASS){
				act = "pass";
				rv = a_CLI_ACT_PASS;
			}else{
				act = "sign";
				rv = a_CLI_ACT_SIGN;
			}
			if(mip->mi_pdp->pd_flags & a_F_V)
				/* (original name was logged by callee, then) */
				su_log_write(su_LOG_INFO, "%sclient exact match IP, DKIM=%s: %s",
					mip->mi_log_id, act, buf);
			goto jleave;
		}
	}

	for(sp = mip->mi_pdp->pd_cli_ip; sp != NIL; sp = sp->s_next){
		uz max, i;
		u32 *ip, mask;

		if((af == AF_INET) != ((sp->s_type & a_SRCH_IPV4) != 0))
			continue;

		/* a_conf__C() LCTA()s this works! */
		su_mem_copy(&sip_x, &sip, sizeof(sip));
		if(af == AF_INET){
			ip = R(u32*,&sip_x.v4.s_addr);
			max = 1;
		}else{
			ip = R(u32*,sip_x.v6.s6_addr);
			max = 4;
		}
		mask = sp->s_mask;

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

		if(((af == AF_INET) ? su_mem_cmp(&sp->s_ip.v4.s_addr, &sip_x.v4.s_addr, sizeof(sip_x.v4.s_addr))
				: su_mem_cmp(sp->s_ip.v6.s6_addr, sip_x.v6.s6_addr, sizeof(sip_x.v6.s6_addr)))){
			char const *act;

			if(sip.f & a_SRCH_VERIFY){
				act = "verify";
				rv = a_CLI_ACT_VERIFY;
			}else if(sip.f & a_SRCH_PASS){
				act = "pass";
				rv = a_CLI_ACT_PASS;
			}else{
				act = "sign";
				rv = a_CLI_ACT_SIGN;
			}
			if(mip->mi_pdp->pd_flags & a_F_V)
				/* (original name was logged by callee, then) */
				su_log_write(su_LOG_INFO, "%sclient match IP CIDR/%u, DKIM=%s: %s",
					mip->mi_log_id, sp->s_mask, act, buf);
			goto jleave;
		}
	}

	/* Default fallback with clients is "pass, ." */
jdefault:
	if(mip->mi_pdp->pd_flags & a_F_V)
		su_log_write(su_LOG_INFO, "%sclient mismatch DKIM=pass, .", mip->mi_log_id);
	rv = a_CLI_ACT_PASS;

jleave:
	NYD_OU;
	return rv;
} /* }}} */

static enum a_cli_action
a_milter__macro_mima(struct a_milter *mip, char *bp, uz bl, char *dp, uz dl){ /* {{{ */
	char *cp;
	char const *mt;
	enum a_cli_action clia;
	struct a_pd *pdp;
	NYD_IN;

	pdp = mip->mi_pdp;
	clia = a_CLI_ACT_SIGN;
	mt = "sign";
	cp = pdp->pd_mima_sign;

jredo:
	if(cp != NIL && !su_cs_cmp(bp, cp)){
		cp += bl;

		if(*++cp == '\0'){
			if(UNLIKELY(pdp->pd_flags & a_F_V))
				su_log_write(su_LOG_INFO, "%smilter-macro name match ok: DKIM=%s, %s",
					mip->mi_log_id, mt, bp);
			goto jleave;
		}else for(;;){
			uz i;

			i = su_cs_len(cp);
			if(i == dl && !su_mem_cmp(cp, dp, i)){
				if(UNLIKELY(pdp->pd_flags & a_F_V))
					su_log_write(su_LOG_INFO, "%smilter-macro value match ok: DKIM=%s, %s, %s",
						mip->mi_log_id, mt, bp, cp);
				goto jleave;
			}
			cp += ++i;
			if(*cp == '\0')
				break;
		}
	}

	if(clia == a_CLI_ACT_SIGN){
		clia = a_CLI_ACT_VERIFY;
		mt = "verify";
		cp = pdp->pd_mima_verify;
		goto jredo;
	}

	clia = a_CLI_ACT_NONE;
jleave:
	NYD_OU;
	return clia;
} /* }}} */

static s32
a_milter__rm_parse(struct a_milter *mip, ZIPENUM(u8,enum a_rm_head_type) rmt, char *dp){ /* {{{ xxx split up in 3/4 */
	s32 mse;
	uz dl, l;
	char *dat, sbuf[256];
	char const *emsg, *dat2, *cp;
	struct su_imf_shtok *shtp;
	void *ls;
	struct su_mem_bag *membp;
	struct a_pd *pdp;
	NYD_IN;

	pdp = mip->mi_pdp;
	membp = &mip->mi_bag;
	ls = NIL;
	shtp = NIL;
	dat2 = emsg = NIL;
	dat = NIL;
	UNINIT(dl, 0);

	/* Drop anyway, .. or parse and match? */
	LCTAV(a_RM_HEAD_TOP_MATCHED > a_RM_HEAD_TOP_TOKEN_MATCH);
	LCTAV(a_RM_HEAD_TOP_TOKEN_MATCH < a_RM_HEAD_TOP_D_SEARCH);
	LCTAV(a_RM_HEAD_TOP_MATCHED >= a_RM_HEAD_TOP_D_SEARCH);

	mse = TRU1;
	if(rmt >= a_RM_HEAD_USER_MAX){
		emsg = "automatic header removal";
		goto jmark;
	}
	if(rmt > a_RM_HEAD_TOP_MATCHED || (pdp->pd_flags & a_RM_HEAD_TYPE_TO_ANY_FLAG(rmt))){
		emsg = "super-wildcard or spec-less match";
		goto jmark;
	}
	if(rmt <= a_RM_HEAD_TOP_TOKEN_MATCH){
		ls = su_imf_snap_create(membp);

		/* 'Thing is, we need to dig it */
		mse = su_imf_parse_struct_header(&shtp, dp, (su_IMF_MODE_RELAX | su_IMF_MODE_OK_DOT_ATEXT |
					su_IMF_MODE_TOK_SEMICOLON | su_IMF_MODE_TOK_EMPTY), membp, NIL);

		/* Microsoft produces invalid Authentication-Results where authserv-id is missing.
		 * XXX We cannot check ERR_CONTENT because IMF parses atext and there is a @ in i=@DOMAIN --
		 * XXX effectively DKIM uses VCHAR instead of atext, but for our point of interest, it is ok */
		if(/*(mse & su_IMF_ERR_CONTENT) ||*/ shtp == NIL || shtp->imfsht_len == 0 || shtp->imfsht_next == NIL){
			if(pdp->pd_flags & a_F_VV){
				snprintf(sbuf, sizeof sbuf, "%s: %.64s",
					(shtp == NIL ? "unparsable (invalid)" : "invalid"), dp);
				emsg = sbuf;
			}
			mse = ((pdp->pd_flags & a_RM_HEAD_TYPE_TO_INV_FLAG(rmt)) != 0);
			goto jmark;
		}

		/* Search for result token */
		for(;; shtp = shtp->imfsht_next){
			dat = shtp->imfsht_dat;
			/* Unquote: should not happen but is owed to our IMF parser which parses 5322 not that mess */
			if(shtp->imfsht_len > 1 && *dat == '"'){
				shtp->imfsht_len -= 2;
				ASSERT(shtp->imfsht_len > 0); /* (empty is not quoted) */
				++dat;
				dat[shtp->imfsht_len] = '\0';
			}

			/* For authentication-results the first token *is* the result; for ARC-a-r it is the 2nd xxx */
			if(rmt == a_RM_HEAD_A_R || rmt == a_RM_HEAD_MO_A_R || mse == TRU2)
				break;
			mse = TRU2;

			if(shtp->imfsht_next == NIL){
jeparse_invalid:
				if(pdp->pd_flags & a_F_VV){
					snprintf(sbuf, sizeof sbuf, "seems invalid: %.64s", dp);
					emsg = sbuf;
				}
				mse = ((pdp->pd_flags & a_RM_HEAD_TYPE_TO_INV_FLAG(rmt)) != 0);
				goto jmark;
			}
		}

		dl = shtp->imfsht_len;
	}else if(rmt <= a_RM_HEAD_TOP_D_SEARCH){ /* XXX low quality parser <> manual! */
		/* Most Y2K standards each introduce their very own ABNF instead of going hard 5322 phrase/2045 K=V :(.
		 * We search for a d= entry specified as "d(FWS)*=(FWS)*v" instead of eg RFC 2045 k="?v", and the ARC-
		 * series is even bogus as it says CFWS for -Signature which is something entirely different than the
		 * claimed "adopted" DKIM-Signature */
		boole sep;
		char *xdp, c;

		sep = TRU1;
		for(xdp = dp; (c = *xdp++) != '\0';){
			if(sep && c == 'd'){
				while(su_imf_c_ANY_WSP((c = *xdp)))
					++xdp;
				if(c == '\0')
					goto jeparse_invalid;
				sep = FAL0;

				if(c == '='){
					while(su_imf_c_ANY_WSP((c = *++xdp))){
					}
					dat = xdp;
					for(;;){
						if(c == '\0')
							goto jeparse_invalid;
						if(c == ';'){
							while(xdp > dat && su_imf_c_ANY_WSP(xdp[-1]))
								--xdp;
							*xdp = '\0';
							dl = P2UZ(xdp - dat);
							break;
						}
						c = *++xdp;
					}
				}
			}else
				sep = (su_imf_c_ANY_WSP(c) || c == ';');
		}
	}

	ASSERT(rmt < a_RM_HEAD_USER_MAX); /* (jumped to jmark:) */
	LCTAV(NELEM(pdp->pd_rm) == a_RM_HEAD_USER_MAX);
	cp = pdp->pd_rm[rmt];
	if(cp == NIL){
		cp = mip->mi_macro_j;
		if(pdp->pd_flags & a_F_VVV)
			su_log_write(su_LOG_INFO, "%s%s: matching against j macro: %s",
				mip->mi_log_id, a_rm_head_names[rmt], cp);
	}

	mse = TRU1;
	for(; *cp != '\0'; cp += ++l){
		boole wildc;

		wildc = (*cp == '.');
		if(wildc){
			++cp;
			ASSERT(*cp != '\0'); /* Super-wildcard matcher handled via flag above */
		}
		/* Invalid matcher handled via flag above */
		else if(cp[0] == '!' && cp[1] == '\0'){
			l = 1;
			continue;
		}

		l = su_cs_len(cp);

		if(l == dl && !su_cs_cmp_case(cp, dat)){
			if(pdp->pd_flags & a_F_VV){
				snprintf(sbuf, sizeof sbuf, "exact match: %s", dat);
				emsg = sbuf;
			}
			goto jmark;
		}

		if(!wildc)
			continue;
		ASSERT(l > 0);

		for(dat2 = dat; (dat2 = su_cs_find_c(dat2, '.')) != NIL;)
			if(!su_cs_cmp_case(++dat2, cp)){
				if(pdp->pd_flags & a_F_VV){
					snprintf(sbuf, sizeof sbuf, "subdomain wildcard match: %s: %s", dat2, dat);
					emsg = sbuf;
				}
				goto jmark;
			}
	}

	if(pdp->pd_flags & a_F_VV){
		snprintf(sbuf, sizeof sbuf, "mismatch: %s", dat);
		emsg = sbuf;
	}
	mse = FAL0;

jmark:
	if(ls != NIL)
		su_imf_snap_gut(membp, ls);

	/* C99 */{
		u32 c, t;
		struct a_rm_head *rmhp;

		rmhp = mip->mi_rm_head[rmt];

		if(rmhp == NIL){
			c = 0;
			t = UZ_BITS >> 1;
			goto Jalloc;
		}else if((c = rmhp->rmh_cnt) + 1 >= (t = rmhp->rmh_top)) Jalloc:{
			struct a_rm_head *rmhpx;
			u32 x;

			x = (t <<= 1);
			x = su_BITS_TO_UZ(x) * sizeof(uz);
			rmhpx = S(struct a_rm_head*,su_LOFI_CALLOC(VSTRUCT_SIZEOF(struct a_rm_head,rmh_bits) + x));
			rmhpx->rmh_cnt = c;
			rmhpx->rmh_top = t;

			if(rmhp != NIL){
				x = su_BITS_WHICH_OFF(c) + 1;
				x *= sizeof(uz);
				su_mem_copy(rmhpx->rmh_bits, rmhp->rmh_bits, x);
			}

			mip->mi_rm_head[rmt] = rmhp = rmhpx;
		}

		rmhp->rmh_cnt = ++c;
		if(mse){
			*rmhp->rmh_bits |= 1u;
			su_bits_array_set(rmhp->rmh_bits, c);
		}

		if(pdp->pd_flags & a_F_VV)
			su_log_write(su_LOG_INFO, "%s%s %u%s%s: %s",
				mip->mi_log_id, a_rm_head_names[rmt],
				c, (emsg != NIL ? ": " : su_empty), (emsg != NIL ? emsg : su_empty),
				(mse ? "remove" : "keep"));
	}

	mse = su_EX_OK;

	NYD_OU;
	return mse;
} /* }}} */

static s32
a_milter__verify(struct a_milter *mip){ /* {{{ TODO stub */
	s32 rv;
	NYD_IN;

	rv = a_milter__rm_heads(mip, FAL0);

	NYD_OU;
	return rv;
} /* }}} */

static s32
a_milter__sign(struct a_milter *mip){ /* {{{ */
	struct a_pd *pdp;
	s32 rv;
	NYD_IN;

#if a_AUTO_RM
	rv = a_milter__rm_heads(mip, TRU1);
	if(rv != su_EX_OK)
		goto jleave;
#endif

	pdp = mip->mi_pdp;

	if(!a_dkim_push_body(mip->mi_dkim, NIL, 0, &mip->mi_bag)){
		rv = su_EX_TEMPFAIL;
		goto jleave;
	}

	if(UNLIKELY(pdp->pd_flags & a_F_VVV))
		su_log_write(su_LOG_INFO, "%screating DKIM signature(s)", mip->mi_log_id);

	if(a_dkim_sign(mip->mi_dkim, &mip->mi_buf[0], &mip->mi_bag)){
		struct a_dkim_res *dkrp;

		for(dkrp = mip->mi_dkim->d_sign_res; dkrp != NIL; dkrp = dkrp->dr_next){
			if(LIKELY(!(pdp->pd_flags & (a_F_REPRO | a_F_DBG)))){
				mip->mi_buf[0] = a_SMFIR_INSHEADER;
				mip->mi_buf[1] = mip->mi_buf[2] = mip->mi_buf[3] = mip->mi_buf[4] = '\0';
				su_mem_copy(&mip->mi_buf[5], dkrp->dr_dat, dkrp->dr_len);

				rv = a_milter__write(mip, 1 + 4 + dkrp->dr_len);
				if(rv != su_EX_OK)
					goto jleave;

				if(LIKELY(!(pdp->pd_flags & a_F_VV)))
					continue;
			}

			/* room for \015\012\0! */
			dkrp->dr_dat[dkrp->dr_name_len] = ':';
			dkrp->dr_dat[dkrp->dr_len - 1] = '\n';
			if(LIKELY(!(pdp->pd_flags & a_F_REPRO))){
				dkrp->dr_dat[dkrp->dr_len] = '\0';
				su_log_write(su_LOG_INFO, "%s%s", mip->mi_log_id, dkrp->dr_dat);
			}else
				fwrite(dkrp->dr_dat, sizeof(*dkrp->dr_dat), dkrp->dr_len, stdout);
		}
		rv = su_EX_OK;
	}else{
		su_log_write(su_LOG_CRIT, _("%serror creating DKIM signature, message unchanged"), mip->mi_log_id);
		rv = su_EX_TEMPFAIL;
	}

jleave:
	NYD_OU;
	return rv;
} /* }}} */

static s32
a_milter__rm_heads(struct a_milter *mip, boole only_autos){ /* {{{ */
	u32 i;
	struct a_pd *pdp;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;
	pdp = mip->mi_pdp;

	for(i = (only_autos ? a_RM_HEAD_USER_MAX : 0); i < a_RM_HEAD_MAX; ++i){
		struct a_rm_head *rmhp;

		if((rmhp = mip->mi_rm_head[i]) != NIL && (*rmhp->rmh_bits & 1u)){
			u32 mpl, otc, orc;

			if(UNLIKELY(pdp->pd_flags & a_F_VVV))
				su_log_write(su_LOG_INFO, "%sremoving: %s", mip->mi_log_id, a_rm_head_names[i]);

			UNINIT(mpl, 0);
			if(LIKELY(!(pdp->pd_flags & (a_F_REPRO | a_F_DBG)))){
				char *cp;

				mip->mi_buf[0] = a_SMFIR_CHGHEADER;
				cp = su_cs_pcopy(&mip->mi_buf[5], a_rm_head_names[i]);
				*++cp = '\0'; /* name\0[value]\0 */
				mpl = S(u32,P2UZ(++cp - &mip->mi_buf[0]));
			}

			for(otc = rmhp->rmh_cnt, orc = 0; otc > 0; --otc){
				/* 1-based */
				if(!su_bits_array_test(rmhp->rmh_bits, otc))
					continue;
				++orc;

				if(LIKELY(!(pdp->pd_flags & (a_F_REPRO | a_F_DBG)))){
					u32 bs;

					bs = su_boswap_net_32(otc);
					su_mem_copy(&mip->mi_buf[1], &bs, sizeof bs);
					rv = a_milter__write(mip, mpl);
					if(rv != su_EX_OK)
						goto jleave;

					if(LIKELY(!(pdp->pd_flags & a_F_VVV)))
						continue;
				}else if(UNLIKELY(pdp->pd_flags & a_F_REPRO))
					printf("SMFIR CHGHEADER %s %u\n", a_rm_head_names[i], otc);

				if(UNLIKELY(pdp->pd_flags & a_F_VVV))
					su_log_write(su_LOG_INFO, "%s%s: removed %u",
							mip->mi_log_id, a_rm_head_names[i], otc);
			}

			if(UNLIKELY(orc > 0 && (pdp->pd_flags & a_F_VV)))
				su_log_write(su_LOG_INFO, "%sremoved %u of %u %s headers",
						mip->mi_log_id, orc, rmhp->rmh_cnt, a_rm_head_names[i]);
		}
	}

jleave:
	NYD_OU;
	return rv;
} /* }}} */
/* }}} */

/* dkim {{{ */
static boole
a_dkim_setup(struct a_dkim *dkp, boole post_eoh, struct a_pd *pdp, struct su_mem_bag *membp, /* {{{ */
		char const *log_id){
	struct a_md *mdp;
	boole rv;
	NYD_IN;
	ASSERT(log_id != NIL);

	rv = TRU1;

	if(post_eoh != TRU1){
		STRUCT_ZERO(struct a_dkim, dkp);
		dkp->d_pdp = pdp;
	}

	dkp->d_log_id = log_id;

	if(post_eoh){
		/* (MD list reduced across keys..) */
		for(mdp = pdp->pd_mds; mdp != NIL; mdp = mdp->md_next){
			struct a_md_ctx *mdcp;

			/* --sign: no selectors: use all keys <> manual! */
			if(dkp->d_sign != NIL){
				uz i;
				struct a_sign *sp;

				for(sp = dkp->d_sign, i = 0;;){
					if(sp->s_sel[i].key == NIL){
						if(i == 0){
							if(UNLIKELY(dkp->d_pdp->pd_flags & a_F_VV))
								su_log_write(su_LOG_INFO,
									"%s--sign without selectors, using all keys",
									log_id);
							break;
						}
						goto jnext_md;
					}
					if(sp->s_sel[i].key->k_md == mdp)
						break;
					if(++i == a_SIGN_MAX_SELECTORS)
						goto jnext_md;
				}
			}

			mdcp = su_LOFI_TALLOC(struct a_md_ctx, 1);
			mdcp->mdc_next = dkp->d_sign_mdctxs;
			dkp->d_sign_mdctxs = mdcp;
			mdcp->mdc_md = mdp;
			/*mdcp->mdc_b_diglen = 0;*/

			mdcp->mdc_md_ctx = EVP_MD_CTX_new();
			if(mdcp->mdc_md_ctx == NIL)
				goto jbail;

			if(!EVP_DigestInit_ex(mdcp->mdc_md_ctx, mdp->md_md, NIL)){
jbail:
				su_log_write(su_LOG_CRIT, _("%scannot EVP_DigestInit_ex(3) message-digest %s: %s\n"),
					log_id, mdp->md_katp->kat_md_name, ERR_error_string(ERR_get_error(), NIL));
				a_dkim_cleanup(dkp);
				rv = FAL0;
				break;
			}
jnext_md:;
		}
		ASSERT(!rv || dkp->d_sign_mdctxs != NIL);
	}

	NYD_OU;
	return rv;
} /* }}} */

static void
a_dkim_cleanup(struct a_dkim *dkp){
	struct a_md_ctx *mdcp;
	NYD_IN;

	while((mdcp = dkp->d_sign_mdctxs) != NIL){
		dkp->d_sign_mdctxs = mdcp->mdc_next;
		if(mdcp->mdc_md_ctx != NIL)
			EVP_MD_CTX_free(mdcp->mdc_md_ctx);
	}

	NYD_OU;
}

static enum a_cli_action
a_dkim_push_header(struct a_dkim *dkp, char const *name, char const *dat, struct su_mem_bag *membp){ /* {{{ */
	enum a_cli_action clia;
	struct a_head *hp, *xhp;
	boole isfrom;
	uz dl, nl, i;
	NYD_IN;

	dl = su_cs_len(dat);
	nl = su_cs_len(name);
	isfrom = (nl == sizeof("from") -1 && !su_cs_cmp("from", name));

	/* With isfrom we are responsible for dkp->d_sign_from_domain storage */
	i = dl;
	if(isfrom){
		i = dkp->d_pdp->pd_sign_longest_domain;
		i = MAX(dl, i);
	}
	i += 2; /* ": " */
	i += nl;
	++i; /* NUL */
	if(isfrom)
		i <<= 1;
	hp = S(struct a_head*,su_LOFI_ALLOC(VSTRUCT_SIZEOF(struct a_head,h_name) + i));
	hp->h_next = hp->h_same_older = hp->h_same_newer = NIL;

	if((xhp = dkp->d_sign_head) == NIL){
		dkp->d_sign_head = hp;
		dkp->d_sign_htail = &hp->h_next;
	}else{
		do if(!su_cs_cmp(name, xhp->h_name)){
			/* Slot exists, link as oldest entry */
			isfrom = FAL0; /* TODO HACK multiple From: fields -> bogus mail! */
			while(xhp->h_same_older != NIL)
				xhp = xhp->h_same_older;
			xhp->h_same_older = hp;
			hp->h_same_newer = xhp;
			break;
		}while((xhp = xhp->h_next) != NIL);

		if(xhp == NIL){
			*dkp->d_sign_htail = hp;
			dkp->d_sign_htail = &hp->h_next;
		}
	}

	hp->h_dlen = S(u32,dl);
	hp->h_nlen = S(u32,nl);
	hp->h_dat = &su_cs_pcopy(hp->h_name, name)[1];
	dat = su_cs_pcopy(hp->h_dat, dat);

	clia = !isfrom ? a_CLI_ACT_NONE : a_dkim__parse_from(dkp, UNCONST(char*,++dat), hp->h_dat, membp);

	NYD_OU;
	return clia;
} /* }}} */

static enum a_cli_action
a_dkim__parse_from(struct a_dkim *dkp, char *store, char const *dat, struct su_mem_bag *membp){ /* {{{ */
	enum a_cli_action clia;
	char *dom, c;
	struct su_imf_addr *ap;
	s32 mse;
	void *ls;
	NYD_IN;

	ls = su_imf_snap_create(membp);

	/* 'Thing is, we need to dig it */
	mse = su_imf_parse_addr_header(&ap, dat, (su_IMF_MODE_RELAX | su_IMF_MODE_OK_DISPLAY_NAME_DOT |
			su_IMF_MODE_STOP_EARLY), membp, NIL);

	if((mse & su_IMF_ERR_CONTENT) || ap == NIL){
		su_log_write(su_LOG_CRIT, "%sFrom: address cannot be parsed, \"pass\"ing message: %s",
			dkp->d_log_id, dat);
		clia = a_CLI_ACT_PASS;
		goto jleave;
	}

	/* Yes, we take this */
	clia = a_CLI_ACT_SIGN;
	dkp->d_sign_from_domain = store;

	/* Normalize to lowercase, except for --domain-name that already is */
	for(dom = ap->imfa_domain; (c = *dom) != '\0'; ++dom)
		*dom = S(char,su_cs_to_lower(c));
	if((dom = dkp->d_pdp->pd_domain_name) == NIL)
		dom = ap->imfa_domain;

	/* Any --sign relations? */
	if(su_cs_dict_count(&dkp->d_pdp->pd_sign) > 0){
		struct a_sign *sp;
		boole any, first;
		char *buf, *cp, *dp;

		if(dkp->d_pdp->pd_flags & a_F_SIGN_LOCAL_PARTS){
			buf = S(char*,su_LOFI_ALLOC(ap->imfa_locpar_len + 1 + ap->imfa_domain_len +1));
			cp = su_cs_pcopy(buf, ap->imfa_locpar);
			*cp++ = '@';
		}else
			buf = cp/* UNINIT */ = NIL;
jdom_redo:
		dp = ap->imfa_domain;

		for(any = FAL0, first = TRU1;; first = FAL0){
			if(buf != NIL)
				su_cs_pcopy(cp, dp);
			sp = S(struct a_sign*,su_cs_dict_lookup(&dkp->d_pdp->pd_sign, (buf != NIL ? buf : dp)));
			if(sp != NIL && (first || sp->s_wildcard)){
				if(dkp->d_pdp->pd_flags & a_F_V)
					su_log_write(su_LOG_INFO,
						"%ssign %s match (From: (%s@)%s->%s): %s%s%s",
						dkp->d_log_id,
						(first ? "exact" : "wildcard"), ap->imfa_locpar, ap->imfa_domain, dom,
						(buf != NIL ? buf : (any ? "." : dp)),
						(sp->s_dom[0] != '\0' ? ", " : su_empty),
						(sp->s_dom[0] != '\0' ? sp->s_dom : su_empty));
				dkp->d_sign = sp;
				if(sp->s_dom[0] != '\0')
					dom = sp->s_dom;
				goto jsign;
			}

			if(any || !(dkp->d_pdp->pd_flags & a_F_SIGN_WILDCARDS))
				break;
			dp = su_cs_find_c(dp, '.');
			if(dp == NIL || *++dp == '\0'){
				any = TRU1;
				dp = UNCONST(char*,su_empty);
			}
		}

		if(buf != NIL){
			buf = NIL;
			goto jdom_redo;
		}

		if(dkp->d_pdp->pd_flags & a_F_V)
			su_log_write(su_LOG_INFO, "%ssign mismatch, DKIM=pass: (%s@)%s[->%s]",
				dkp->d_log_id, ap->imfa_locpar, ap->imfa_domain, dom);
		clia = a_CLI_ACT_PASS;
		goto jleave;
	}else{
		/* sign,localhost (verify,.) */
		if(!su_cs_cmp(ap->imfa_domain, a_localhost)){
			if(dkp->d_pdp->pd_flags & a_F_VV)
				su_log_write(su_LOG_INFO, "%sno sign and From: %s@localhost, DKIM=pass",
					dkp->d_log_id, ap->imfa_locpar);
			clia = a_CLI_ACT_PASS;
			goto jleave;
		}

		if(dkp->d_pdp->pd_flags & a_F_VV){
			boole xlog;

			xlog = (su_cs_cmp_case(dom, ap->imfa_domain) != 0);
			su_log_write(su_LOG_INFO, "%sno sign not @localhost (From: %s@%s%s%s%s), DKIM=sign",
				dkp->d_log_id, ap->imfa_locpar, ap->imfa_domain,
				(xlog ? "[->" : su_empty), (xlog ? dom : su_empty), (xlog ? "]" : su_empty));
		}
	}

jsign:
	ASSERT(clia == a_CLI_ACT_SIGN);
	su_cs_pcopy(store, dom);
jleave:
	su_imf_snap_gut(membp, ls);

	NYD_OU;
	return clia;
} /* }}} */

static boole
a_dkim_push_body(struct a_dkim *dkp, char *dp, uz dl, struct su_mem_bag *membp){ /* {{{ */
	/* a.	Reduce whitespace:
	 *	* Ignore all whitespace at the end of lines.
	 *	  Implementations MUST NOT remove the CRLF at the end of the line.
	 *	* Reduce all sequences of WSP within a line to a single SP character.
	 * b.	Ignore all empty lines at the end of the message body.
	 *	"Empty line" is defined in Section 3.4.3.  If the body is non-empty but does not end with a CRLF,
	 *	a CRLF is added.  (For email, this is only possible when using extensions to SMTP or non-SMTP transport
	 *	mechanisms.) */
	enum{
		a_NONE,
		a_CR_TAKEOVER = 1u<<0,
		a_LN_ANY = 1u<<1,
		a_LN_WS = 1<<2,
		a_LN_MASK = a_LN_ANY | a_LN_WS,

		a_KEEP_MASK = 0xFu,
		a_ERR = 1u<<5,
		a_BUF_ALLOC = 1u<<6,
		a_FINAL = 1u<<7
	};

	uz alloc_size;
	char *ob_base_alloc, *ob, *ob_base, eln_buf[128];
	u32 f, eln;
	NYD_IN;
	ASSERT((dl != 0 || dp == NIL) && (dp == NIL || dl != 0)); /* "finalization"? */

	f = dkp->d_sign_body_f;
	eln = dkp->d_sign_body_eln;
	UNINIT(ob_base_alloc, NIL);
	UNINIT(alloc_size, 0);

	ASSERT((!(f & a_CR_TAKEOVER) || eln == 0) && (eln == 0 || !(f & a_CR_TAKEOVER)));
	ASSERT(!(f & ~a_KEEP_MASK));

	/* "finalize"? */
	if(dl == 0){
		f |= a_FINAL;
		dl = 1;
		ob = ob_base = eln_buf;
		if(f & a_CR_TAKEOVER){
			*ob++ = '\015';
			f |= a_LN_ANY;
		}
		if(f & a_LN_ANY){
			ob[0] = '\015';
			ob[1] = '\012';
			ob += 2;
			f &= ~a_LN_MASK;
			goto jdigup;
		}
		goto jfinal;
	}

	for(ob = ob_base = dp; dl > 0; ++dp, --dl){
		char c;

		if((c = *dp) == '\015'){
			if(!(f & a_CR_TAKEOVER)){
				f |= a_CR_TAKEOVER;
				continue;
			}
		}

		if(LIKELY(!(f & a_CR_TAKEOVER))){
			if(su_cs_is_blank(c)){
				f |= a_LN_WS;
				continue;
			}
		}else{
			f ^= a_CR_TAKEOVER;
			if(LIKELY(c == '\012')){
				if(!(f & a_LN_ANY)){
					f &= ~a_LN_MASK;
					++eln;
					continue;
				}
				ASSERT(eln == 0);
				ob[0] = '\015';
				ob[1] = '\012';
				ob += 2;
				f &= ~a_LN_MASK;
				continue;
			}else{
				--dp;
				++dl;
				c = '\015';
			}
		}

		/* We store some data; there could be pending empty lines or what */
		if(LIKELY(eln == 0)){
jafter_eln:
			if(f & a_LN_WS){
				f ^= a_LN_WS;
				*ob++ = ' ';
			}
			f |= a_LN_ANY;
			*ob++ = c;
			continue;
		}else{
			/* Optimize usual case of non-trailing empty lines we skipped over */
			if(LIKELY(P2UZ(dp - ob) >= eln << 1)){
				for(; eln > 0; ob += 2, --eln){
					ob[0] = '\015';
					ob[1] = '\012';
				}
				goto jafter_eln;
			}

			--dp;
			++dl;

			/* xxx This likely (logically) does not happen */
			if(UNLIKELY(ob != ob_base)){
				if(c == '\015')
					f |= a_CR_TAKEOVER;
				goto jdigup;
			}
			ob = ob_base = eln_buf;

			if(UNLIKELY(eln >= sizeof(eln_buf) / 2)){
				if(!(f & a_BUF_ALLOC) || eln >= alloc_size >> 1){
					if(f & a_BUF_ALLOC)
						su_LOFI_FREE(ob_base_alloc);
					alloc_size = dkp->d_pdp->pd_key_md_maxsize_b64; /* xxx only if final, else 0?? */
					eln <<= 1;
					alloc_size = MAX(alloc_size, eln);
					eln >>= 1;
					ob_base_alloc = su_LOFI_TALLOC(char, alloc_size +1);
				}
				ob = ob_base = ob_base_alloc;
				f |= a_BUF_ALLOC;
			}

			for(; eln > 0; ob += 2, --eln){
				ob[0] = '\015';
				ob[1] = '\012';
			}
		}

jdigup:		/* C99 */{
			struct a_md_ctx *mdcp;

			for(mdcp = dkp->d_sign_mdctxs; mdcp != NIL; mdcp = mdcp->mdc_next){
				if(!EVP_DigestUpdate(mdcp->mdc_md_ctx, ob_base, P2UZ(ob - ob_base))){
					su_log_write(su_LOG_CRIT, _("%scannot EVP_DigestUpdate(3) for %s: %s\n"),
						dkp->d_log_id, mdcp->mdc_md->md_katp->kat_md_name,
						ERR_error_string(ERR_get_error(), NIL));
					f |= a_ERR;
					goto jleave;
				}
			}
		}
		ob = ob_base = dp;
	}

	if(ob != ob_base){
		dl = 1;
		goto jdigup;
	}

	if(f & a_FINAL){
		/*dl = 1;*/
		goto jfinal;
	}

jleave:
	dkp->d_sign_body_f = (f &= a_KEEP_MASK);
	dkp->d_sign_body_eln = eln;

	NYD_OU;
	return ((f &= a_ERR) == a_NONE);

jfinal:/* C99 */{
	struct a_md_ctx *mdcp;

	if(f & a_BUF_ALLOC)
		ob = ob_base_alloc;
	else{
		ob = eln_buf;
		alloc_size = sizeof(eln_buf);
	}
	if(alloc_size <= dkp->d_pdp->pd_key_md_maxsize)
		ob = su_LOFI_TALLOC(char, dkp->d_pdp->pd_key_md_maxsize +1);

	for(mdcp = dkp->d_sign_mdctxs; mdcp != NIL; mdcp = mdcp->mdc_next){
		u32 obl;

		obl = 0; /* xxx out only */
		if(!EVP_DigestFinal(mdcp->mdc_md_ctx, R(uc*,ob), &obl)){
			su_log_write(su_LOG_CRIT, _("%scannot EVP_DigestFinal(3) %s: %s\n"),
				dkp->d_log_id, mdcp->mdc_md->md_katp->kat_md_name,
				ERR_error_string(ERR_get_error(), NIL));
			f |= a_ERR;
			goto jleave;
		}
		mdcp->mdc_b_diglen = S(u32,EVP_EncodeBlock(R(uc*,mdcp->mdc_b_digdat), R(uc*,ob), S(int,obl)));
	}
	}goto jleave;
} /* }}} */

static boole
a_dkim_sign(struct a_dkim *dkp, char *mibuf, struct su_mem_bag *membp){ /* {{{ */
	struct su_timespec ts, ts_exp;
	union {u32 sl32; uz slz; char const *cp;} a;
	uc *sigp, *b64sigp;
	struct a_head *hp, *xhp;
	uz i, dfromdlen;
	struct a_key *kp;
	struct a_md_ctx *mdcp;
	char *dkim_start, *dkim_var_start, *dkim_res_start, itoa_buf[su_IENC_BUFFER_SIZE];
	struct a_pd *pdp;
	boole rv;
	NYD_IN;

	rv = FAL0;
	pdp = dkp->d_pdp;

	/* (Cannot overflow on earth) */
	if(pdp->pd_flags & a_F_REPRO){
		ts.ts_sec = pdp->pd_source_date_epoch;
		ts.ts_nano = 0;
	}else
		su_timespec_current(&ts);
	ts_exp.ts_sec = (pdp->pd_dkim_sig_ttl != 0 ? ts.ts_sec + pdp->pd_dkim_sig_ttl : 0);
	ts_exp.ts_nano = 0;

	/* Because of algorithms which use non-configurable message-digests and/or need a complete data copy for
	 * multiple iterations on it we need a readily prepared single chunk version of all headers.
	 * Since we have to do this, include digest/signature ouput and base64 variants in that heap, too.
	 * And if really the milter buffer is not large enough, do a single allocation */

	for(hp = dkp->d_sign_head; (xhp = hp) != NIL; hp = hp->h_next){
		do
			dkp->d_sign_head_totlen += xhp->h_nlen + 1 + xhp->h_dlen + 1 + 1; /* xxx wrap */
		while((xhp = xhp->h_same_newer) != NIL);
	}
	a.cp = pdp->pd_header_seal;
	if(a.cp != NIL){
		for(;;){
			uz j;

			j = su_cs_len(a.cp) +1;
			dkp->d_sign_head_totlen += j + 1 + 1 + 1;
			a.cp += j;
			if(*a.cp == '\0')
				break;
		}
	}

	/* Do fully populated DKIM-Signature: (twice: normal and normalized) and tmp heap fit? */
	dfromdlen = su_cs_len(dkp->d_sign_from_domain);
	i = dkp->d_sign_head_totlen + pdp->pd_key_md_maxsize + pdp->pd_key_md_maxsize_b64 + pdp->pd_key_sel_len_max +
			3*80/* xxx fuzzy*/ + dfromdlen;
	i <<= 1;
	if(i >= a_MILTER_CHUNK_SIZE){
		i = ALIGN_PAGE(i);
		mibuf = S(char*,su_LOFI_ALLOC(i));
	}DVL(else i = a_MILTER_CHUNK_SIZE - 1;)

	sigp = R(uc*,mibuf);
	b64sigp = &sigp[pdp->pd_key_md_maxsize];

	dkim_start = R(char*,&b64sigp[pdp->pd_key_md_maxsize_b64]);
	dkim_var_start = dkim_start;
	dkim_res_start = &dkim_start[i >> 1]; /* should be sufficient anyway! */

	/* All right, prepare the headers.  RFC 6376, 5.4.2: from bottom up */
	for(hp = dkp->d_sign_head; hp != NIL; hp = hp->h_next){
		xhp = hp;
		while(xhp->h_same_older != NIL)
			xhp = xhp->h_same_older;
		do
			a_dkim__head_prep(dkp, hp->h_name, xhp->h_dat, &dkim_var_start, TRU1);
		while((xhp = xhp->h_same_newer) != NIL);
	}

	/* And so finally we iterate the keys and create a DKIM-Signature: for them all */
	for(kp = pdp->pd_keys; kp != NIL; kp = kp->k_next){
		uz const min_len_long_seq = 40;

		char *cp, *cpx, *dkim_end;
		struct a_dkim_res *dkrp;

		/* Key might be --sign constrained though */
		if(dkp->d_sign != NIL && dkp->d_sign->s_anykey){
			struct a_sign *sp;

			for(sp = dkp->d_sign, i = 0;;){
				if(sp->s_sel[i].key == NIL)
					goto jnext_key; /* "continue outer" */
				if(sp->s_sel[i].key == kp)
					break;
				if(++i == a_SIGN_MAX_SELECTORS)
					goto jnext_key;
			}
		}

		/* Find MD for it */
		for(mdcp = dkp->d_sign_mdctxs; mdcp->mdc_md != kp->k_md; mdcp = mdcp->mdc_next){
			ASSERT(mdcp->mdc_next != NIL);
		}

		cp = dkim_res_start;
		cp = su_cs_pcopy(cp, "v=1; a=");
		cp = su_cs_pcopy(cp, kp->k_katp->kat_pkey_name);
		*cp++ = '-';
		cp = su_cs_pcopy(cp, kp->k_katp->kat_md_name);
		cp = su_cs_pcopy(cp, "; c=relaxed/relaxed");

		/* This is ok only because it surely is far inside the buffer! */
		cpx = &dkim_res_start[-sizeof("dkim-signature:")];

		*cp++ = ';';
		if(P2UZ(cp - cpx) + sizeof(" d=") -1 + dfromdlen < 78 - 3)
			*cp++ = ' ';
		else{
			/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp += 2;
			cpx = cp;
		}
		cp[0] = 'd'; cp[1] = '='; cp += 2;
		cp = su_cs_pcopy(cp, dkp->d_sign_from_domain);

		*cp++ = ';';
		if(P2UZ(cp - cpx) + sizeof(" s=") -1 + kp->k_sel_len < 78 - 3)
			*cp++ = ' ';
		else{
			/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp += 2;
			cpx = cp;
		}
		cp[0] = 's'; cp[1] = '='; cp += 2;
		cp = su_cs_pcopy(cp, kp->k_sel);

		*cp++ = ';';
		if(P2UZ(cp - cpx) + sizeof(" t=") -1 + 20 < 78 - 3)
			*cp++ = ' ';
		else{
			/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp += 2;
			cpx = cp;
		}
		cp[0] = 't'; cp[1] = '='; cp += 2;
		cp = su_cs_pcopy(cp, su_ienc_u64(itoa_buf, S(u64,ts.ts_sec), 10));

		if(ts_exp.ts_sec != 0){
			*cp++ = ';';
			if(P2UZ(cp - cpx) + sizeof(" x=") -1 + 20 < 78 - 3)
				*cp++ = ' ';
			else{
				/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp += 2;
				cpx = cp;
			}
			cp[0] = 'x'; cp[1] = '='; cp += 2;
			cp = su_cs_pcopy(cp, su_ienc_u64(itoa_buf, S(u64,ts_exp.ts_sec), 10));
		}

		*cp++ = ';';
		if(P2UZ(cp - cpx) + sizeof(" h=from:") < 78 - 3)
			*cp++ = ' ';
		else{
			/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp += 2;
			cpx = cp;
		}
		cp[0] = 'h'; cp[1] = '='; cp += 2;
		for(hp = dkp->d_sign_head; (xhp = hp) != NIL; hp = hp->h_next){
			do{
				char *old;

				if(xhp != hp || hp != dkp->d_sign_head)
					*cp++ = ':';
				for(old = cp;;){
					cp = su_cs_pcopy(cp, hp->h_name);
					if(P2UZ(cp - cpx) < 78 - 4)
						break;
					cp = old;
					/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp[2] = ' '; cp += 3;
					cpx = cp;
				}
			}while((xhp = xhp->h_same_older) != NIL);
		}

		a.cp = pdp->pd_header_seal;
		if(a.cp != NIL){
			char *old;

			*cp++ = ':';
			for(old = cp;;){
				cp = su_cs_pcopy(cp, a.cp);
				if(P2UZ(cp - cpx) >= 78 - 4){
					cp = old;
					/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp[2] = ' '; cp += 3;
					cpx = cp;
				}else{
					a.cp += su_cs_len(a.cp) +1;
					if(*a.cp == '\0')
						break;
					*cp++ = ':';
					old = cp;
				}
			}
		}

		*cp++ = ';';
		if(P2UZ(cp - cpx) + sizeof(" bh=") <= min_len_long_seq)
			*cp++ = ' ';
		else{
			/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp += 2;
			cpx = cp;
		}
		cp[0] = 'b'; cp[1] = 'h'; cp[2] = '='; cp += 3;
		if(P2UZ(cp - cpx) + mdcp->mdc_b_diglen <= 78 - 3)
			cp = su_cs_pcopy(cp, mdcp->mdc_b_digdat);
		else{
			char c;
			char const *sp;

			for(sp = mdcp->mdc_b_digdat; (c = *sp++) != '\0'; ++i){
				if(P2UZ(cp - cpx) >= 78 - 4){
					/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp[2] = ' '; cp += 3;
					cpx = cp;
				}
				*cp++ = c;
			}
		}

		/* Finished setup! */
		*cp++ = ';';
		if(P2UZ(cp - cpx) <= min_len_long_seq)
			*cp++ = ' ';
		else{
			/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp += 2;
			cpx = cp;
		}
		cp[0] = 'b'; cp[1] = '='; cp += 2;
		*cp = '\0';

		dkim_end = dkim_var_start;

		a_dkim__head_prep(dkp, "DKIM-Signature", dkim_res_start, &dkim_end, FAL0);

		/* C99 */{
			EVP_MD const *mdp;
			uz dl;
			uc *dp;

			dp = R(uc*,dkim_start);
			dl = P2UZ(dkim_end - dkim_start);

			if(kp->k_katp->kat_extern_md){
				mdp = mdcp->mdc_md->md_md;

				EVP_MD_CTX_reset(mdcp->mdc_md_ctx);
				if(!EVP_DigestInit_ex(mdcp->mdc_md_ctx, mdp, NIL) ||
						!EVP_DigestUpdate(mdcp->mdc_md_ctx, dp, dl) ||
						!EVP_DigestFinal(mdcp->mdc_md_ctx, b64sigp, &a.sl32)){
					su_log_write(su_LOG_CRIT,
						_("%scannot handle non-adaptive EVP_Digest*(3) %s-%s(=%s=%s): %s\n"),
						dkp->d_log_id, kp->k_katp->kat_name, kp->k_katp->kat_md_name,
						kp->k_sel, kp->k_file, ERR_error_string(ERR_get_error(), NIL));
					goto jleave;
				}

				dp = b64sigp;
				dl = a.sl32;
			}

			mdp = kp->k_katp->kat_sign_md ? mdcp->mdc_md->md_md : NIL;

			EVP_MD_CTX_reset(mdcp->mdc_md_ctx);
			if(!EVP_DigestSignInit(mdcp->mdc_md_ctx, NIL, mdp, NIL, kp->k_key)){
jesifi:
				su_log_write(su_LOG_CRIT,
					_("%scannot EVP_DigestSign(Init)?(3) %s-%s(=%s=%s): %s\n"),
					dkp->d_log_id, kp->k_katp->kat_name, kp->k_katp->kat_md_name,
					kp->k_sel, kp->k_file, ERR_error_string(ERR_get_error(), NIL));
				goto jleave;
			}

			a.slz = pdp->pd_key_md_maxsize;
			if(!EVP_DigestSign(mdcp->mdc_md_ctx, sigp, &a.slz, dp, dl))
				goto jesifi;
		}
		i = S(uz,EVP_EncodeBlock(b64sigp, sigp, S(int,a.slz))) +1;

		/* Finalize writing " b=" */
		/* C99 */{
			char c;
			char const *sp;

			for(sp = R(char*,b64sigp); (c = *sp++) != '\0'; ++i){
				if(P2UZ(cp - cpx) >= 78 - 4){
					/*cp[0] = '\015'; */cp[0] = '\012'; cp[1] = ' '; cp[2] = ' '; cp += 3;
					cpx = cp;
				}
				*cp++ = c;
			}
		}

		/*cp[0] = '\015'; *cp[1] = '\012'; *cp += 2;*/
		*cp = '\0';

		/* Result! */
		i = P2UZ(cp - dkim_res_start) +1;
		dkrp = S(struct a_dkim_res*,su_LOFI_ALLOC(VSTRUCT_SIZEOF(struct a_dkim_res,dr_dat) +
				sizeof("DKIM-Signature") -1 + i + 2 +1));
		dkrp->dr_next = dkp->d_sign_res;
		dkp->d_sign_res = dkrp;
		dkrp->dr_name_len = sizeof("DKIM-Signature") -1;
		dkrp->dr_len = S(u32,sizeof("DKIM-Signature") + i);
		su_mem_copy(&su_cs_pcopy(dkrp->dr_dat, "DKIM-Signature")[1], dkim_res_start, i);
		dkrp->dr_dat[dkrp->dr_len] = '\0';
		if(pdp->pd_flags & a_F_VV)
			su_log_write(su_LOG_INFO, "%sDKIM create ok: %s-%s(=%s=%s)\n",
				dkp->d_log_id, kp->k_katp->kat_name, kp->k_katp->kat_md_name, kp->k_sel, kp->k_file);
jnext_key:;
	}

	rv = TRU1;
jleave:
	NYD_OU;
	return rv;
} /* }}} */

static void
a_dkim__head_prep(struct a_dkim *dkp, char const *np, char const *dp, char **mibuf, boole trail_crlf){ /* {{{ */
	boole ws;
	char const *cp;
	char *to, c;
	NYD_IN;
	UNUSED(dkp);

	to = *mibuf;

	/* Convert name to lower case */
	for(cp = np; (c = *cp) != '\0'; ++cp){
		/*if(su_cs_is_blank(c)) @HVALWS
		 *	break;*/
		*to++ = S(char,su_cs_to_lower(c));
	}
	*to++ = ':';

	cp = dp;
	/* Skip leading blanks as such */
	while(su_cs_is_blank(*cp))
		++cp;
	/* Unfold continuation lines, squeeze WSP, drop WSP at EOL */
	for(ws = FAL0;;){
		c = *cp++;

		if(c == '\0')
			break;

		/* The milter protocol (may) pass(es) continuation only via LF; "unfold" that */
		if(c == '\012')
			continue;
		if(c == '\015' && *cp == '\012'){
			++cp;
			continue;
		}

		if(su_cs_is_blank(c)){
			ws = TRU1;
			continue;
		}

		if(ws)
			*to++ = ' ';
		ws = FAL0;
		*to++ = c;
	}
	ASSERT(to[-1] != ' ');

	/* Terminate with single CRLF */
	if(trail_crlf){
		to[0] = '\015';
		to[1] = '\012';
		to += 2;
	}
	*to = '\0'; /* (for debug etc) */

	*mibuf = to;

	NYD_OU;
} /* }}} */
/* }}} */

/* conf {{{ */
static void
a_conf_setup(struct a_pd *pdp, boole init){
	NYD_IN;

	pdp->pd_flags &= ~S(uz,a_F_SETUP_MASK);
	if(su_state_has(su_STATE_REPRODUCIBLE))
		pdp->pd_flags |= a_F_REPRO;

	if(init){
		su_cs_dict_create(&pdp->pd_cli, su_CS_DICT_HEAD_RESORT, NIL);
		su_cs_dict_create(&pdp->pd_sign, su_CS_DICT_HEAD_RESORT, NIL);
	}

	su_cs_dict_add_flags(&pdp->pd_cli, su_CS_DICT_FROZEN);
	su_cs_dict_add_flags(&pdp->pd_sign, su_CS_DICT_FROZEN);

	NYD_OU;
}

static s32
a_conf_finish(struct a_pd *pdp){ /* {{{ */
	struct su_cs_dict_view dv;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;

	if(pdp->pd_keys == NIL && !su_state_has(su_STATE_REPRODUCIBLE)){
		a_conf__err(pdp, _("At least one --key is required\n"));
		pdp->pd_flags |= a_F_TEST_ERRORS;
		rv = su_EX_CONFIG;
		if(!(pdp->pd_flags & a_F_MODE_TEST))
			goto jleave;
	}
	pdp->pd_key_md_maxsize = MAX(pdp->pd_key_md_maxsize, EVP_MAX_MD_SIZE); /* XXX we can do latter better! */
	pdp->pd_key_md_maxsize_b64 = ((pdp->pd_key_md_maxsize +3) * 4) / 3 +1 +1;

	/* */
	su_cs_dict_balance(&pdp->pd_cli);

	/* --sign selectors must resolve to keys */
	su_cs_dict_balance(&pdp->pd_sign);
	su_CS_DICT_FOREACH(&pdp->pd_sign, &dv){
		u32 i;
		struct a_sign *sp;

		sp = S(struct a_sign*,su_cs_dict_view_data(&dv));

		if(!sp->s_anykey)
			continue;

		for(i = 0; i < a_SIGN_MAX_SELECTORS; ++i){
			struct a_key *kp;
			char const *sel;

			sel = sp->s_sel[i].name;
			if(sel == NIL)
				break;

			for(kp = pdp->pd_keys;; kp = kp->k_next){
				if(kp == NIL){
					a_conf__err(pdp, _("--sign: selector does not resolve to key: %s\n"), sel);
					sp->s_sel[i].key = NIL; /* --test-mode! */
					pdp->pd_flags |= a_F_TEST_ERRORS;
					rv = -su_EX_DATAERR;
					break;
				}else if(!su_cs_cmp(kp->k_sel, sel)){
					sp->s_sel[i].key = kp;
					break;
				}
			}
		}
	}

	/* non-test mode shortcut */
	if(LIKELY(!(pdp->pd_flags & a_F_MODE_TEST)))
		goto jleave;

	/* --header-seal: verify members are part of --header-sign */
	if(pdp->pd_header_seal != NIL){
		char const *sea, *sig;

		for(sea = pdp->pd_header_seal;;){
			sig = pdp->pd_header_sign;
			if(sig == NIL)
				sig = a_header_sigsea[a_HEADER_SIGSEA_OFF_SIGN];

			for(;;){
				if(!su_cs_cmp(sig, sea))
					break;
				sig += su_cs_len(sig) +1;
				if(*sig == '\0'){
					a_conf__err(pdp, _("--header-seal: %s is not part of --header-sign\n"), sea);
					pdp->pd_flags |= a_F_TEST_ERRORS;
					rv = su_EX_CONFIG;
					break;
				}
			}

			sea += su_cs_len(sea) +1;
			if(*sea == '\0')
				break;
		}
	}

	if(pdp->pd_flags & a_F_RM_ANY){
		u32 rmt;

		for(rmt = 0; rmt <= a_RM_HEAD_TOP_MATCHED; ++rmt){
			if(pdp->pd_flags & a_RM_HEAD_TYPE_TO_ANY_FLAG(rmt)){
				if(pdp->pd_rm[rmt][0] != '.' || pdp->pd_rm[rmt][1] != '\0' ||
						pdp->pd_rm[rmt][2] != '\0'){
					a_conf__err(pdp, _("--remove: . implies anything else, including !: %s\n"),
						a_rm_head_names[rmt]);
					pdp->pd_flags |= a_F_TEST_ERRORS;
				}
			}
		}
	}

jleave:
	NYD_OU;
	return rv;
} /* }}} */

#if DVLOR(DBGXOR(1, 0), 0)
static void
a_conf_cleanup(struct a_pd *pdp){ /* {{{ */
	struct su_cs_dict_view dv;
	struct a_srch *sp;
	struct a_md *mdp;
	struct a_key *kp;
	NYD_IN;

	if(pdp->pd_domain_name != NIL)
		su_FREE(pdp->pd_domain_name);

	if(pdp->pd_header_sign != NIL)
		su_FREE(pdp->pd_header_sign);
	if(pdp->pd_header_seal != NIL)
		su_FREE(pdp->pd_header_seal);

	if(pdp->pd_mima_sign != NIL)
		su_FREE(pdp->pd_mima_sign);
	if(pdp->pd_mima_verify != NIL)
		su_FREE(pdp->pd_mima_verify);

	if(pdp->pd_flags & a_F_RM_ANY){
		u32 i;

		for(i = 0; i < NELEM(pdp->pd_rm); ++i)
			if(pdp->pd_rm[i] != NIL)
				su_FREE(pdp->pd_rm[i]);
	}

	while((kp = pdp->pd_keys) != NIL){
		pdp->pd_keys = kp->k_next;
		EVP_PKEY_free(kp->k_key);
		su_FREE(kp);
	}

	while((mdp = pdp->pd_mds) != NIL){
		pdp->pd_mds = mdp->md_next;
# ifdef a_MD_FETCH
		EVP_MD_free(UNCONST(EVP_MD*,mdp->md_md));
# endif
		su_FREE(mdp);
	}

	while((sp = pdp->pd_cli_ip) != NIL){
		pdp->pd_cli_ip = sp->s_next;
		su_FREE(sp);
	}
	pdp->pd_cli_ip_tail = NIL;
	su_cs_dict_gut(&pdp->pd_cli);

	su_CS_DICT_FOREACH(&pdp->pd_sign, &dv)
		su_FREE(su_cs_dict_view_data(&dv));
	su_cs_dict_gut(&pdp->pd_sign);

	NYD_OU;
} /* }}} */
#endif /* DVLOR(DBGXOR(1, 0), 0) */

static s32
a_conf_list_values(struct a_pd *pdp){ /* {{{ */
	struct su_cs_dict_view dv;
	uz i, j;
	char const **arr, *cp;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;

	j = su_cs_dict_count(&pdp->pd_cli);
	i = su_cs_dict_count(&pdp->pd_sign);
	i = MAX(i, j);
	arr = (i > 0) ? su_TALLOC(char const*, ++i) : NIL;

	fprintf(stdout,
		"%s"
		"%s""%s""%s"
		,
		(pdp->pd_flags & a_F_DBG ? "debug\n" : su_empty),
		(pdp->pd_flags & a_F_V ? "verbose\n" : su_empty),
			(pdp->pd_flags & a_F_VV ? "verbose\n" : su_empty),
			(pdp->pd_flags & a_F_VVV ? "verbose\n" : su_empty));

	/* C99 */{
		struct a_key *kp;

		for(kp = pdp->pd_keys; kp != NIL; kp = kp->k_next)
			fprintf(stdout, "key %s-%s, %s,%s%s\n", kp->k_katp->kat_name, kp->k_katp->kat_md_name,
				kp->k_sel, ((kp->k_sel_len > 25 || su_cs_len(kp->k_file) > 25) ? "\\\n\t" : " "),
				kp->k_file);
	}

	if((cp = pdp->pd_mima_sign) != NIL)
		a_conf__list_cpxarr("milter-macro sign,", NIL, cp, FAL0);
	if((cp = pdp->pd_mima_verify) != NIL)
		a_conf__list_cpxarr("milter-macro verify,", NIL, cp, FAL0);

	/* --client {{{ */
	if(pdp->pd_flags & (a_F_CLI_DOMAINS | a_F_CLI_IPS)){
		uz cnt;

		cnt = 0;
		su_CS_DICT_FOREACH(&pdp->pd_cli, &dv)
			arr[cnt++] = su_cs_dict_view_key(&dv);
		arr[cnt] = NIL;
		su_sort_shell_vpp(R(void const**,arr), cnt, su_cs_toolbox.tb_cmp);

		for(cnt = 0; arr[cnt] != NIL; ++cnt){
			union {void *vp; uz f;} u;
			char const *spec;

			spec = arr[cnt];
			u.vp = su_cs_dict_lookup(&pdp->pd_cli, spec);

			i = su_cs_len(spec);
			if(u.f & (a_SRCH_IPV4 | a_SRCH_IPV6)){
				ASSERT(u.f & a_SRCH_EXACT);
				--i;
				ASSERT(spec[i] == '\06');
			}

			fprintf(stdout, "client %s, %s%.*s\n",
				(u.f & a_SRCH_VERIFY ? "verify" : (u.f & a_SRCH_PASS ? "pass" : "sign")),
				(u.f & a_SRCH_EXACT ? su_empty : "."),
				S(int,i), spec);
		}

		if(pdp->pd_cli_ip != NIL)
			fputc('\n', stdout);
	}
	/* C99 */{
		char buf[INET6_ADDRSTRLEN];
		struct a_srch *sp;

		for(sp = pdp->pd_cli_ip; sp != NIL; sp = sp->s_next){
			cp = inet_ntop((sp->s_type & a_SRCH_IPV4 ? AF_INET : AF_INET6),
					(sp->s_type & a_SRCH_IPV4 ? S(void*,&sp->s_ip.v4)
						: S(void*,&sp->s_ip.v6)), buf, sizeof(buf));
			if(cp == NIL){
				a_conf__err(pdp, _("--client: error displaying IP address\n"));
				rv = su_EX_OSERR;
				continue;
			}
			fprintf(stdout, "client %s, %s/%u\n",
				(sp->s_type & a_SRCH_VERIFY ? "verify" :
					(sp->s_type & a_SRCH_PASS ? "pass" : "sign")), cp, sp->s_mask);
		}
	} /* }}} */

	if(pdp->pd_domain_name != NIL)
		fprintf(stdout, "domain-name %s\n", pdp->pd_domain_name);

	/* --sign {{{ */
	if(su_cs_dict_count(&pdp->pd_sign) > 0){
		uz cnt;

		cnt = 0;
		su_CS_DICT_FOREACH(&pdp->pd_sign, &dv)
			arr[cnt++] = su_cs_dict_view_key(&dv);
		arr[cnt] = NIL;
		su_sort_shell_vpp(R(void const**,arr), cnt, su_cs_toolbox.tb_cmp);

		for(cnt = 0; arr[cnt] != NIL; ++cnt){
			struct a_sign *sp;
			char const *spec;

			spec = arr[cnt];
			sp = S(struct a_sign*,su_cs_dict_lookup(&pdp->pd_sign, spec));

			if(pdp->pd_flags & a_F_VV)
				fprintf(stdout, "# %s%s%s\n",
					(sp->s_wildcard ? "wildcard" : "exact"),
					(sp->s_spec_dom_off != 0 ? ", has local-part, domain is: " : su_empty),
					(sp->s_spec_dom_off != 0 ? &spec[sp->s_spec_dom_off] : su_empty));

			fputs("sign ", stdout);
			j = sizeof("sign ") -1;

			if(sp->s_spec_dom_off == 0){
				if(sp->s_wildcard){
					putc('.', stdout);
					++j;
				}
				fputs(spec, stdout);
				j += su_cs_len(spec);
			}else
				j += S(uz,fprintf(stdout, "%.*s@%s%s", S(int,sp->s_spec_dom_off - 1), spec,
						(sp->s_wildcard ? "." : su_empty), &spec[sp->s_spec_dom_off]));

			if(*sp->s_dom != '\0' || sp->s_anykey){
				putc(',', stdout);
				++j;
				if(*sp->s_dom != '\0'){
					putc(' ', stdout);
					fputs(sp->s_dom, stdout);
					j += su_cs_len(sp->s_dom);
				}

				if(sp->s_anykey){
					putc(',', stdout);
					++j;
					for(i = 0; i < a_SIGN_MAX_SELECTORS; ++i){
						uz k;

						if(sp->s_sel[i].key == NIL)
							break;

						k = sp->s_sel[i].key->k_sel_len;
						if(j + k >= 72){
							if(i != 0)
								putc(':', stdout);
							putc('\\', stdout); putc('\n', stdout); putc('\t', stdout);
							j = 8;
						}else{
							putc((i != 0 ? ':' : ' '), stdout);
							++j;
						}
						j += k;
						fputs(sp->s_sel[i].key->k_sel, stdout);
					}
				}
			}

			putc('\n', stdout);
		}
	} /* }}} */

	/* --header-{sign,seal} {{{ */
	/* C99 */{
		char *base;

		base = pdp->pd_header_sign;
jhredo:
		if(base != NIL){
			j = S(uz,fprintf(stdout, "header-%s ", (base == pdp->pd_header_sign ? "sign" : "seal")));
			for(cp = base;;){
				i = su_cs_len(cp) +1;
				if(j + i > 72){
					putc(',', stdout); putc('\\', stdout); putc('\n', stdout); putc('\t', stdout);
					j = 8;
				}else if(cp != base){
					putc(',', stdout); putc(' ', stdout);
					j += 2;
				}

				fputs(cp, stdout);
				cp += i;
				j += i;
				if(*cp == '\0')
					break;
			}
			putc('\n', stdout);
		}

		if(base != pdp->pd_header_seal && (base = pdp->pd_header_seal) != NIL)
			goto jhredo;
	} /* }}} */

	if(pdp->pd_dkim_sig_ttl != 0)
		fprintf(stdout, "ttl %lu\n", S(ul,pdp->pd_dkim_sig_ttl));

	if(pdp->pd_flags & a_F_RM_ANY){
		for(i = 0; i < NELEM(pdp->pd_rm); ++i)
			if((cp = pdp->pd_rm[i]) != NIL)
				a_conf__list_cpxarr("remove ", a_rm_head_ids[i], cp, TRU1);
	}

	if(arr != NIL)
		su_FREE(arr);

	if(rv == su_EX_OK && ferror(stdout))
		rv = su_EX_IOERR;

	NYD_OU;
	return rv;
} /* }}} */

static void
a_conf__list_cpxarr(char const *name, const char *name2_or_nil, char const *cp, boole comma_sep){ /* {{{ */
	uz j, i;
	NYD_IN;

	fputs(name, stdout);
	j = su_cs_len(name);

	if(name2_or_nil != NIL){
		fputs(name2_or_nil, stdout);
		j += su_cs_len(name2_or_nil);
	}

	for(;; comma_sep = TRU1, j += i, cp += i){
		if(*cp == '\0')
			break;

		i = su_cs_len(cp) +1;
		putc((comma_sep ? ',' : ' '), stdout);
		if(j + i > 72){
			putc('\\', stdout); putc('\n', stdout); putc('\t', stdout);
			j = 8;
		}else if(comma_sep){
			putc(' ', stdout);
			++j;
		}
		fputs(cp, stdout);
	}
	putc('\n', stdout);

	NYD_OU;
} /* }}} */

static s32
a_conf_arg(struct a_pd *pdp, s32 o, char *arg){ /* {{{ */
	union {char *cp; uz i; u32 f;} x;
	NYD_IN;

	/* In long-option order */
	switch(o){
	default: break;
	case 'C': o = a_conf__C(pdp, arg, NIL); break;
	case 'c': o = a_conf__c(pdp, arg); break;

	case 'd':
		if(!a_misc_is_rfc5321_domain(arg)){
			a_conf__err(pdp, _("--domain-name: invalid RFC 5321 domain name: %s\n"), arg);
			o = -su_EX_DATAERR;
			break;
		}
		if((x.cp = pdp->pd_domain_name) != NIL)
			su_FREE(x.cp);
		/* Normalize to lowercase */
		for(x.cp = arg; *x.cp != '\0'; ++x.cp)
			*x.cp = S(char,su_cs_to_lower(*x.cp));
		x.i = P2UZ(x.cp - arg);
		pdp->pd_sign_longest_domain = MAX(pdp->pd_sign_longest_domain, S(u32,x.i));
		pdp->pd_domain_name = su_cs_dup(arg, 0);
		break;

	case '~': o = a_conf__header_sigsea(pdp, arg, TRU1); break;
	case '!': o = a_conf__header_sigsea(pdp, arg, FAL0); break;

	case 'k': o = a_conf__k(pdp, arg); break;

	case 'M': o = a_conf__M(pdp, arg); break;

	case 'R': o = a_conf__R(pdp, arg); break;

	case 'r': o = a_conf__r(pdp, arg); break;

	case 'S': o = a_conf__S(pdp, arg); break;
	case 's': o = a_conf__s(pdp, arg); break;

	case 't':
		/* Adjust manual on change; ensure time_current()+X 64-bit overflow "cannot happen" */
		if((su_idec_u32(&pdp->pd_dkim_sig_ttl, arg, UZ_MAX, 10, NIL
					) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)) != su_IDEC_STATE_CONSUMED ||
				pdp->pd_dkim_sig_ttl < 30 || pdp->pd_dkim_sig_ttl > su_TIME_DAY_SECS * 1000){
			a_conf__err(pdp, _("--ttl: not a number, or not inside 30 seconds .. 1000 days: %s\n"), arg);
			o = -su_EX_DATAERR;
		}
		break;

	case -3: o = -o; pdp->pd_flags |= a_F_DBG; break;
	case -4:
		o = -o;
		x.f = pdp->pd_flags;
#if DVLDBGOR(0, 1)
		if(!(x.f & a_F_V))
			su_log_set_level(su_LOG_INFO);
#endif
		x.f = ((x.f << 1) | a_F_V) & a_F_V_MASK;
		pdp->pd_flags = (pdp->pd_flags & ~S(uz,a_F_V_MASK)) | x.f;
		break;
	}

	if(o < 0 && (pdp->pd_flags & a_F_MODE_TEST)){
		pdp->pd_flags |= a_F_TEST_ERRORS;
		o = su_EX_OK;
	}

	NYD_OU;
	return o;
} /* }}} */

static s32
a_conf__C(struct a_pd *pdp, char *arg, char const *act_or_nil){ /* {{{ */
	union a_srch_ip sip;
	char c, *cp;
	s32 rv;
	u32 act, m;
	char const *action;
	NYD_IN;

	if(act_or_nil != NIL)
		action = act_or_nil;
	else{
		action = su_cs_sep_c(&arg, ',', FAL0);
		if(arg != NIL)
			arg = su_cs_trim(arg);
		else{
			arg = UNCONST(char*,action);
			action = "sign";
			act = a_SRCH_NONE;
			goto jactok;
		}
	}

	if(action[1] == '\0'){
		switch(action[0]){
		case 's': act = a_SRCH_NONE; break;
		case 'v': act = a_SRCH_VERIFY; break;
		case 'p': act = a_SRCH_PASS; break;
		default: goto jeact;
		}
	}else if(!su_cs_cmp(action, "sign"))
		act = a_SRCH_NONE;
	else if(!su_cs_cmp(action, "verify"))
		act = a_SRCH_VERIFY;
	else if(!su_cs_cmp(action, "pass"))
		act = a_SRCH_PASS;
	else{
jeact:
		sip.cp = N_("--client: invalid action: %s, %s\n");
		goto jedata;
	}

jactok:
	/*rv = su_EX_OK;*/

	arg = su_cs_trim(arg);
	if(*arg == '\0'){
		sip.cp = N_("--client: invalid or empty spec: %s, %s\n");
		goto jedata;
	}

	/* Domain plus subdomain match */
	if(*arg == '.'){
		++arg;
		m = 1;
		goto jcname;
	}

	/* A CIDR match? */
	m = U32_MAX;
	if((cp = su_cs_find_c(arg, '/')) != NIL){
		*cp++ = '\0';
		if((su_idec_u32(&m, cp, UZ_MAX, 10, NIL) & (su_IDEC_STATE_EMASK | su_IDEC_STATE_CONSUMED)
				) != su_IDEC_STATE_CONSUMED || /* unrecog. otherw. */m == U32_MAX){
			cp[-1] = '/';
			sip.cp = N_("--client: invalid CIDR mask: %s, %s\n");
			goto jedata;
		}
	}

	if(su_cs_find_c(arg, ':') != NIL){
		if(m != U32_MAX && m > 128){
			cp[-1] = '/';
			sip.cp = N_("--client: invalid IPv6 mask: %s, %s\n");
			goto jedata;
		}
		rv = AF_INET6;
		goto jca;
	}else if(su_cs_first_not_of(arg, "0123456789.") == UZ_MAX){
		if(m != U32_MAX && m > 32){
			cp[-1] = '/';
			sip.cp = N_("--client: invalid IPv4 mask: %s, %s\n");
			goto jedata;
		}
		rv = AF_INET;
		goto jca;
	}else if(m != U32_MAX){
		cp[-1] = '/';
		sip.cp = N_("--client: invalid domain (CIDR notation?): %s, %s\n");
		goto jedata;
	}else{
		m = 0;
		goto jcname;
	}

jleave:
	NYD_OU;
	return rv;

jcname:
	ASSERT(m == 0 || m == 1); /* "wildcard" */

	if(*arg != '\0' && !a_misc_is_rfc5321_domain(arg)){
		sip.cp = N_("--client: invalid domain name: %s, %s\n");
		goto jedata;
	}
	/* Normalize */
	for(cp = arg; (c = *cp) != '\0'; ++cp)
		*cp = S(char,su_cs_to_lower(c));

	pdp->pd_flags |= (a_F_CLI_DOMAINS | (m ? a_F_CLI_DOMAIN_WILDCARDS : a_F_NONE));

	sip.f = a_SRCH_SET | act | (m ? 0 : a_SRCH_EXACT);
	rv = su_cs_dict_replace(&pdp->pd_cli, arg, sip.vp);
	if(rv > 0){
		a_conf__err(pdp, _("--client: software error: %s\n"), su_err_doc(rv));
		rv = -su_EX_SOFTWARE;
		goto jleave;
	}else if(rv == -1 && (pdp->pd_flags & (a_F_MODE_TEST | a_F_V))){
		a_conf__err(pdp, _("--client: domain name yet seen: %s\n"), arg);
		rv = su_EX_OK;
	}else{
		ASSERT(rv == su_EX_OK);
	}
	ASSERT(rv == su_EX_OK);
	goto jleave;

jca:/* C99 */{
	char buf[INET6_ADDRSTRLEN + 1];
	union a_srch_ip sip_test;
	boole exact;

	if(inet_pton(rv, arg, (rv == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6))) != 1){
		sip.cp = N_("--client: invalid internet address: %s, %s\n");
		goto jedata;
	}

	exact = (m == U32_MAX);

	if(!exact){
		uz max, i;
		u32 *ip, mask;

		if(pdp->pd_flags & a_F_MODE_TEST)
			su_mem_copy(&sip_test, &sip, sizeof(sip));

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

	/* We need to normalize through the system's C library to match it! */
	if(inet_ntop(rv, (rv == AF_INET ? S(void*,&sip.v4) : S(void*,&sip.v6)), buf, sizeof(buf)) == NIL){
		if(!exact)
			cp[-1] = '/';
		sip.cp = N_("--client: invalid internet address: %s, %s\n");
		goto jedata;
	}

	if(!exact && (pdp->pd_flags & a_F_MODE_TEST) &&
			((rv == AF_INET) ? su_mem_cmp(&sip.v4.s_addr, &sip_test.v4.s_addr, sizeof(sip.v4.s_addr))
				: su_mem_cmp(sip.v6.s6_addr, sip_test.v6.s6_addr, sizeof(sip.v6.s6_addr)))){
		*--cp = '/';
		a_conf__err(pdp, _("--client: address masked, should be %s/%s not %s\n"), buf, &cp[1], arg);
		*cp = '\0';
	}

	pdp->pd_flags |= a_F_CLI_IPS;

	if(exact){
		sip.f = su_cs_len(buf);
		buf[sip.f] = '\06';
		buf[++sip.f] = '\0';
		sip.f = a_SRCH_SET | (rv == AF_INET ? a_SRCH_IPV4 : a_SRCH_IPV6) | a_SRCH_EXACT | act;
		rv = su_cs_dict_replace(&pdp->pd_cli, buf, sip.vp);
		if(rv > 0){
			a_conf__err(pdp, _("--client: software error: %s\n"), su_err_doc(rv));
			rv = -su_EX_SOFTWARE;
			goto jleave;
		}else if(rv == -1 && (pdp->pd_flags & (a_F_MODE_TEST | a_F_V))){
			buf[su_cs_len(buf) -1] = '\0';
			a_conf__err(pdp, _("--client: IP address yet seen: %s\n"), buf);
		}
	}else{
		struct a_srch *sp;
		ASSERT(m != U32_MAX);

		sp = su_TALLOC(struct a_srch, 1);
		if(pdp->pd_cli_ip == NIL)
			pdp->pd_cli_ip = sp;
		else
			*pdp->pd_cli_ip_tail = sp;
		pdp->pd_cli_ip_tail = &sp->s_next;
		sp->s_next = NIL;
		sp->s_type = (rv == AF_INET ? a_SRCH_IPV4 : a_SRCH_IPV6) | act;
		sp->s_mask = m;
		su_mem_copy(&sp->s_ip, &sip, sizeof(sip));
	}

	rv = su_EX_OK;
	}goto jleave;

jedata:
	a_conf__err(pdp, V_(sip.cp), action, arg);
	rv = -su_EX_DATAERR;
	goto jleave;
} /* }}} */

static s32
a_conf__c(struct a_pd *pdp, char *arg){ /* {{{ */
	struct a_line line;
	sz lnr;
	s32 fd, rv;
	char *action, *path;
	NYD_IN;

	path = su_cs_sep_c(&arg, ',', FAL0);
	if(arg == NIL)
		action = UNCONST(char*,"sign");
	else{
		action = path;
		path = su_cs_trim(arg);
		/* xxx many err logs if action is bogus */
	}

	if((fd = a_misc_open(pdp, path)) == -1){
		a_conf__err(pdp, _("--client-file: cannot open: %s: %s\n"), path, V_(su_err_doc(-1)));
		rv = -su_EX_IOERR;
		goto jleave;
	}

	a_LINE_SETUP(&line);
	rv = su_EX_OK;
	while((lnr = a_misc_line_get(pdp, fd, &line)) != -1){
		if(lnr != 0 && (rv = a_conf__C(pdp, line.l_buf, action)) != su_EX_OK){
			if(!(pdp->pd_flags & a_F_MODE_TEST))
				break;
			rv = su_EX_OK;
		}
	}
	if(rv == su_EX_OK && line.l_err != su_ERR_NONE)
		rv = -su_EX_IOERR;

	close(fd);

jleave:
	NYD_OU;
	return rv;
} /* }}} */

static s32
a_conf__header_sigsea(struct a_pd *pdp, char *arg, boole sign){ /* {{{ */
	boole tx, from;
	uz i;
	char **store, *xarg, *vp, *cp;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;
	store = sign ? &pdp->pd_header_sign : &pdp->pd_header_seal;

jon_error_arg_nul:
	if(*store != NIL){
		su_FREE(*store);
		*store = NIL;
	}

	if(*arg == '\0')
		goto jleave;
	/* (not reached for jon_error..) */

	tx = FAL0;
	if(*arg == '@' || (tx = (*arg == '*')) || (!sign && (tx = (*arg == '+' ? TRU2 : FAL0)))){
		++arg;
		xarg = (su_cs_find_c(arg, '!') == NIL) ? R(char*,-1) : arg;
	}else if(su_cs_first_of(arg, "@*+!") != UZ_MAX){
		a_conf__err(pdp, _("--header-(sign|seal): @ / * / + must be first, ! only usable then: %s\n"), arg);
		rv = -su_EX_DATAERR;
		goto jleave;
	}else
		xarg = NIL;

	/* C99 */{
		char c;

		for(vp = cp = arg; (c = *cp) != '\0'; ++cp)
			*cp = S(char,su_cs_to_lower(c));
		i = P2UZ(cp - vp) + 1;
	}

	/* We need temporary storage in xarg!=NIL case, and we have nothing but plain HEAP here anyway,
	 * and the string is usually pretty short..: just place it at end */
	if(U32_MAX - a_HEADER_SIGSEA_MAX <= i || U32_MAX - a_HEADER_SIGSEA_MAX - i <= i){
		a_conf__err(pdp, _("--header-(sign|seal): argument too long: %s\n"), arg);
		rv = -su_EX_DATAERR;
		goto jleave;
	}
	/* Note that store MUST be \0\0 terminated if returned! */
	*store = vp = su_TALLOC(char, i + (xarg != NIL ? i + a_HEADER_SIGSEA_MAX : 0) +1+1);
	from = FAL0;

	/* If we modify the default list the way is longer; practically no validity tests <> manual! */
	if(xarg != NIL){
		uz templ;
		char const *tempd;

		if(sign){
			tempd = a_header_sigsea[a_HEADER_SIGSEA_OFF_SIGN + tx];
			templ = tx ? sizeof(a_HEADER_SIGSEA_SIGN_EXT) : sizeof(a_HEADER_SIGSEA_SIGN);
		}else{
			tempd = a_header_sigsea[a_HEADER_SIGSEA_OFF_SEAL + tx];
			templ = (tx == TRU2) ? sizeof(a_HEADER_SIGSEA_SEAL_EXT_ML)
					: tx ? sizeof(a_HEADER_SIGSEA_SEAL_EXT) : sizeof(a_HEADER_SIGSEA_SEAL);
		}

		if(xarg == R(char*,-1)){
			su_mem_copy(vp, tempd, --templ); /* \0\0 */
			vp += templ;
			from = TRU1;
		}else{
			char const *xt;

			for(xt = tempd;;){
				xarg = &(*store)[i + templ];
				su_mem_copy(xarg, arg, i);
				while((cp = su_cs_sep_c(&xarg, ',', TRU1)) != NIL){
					if(*cp == '!'){
						/* xxx "!\0" "simply" does not match */
						if(su_cs_cmp(xt, ++cp))
							continue;
						goto jxt_next;
					}
				}

				/* May take that */
				if(!from)
					from = (su_cs_cmp(xt, "from") == 0);
				vp = su_cs_pcopy(vp, xt) +1;
jxt_next:
				xt += su_cs_len(xt) +1;
				if(*xt == '\0')
					break;
			}
			xarg = R(char*,-1);
		}
	}

	while((cp = su_cs_sep_c(&arg, ',', TRU1)) != NIL){
		boole ck;

		if(xarg != NIL && *cp == '!')
			continue;

		ck = TRU1;
		if(!from){
			from = (su_cs_cmp(cp, "from") == 0);
			ck = !from;
		}

		if(ck){
#if a_AUTO_RM
			for(i = a_RM_HEAD_USER_MAX; i < a_RM_HEAD_MAX; ++i)
				if(UNLIKELY(!su_cs_cmp(a_rm_head_names[i], cp))){
					a_conf__err(pdp, _("--header-(sign|seal): cannot sign/seal: %s\n"), cp);
					rv = -su_EX_DATAERR;
					*vp = '\0'; /* \0\0 */
					goto jleave;
				}
#endif
		}

		vp = su_cs_pcopy(vp, cp) +1;
	}
	*vp = '\0';

	if(vp == *store){
		arg = UNCONST(char*,su_empty);
		goto jon_error_arg_nul;
	}

	if(!from){
		a_conf__err(pdp, _("--header-(sign|seal): From: header must not be missing\n"));
		rv = -su_EX_DATAERR;
	}

jleave:
	NYD_OU;
	return rv;
} /* }}} */

static s32
a_conf__k(struct a_pd *pdp, char *arg){ /* {{{ */
	struct a_key_algo_tuple const *katp;
	uz i;
	char *arg_orig, *xarg, *cp, *sel;
	s32 rv;
	EVP_PKEY *pkeyp;
	NYD_IN;

	pkeyp = NIL;
	UNINIT(sel, NIL);
	UNINIT(katp, &a_kata[0]);

	for(rv = 0, arg_orig = arg; (xarg = su_cs_sep_c(&arg, ',', FAL0)) != NIL; ++rv){
		switch(rv){
		default: goto jekey;
		case 0:
			cp = su_cs_find_c(xarg, '-');
			if(cp == NIL){
jekey:
				a_conf__err(pdp, _("--key: invalid (algo-digest,selector,pem-file): %s\n"), arg_orig);
				if(pkeyp != NIL)
					EVP_PKEY_free(pkeyp);
				rv = -su_EX_DATAERR;
				goto jleave;
			}
			i = P2UZ(cp - xarg);
			for(katp = &a_kata[0];;){
				if(!su_cs_cmp_case_n(xarg, katp->kat_name, i))
					break;
				else if(++katp == &a_kata[NELEM(a_kata)])
					goto jekey;
			}

			for(xarg = ++cp;; ++katp){
				if(!su_cs_cmp_case(xarg, katp->kat_md_name)){
					if(pdp->pd_flags & a_F_MODE_TEST){
						boole x;

						x = ((pdp->pd_flags & a_F_TEST_ERRORS) != 0);
						if(katp->kat_obs_pkey)
							a_conf__err(pdp, _("--key: usage of obsolete algo %s: %s\n"),
								katp->kat_pkey_name, arg_orig);
						if(katp->kat_obs_md)
							a_conf__err(pdp, _("--key: usage of obsolete digest %s: %s\n"),
								katp->kat_md_name, arg_orig);
						if(!x)
							pdp->pd_flags &= ~a_F_TEST_ERRORS;
					}
					break;
				}
				if(&katp[1] == &a_kata[NELEM(a_kata)] || katp->kat_pkey != katp[1].kat_pkey){
					a_conf__err(pdp, _("--key: digest invalid (for chosen key algorithm)\n"));
					goto jekey;
				}
			}
			break;

		case 1:
			sel = xarg;
			if(!a_misc_is_rfc5321_domain(sel)){
				a_conf__err(pdp, _("--key: selector is an invalid RFC 5321 domain name\n"));
				goto jekey;
			}
			break;

		case 2:/* C99 */{
			struct a_md *mdp;
			FILE *fp;
			struct a_key **lkpp, *kp;

			if(*xarg == '\0'){
				a_conf__err(pdp, _("--key: no key file specified\n"));
				goto jekey;
			}

			for(lkpp = &pdp->pd_keys; (kp = *lkpp) != NIL; lkpp = &kp->k_next){
				/* (It was a hard error; but then, maybe yet another selector??) */
				if((pdp->pd_flags & a_F_MODE_TEST) && kp->k_katp == katp &&
						!su_cs_cmp(kp->k_file, xarg))
					su_log_write(su_LOG_DEBUG, _("--key: already specified: %s\n"), xarg);

				if(!su_cs_cmp(kp->k_sel, sel)){
					a_conf__err(pdp, _("--key: selector already used, skip: %s: %s\n"), sel, xarg);
					goto jleave;
				}
			}

			/* Load private key file */
			/* C99 */{
				s32 fd;

				fd = a_misc_open(pdp, xarg);
				if(UNLIKELY(fd == -1)){
jekeyo:
					a_conf__err(pdp, _("--key: cannot open: %s: %s\n"), xarg, V_(su_err_doc(-1)));
					goto jekey;
				}
				fp = fdopen(fd, "r");
				if(fp == NIL){
					su_err_by_errno();
					close(fd);
					goto jekeyo;
				}
			}
			pkeyp = PEM_read_PrivateKey(fp, NIL, NIL, NIL);
			fclose(fp);
			if(pkeyp == NIL){
				a_conf__err(pdp, _("--key: not a valid private key file in PEM format: %s: %s\n"),
					xarg, ERR_error_string(ERR_get_error(), NIL));
				goto jekey;
			}

			if(UCMP(32, EVP_PKEY_id(pkeyp), !=, ABS(katp->kat_pkey))){
				a_conf__err(pdp,
					("--key: private key is not of the specified algorithm: %s (%s): %s\n"),
					katp->kat_name, katp->kat_pkey_name, xarg);
				goto jekey;
			}else{
				u32 kmaxsize;

				kmaxsize = S(u32,a_PKEY_GET_SIZE(pkeyp));
				if(kmaxsize == 0 || kmaxsize > S32_MAX){
					a_conf__err(pdp,
						("--key: cannot determine EVP_PKEY_get_size(): %s (%s): %s\n"),
						katp->kat_name, katp->kat_pkey_name, xarg);
					goto jekey;
				}
				pdp->pd_key_md_maxsize = MAX(pdp->pd_key_md_maxsize, kmaxsize);
			}

			/* So then, find message digest, or create it anew */
			for(mdp = pdp->pd_mds; mdp != NIL; mdp = mdp->md_next)
				if(mdp->md_katp->kat_md == katp->kat_md)
					break;
			if(mdp == NIL){
				/* It may not be available in this installation */
				EVP_MD const *mdmdp;

				mdmdp =
#ifdef a_MD_FETCH
					EVP_MD_fetch(NIL, katp->kat_md_name, NIL)
#else
					EVP_get_digestbyname(katp->kat_md_name)
#endif
					;
				if(mdmdp == NIL){
					a_conf__err(pdp, _("--key: message digest algorithm not available: %s: %s\n"),
						katp->kat_md_name, ERR_error_string(ERR_get_error(), NIL));
					goto jekey;
				}

				mdp = su_TALLOC(struct a_md, 1);
				mdp->md_next = pdp->pd_mds;
				pdp->pd_mds = mdp;
				mdp->md_md = mdmdp;
				mdp->md_katp = katp;
			}

			kp = S(struct a_key*,su_ALLOC(VSTRUCT_SIZEOF(struct a_key,k_file) +
					su_cs_len(xarg) +1 + su_cs_len(sel) +1));
			*lkpp = kp;
			kp->k_next = NIL;
			kp->k_md = mdp;
			kp->k_key = pkeyp;
			kp->k_sel = su_cs_pcopy(kp->k_file, xarg) +1;
			sel = su_cs_pcopy(kp->k_sel, sel);
			kp->k_sel_len = P2UZ(sel - kp->k_sel);
			pdp->pd_key_sel_len_max = MAX(pdp->pd_key_sel_len_max, kp->k_sel_len);
			kp->k_katp = katp;
			}break;
		}
	}

	rv = (rv == 3) ? su_EX_OK : -su_EX_CONFIG;

jleave:
	NYD_OU;
	return rv;
} /* }}} */

static s32
a_conf__M(struct a_pd *pdp, char *arg){ /* {{{ */
	char *vp_base, *vp, **mac;
	union {char const *cp; uz i;} x;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;
	x.i = su_cs_len(arg) +1 +1; /* Last value needs \0\0 */
	vp = vp_base = su_TALLOC(char, x.i);
	mac = NIL;

	while((x.cp = su_cs_sep_c(&arg, ',', (mac != NIL && *mac != NIL))) != NIL){
		if(mac == NIL){
			if(!su_cs_cmp_case(x.cp, "sign"))
				mac = &pdp->pd_mima_sign;
			else if(!su_cs_cmp_case(x.cp, "verify"))
				mac = &pdp->pd_mima_verify;
			else{
				a_conf__err(pdp, _("--milter-macro: unknown action: %s\n"), x.cp);
				rv = -su_EX_DATAERR;
				goto jleave;
			}
			if(*mac != NIL)
				su_FREE(*mac);
			*mac = NIL;
			if(arg == NIL)
				goto jenodat;
		}else if(*x.cp == '\0'){
jenodat:
			a_conf__err(pdp, _("--milter-macro %s: empty macro name\n"),
				(mac == &pdp->pd_mima_sign ? "sign" : "verify"));
			rv = -su_EX_DATAERR;
			goto jleave;
		}else{
			if(*mac == NIL)
				*mac = vp;
			vp = su_cs_pcopy(vp, x.cp) +1;
		}
	}
	*vp = '\0';

jleave:
	if(rv != su_EX_OK)
		su_FREE(vp_base);

	NYD_OU;
	return rv;
} /* }}} */

static s32
a_conf__R(struct a_pd *pdp, char *path){ /* {{{ */
	struct a_line line;
	struct su_avopt avo;
	sz lnr;
	s32 fd, mpv;
	NYD_IN;

	if((fd = a_misc_open(pdp, path)) == -1){
		mpv = su_err();
jerrno:
		a_conf__err(pdp, _("--resource-file: cannot handle: %s: %s\n"), path, V_(su_err_doc(mpv)));
		mpv = -su_EX_IOERR;
		goto jleave;
	}

	su_avopt_setup(&avo, 0, NIL, NIL, a_lopts);

	a_LINE_SETUP(&line);
	while((lnr = a_misc_line_get(pdp, fd, &line)) != -1){
		/* Empty lines are ignored */
		if(lnr == 0)
			continue;

		switch((mpv = su_avopt_parse_line(&avo, line.l_buf))){
		a_AVOPT_CASES
			if((mpv = a_conf_arg(pdp, mpv, UNCONST(char*,avo.avo_current_arg))) < 0 &&
					!(pdp->pd_flags & a_F_MODE_TEST))
				goto jleave;
			break;

		default:
			a_conf__err(pdp,
				_("Option unknown or falsely used (in --resource-file; see --long-help): %s: %s\n"),
				path, line.l_buf);
			if(pdp->pd_flags & a_F_MODE_TEST)
				break;
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

	NYD_OU;
	return mpv;
} /* }}} */

static s32
a_conf__r(struct a_pd *pdp, char *arg){ /* {{{ */
	u32 ftyp;
	char *vp_base, *vp, **mac;
	union {char const *cp; uz i;} x;
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;
	x.i = su_cs_len(arg) +1 +1; /* Last value needs \0\0 */
	vp = vp_base = su_TALLOC(char, x.i);
	mac = NIL;
	UNINIT(ftyp, 0);

	while((x.cp = su_cs_sep_c(&arg, ',', (mac != NIL))) != NIL){
		if(mac == NIL){
			for(ftyp = 0;;){
				if(!su_cs_cmp_case(x.cp, a_rm_head_ids[ftyp])){
					mac = &pdp->pd_rm[ftyp];
					break;
				}
				if(++ftyp == NELEM(pdp->pd_rm)){
					a_conf__err(pdp, _("--remove: unknown type: %s\n"), x.cp);
					rv = -su_EX_DATAERR;
					goto jleave;
				}
			}

			if(*mac != NIL){
				pdp->pd_flags &= ~(a_RM_HEAD_TYPE_TO_ANY_FLAG(ftyp) | a_RM_HEAD_TYPE_TO_INV_FLAG(ftyp));
				su_FREE(*mac);
			}
			*mac = vp;
			pdp->pd_flags |= a_F_RM_ANY;
			if(arg == NIL)
				*vp++ = '\0'; /* <-> a_milter::mi_macro_j (if used) */
			else if(ftyp > a_RM_HEAD_TOP_MATCHED){
				a_conf__err(pdp, _("--remove: type does not take argument: %s\n"), x.cp);
				rv = -su_EX_DATAERR;
				goto jleave;
			}
		}else{
			if(x.cp[1] == '\0'){
				if(x.cp[0] == '.')
					pdp->pd_flags |= a_RM_HEAD_TYPE_TO_ANY_FLAG(ftyp) |
							a_RM_HEAD_TYPE_TO_INV_FLAG(ftyp);
				else if(x.cp[0] == '!')
					pdp->pd_flags |= a_RM_HEAD_TYPE_TO_INV_FLAG(ftyp);
			}
			/* We do not lowercase it for -# */
			vp = su_cs_pcopy(vp, x.cp) +1;
		}
	}
	*vp = '\0';

jleave:
	if(rv != su_EX_OK)
		su_FREE(vp_base);

	NYD_OU;
	return rv;
} /* }}} */

static s32
a_conf__S(struct a_pd *pdp, char *arg){ /* {{{ */
	char *arg_orig, *xarg, *spec, *dom;
	s32 rv;
	u32 dom_off;
	boole wildcard;
	NYD_IN;

	wildcard = FAL0;
	dom_off = 0;
	UNINIT(spec, NIL);
	dom = UNCONST(char*,su_empty);

	for(rv = 0, arg_orig = arg; (xarg = su_cs_sep_c(&arg, ',', FAL0)) != NIL; ++rv){
		switch(rv){
		default: goto jerr;
		case 0:
			spec = xarg;

			if((xarg = su_cs_rfind_c(spec, '@')) == NIL)
				xarg = spec;
			else{
				pdp->pd_flags |= a_F_SIGN_LOCAL_PARTS;
				dom_off = S(u32,P2UZ(++xarg - spec));

				if(UNLIKELY(pdp->pd_flags & a_F_MODE_TEST)){ /* --test-mode "verifies" {{{ */
					struct su_mem_bag memb;
					struct su_imf_addr *imfap;
					boole ok;

					su_mem_bag_create(&memb, 0);

					rv = su_imf_parse_addr_header(&imfap, spec, su_IMF_MODE_RELAX, &memb, NIL);
					ok = (rv == su_ERR_NONE);
					if(!ok)
						a_conf__err(pdp, _("--sign: spec failed parse (need quoting?): %s\n"),
							spec);
					if(imfap != NIL){
						if(imfap->imfa_next != NIL){ /* (cannot happen as comma not passed */
							ok = FAL0;
							a_conf__err(pdp, _("--sign: spec not a single address: %s\n"),
								spec);
						}

						if((imfap->imfa_mse & (su_IMF_STATE_DISPLAY_NAME_DOT |
									su_IMF_STATE_ADDR_SPEC_NO_DOMAIN |
									su_IMF_ERR_MASK)) ||
								imfap->imfa_locpar_len == 0 ||
									imfap->imfa_locpar_len != dom_off - 1 ||
									su_mem_cmp(spec, imfap->imfa_locpar,
										imfap->imfa_locpar_len) ||
								su_cs_len(xarg) != imfap->imfa_domain_len ||
									su_mem_cmp(xarg, imfap->imfa_domain,
										imfap->imfa_domain_len)){
							ok = FAL0;

							a_conf__err(pdp,
								_("--sign: bogus input <%s>\n"
									"  Parsed: group display <%s> display <%s> "
										"local-part <%s> domain <%s>%s\n"),
								spec, imfap->imfa_group_display_name,
								imfap->imfa_display_name, imfap->imfa_locpar,
								imfap->imfa_domain,
								(imfap->imfa_mse & su_IMF_ERR_MASK ? " ERRORS"
								 : su_empty));
						}
					}

					su_mem_bag_gut(&memb);

					if(!ok){
						pdp->pd_flags |= a_F_TEST_ERRORS;
						rv = -su_EX_DATAERR;
						goto jleave;
					}
				} /* }}} */
			}

			/* Catch-all domain wildcard? */
			if(*xarg == '\0'){
jerr:
				a_conf__err(pdp, _("--sign: invalid spec[,domain[,selector(s)]]: %s: stopped: %s\n"),
					arg_orig, xarg);
				rv = -su_EX_DATAERR;
				goto jleave;
			}

			wildcard = (*xarg == '.');
			if(wildcard){
				pdp->pd_flags |= a_F_SIGN_WILDCARDS;
				/* spec must not contain this dot */
				su_cs_pcopy(xarg, &xarg[1]);
			}

			if(*xarg != '\0'){
				if(!a_misc_is_rfc5321_domain(xarg)){
					a_conf__err(pdp, _("--sign: spec is an invalid RFC 5321 domain: %s\n"), arg);
					goto jerr;
				}

				/* Normalize domain name; added in v0.6.3: all other "domain"s were always normalized,
				 * and it was not documented this must be lowercase */
				do
					*xarg = S(char,su_cs_to_lower(*xarg));
				while(*++xarg != '\0');
			}
			break;

		case 1:
			dom = xarg;
			if(*dom == '\0')
				break;
			if(a_misc_is_rfc5321_domain(dom)){
				u32 i;

				i = S(u32,su_cs_len(dom));
				if(i > pdp->pd_sign_longest_domain)
					pdp->pd_sign_longest_domain = i;

				/* Normalize domain name */
				while(i-- != 0)
					dom[i] = S(char,su_cs_to_lower(dom[i]));
			}else{
				a_conf__err(pdp, _("--sign: domain is invalid RFC 5321: %s: %s\n"), spec, dom);
				goto jerr;
			}
			break;

		case 2:/* C99 */ Jdoit:{
			char *snp, *xxarg;
			struct a_sign *sp;
			uz i;

			sp = S(struct a_sign*,su_ALLOC(VSTRUCT_SIZEOF(struct a_sign,s_dom) +
					su_cs_len(dom) +1 + su_cs_len(xarg) +a_SIGN_MAX_SELECTORS));

			snp = su_cs_pcopy(sp->s_dom, dom) +1;

			/* TODO DKIM-I --sign separates with : for possible later extension to define DKIM i= */
			for(i = 1; (xxarg = su_cs_sep_c(&xarg, ':', TRU1)) != NIL; ++i){
				if(i > a_SIGN_MAX_SELECTORS){
					a_conf__err(pdp, _("--sign: more than %d selectors\n"), a_SIGN_MAX_SELECTORS);
					goto jerr;
				}
				xxarg = su_cs_pcopy(snp, xxarg) +1;
				sp->s_sel[i - 1].name = snp;
				snp = xxarg;
			}
			sp->s_anykey = (i > 1);
			while(i <= a_SIGN_MAX_SELECTORS)
				sp->s_sel[i++ - 1].name = NIL;
			sp->s_spec_dom_off = dom_off;
			sp->s_wildcard = wildcard;
			su_cs_dict_insert(&pdp->pd_sign, spec, sp);
			}break;
		}
	}
	if(rv < 3){
		if(rv == 0)
			goto jerr;
		xarg = &spec[su_cs_len(spec)];
		rv = 2;
		goto Jdoit;
	}

	rv = su_EX_OK;
jleave:
	NYD_OU;
	return rv;
} /* }}} */

static s32
a_conf__s(struct a_pd *pdp, char *arg){ /* {{{ */
	struct a_line line;
	sz lnr;
	s32 fd, rv;
	NYD_IN;

	if((fd = a_misc_open(pdp, arg)) == -1){
		a_conf__err(pdp, _("--sign-file: cannot open: %s: %s\n"), arg, V_(su_err_doc(-1)));
		rv = -su_EX_IOERR;
		goto jleave;
	}

	a_LINE_SETUP(&line);
	rv = su_EX_OK;
	while((lnr = a_misc_line_get(pdp, fd, &line)) != -1){
		if(lnr != 0 && (rv = a_conf__S(pdp, line.l_buf)) != su_EX_OK){
			if(!(pdp->pd_flags & a_F_MODE_TEST))
				break;
			rv = su_EX_OK;
		}
	}
	if(rv == su_EX_OK && line.l_err != su_ERR_NONE)
		rv = -su_EX_IOERR;

	close(fd);

jleave:
	NYD_OU;
	return rv;
} /* }}} */

static void
a_conf__err(struct a_pd *pdp, char const *msg, ...){
	va_list vl;

	va_start(vl, msg);

	if(pdp->pd_flags & a_F_MODE_TEST)
		vfprintf(stderr, msg, vl);
	else
		su_log_vwrite(su_LOG_CRIT, msg, &vl);

	va_end(vl);

	pdp->pd_flags |= a_F_TEST_ERRORS;
}
/* }}} */

/* misc {{{ */
static boole
a_misc_is_rfc5321_domain(char const *dom){
	char c;
	char const *cp;
	NYD_IN;

	for(cp = dom; (c = *cp) != '\0'; ++cp)
		if(!su_cs_is_alnum(c) && (cp == dom || (c != '-' && c != '.'))){
			dom = NIL;
			break;
		}
	if(cp == dom)
		dom = NIL;

	NYD_OU;
	return (dom != NIL);
}

static boole
a_misc_resource_delay(s32 err){
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
a_misc_open(struct a_pd *pdp, char const *path){
	s32 fd;
	NYD_IN;
	UNUSED(pdp);

	for(;;){
		fd = open(path, O_RDONLY);
		if(fd == -1){
			if((fd = su_err_by_errno()) == su_ERR_INTR)
				continue;
			if(a_misc_resource_delay(fd))
				continue;
			fd = -1;
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

/* _misc_line_* {{{ */
static sz
a_misc_line_get(struct a_pd *pdp, s32 fd, struct a_line *lp){
	/* XXX a_LINE_GETC(): tremendous optimization possible! */
#define a_LINE_GETC(LP,FD) ((LP)->l_curr < (LP)->l_fill ? (LP)->l_buf[(LP)->l_curr++] : a_misc_line__uflow(FD, LP))
	sz rv;
	char *cp, *top, cx;
	NYD_IN;
	UNUSED(pdp);

jredo:
	cp = lp->l_buf;
	top = &cp[sizeof(lp->l_buf) - 1];
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
			/* Support escaped LF */
			if(cx == '\\'){
				--cp;
				cx = ' ';
				continue;
			}
jfakenl:
			rv = S(sz,P2UZ(cp - lp->l_buf));
			if(rv > 0 && su_cs_is_space(cp[-1])){
				--cp;
				--rv;
				ASSERT(rv == 0 || !su_cs_is_space(cp[-1]));
			}
			*cp = '\0';
			break;
		}
		if(c == '#' && cx == '\0')
			goto jskip;
		if(su_cs_is_space(c) && (cx == '\0' || su_cs_is_space(cx)))
			continue;

		if(cp == top)
			goto jelong;
		*cp++ = cx = S(char,c);
	}

jleave:
	NYD_OU;
	return rv;

jelong:
	*cp = '\0';
	su_log_write(su_LOG_ERR, _("line too long, skip: %s"), cp);
jskip:
	for(cx = '#';;){
		s32 c;

		if((c = a_LINE_GETC(lp, fd)) == -1){
			rv = -1;
			goto jleave;
		}else if(c == '\n'){
			/* Support escaped LF */
			if(cx != '\\')
				goto jredo;
		}
		cx = S(char,c);
	}
#undef a_LINE_GETC
}

static s32
a_misc_line__uflow(s32 fd, struct a_line *lp){
	s32 rv;
	NYD_IN;

	for(;;){
		ssize_t r;

		if((r = read(fd, &lp->l_buf[a_LINE_BUF_SIZE + 1],
				FIELD_SIZEOF(struct a_line,l_buf) - a_LINE_BUF_SIZE - 2)) == -1){
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
				rv = lp->l_buf[a_LINE_BUF_SIZE + 1];
				lp->l_curr = a_LINE_BUF_SIZE + 1 + 1;
				lp->l_fill = a_LINE_BUF_SIZE + 1 + S(u32,r);
			}
		}
		break;
	}

	NYD_OU;
	return rv;
}
/* }}} */

/* _misc_log_* {{{ */
static s32
a_misc_log_open(boole isrepro){
	s32 rv;
	NYD_IN;

	rv = su_EX_OK;

	if(LIKELY(!isrepro)){
		close(a_BASE_FD);
		openlog(VAL_NAME, a_OPENLOG_FLAGS, LOG_MAIL);
	}

	su_log_set_write_fun(&a_misc_log_write);

	NYD_OU;
	return rv;
}

static void
a_misc_log_write(u32 lvl_a_flags, char const *msg, uz len){
	/* We need to deal with CANcelled newlines ..
	 * Restrict to < 1024 so no memory allocator kicks in! */
	static char xb[999 +1];
	static uz xl;

	LCTAV(su_LOG_EMERG == LOG_EMERG && su_LOG_ALERT == LOG_ALERT && su_LOG_CRIT == LOG_CRIT &&
		su_LOG_ERR == LOG_ERR && su_LOG_WARN == LOG_WARNING && su_LOG_NOTICE == LOG_NOTICE &&
		su_LOG_INFO == LOG_INFO && su_LOG_DEBUG == LOG_DEBUG);
	LCTAV(su_LOG_PRIMASK < (1u << 6));

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

	if(UNLIKELY(su_state_has(su_STATE_REPRODUCIBLE)))
		write(STDERR_FILENO, msg, len);
	else{
		char *cp, c;

		if((cp = su_cs_find_c(msg, '\n')) != NIL && cp[1] != '\0'){
			if(msg != xb){
				su_cs_pcopy_n(xb, msg, sizeof(xb));
				msg = xb;
			}

			for(cp = xb; (c = *cp) != '\0' && *++cp != '\0';)
				if(c == '\n')
					cp[-1] = ' ';
		}

		syslog(S(int,lvl_a_flags & su_LOG_PRIMASK), "%.950s", msg);
	}

jleave:;
}
/* }}} */

static void
a_misc_usage(FILE *fp){
	static char const a_1[] = N_(
"%s (%s%s%s): postfix(1)-only DKIM sign-only milter\n"
"\n"
". Algorithms: "),
		a_2[] = N_(
"\n"
". Please use --long-help (-H) for option summary\n"
"  (Options marked [*] cannot be placed in a resource file)\n"
". Bugs/Contact via %s\n");

	struct a_key_algo_tuple const *katp;
	NYD_IN;

	fprintf(fp, V_(a_1), VAL_NAME, (VAL_NAME_IS_MYNAME ? "" : MYNAME), (VAL_NAME_IS_MYNAME ? "" : " "), a_VERSION);

	for(katp = a_kata; katp < &a_kata[NELEM(a_kata)]; ++katp)
		fprintf(fp, "%s%s-%s", (katp == a_kata ? su_empty : ", "), katp->kat_name, katp->kat_md_name);
#if a_AUTO_RM
	putc('.', fp); /* <> "test-script-uses" for matching <> have_auto_rm! */
#endif

	fprintf(fp, V_(a_2), a_CONTACT);

	NYD_OU;
}

static boole
a_misc_dump_doc(up cookie, boole has_arg, char const *sopt, char const *lopt, char const *doc){
	char const *x1, *x2, *x3;
	NYD_IN;
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
	fprintf(R(FILE*,cookie), _("%s%s%s%s%s: %s\n"), lopt, x1, x2, sopt, x3, V_(doc));

	NYD_OU;
	return TRU1;
}

#ifdef su_NYD_ENABLE /* {{{ */
static void
a_misc_oncrash(int signo){
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
#endif /* def su_NYD_ENABLE }}} */
/* }}} */

int
main(int argc, char *argv[]){ /* {{{ */
	struct su_avopt avo;
	struct a_pd pd;
	s32 mpv;
	boole isrepro_x;

	avo.avo_current_arg = getenv("SOURCE_DATE_EPOCH"); /* xxx su_env_get? */
	isrepro_x = (avo.avo_current_arg != NIL);
	su_state_create(su_STATE_CREATE_RANDOM, (!isrepro_x ? NIL : VAL_NAME),
		(DVLDBGOR(su_LOG_DEBUG, (!isrepro_x ? su_LOG_ERR : su_LOG_DEBUG)) | DVL(su_STATE_DEBUG |)
			(!isrepro_x ? (su_STATE_LOG_SHOW_LEVEL | su_STATE_LOG_SHOW_PID)
				: (su_STATE_LOG_SHOW_LEVEL | su_STATE_LOG_SHOW_PID | su_STATE_REPRODUCIBLE))),
		su_STATE_ERR_NOPASS);
	DVL(su_mem_set_conf(su_MEM_CONF_LINGER_FREE, TRU1);)

#ifdef su_NYD_ENABLE
	signal(SIGABRT, &a_misc_oncrash);
# ifdef SIGBUS
	signal(SIGBUS, &a_misc_oncrash);
# endif
	signal(SIGFPE, &a_misc_oncrash);
	signal(SIGILL, &a_misc_oncrash);
	signal(SIGSEGV, &a_misc_oncrash);
#endif

	STRUCT_ZERO(struct a_pd, &pd);
	pd.pd_argc = S(u32,(argc > 0) ? --argc : argc);
	pd.pd_argv = ++argv;
	if(avo.avo_current_arg != NIL)
		(void)su_idec_s64_cp(&pd.pd_source_date_epoch, avo.avo_current_arg, 0, NIL); /* devel option only! */
	a_conf_setup(&pd, TRU1);

	su_avopt_setup(&avo, pd.pd_argc, C(char const*const*,pd.pd_argv), a_sopts, a_lopts);
	while((mpv = su_avopt_parse(&avo)) != su_AVOPT_STATE_DONE){
		char const *emsg;

		/* In long-option order (mostly) */
		switch(mpv){
		/* Problem: -R may be able to succeed with -# if run by root, but fail for an anonymous user when run
		 * as a milter, causing protocol error and killing.  Therefore -# must be first, log_open then */
		case '#':
			if(isrepro_x < FAL0){
				a_conf__err(&pd, _("--test-mode must be first argument\n"));
				mpv = su_EX_USAGE;
				goto jleave;
			}
			pd.pd_flags |= a_F_MODE_TEST;
			break;

		a_AVOPT_CASES
			if((mpv = a_conf_arg(&pd, mpv, UNCONST(char*,avo.avo_current_arg))) < 0){
				mpv = -mpv;
				goto jleave;
			}
			break;

		case -1: FALLTHRU /* --header-sign-show */
		case -2:/* C99 */{ /* --header-seal-show */
			char const * const *base, *cp;

			base = &a_header_sigsea[mpv == -1 ? a_HEADER_SIGSEA_OFF_SIGN : a_HEADER_SIGSEA_OFF_SEAL];
			putc('@', stdout);
jhss_redo:
			putc(':', stdout);
			for(cp = *base;;){
				putc(' ', stdout);
				fputs(cp, stdout);
				cp += su_cs_len(cp) +1;
				if(*cp == '\0')
					break;
			}
			putc('\n', stdout);

			if(base == &a_header_sigsea[mpv == -1 ? a_HEADER_SIGSEA_OFF_SIGN : a_HEADER_SIGSEA_OFF_SEAL]){
				++base;
				putc('*', stdout);
				goto jhss_redo;
			}else if(mpv == -2){
				--mpv;
				++base;
				putc('+', stdout);
				goto jhss_redo;
			}
			mpv = su_EX_OK;
			}goto jleave;

		case -42:
			fprintf(stdout, a_COPYRIGHT);
			mpv = su_EX_OK;
			goto jleave;
		case 'H':
		case 'h':
			a_misc_usage(stdout);
			if(mpv == 'H'){
				fprintf(stdout, _("\nLong options:\n"));
				(void)su_avopt_dump_doc(&avo, &a_misc_dump_doc, R(up,stdout));
			}
			mpv = su_EX_OK;
			goto jleave;

		default: break;
		case su_AVOPT_STATE_ERR_ARG:
			emsg = su_avopt_fmt_err_arg;
			goto jerropt;
		case su_AVOPT_STATE_ERR_OPT:
			emsg = su_avopt_fmt_err_opt;
jerropt:
			fprintf(stderr, V_(emsg), avo.avo_current_err_opt);
			if(pd.pd_flags & a_F_MODE_TEST){
				pd.pd_flags |= a_F_TEST_ERRORS;
				break;
			}
			a_misc_usage(stderr);
			mpv = su_EX_USAGE;
			goto jleave;
		}

		if(!(pd.pd_flags & a_F_MODE_TEST) && isrepro_x >= FAL0)
			(void)a_misc_log_open(isrepro_x);
		isrepro_x = TRUM1;
	}

	if(pd.pd_flags & a_F_MODE_TEST){
		if(avo.avo_argc != 0){
			fprintf(stderr, _("%d excess arguments given: "), avo.avo_argc);
			while(avo.avo_argc-- != 0)
				fprintf(stderr, "%s%s", *avo.avo_argv++, (avo.avo_argc > 0 ? ", " : su_empty));
			putc('\n', stderr);
			pd.pd_flags |= a_F_TEST_ERRORS;
		}
	}

	mpv = a_conf_finish(&pd);

	if(!(pd.pd_flags & a_F_MODE_TEST)){
		if(mpv == su_EX_OK){
			if(isrepro_x >= FAL0)
				(void)a_misc_log_open(isrepro_x);
			mpv = !(pd.pd_flags & a_F_REPRO) ? a_server(&pd) : a_milter(&pd, STDIN_FILENO);
		}
	}else{
		mpv = a_conf_list_values(&pd);
		if(mpv == su_EX_OK)
			mpv = (pd.pd_flags & a_F_TEST_ERRORS) ? su_EX_USAGE : su_EX_OK;
	}

jleave:
#if DVLOR(DBGXOR(1, 0), 0)
	a_conf_cleanup(&pd);
#endif
	su_state_gut(mpv == su_EX_OK
		? su_STATE_GUT_ACT_NORM
#if a_DBGIF
			| su_STATE_GUT_MEM_TRACE
#endif
		: su_STATE_GUT_ACT_QUICK);

	return mpv;
} /* }}} */

#include "su/code-ou.h"
#undef su_FILE
/* s-itt-mode */
