#@ Makefile for s-postgray(8).
#@ For example "$ make -f s-postgray.makefile DESTDIR=.x CC=clang".
#@ NOTE: for now requires bundled SU tools that are part of S-nail!!

DESTDIR =
PREFIX = /usr/local

# What is "libexec"?  ("sbin" maybe not?)
LIBEXEC = libexec

# Directory for permanent (DB) storage and client/server socket.
# Must be writable by the spawn(8) defined user/group.
VAL_STORE_PATH = /var/lib/postfix-lmdb

# Our name (test script and manual do not adapt!)
VAL_NAME = s-postgray

##

# --[46]-mask
VAL_4_MASK = 24
VAL_6_MASK = 64

# ..; NIL for DEFER_MSG means the builtin default (also see manual)
VAL_COUNT = 2
VAL_DEFER_MSG = NIL
VAL_DELAY_MAX = 300
VAL_DELAY_MIN = 5
VAL_GC_REBALANCE = 3
VAL_GC_TIMEOUT = 10080
VAL_LIMIT = 242000
VAL_LIMIT_DELAY = 221000
VAL_SERVER_QUEUE = 64
VAL_SERVER_TIMEOUT = 30

##

#SULIB=$(SULIB_TARGET)
SULIB=-lsu-dvldbg#-asan
SULIB_BLD=#$(SULIB_TARGET)
SUFLVLC=#-std=c89
SUFOPT=-O1 -g -Dsu_HAVE_DEVEL -Dsu_HAVE_DEBUG #-I./include
#SUFOPT=-O2 #-I./include
SUFS=-fPIE -fstack-protector-strong #-D_FORTIFY_SOURCE=2 #-fsanitize=address
STRIP=#strip

## >8 -- 8<

LIBEXECDIR = $(DESTDIR)$(PREFIX)/$(LIBEXEC)
MANDIR = $(DESTDIR)$(PREFIX)/share/man/man8

SULIB_TARGET=./libsu.a

SUFWW=-Weverything \
	-Wno-atomic-implicit-seq-cst \
	-Wno-c++98-compat \
	-Wno-documentation-unknown-command \
	-Wno-duplicate-enum \
	-Wno-reserved-identifier \
	-Wno-reserved-macro-identifier \
	-Wno-unused-macros

#$(SUFWW)
SUFW=-W -Wall -pedantic \
	-Wno-uninitialized -Wno-unused-result -Wno-unused-value \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \

CFLAGS+=$(SUFLVLC) $(SUFW) $(SUFS) $(SUFOPT)

LDFLAGS+=-Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed \
	-Wl,--enable-new-dtags \
	-fpie

CC = cc
INSTALL = install
MKDIR = mkdir
RM = rm

.PHONY: all clean distclean install uninstall
all: $(SULIB_BLD) $(VAL_NAME)

$(SULIB_TARGET):
	cd src/su && $(MAKE) -f .makefile &&\
	$(INSTALL) -m 0644 .clib.a ../../$(SULIB_TARGET)

$(VAL_NAME): $(SULIB_BLD) s-postgray.c
	$(CC) \
		-DVAL_NAME="\"$(VAL_NAME)\"" \
		\
		-DVAL_STORE_PATH="\"$(VAL_STORE_PATH)\"" \
		\
		\
		-DVAL_4_MASK=$(VAL_4_MASK) \
		-DVAL_6_MASK=$(VAL_6_MASK) \
		\
		-DVAL_COUNT=$(VAL_COUNT) \
		-DVAL_DEFER_MSG=$(VAL_DEFER_MSG) \
		-DVAL_DELAY_MAX=$(VAL_DELAY_MAX) \
		-DVAL_DELAY_MIN=$(VAL_DELAY_MIN) \
		-DVAL_GC_REBALANCE=$(VAL_GC_REBALANCE) \
		-DVAL_GC_TIMEOUT=$(VAL_GC_TIMEOUT) \
		-DVAL_LIMIT=$(VAL_LIMIT) \
		-DVAL_LIMIT_DELAY=$(VAL_LIMIT_DELAY) \
		-DVAL_SERVER_QUEUE=$(VAL_SERVER_QUEUE) \
		-DVAL_SERVER_TIMEOUT=$(VAL_SERVER_TIMEOUT) \
		\
		\
		$(CFLAGS) $(SUFLAGS) $(LDFLAGS) \
		-o $(@) s-postgray.c $(SULIB)

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

# s-mk-mode
