/*@ s-port-knock-bin.c: C backend for s-port-knock.sh; please see there.
 *@ TODO - capsicum / pledge/unveil (fork from server a forker process that forks+execv the command)
 *
 * Copyright (c) 2020 - 2024 Steffen Nurpmeso <steffen@sdaoden.eu>.
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
#define _GNU_SOURCE

#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>

#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>

#include <ctype.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Largest possible pubkey encryption + 1 + 1 + SSH signature (ED25519=~295+, RSA=~1560+) + 1 +1; packet is
 *	1. password encrypted by X509 pubkey (base64) + LF
 *	3. SSH signature cipher-encrypted with password in 1. (base64) + LF */
#define a_BUF_LEN (2048 + 1024)

/* Minimum bytes the encrypted SSH signature should have (do not even try to decrypt it, block sender).
 * ED25519 encrypted with -aes256 is 273 bytes */
#define a_SIG_LEN_MIN 256

/* Used if $PORT_KNOCK_SHELL is not set */
#define a_BIN_SH "/bin/sh"

/* Whether we should open distinct IPv4 and IPv6 sockets */
#undef a_DISTINCT_SOCKS
#if defined __FreeBSD__ || defined __NetBSD__ || defined __OpenBSD__
# define a_DISTINCT_SOCKS
#endif

/*  >8 -- 8< */

enum{
	a_EX_OK,
	a_EX_ERR,
	a_EX_USAGE = 64,
	a_EX_DATAERR = 65,
	a_EX_NOHOST = 68,
	a_EX_UNAVAILABLE = 69,
	a_EX_OSERR = 71,
	a_EX_IOERR = 74
};

static int a_verbose;
static int volatile a_sig_seen;

static int a_server(unsigned short port, char const *cmd_path, char const *privkey, char const *sigpool);
static int a_client(char const *host, char const *port, char const *enckey, char const *encsig);

static long a_fork(void);
static void a_sig_hdl(int sig);

int
main(int argc, char **argv){
	char const *prog;
	int es, srv, portno;

	es = 1;
	prog = (argc == 0) ? "port-knock" : argv[0];

	fclose(stdin);
	fclose(stdout);

	if(argc > 1 && !strcmp(argv[1], "-v")){
		a_verbose = 1;
		--argc;
		++argv;
	}

	if(argc != 6)
		goto jesyn;

	if(!strcmp(argv[1], "server"))
		srv = 1;
	else if(!strcmp(argv[1], "client"))
		srv = 0;
	else
		goto jesyn;

	portno = atoi(argv[2]);
	if(portno <= 0 || portno > 65535){
		fprintf(stderr, "Bad port (must be >0 and <65536): %s -> %d\n", argv[3], portno);
		goto jesyn;
	}

	/* TODO chdir, [chroot], pledge/unveil */

	es = srv ? a_server((unsigned short)portno, argv[3], argv[4], argv[5])
			: a_client(argv[3], argv[2], argv[4], argv[5]);
jleave:
	return es;

jesyn:
	fprintf(stderr,
		"Synopsis: %s [-v] server port cmd-path prikey allowed-sigs-db\n"
		"Synopsis: %s client port host enckey encsig\n",
		prog, prog);
	goto jleave;
}

