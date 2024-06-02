#@ Makefile for s-dkim-sign(8).
#@	$ CFLAGS=-O2 SUFOPT=' ' make DESTDIR=.x CC=clang test install
#@ NOTE 1: "test" target with sanitizer requires SANITIZER=y make(1) argument.
#@ NOTE 2: for now requires bundled SU tools that are part of S-nail!!

DESTDIR =
PREFIX = /usr/local

# What is "libexec"?  ("sbin" maybe not?)
LIBEXEC = libexec

# What is the sbin directory?
SBIN = sbin

# The linker addition for the needed libcrypto.
VAL_LD_OSSL = -lcrypto

# Our name (test script and manual do not adapt!)
VAL_NAME = s-dkim-sign

## >8 -- 8<

MYNAME = s-dkim-sign
MYMANEXT = 8

SULIB=-lsu-dvldbg#-asan
#SULIB=$(SULIB_BLD)
SULIB_BLD=
#SULIB_BLD=src/su/.clib.a
SUINC=
#SUINC=-I./include
SUFLVLC=-std=c99
SUFDEVEL=-Dsu_HAVE_DEBUG -Dsu_HAVE_DEVEL -Dsu_NYD_ENABLE -g
#SUFDEVEL=-DNDEBUG
SUFOPT?=-O1
#SUFOPT?=-O2
SULDF_SUN=
SULDF_X=-Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed -Wl,--enable-new-dtags -fPIE -pie
SULDF=$$(x=$$(uname); [ "$${x}" = "$${x\#Sun*}" ] && echo "$(SULDF_X)" || echo "$(SULDF_SUN)")
SULDFOPT_SUN=
SULDFOPT_X=
#SULDFOPT_X=-Wl,-O1 -Wl,--sort-common
SULDFOPT=$$(x=$$(uname); [ "$${x}" = "$${x\#Sun*}" ] && echo "$(SULDFOPT_X)" || echo "$(SULDFOPT_SUN)")
SUSTRIP=
#SUSTRIP=strip

## >8 -- 8<

LIBEXECDIR = $(DESTDIR)$(PREFIX)/$(LIBEXEC)
SBINDIR = $(DESTDIR)$(PREFIX)/$(SBIN)
MANDIR = $(DESTDIR)$(PREFIX)/share/man/man$(MYMANEXT)

SUF = $(SUINC) $(SUFDEVEL) \

SUFWW = #-Weverything
SUFW = -W -Wall -pedantic $(SUFWW) \
	\
	-Wno-atomic-implicit-seq-cst \
	-Wno-c++98-compat \
	-Wno-documentation-unknown-command \
	-Wno-duplicate-enum \
	-Wno-reserved-identifier \
	-Wno-reserved-macro-identifier \
	-Wno-unused-macros \
	\
	-Werror=format-security -Werror=int-conversion \

SUFS = -fPIE \
	-fno-common \
	-fstrict-aliasing -fstrict-overflow \
	-fstack-protector-strong \
	-D_FORTIFY_SOURCE=3 \
	$$(x=$$(uname -m); [ "$${x}" != "$${x\#x86*}" ] && echo -fcf-protection=full) \
	\
#	-DHAVE_SANITIZER \
#		-fsanitize=undefined \
#		-fsanitize=address \

CFLAGS += $(SUFLVLC) $(SUF) $(SUFW) $(SUFS) $(SUFOPT)
LDFLAGS += $(SULDF) $(SULDFOPT)

CC ?= cc
INSTALL = install
LN = ln
MKDIR = mkdir
RM = rm

.PHONY: all clean distclean install uninstall
all: $(SULIB_BLD) $(VAL_NAME)

src/su/.clib.a:
	cd src/su && $(MAKE) -f .makefile .clib.a

