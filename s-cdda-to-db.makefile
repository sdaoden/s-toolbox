#@ Makefile for S-cdda-to-db(1).

PREFIX = /usr/local
DESTDIR =
BINDIR = $(DESTDIR)$(PREFIX)/bin
MANDIR = $(DESTDIR)$(PREFIX)/share/man/man1
TARGET = s-cdda-to-db

INSTALL = install
CP = cp
RM = rm

.PHONY: all clean distclean install uninstall
all: $(TARGET)

$(TARGET): s-cdda-to-db.pl
	$(CP) -f $(?) $(@)

clean:
	$(RM) -f $(TARGET)

distclean: clean

install: all
	$(INSTALL) -D -m 0755 $(TARGET) $(BINDIR)/$(TARGET)
	$(INSTALL) -D -m 0644 $(TARGET).1 $(MANDIR)/$(TARGET).1

uninstall:
	$(RM) -f $(BINDIR)/$(TARGET) $(MANDIR)/$(TARGET).1

# s-mk-mode