static int
a_server(unsigned short portno, char const *cmd, char const *privkey, char const *sigpool){
	char dbuf[a_BUF_LEN], nbuf[INET6_ADDRSTRLEN +1];
	char const *myshell, *argv[9];
	struct sigaction siac;
	socklen_t soal;
#ifdef a_DISTINCT_SOCKS
	fd_set rfds;
	struct sockaddr_in soa4;
	int sofd4;
#endif
	struct sockaddr_in6 soa6;
	int sofd6, es;

	if(!a_verbose)
		freopen("/dev/null", "w", stderr);

	portno = htons(portno);

	sofd6 = -1;

#ifdef a_DISTINCT_SOCKS
	while((sofd4 = socket(AF_INET, SOCK_DGRAM, 0)) == -1){
		es = errno;
		if(es == EINTR)
			continue;
		if(es == EAFNOSUPPORT){
			fprintf(stderr, "IPv4 socket unsupported, skipping this\n");
			break;
		}
		fprintf(stderr, "IPv4 server socket creation failed: %s\n", strerror(es));
		es = a_EX_OSERR;
		goto jleave;
	}

	if(sofd4 != -1){
		soa4.sin_family = AF_INET;
		soa4.sin_port = portno;
		soa4.sin_addr.s_addr = INADDR_ANY;

		while(bind(sofd4, (struct sockaddr const*)&soa4, sizeof soa4) == -1){
			es = errno;
			if(es != EINTR){
				fprintf(stderr, "IPv4 server socket cannot bind: %s\n", strerror(es));
				es = a_EX_OSERR;
				goto jleave;
			}
		}
	}
#endif /* a_DISTINCT_SOCKS */

	while((sofd6 = socket(AF_INET6, SOCK_DGRAM, 0)) == -1){
		es = errno;
		if(es == EINTR)
			continue;
#ifdef a_DISTINCT_SOCKS
		if(es == EAFNOSUPPORT){
			fprintf(stderr, "IPv6 socket unsupported, skipping this\n");
			break;
		}
#endif
		fprintf(stderr, "IPv6 server socket creation failed: %s\n", strerror(es));
		es = a_EX_OSERR;
		goto jleave;
	}

	if(sofd6 != -1){
#if defined a_DISTINCT_SOCKS && defined IPV6_V6ONLY
		int one;

		one = 1;
		if(setsockopt(sofd6, IPPROTO_IPV6, IPV6_V6ONLY, (void*)&one, sizeof(one)) == -1){
			fprintf(stderr, "IPv6 cannot set server socket option V6ONLY: %s\n", strerror(errno));
			es = a_EX_OSERR;
			goto jleave;
		}
#endif

		soa6.sin6_family = AF_INET6;
		soa6.sin6_port = portno;
		memcpy(&soa6.sin6_addr, &in6addr_any, sizeof soa6.sin6_addr);

		while(bind(sofd6, (struct sockaddr const*)&soa6, sizeof soa6) == -1){
			es = errno;
			if(es != EINTR){
				fprintf(stderr, "IPv6 server socket cannot bind: %s\n", strerror(es));
				es = a_EX_OSERR;
				goto jleave;
			}
		}
	}
#ifdef a_DISTINCT_SOCKS
	else if(sofd4 == -1){
		fprintf(stderr, "Cannot create any server socket, bailing out\n");
		es = a_EX_OSERR;
		goto jleave;
	}
#endif

        memset(&siac, 0, sizeof siac);
        sigemptyset(&siac.sa_mask);

        siac.sa_handler = &a_sig_hdl;
        sigaction(SIGHUP, &siac, NULL);
	/*if(a_verbose)*/
		sigaction(SIGINT, &siac, NULL);
        sigaction(SIGTERM, &siac, NULL);

	siac.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &siac, NULL);
	sigaction(SIGPIPE, &siac, NULL);

	argv[0] = "sh";
	argv[1] = cmd;
	argv[2] = "verify";
	argv[3] = nbuf;
	/* argv[4] = privkey or NULL, our trigger */
	argv[5] = sigpool;
	argv[6] = dbuf; /* enckey */
	/*argv[7] = encsig;*/
	argv[8] = NULL;

	myshell = getenv("PORT_KNOCK_SHELL");
	if(myshell == NULL)
		myshell = a_BIN_SH;

	while(!a_sig_seen){
		ssize_t rb, i;
		void *sadp;
		struct sockaddr *sap;
		int fd;

#ifdef a_DISTINCT_SOCKS
		FD_ZERO(&rfds);
		if(sofd4 != -1)
			FD_SET(sofd4, &rfds);
		if(sofd6 != -1)
			FD_SET(sofd6, &rfds);

		es = select(((sofd4 > sofd6) ? sofd4 : sofd6) + 1, &rfds, NULL, NULL, NULL);
		if(es == -1){
			es = errno;
			if(es == EINTR)
				continue;
			fprintf(stderr, "Selection on server socket I/O failed: %s\n", strerror(es));
			es = a_EX_OSERR;
			goto jleave;
		}else if(es == 0) /* ?? */
			continue;

		if(sofd4 != -1 && FD_ISSET(sofd4, &rfds)){
			FD_CLR(sofd4, &rfds);
			sadp = &soa4.sin_addr;
			sap = (struct sockaddr*)&soa4;
			soal = sizeof soa4;
			fd = sofd4;
		}else if(sofd6 != -1) jNext_socket:{
			if(FD_ISSET(sofd6, &rfds)){
				FD_CLR(sofd6, &rfds);
#endif /* a_DISTINCT_SOCKS */
				sadp = &soa6.sin6_addr;
				sap = (struct sockaddr*)&soa6;
				soal = sizeof soa6;
				fd = sofd6;
#ifdef a_DISTINCT_SOCKS
			}else
				continue;
		}else /* pacify clang */
			continue;
#endif

		rb = recvfrom(fd, dbuf, sizeof(dbuf) -1, 0, sap, &soal);
		if(rb == 0)
			continue;
		if(rb == -1){
			es = errno;
			if(es == EINTR)
				continue;
			fprintf(stderr, "Failed receiving packet: %s\n", strerror(es));
			/* (xxx CONNRESET should trigger firewall rules, so do not care..) */
			if(es != EBADF && es != EINVAL)
				continue;
			es = a_EX_OSERR;
			goto jleave;
		}

		if(inet_ntop(sap->sa_family, sadp, nbuf, sizeof nbuf) == NULL){
			fprintf(stderr, "IMPL ERROR: cannot inet_ntop() peer address after recvfrom(2)\n");
			continue;
		}

		/* Linux kernel iptables xt_recent 6.1.98/6.6.40 do not deal with mapped addresses
		 * (https://bugzilla.kernel.org/show_bug.cgi?id=219038) */
		if(sap->sa_family == AF_INET6 && strchr(nbuf, '.') != NULL){
			size_t j;

			j = strlen(nbuf);
			if(j <= sizeof("::ffff:") -1 + 4+4){
				fprintf(stderr, "IMPL ERROR: IPv4 mapped address is bogus\n");
				continue;
			}
			j -= sizeof("::ffff:") -1;
			memmove(nbuf, &nbuf[sizeof("::ffff:") -1], j +1);
		}

		/* Default: do not inspect packet, only block this IP */
		argv[4] = NULL;

		/* Buffer spaced so excess is error */
		if(rb == (ssize_t)sizeof(dbuf) -1)
			goto jfork;
		dbuf[(size_t)rb] = '\0';

		/* Inspect packet, find enckey and encsig boundaries (for format see a_BUF_LEN #define above) */
		argv[7] = NULL;
		i = 0;
		for(;;){
			char c;

			c = dbuf[(size_t)i];
			if(c != '\n'){
				if(((unsigned)c & 0x80) || iscntrl(c))
					goto jfork;
				if(++i == rb)
					goto jfork;
				continue;
			}

			dbuf[(size_t)i] = '\0';
			++i;

			if(argv[7] == NULL){
				if(i == rb)
					goto jepack;
				argv[7] = &dbuf[(size_t)i];
				if(rb - i < a_SIG_LEN_MIN)
					goto jfork;
			}else if(i != rb){
jepack:
				if(a_verbose)
					fprintf(stderr, "Invalid packet content\n");
				goto jfork;
			}else
				break;
		}

		/* Hook may inspect packet data and decide further */
		argv[4] = privkey;
jfork:
		if(a_verbose)
			fprintf(stderr, "execv: %s %s %s %s %s %s %s %s (%ld bytes input)\n",
				myshell, argv[1], argv[2], argv[3],
				(argv[4] != NULL ? argv[4] : ""),
				(argv[4] != NULL ? argv[5] : ""),
				(argv[4] != NULL ? argv[6] : ""),
				(argv[4] != NULL ? argv[7] : ""),
				(argv[4] != NULL ? (long)rb : 0));

		i = a_fork();
		if(i < 0){
			es = (int)-i;
			fprintf(stderr, "Server fork failed: %s\n", strerror(es));
			es = a_EX_OSERR;
			goto jleave;
		}else if(i == 0){
			execv(a_BIN_SH, (char*const*)argv);
			for(;;)
				_exit(a_EX_OSERR);
		}

#ifdef a_DISTINCT_SOCKS
		if(fd != sofd6 && sofd6 != -1)
			goto jNext_socket;
#endif
	}

	es = a_EX_OK;
