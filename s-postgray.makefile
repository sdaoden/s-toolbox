#@ Makefile for s-postgray(8).
#@	$ make -f s-postgray.makefile DESTDIR=.x CC=clang VAL_OS_SANDBOX=0
#@ NOTE: for now requires bundled SU tools that are part of S-nail!!

DESTDIR =
PREFIX = /usr/local

# What is "libexec"?  ("sbin" maybe not?)
LIBEXEC = libexec

# Directory for permanent (DB) storage and client/server socket.
# Must exist and be writable by the spawn(8) defined user/group.
# Should not be accessible by anyone else.
VAL_STORE_PATH = /var/lib/postgray

# 0=disable, 1=enable, 2=enable+debug (DO NOT USE REGULARY; May log to STDERR!)
# A setrlimit(2) sandbox is _always_ used, this uses in addition on
# - OpenBSD
#   pledge(2)/unveil(2) -- just works
# - Linux
#   prctl(2)/seccomp(2) -- _may_ fail with violations if the C library
#   requires uncovered system calls; please report such.
#   Saying VAL_OS_SANDBOX=2 will trap and write to stderr bad syscall numbers.
#   To have a glue on all system calls, you need strace(1) (https://strace.io),
#   then compile with VAL_OS_SANDBOX=0 and use the test-strace make(1) target.
#   It outputs two lines which can then be used -- but note these contain _all_
#   used system calls, not only those required in the sandbox(es).
VAL_OS_SANDBOX = 1
# If set to a list of "a_Y(X),.." (as generated by test-strace target) used
# _instead_ of the built-in ones!
#VAL_OS_SANDBOX_CLIENT_RULES =
#VAL_OS_SANDBOX_SERVER_RULES =

# Our name (test script and manual do not adapt!)
VAL_NAME = s-postgray

##

# --[46]-mask
VAL_4_MASK = 24
VAL_6_MASK = 64

# ..; NIL for _MSG_* means the builtin default (also see manual)
# Otherwise _MSG_* cannot contain quotes.
VAL_COUNT = 2
VAL_DELAY_MAX = 300
VAL_DELAY_MIN = 5
VAL_GC_REBALANCE = 3
VAL_GC_TIMEOUT = 10080
VAL_LIMIT = 242000
VAL_LIMIT_DELAY = 221000
VAL_MSG_ALLOW = NIL
VAL_MSG_BLOCK = NIL
VAL_MSG_DEFER = NIL
VAL_SERVER_QUEUE = 64
VAL_SERVER_TIMEOUT = 30

##

#SULIB=$(SULIB_TARGET)
SULIB=-lsu-dvldbg#-asan
SULIB_BLD=#$(SULIB_TARGET)
SUFLVLC=#-std=c89
STRIP=#strip
SUFOPT=-O1 -g -Dsu_HAVE_DEVEL -Dsu_HAVE_DEBUG -Dsu_HAVE_NYD #-I./include
#SUFOPT=-DNDEBUG -O2 #-I./include

## >8 -- 8<

LIBEXECDIR = $(DESTDIR)$(PREFIX)/$(LIBEXEC)
MANDIR = $(DESTDIR)$(PREFIX)/share/man/man8

SULIB_TARGET=./libsu.a

SUFWWW = #-Weverything
SUFWW = -W -Wall -pedantic $(SUFWWW) \
	-Wno-atomic-implicit-seq-cst \
	-Wno-c++98-compat \
	-Wno-documentation-unknown-command \
	-Wno-duplicate-enum \
	-Wno-reserved-identifier \
	-Wno-reserved-macro-identifier \
	-Wno-unused-macros

SUFW = -W -Wall -pedantic

SUFS = -fPIE \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \
	-fstack-protector-strong \
	-D_FORTIFY_SOURCE=3 \
	\
#	-DHAVE_SANITIZER \
#		-fsanitize=undefined \
#		-fsanitize=address \

CFLAGS += $(SUFLVLC) $(SUF) $(SUFWW) $(SUFS) $(SUFOPT)

LDFLAGS += -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed \
	-Wl,--enable-new-dtags \
	-fpie

CC = cc
INSTALL = install
MKDIR = mkdir
RM = rm

.PHONY: all clean distclean install uninstall
all: $(SULIB_BLD) $(VAL_NAME)

$(SULIB_TARGET):
	cd src/su && $(MAKE) -f .makefile .clib.a &&\
	$(INSTALL) -m 0644 .clib.a ../../$(SULIB_TARGET)

