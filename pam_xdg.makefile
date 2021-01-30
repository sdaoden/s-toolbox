#@ Makefile for pam_xdg(8).

PREFIX = /
MANPREFIX = /usr
DESTDIR =
LIBDIR = $(DESTDIR)$(PREFIX)/lib/security
MANDIR = $(DESTDIR)$(MANPREFIX)/share/man/man8
NAME = pam_xdg

CC = cc
CFLAGS = -DNDEBUG \
	-O2 -W -Wall -Wextra -pedantic \
	-Wno-uninitialized -Wno-unused-result -Wno-unused-value \
	-fno-asynchronous-unwind-tables -fno-unwind-tables \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \
	-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE
LDFLAGS = -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed \
	-Wl,--enable-new-dtags -pie -shared
INSTALL = install
RM = rm

.PHONY: all clean distclean install uninstall
all: $(NAME).so

$(NAME).so: $(NAME).c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(@) $(?)

clean:
	$(RM) -f $(NAME).so

distclean: clean

install: all
	$(INSTALL) -D -m 0755 $(NAME).so $(LIBDIR)/$(NAME).so
	$(INSTALL) -D -m 0644 $(NAME).8 $(MANDIR)/$(NAME).8

uninstall:
	$(RM) -f $(LIBDIR)/$(NAME).so $(MANDIR)/$(NAME).8

# s-mk-mode