$(VAL_NAME): $(SULIB_BLD) $(MYNAME).c
	eval $(CC) \
		-DVAL_NAME="\\\"$(VAL_NAME)\\\"" \
		\
		\
		-DVAL_NAME_IS_MYNAME=$$([ "$(VAL_NAME)" = "$(MYNAME)" ] && echo 1 || echo 0) \
		-DMYNAME="\\\"$(MYNAME)\\\"" \
		\
		\
		$(CFLAGS) $(LDFLAGS) \
			-o $(@) $(MYNAME).c $(SULIB) $(VAL_LD_OSSL)

test: all
	exec ./$(MYNAME)-test.sh

clean:
	if [ -n "$(SULIB_BLD)" ]; then \
		cd src/su && $(MAKE) -f .makefile clean rm="$(RM)" CC="$(CC)";\
	fi
	$(RM) -rf "$(VAL_NAME)" .test

distclean: clean

install: all
	$(MKDIR) -p -m 0755 "$(LIBEXECDIR)"
	$(MKDIR) -p -m 0755 "$(SBINDIR)"
	$(INSTALL) -m 0755 "$(VAL_NAME)" "$(LIBEXECDIR)"/
	if [ -n "$(SUSTRIP)" ]; then $(SUSTRIP) -s "$(LIBEXECDIR)/$(VAL_NAME)"; fi
	$(INSTALL) -m 0755 "$(MYNAME)"-key-create.sh "$(SBINDIR)"/"$(VAL_NAME)"-key-create
	$(MKDIR) -p -m 0755 "$(MANDIR)"
	$(INSTALL) -m 0644 $(MYNAME).$(MYMANEXT) "$(MANDIR)/$(VAL_NAME).$(MYMANEXT)"
	$(LN) -s "$(VAL_NAME).$(MYMANEXT)" "$(MANDIR)/$(VAL_NAME)-key-create.$(MYMANEXT)"

uninstall:
	$(RM) -f "$(LIBEXECDIR)/$(VAL_NAME)" "$(SBINDIR)/$(VAL_NAME)"-key-create \
		"$(MANDIR)/$(VAL_NAME).$(MYMANEXT)" "$(MANDIR)/$(VAL_NAME)-key-create.$(MYMANEXT)"

d-release:
	XVER=$$(sed -Ee '/a_VERSION/b V;d;:V; s/^.+"([^"]+)"/\1/;q' < $(MYNAME).c) &&\
	VER=.$(MYNAME)-$$XVER &&\
	umask 0022 &&\
	mkdir $$VER &&\
	sed -i'' -E -e 's/^\.Dd .+$$/.Dd '"$$(date +"%B %d, %Y")"'/' \
		-e 's/^\.ds VV .+$$/.ds VV \\\\%v'"$$XVER"'/' $(MYNAME).$(MYMANEXT) &&\
	\
	cp $(MYNAME)* $$VER/ &&\
	cd $$VER &&\
	mv $(MYNAME).makefile makefile &&\
	mv $(MYNAME).README README &&\
	\
	sh $$HOME/src/nail.git/mk/mdocmx.sh < ../$(MYNAME).$(MYMANEXT) > $(MYNAME).$(MYMANEXT) &&\
	< $(MYNAME).$(MYMANEXT) MDOCMX_ENABLE=1 s-roff -Thtml -mdoc > /tmp/$(MYNAME)-manual.html &&\
	mkdir include src mk &&\
	cp -r $$HOME/src/nail.git/include/su include/ &&\
	cp -r $$HOME/src/nail.git/src/su src/ &&\
	cp $$HOME/src/nail.git/mk/su-make-errors.sh mk/ &&\
	rm -f src/su/*.cxx src/su/.*.cxx &&\
	sh $$HOME/src/nail.git/mk/su-make-strip-cxx.sh &&\
	cd include/su && perl $$HOME/src/nail.git/mk/su-doc-strip.pl *.h &&\
	\
	git reset &&\
	echo 'now edit makefile and src/su/.makefile, then run' &&\
	echo 's-nail -Aich -Snofollowup-to -Sreply-to=ich -Ssmime-sign -a ~/src/www.git/steffen.asc s-announce@lists.sdaoden.eu'

# s-mk-mode