$(VAL_NAME): $(SULIB_BLD) s-postgray.c
	CRULES= SRULES=;\
	if [ -n "$(VAL_OS_SANDBOX_CLIENT_RULES)" ]; then \
		CRULES='-DVAL_OS_SANDBOX_CLIENT_RULES="$(VAL_OS_SANDBOX_CLIENT_RULES)"';\
	fi;\
	if [ -n "$(VAL_OS_SANDBOX_SERVER_RULES)" ]; then \
		SRULES='-DVAL_OS_SANDBOX_SERVER_RULES="$(VAL_OS_SANDBOX_SERVER_RULES)"';\
	fi;\
	VA="$(VAL_MSG_ALLOW)"; if [ "$$VA" != NIL ]; then VA='"\"$(VAL_MSG_ALLOW)\""'; fi;\
	VB="$(VAL_MSG_BLOCK)"; if [ "$$VB" != NIL ]; then VB='"\"$(VAL_MSG_BLOCK)\""'; fi;\
	VD="$(VAL_MSG_DEFER)"; if [ "$$VD" != NIL ]; then VD='"\"$(VAL_MSG_DEFER)\""'; fi;\
	eval $(CC) \
		-DVAL_NAME="\\\"$(VAL_NAME)\\\"" \
		\
		-DVAL_STORE_PATH="\\\"$(VAL_STORE_PATH)\\\"" \
		\
		-DVAL_OS_SANDBOX=$(VAL_OS_SANDBOX) \
		$$CRULES $$SRULES \
		\
		-DVAL_4_MASK=$(VAL_4_MASK) \
		-DVAL_6_MASK=$(VAL_6_MASK) \
		\
		-DVAL_COUNT=$(VAL_COUNT) \
		-DVAL_DELAY_MAX=$(VAL_DELAY_MAX) \
		-DVAL_DELAY_MIN=$(VAL_DELAY_MIN) \
		-DVAL_GC_REBALANCE=$(VAL_GC_REBALANCE) \
		-DVAL_GC_TIMEOUT=$(VAL_GC_TIMEOUT) \
		-DVAL_LIMIT=$(VAL_LIMIT) \
		-DVAL_LIMIT_DELAY=$(VAL_LIMIT_DELAY) \
		-DVAL_MSG_ALLOW=$$VA -DVAL_MSG_BLOCK=$$VB -DVAL_MSG_DEFER=$$VD \
		-DVAL_SERVER_QUEUE=$(VAL_SERVER_QUEUE) \
		-DVAL_SERVER_TIMEOUT=$(VAL_SERVER_TIMEOUT) \
		\
		\
		$(CFLAGS) $(LDFLAGS) \
		-o $(@) s-postgray.c $(SULIB)

test: all
	PG="../$(VAL_NAME)" exec ./s-postgray-test.sh

