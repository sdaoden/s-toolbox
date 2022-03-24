#@ Makefile for s-postgray(8).
#@ For example "$ make -f s-postgray.makefile DESTDIR=.x CC=clang".
#@ NOTE: for now requires bundled SU tools that are part of S-nail!!

DESTDIR =
PREFIX = /usr

# What is "libexec"?  ("sbin" maybe not?)
LIBEXEC = libexec

# Directory for permanent (DB) storage and client/server socket.
# Must be writable by the spawn(8) defined user/group.
VAL_STORE_PATH = /var/lib/postfix-lmdb

# Our name
VAL_NAME = s-postgray

##

# --[46]-mask
VAL_4_MASK = 24
VAL_6_MASK = 64

# ..; NIL for DEFER_MSG means the builtin default (also see manual)
VAL_COUNT = 3
VAL_DEFER_MSG = NIL
VAL_DELAY_MAX = 300
VAL_DELAY_MIN = 5
VAL_GC_REBALANCE = 3
VAL_GC_TIMEOUT = 10080
VAL_LIMIT = 242000
VAL_LIMIT_DELAY = 221000

# --server-timeout (0: never)
VAL_SERVER_TIMEOUT = 30

##

CMODE = -DNDEBUG -O2
#CMODE = -O1 -g #-fsanitize=address

## >8 -- 8<

SULIB = -lsu#-dvldbg#-asan
SUFLAGS =

LIBEXECDIR = $(DESTDIR)$(PREFIX)/$(LIBEXEC)
MANDIR = $(DESTDIR)$(PREFIX)/share/man/man8

CC = cc
SUFWW=-Weverything \
	-Wno-atomic-implicit-seq-cst \
	-Wno-c++98-compat \
	-Wno-documentation-unknown-command \
	-Wno-duplicate-enum \
	-Wno-reserved-identifier \
	-Wno-reserved-macro-identifier \
	-Wno-unused-macros
CFLAGS = $(CMODE) \
	-W -Wall -Wextra -pedantic \
	-Wno-uninitialized -Wno-unused-result -Wno-unused-value \
	-fno-asynchronous-unwind-tables -fno-unwind-tables \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \
	-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE
LDFLAGS = -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed \
	-Wl,--enable-new-dtags -fpie

INSTALL = install
MKDIR = mkdir
RM = rm

.PHONY: all clean distclean install uninstall
all: $(VAL_NAME)

$(VAL_NAME): s-postgray.c
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
		\
		-DVAL_SERVER_TIMEOUT=$(VAL_SERVER_TIMEOUT) \
		\
		\
		$(CFLAGS) $(SUFLAGS) $(LDFLAGS) \
		-o $(@) s-postgray.c $(SULIB)

clean:
	$(RM) -f $(VAL_NAME)

distclean: clean

install: all
	$(MKDIR) -p -m 0755 $(LIBEXECDIR)
	$(INSTALL) -m 0755 $(VAL_NAME) $(LIBEXECDIR)/
	$(MKDIR) -p -m 0755 $(MANDIR)
	$(INSTALL) -m 0644 s-postgray.8 $(MANDIR)/$(VAL_NAME).8

uninstall:
	$(RM) -f $(LIBEXECDIR)/$(VAL_NAME) $(MANDIR)/$(VAL_NAME).8

# s-mk-mode