jleave:
	if(sofd6 != -1)
		close(sofd6);
#ifdef a_DISTINCT_SOCKS
	if(sofd4 != -1)
		close(sofd4);
#endif

	return es;
}

static int
a_client(char const *host, char const *port, char const *enckey, char const *encsig){
	char buf[a_BUF_LEN];
	struct addrinfo hints, *aip0, *aip;
	size_t l, yet;
	int sofd, es;

	memset(&hints, 0, sizeof hints);
	hints.ai_flags = AI_NUMERICSERV
#ifdef AI_ADDRCONFIG
			| AI_ADDRCONFIG
#endif
#if /* always, we do not care who gives !defined a_DISTINCT_SOCKS &&*/ defined AI_V4MAPPED
			| AI_V4MAPPED
#endif
			;
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_DGRAM;

	sofd = -1;
	aip0 = NULL;
	es = a_EX_DATAERR;

	l = strlen(enckey);
	if(l >= sizeof(buf) - 1 - 1 -1){
		fprintf(stderr, "Encrypted key is too long\n");
		goto jleave;
	}
	memcpy(buf, enckey, l);
	buf[l++] = '\n';

	yet = strlen(encsig);
	if(yet >= sizeof(buf) - 1 -1 - l){
		fprintf(stderr, "Encrypted signature is too long\n");
		goto jleave;
	}
	memcpy(&buf[l], encsig, yet);
	buf[l += yet] = '\n';
	buf[++l] = '\0';

	es = getaddrinfo(host, port, &hints, &aip0);
	if(es != 0){
		fprintf(stderr, "DNS lookup failed for: %s:%s %s\n", host, port, gai_strerror(es));
		es = a_EX_NOHOST;
		goto jleave;
	}

	for(aip = aip0; aip != NULL; aip = aip->ai_next){
		for(;;){
			sofd = socket(aip->ai_family, aip->ai_socktype, aip->ai_protocol);
			if(sofd != -1)
				goto jso;
			es = errno;
			if(es != EINTR)
				break;
		}
		fprintf(stderr, "Socket creation failed: %s\n", strerror(es));
	}
	es = a_EX_UNAVAILABLE;
	goto jleave;

jso:
	/* One tick though */
	yet = 0;
	while(l > 0){
		ssize_t wb;

		wb = sendto(sofd, &buf[yet], l, 0, aip->ai_addr, aip->ai_addrlen);
		if(wb == -1){
			es = errno;
			if(es == EINTR)
				continue;
			fprintf(stderr, "Packet transmit failed: %s\n", strerror(es));
			es = a_EX_IOERR;
			goto jleave;
		}
		yet += (size_t)wb;
		l -= (size_t)wb;
	}

	es = a_EX_OK;
jleave:
	if(aip0 != NULL)
		freeaddrinfo(aip0);
	if(sofd != -1)
		close(sofd);

	return es;
}

static long
a_fork(void){
	struct timespec ts;
	long i;

	ts.tv_sec = 0;
	ts.tv_nsec = 250000000L;

	for(;;){
		i = fork();
		if(i != -1)
			break;
		i = -(errno);
		if(i == -ENOSYS)
			break;
		nanosleep(&ts, NULL);
	}

	return i;
}

static void
a_sig_hdl(int sig){
	(void)sig;
	a_sig_seen = 1;
}

/* s-itt-mode */