# test-strace {{{
test-strace: all
	if [ "$(VAL_OS_SANDBOX)" -ne 0 ]; then echo >&2 this will not do; exit 1; fi;\
	trap "rm -rf .z .b.rc .r.rc .c.xout .c.out .s.strace .c.strace" EXIT; trap "exit 1" INT HUP QUIT TERM;\
	mkdir .z || exit 2;\
	{ \
		echo action=DEFER_IF_PERMIT 4.2.0;echo;\
		echo action=DUNNO;echo;\
		echo action=REJECT;echo;\
		echo action=DUNNO;echo;\
		echo action=DUNNO;echo;\
		echo action=REJECT;echo;\
	} > .c.xout || exit 3;\
	echo test.localdomain > .b.rc || exit 4;\
	echo test2.localdomain > .z/a.rc || exit 5;\
	pwd=$$(pwd);\
	{ \
		echo msg-defer DEFER_IF_PERMIT 4.2.0;\
		echo store-path $$pwd/.z; echo block-file $$pwd/.b.rc; echo allow-file $$pwd/.z/a.rc;\
		echo verbose; echo verbose; echo count 1; echo delay-min 0;\
	} > .r.rc || exit 6;\
	\
	strace -f -c -U name -o .s.strace ./"$(VAL_NAME)" -R $$pwd/.r.rc --startup & [ $$? -eq 0 ] || exit 10;\
	sleep 2;\
	{ \
	echo recipient=x1@y; echo sender=y@z; echo client_address=127.1.2.2; echo client_name=xy; echo;\
	echo recipient=x1@y; echo sender=y@z; echo client_address=127.1.2.2; echo client_name=test2.localdomain; echo;\
	echo recipient=x1@y; echo sender=y@z; echo client_address=127.1.2.2; echo client_name=test.localdomain; echo;\
	echo recipient=x1@y; echo sender=y@z; echo client_address=127.1.2.2; echo client_name=xy; echo;\
	} | strace -c -U name -o .c.strace ./"$(VAL_NAME)" -R $$pwd/.r.rc >> .c.out || exit 11;\
	sleep 2;\
	\
	./"$(VAL_NAME)" -R $$pwd/.r.rc --status || exit 12;\
	./"$(VAL_NAME)" -R $$pwd/.r.rc --shutdown || exit 13;\
	./"$(VAL_NAME)" -R $$pwd/.r.rc --status && exit 14;\
	\
	echo once >> .r.rc || exit 20;\
	strace -A -f -c -U name -o .s.strace ./"$(VAL_NAME)" -R $$pwd/.r.rc --startup & [ $$? -eq 0 ] || exit 21;\
	{ \
	echo recipient=x1@y; echo sender=y@z; echo client_address=127.1.2.2; echo client_name=xy; echo;\
	echo this should not create result;echo;\
	} | strace -A -c -U name -o .c.strace ./"$(VAL_NAME)" -R $$pwd/.r.rc >> .c.out || exit 22;\
	sleep 2;\
	./"$(VAL_NAME)" -R $$pwd/.r.rc --status || exit 23;\
	\
	echo 'block xy' >> .r.rc || exit 24;\
	kill -HUP $$(cat $$pwd/.z/"$(VAL_NAME)".pid) || exit 25;\
	sleep 2;\
	kill -USR1 $$(cat $$pwd/.z/"$(VAL_NAME)".pid) || exit 26;\
	sleep 2;\
	kill -USR2 $$(cat $$pwd/.z/"$(VAL_NAME)".pid) || exit 27;\
	sleep 2;\
	{ \
	echo recipient=x1@y; echo sender=y@z; echo client_address=127.1.2.2; echo client_name=xy; echo;\
	} | strace -A -c -U name -o .c.strace ./"$(VAL_NAME)" -R $$pwd/.r.rc >> .c.out || exit 28;\
	\
	./"$(VAL_NAME)" -R $$pwd/.r.rc --status || exit 29;\
	./"$(VAL_NAME)" -R $$pwd/.r.rc --shutdown || exit 30;\
	\
	diff -u .c.xout .c.out; echo diff said $$?;\
	\
	< .c.strace awk '\
		BEGIN{c=hot=0}\
		/^-+$$/{hot=!hot;next}\
		{if(!hot) next; for(i=1; i <= c; ++i) if(a[i] == $$1) next; a[++c] = $$1}\
		END{for(i=1;i<=c;++i) print "a_Y(SYS_" a[i] "),"}\
	' > .c.txt;\
	echo 'VAL_OS_SANDBOX_CLIENT_RULES="'$$(cat .c.txt)'"';\
	\
	< .s.strace awk '\
		BEGIN{c=hot=0}\
		/^-+$$/{hot=!hot;next}\
		{if(!hot) next; for(i=1; i <= c; ++i) if(a[i] == $$1) next; a[++c] = $$1}\
		END{for(i=1;i<=c;++i) print "a_Y(SYS_" a[i] "),"}\
	' > .s.txt;\
	echo 'VAL_OS_SANDBOX_SERVER_RULES="'$$(cat .s.txt)'"';
# }}}

clean:
	if [ -n "$(SULIB_BLD)" ]; then \
		cd src/su && $(MAKE) -f .makefile clean rm="$(RM)" CC="$(CC)";\
	fi
	$(RM) -f $(SULIB_TARGET) "$(VAL_NAME)"

distclean: clean

install: all
	$(MKDIR) -p -m 0755 "$(LIBEXECDIR)"
	$(INSTALL) -m 0755 "$(VAL_NAME)" "$(LIBEXECDIR)"/
	if [ -n "$(STRIP)" ]; then $(STRIP) "$(LIBEXECDIR)/$(VAL_NAME)"; fi
	$(MKDIR) -p -m 0755 "$(MANDIR)"
	$(INSTALL) -m 0644 s-postgray.8 "$(MANDIR)/$(VAL_NAME).8"

uninstall:
	$(RM) -f "$(LIBEXECDIR)/$(VAL_NAME)" "$(MANDIR)/$(VAL_NAME).8"

d-release:
	VER=.s-postgray-$$(sed -Ee '/a_VERSION/b V;d;:V; s/^.+"([^"]+)"/\1/;q' < s-postgray.c) &&\
	mkdir $$VER &&\
	cp s-postgray* $$VER/ &&\
	cd $$VER &&\
	mv s-postgray.makefile makefile &&\
	mv s-postgray.README README &&\
	mkdir include src mk &&\
	cp -r ../../nail.git/include/su include/ &&\
	cp -r ../../nail.git/src/su src/ &&\
	cp ../../nail.git/mk/su-make-errors.sh mk/ &&\
	rm -f src/su/*.cxx src/su/.*.cxx &&\
	sh ../../nail.git/mk/su-make-strip-cxx.sh &&\
	cd include/su && perl ../../../../nail.git/mk/su-doc-strip.pl *.h &&\
	git reset&&\
	echo now edit makefile and src/su/.makefile

# s-mk-mode
