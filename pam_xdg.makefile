#@ Makefile for pam_xdg(8).
#@ For example "$ make -f pam_xdg.makefile DESTDIR=.x CC=clang".

PREFIX =
MANPREFIX = $(PREFIX)/usr
DESTDIR =
LIBDIR = $(DESTDIR)$(PREFIX)/lib/security
MANDIR = $(DESTDIR)$(MANPREFIX)/share/man/man8
NAME = pam_xdg

XDG_CONFIG_DIR = /etc
# Standard says /usr/local/share/:/usr/share/, but instead of that
# /usr/local/ one may use a different prefix by changing this
XDG_DATA_DIR_LOCAL = /usr/local
# Of _RUNTIME_DIR_OUTER, only the last component is created if non-existing
XDG_RUNTIME_DIR_OUTER = /run

## >8 -- 8<

XDG_FLAGS = \
	-D XDG_CONFIG_DIR=$(XDG_CONFIG_DIR) \
	-D XDG_DATA_DIR_LOCAL=$(XDG_DATA_DIR_LOCAL) \
	-D XDG_RUNTIME_DIR_OUTER=$(XDG_RUNTIME_DIR_OUTER) \

CC = cc
CFLAGS = -DNDEBUG \
	-O2 -W -Wall -Wextra -pedantic \
	-Wno-uninitialized -Wno-unused-result -Wno-unused-value \
	-fno-asynchronous-unwind-tables -fno-unwind-tables \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \
	-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE
LDFLAGS = -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed \
	-Wl,--enable-new-dtags -fpie -shared
LDLIBS = -lpam

INSTALL = install
MKDIR = mkdir
RM = rm

.PHONY: all clean distclean install uninstall
all: $(NAME).so

$(NAME).so: $(NAME).c
	$(CC) $(CFLAGS) $(XDG_FLAGS) $(LDFLAGS) -o $(@) $(?) $(LDLIBS)

clean:
	$(RM) -f $(NAME).so

distclean: clean

install: all
	$(MKDIR) -p -m 0755 $(LIBDIR)
	$(INSTALL) -m 0755 $(NAME).so $(LIBDIR)/$(NAME).so
	$(MKDIR) -p -m 0755 $(MANDIR)
	$(INSTALL) -m 0644 $(NAME).8 $(MANDIR)/$(NAME).8

uninstall:
	$(RM) -f $(LIBDIR)/$(NAME).so $(MANDIR)/$(NAME).8

# s-mk-mode
