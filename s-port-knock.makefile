#@ Makefile for S-port-knock(8).
#@ Pass outer CFLAGS/LDFLAGS via EXTRA_CFLAGS/EXTRA_LDFLAGS.
#@ For example "$ make -f s-port-knock.makefile DESTDIR=.x CC=clang".

PREFIX = /usr/local
DESTDIR =
BINDIR = bin
SBINDIR = sbin
MANDIR = share/man/man8
TARGET = s-port-knock

CC = cc
CFLAGS = -DNDEBUG \
	-O2 -W -Wall -Wextra -pedantic \
	-fno-asynchronous-unwind-tables -fno-unwind-tables \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \
	-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE \
	$(EXTRA_CFLAGS)
LDFLAGS = -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed \
	-Wl,--enable-new-dtags -pie \
	$(EXTRA_LDFLAGS) \
	`os=\`uname -s|tr [[:upper:]] [[:lower:]]\`;\
	if [ "$$os" = sunos ]; then printf -- -lsocket; fi`

INSTALL = install
RM = rm
SED = sed

.PHONY: all clean distclean install uninstall
all: $(TARGET)-bin $(TARGET)

$(TARGET)-bin: $(TARGET)-bin.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(@) $(?)

$(TARGET): $(TARGET).sh
	$(SED) -E \
		-e 's|^SELF=.*$$|SELF=$(TARGET)|' \
		-e 's|^:[[:space:]]*\$$\{PORT_KNOCK_BIN:=.+$$|: $${PORT_KNOCK_BIN:=$(PREFIX)/$(SBINDIR)/$(TARGET)-bin}|' \
	< $(?) > $(@)

clean:
	$(RM) -f $(TARGET) $(TARGET)-bin

distclean: clean

install: all
	$(INSTALL) -D -m 0755 $(TARGET) $(DESTDIR)$(PREFIX)/$(BINDIR)/$(TARGET)
	$(INSTALL) -D -m 0755 $(TARGET)-bin $(DESTDIR)$(PREFIX)/$(SBINDIR)/$(TARGET)-bin
	$(INSTALL) -D -m 0644 $(TARGET).8 $(DESTDIR)$(PREFIX)/$(MANDIR)/$(TARGET).8

uninstall:
	$(RM) -f $(PREFIX)/$(BINDIR)/$(TARGET) $(PREFIX)/$(SBINDIR)/$(TARGET)-bin $(PREFIX)/$(MANDIR)/$(TARGET).8

# s-mk-mode
