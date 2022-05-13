#@ Makefile for S-cdda(1).
#@ Pass outer CFLAGS/LDFLAGS via EXTRA_CFLAGS/EXTRA_LDFLAGS.
#@ For example "$ make -f s-cdda.makefile DESTDIR=.x CC=clang".

PREFIX = /usr/local
DESTDIR =
BINDIR = $(DESTDIR)$(PREFIX)/bin
MANDIR = $(DESTDIR)$(PREFIX)/share/man/man1
TARGET = s-cdda

CC = cc
CFLAGS = -DNDEBUG \
	-O2 -W -Wall -Wextra -pedantic \
	-Wno-uninitialized -Wno-unused-result -Wno-unused-value \
	-fno-asynchronous-unwind-tables -fno-unwind-tables \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \
	-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE \
	$(EXTRA_CFLAGS)
LDFLAGS = -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed \
	-Wl,--enable-new-dtags -pie \
	$(EXTRA_LDFLAGS) \
	`os=\`uname -s|tr [[:upper:]] [[:lower:]]\`;\
	if [ "$$os" = freebsd ] || [ "$$os" = dragonfly ]; then \
		printf -- -lcam;\
	fi`
INSTALL = install
RM = rm

.PHONY: all clean distclean install uninstall
all: $(TARGET)

$(TARGET): s-cdda.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(@) $(?)

clean:
	$(RM) -f $(TARGET)

distclean: clean

install: all
	$(INSTALL) -D -m 0755 $(TARGET) $(BINDIR)/$(TARGET)
	$(INSTALL) -D -m 0644 $(TARGET).1 $(MANDIR)/$(TARGET).1

uninstall:
	$(RM) -f $(BINDIR)/$(TARGET) $(MANDIR)/$(TARGET).1

# s-mk-mode
