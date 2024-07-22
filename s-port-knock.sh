#!/bin/sh -
#@ s-port-knock.sh: a simple port knock via SSH signatures.
#@ Requires (modern) openssl and ssh-keygen with -Y support.
#
# (Do not change these, the makefile watches out)
: ${PORT_KNOCK_BIN:=/usr/sbin/s-port-knock-bin}
SELF=s-port-knock.sh
VERSION=0.8.1
CONTACT='Steffen Nurpmeso <steffen@sdaoden.eu>'
#
syno() {
	echo >&2 $SELF' ('$VERSION'): simple UDP based port knock client/server'
	echo >&2
	echo >&2 'SYNOPSIS: '$SELF' knock host port pubkey ssh-client-pubkey'
	echo >&2 '          - knock for ssh-client-pubkey at server (host:port, pubkey).'
	echo >&2 '            Requires '$PORT_KNOCK_BIN', or bash(1) in $PATH'
	echo >&2
	echo >&2 'SYNOPSIS: '$SELF' create-server-key filename-prefix [rsa[:bits]]'
	echo >&2 '          - generate *-{pri,pub}.pem; -pub.pem is needed by clients'
	echo >&2 'SYNOPSIS: '$SELF' start-server [-v] port cmd prikey allowed-signers'
	echo >&2 '           - cmd is sh(1) script to "verify" with (ie this one); Read README!'
	echo >&2 '           - With -v one should add --no-close and --output to s-s-d options'
	echo >&2 '               --start --background --make-pidfile --pidfile XY --exec'
	echo >&2 'SYNOPSIS: '$SELF' verify IP [prikey allowed-signers enc-key enc-sig]'
	echo >&2 '          - (called by server); if prikey and allowed-signers (see ssh-keygen)'
	echo >&2 '            are given, verify enc-key and enc-sig, else just block IP address'
	echo >&2
	echo >&2 '. Set $PORT_KNOCK_BIN environment to replace '$PORT_KNOCK_BIN','
	echo >&2 '  $PORT_KNOCK_SHELL (/bin/sh), and $MAGIC to include a "magic string" in sigs.'
	echo >&2 '. Set $PORT_KNOCK_RC to specify a resource file'
	echo >&2 '          MAGIC= # (server *verifies* sig additionally only if non-empty!) '
	echo >&2 '          act_sent() { echo >&2 "client sent to $1"; return 0; } # !0: retry!'
	echo >&2 '          act_block() { echo >&2 "server blocking "$1; }'
	echo >&2 '          act_allow() { echo >&2 "server allowing $1, principal: $2"; }'
	echo >&2 '. Bugs/Contact via '$CONTACT
	exit 64 # EX_USAGE
}
#
# 2020 - 2024 Steffen Nurpmeso <steffen@sdaoden.eu>
# SPDX-License-Identifier: ISC
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

: ${RSA_DEFBITS:=2048}
: ${RSA_MINBITS:=1024}

: ${SHELL:=/bin/sh}
: ${OPENSSL:=openssl}

: ${TMPDIR:=/tmp}
: ${ENV_TMP:="$TMPDIR:$TMP:$TEMP"}

# >8 -- 8<

# knock: save encrypted key and signature there
# verify: fetch enc-key and enc-sig from $DEBUG
: ${DEBUG:=}

LC_ALL=C
EX_DATAERR=65 EX_CANTCREAT=73 EX_TEMPFAIL=75

# For heaven's sake auto-redirect on SunOS/Solaris, and for pipefail, if necessary
if [ -z "$__PORT_KNOCK_UP" ]; then
	if [ $# -eq 0 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
		syno
	fi

	if (set -C -o pipefail) >/dev/null 2>&1; then
		:
	elif [ -n "$PORT_KNOCK_SHELL" ]; then
		__PORT_KNOCK_UP=$PORT_KNOCK_SHELL
		#printf >&2 'INFO: "set -C -o pipefail" unsupported, redirect via $PORT_KNOCK_SHELL='$__PORT_KNOCK_UP
	else
		__PORT_KNOCK_UP=$(command -v bash 2>&1)
		if [ $? -eq 0 ]; then
			#printf >&2 'INFO: "set -C -o pipefail" unsupported, redirect via '$__PORT_KNOCK_UP
			:
		elif [ -d /usr/xpg4 ]; then
			if [ x"$SHELL" = x/bin/sh ]; then
				__PORT_KNOCK_UP=/usr/xpg4/bin/sh PATH=/usr/xpg4/bin:${PATH}
				#printf >&2 'INFO: SunOS/Solaris, redirect via '$__PORT_KNOCK_UP
			fi
		else
			__PORT_KNOCK_UP= # (should be but whee)
		fi
	fi

	if [ -n "$__PORT_KNOCK_UP" ]; then
		PORT_KNOCK_SHELL=$__PORT_KNOCK_UP
		export __PORT_KNOCK_UP PATH PORT_KNOCK_SHELL
		exec "$PORT_KNOCK_SHELL" "$0" "$@"
	fi
fi
unset __PORT_KNOCK_UP

if (set -o pipefail); then # >/dev/null 2>&1; then
	set -o pipefail
else
	# XXX circumvent via estat=$(exec 3>&1 1>&2; { DOIT; echo $? >&3; } | BLA)
	echo >&2 'WARNING: shell ('$SHELL') does not support "set -o pipefail", this HIDES ERRORS'
	echo >&2 'Run with a more modern shell like so: SHELL '$0' '$*
fi

if (set -C) >/dev/null 2>&1; then :; else
	echo >&2 'ERROR: shell does not support noclobber option aka set -C'
	echo >&2 'ERROR: please run with a more modern shell like so: SHELL '$0' '$*
	exit $EX_TEMPFAIL
fi

umask 077

# $PORT_KNOCK_RC defaults
: ${MAGIC:=}
act_block() { echo >&2 'blocking '$1; }
act_allow() { echo >&2 'allowing '$1', principal: '$2; }
__wW=
act_sent() {
	# (specific to how my firewall works and assumes we were blocked before OR now)
	echo >&1 'Pinging '$1
	ping=ping
	[ "$1" != "${1##*::}" ] && command -v ping6 >/dev/null 2>&1 && ping=ping6
	if [ -z "$__wW" ]; then
		if ($ping -c1 -w1 localhost >/dev/null 2>&1); then
			__wW=-w1
		elif ($ping -c1 -W500 localhost >/dev/null 2>&1); then
			__wW=-W1000
		fi
	fi

	sleep 1
	$ping -c1 $__wW "$1" && return 0
	echo 'Did not work out, sleeping 60 seconds: '$ping -c1 $__wW "$1"
	sleep 60
	return 1
}

tmp_dir= tmp_file=  __tmp_no=1 __tmpfiles=
tmp_file_new() {
	if [ -z "$tmp_dir" ]; then
		_tmp_dir() {
			i=$IFS
			IFS=:
			set -- $ENV_TMP
			IFS=$i
			# for i; do -- new in POSIX Issue 7 + TC1
			for tmp_dir
			do
				[ -d "$tmp_dir" ] && return 0
			done
			tmp_dir=$TMPDIR
			[ -d "$tmp_dir" ] && return 0
			echo >&2 'Cannot find a temporary directory, please set $TMPDIR'
			exit $EX_TEMPFAIL
		}
		_tmp_dir

		trap "exit $EX_TEMPFAIL" HUP INT QUIT PIPE TERM
		trap "trap \"\" HUP INT QUIT PIPE TERM EXIT; rm -f \$__tmpfiles" EXIT
	fi

	while :; do
		tmp_file="$tmp_dir/port-knock-$$-$__tmp_no.dat"
		(
			set -C
			> "$tmp_file"
		) >/dev/null 2>&1 && break
		__tmp_no=$((__tmp_no + 1))
	done
	__tmpfiles="$__tmpfiles $tmp_file"
}

ossl() (
	set +e

	x=
	while :; do
		"$OPENSSL" "$@"
		[ $? -eq 0 ] && return 0

		echo >&2
		echo >&2 '$OPENSSL='$OPENSSL' seems incompatible; is it an old version?'
		echo >&2 '  Command was: '$*
		if [ -x /usr/openssl/3.1/bin/openssl ]; then
			x=/usr/openssl/3.1/bin/openssl
		elif [ -x /usr/openssl/1.1/bin/openssl ]; then
			x=/usr/openssl/1.1/bin/openssl
		elif [ -x /usr/pkg/bin/openssl ]; then
			x=/usr/pkg/bin/openssl
		elif [ -x /opt/csw/bin/openssl ]; then
			x=/opt/csw/bin/openssl
		fi
		if [ x = x"$x" ] || [ x"$x" = x"$OPENSSL" ]; then
			echo >&2 'Please place version >= 1.1.0 (early) in $PATH, or $OPENSSL=, rerun.'
			exit $EX_DATAERR
		fi
		OPENSSL=$x
		echo >&2 'I will try $OPENSSL='$OPENSSL' instead; restarting operation ...'
		echo >&2
	done
)

incrc() {
	[ -n "$PORT_KNOCK_RC" ] && [ -r "$PORT_KNOCK_RC" ] && . "$PORT_KNOCK_RC"
}

case "$1" in
create-server-key)
	[ $# -gt 3 ] && syno
	[ $# -lt 2 ] && syno
	fprefix=$2

	algo=rsa opt=
	[ $# -gt 2 ] && algo=$3
	case $algo in
	rsa|rsa:*)
		bits=${algo##*:}
		algo=${algo%%:*}
		if [ "$bits" = "$algo" ] || [ -z "$bits" ]; then
			bits=$RSA_DEFBITS
		else
			i=${bits#${bits%%[!0-9]*}}
			i=${i%${i##*[!0-9]}} # xxx why?
			if [ -n "$i" ]; then
				echo >&2 'RSA bits is not a number'
				exit $EX_DATAERR
			fi
			if [ $bits -lt $RSA_MINBITS ]; then
				echo >&2 'RSA bits insufficient (RFC 8301), need at least '$RSA_MINBITS
				exit $EX_DATAERR
			fi
		fi
		opt="-pkeyopt rsa_keygen_bits:$bits"
		;;
	*) syno;;
	esac

	(
		set -C
		> "$fprefix"-pri.pem
		> "$fprefix"-pub.pem
	) || exit $EX_CANTCREAT

	set -e
	ossl genpkey -out "$fprefix"-pri.pem -outform PEM -algorithm $algo $opt
	ossl pkey -pubout -out "$fprefix"-pub.pem -outform PEM < "$fprefix"-pri.pem
	set +e

	echo 'Server keys stored in'
	echo '   '"$fprefix"-pri.pem
	echo '   '"$fprefix"-pub.pem
	echo 'Server also needs a ssh-keygen(1) allowed_signers_file in format'
	echo '  PRINCIPAL(ie, email address) KEYTYPE PUBKEY [COMMENT]'
	echo '(ie, authorized_keys format but prefixed by a PRINCIPAL)'
	;;
knock)
	[ $# -ne 5 ] && syno

	if [ -n "$DEBUG" ]; then
		kpk= kexe=
	else
		incrc
		kpk= kexe=
		if [ -x "$PORT_KNOCK_BIN" ]; then
			kpk=y
			kexe=$PORT_KNOCK_BIN
		else
			kexe=$(command -v bash 2>/dev/null)
			if [ $? -ne 0 ]; then
				echo >&2 'Knocking requires bash in $PATH; or '$PORT_KNOCK_BIN
				syno
			fi
		fi
	fi

	k=$(dd if=/dev/urandom bs=64 count=1 2>/dev/null | tr -cd 'a-zA-Z0-9_.,=@%^+-')
	if [ $? -ne 0 ]; then
		echo >&2 'Failed to create a random key'
		exit $EX_TEMPFAIL
	fi
	ek=$(echo "$k" | ossl pkeyutl -encrypt -pubin -inkey "$4" | ossl base64 | tr -d '\012 ')
	if [ $? -ne 0 ] || [ -z "$ek" ]; then
		echo >&2 'Failed to pkeyutl encrypt'
		exit $EX_TEMPFAIL
	fi

	es=$(printf '%s' "$MAGIC" | ssh-keygen -Y sign -n pokn -f "$5" |
		sed -Ee '/^-+BEGIN SSH/d;/^-+END SSH/d;s/$/ /' | tr -d '\012 ' |
		ossl enc -aes256 -pass "pass:$k" -pbkdf2 -e -A -a)
	if [ $? -ne 0 ] || [ -z "$es" ]; then
		echo >&2 'Failed to encrypt signature'
		exit $EX_TEMPFAIL
	fi

	if [ -n "$DEBUG" ]; then
		set -e
		{ echo "$ek"; echo "$es"; } > "$DEBUG"
	else
		if [ -z "$kpk" ]; then
			tmp_file_new
			printf "%s\n%s\n" "$ek" "$es" > "$tmp_file"
		fi

		while :; do
			printf 'knocking (via %s)... ' "$kexe"
			if [ -n "$kpk" ]; then
				"$kexe" client "$3" "$2" "$ek" "$es"
			else
				</dev/null $kexe -c '
					set -e
					cat "'"$tmp_file"'" > /dev/udp/"'"$2"'"/"'"$3"'"
				'
			fi
			[ $? -ne 0 ] && break
			echo 'done'
			act_sent "$2" && break
		done
	fi
	;;
verify)
	if [ -z "$DEBUG" ]; then
		[ $# -eq 2 ] || [ $# -eq 6 ] || syno
		incrc
		if [ $# -eq 6 ]; then
			ek=$5 es=$6
		fi
	elif [ $# -eq 2 ]; then
		:
	else
		[ $# -eq 4 ] || syno
		if [ ! -f "$DEBUG" ]; then
			echo >&2 'The result of "knock" does not exist: '$DEBUG
			syno
		fi
		{
			read ek
			read es
		} < "$DEBUG"
	fi

	if [ $# -eq 2 ]; then
		act_block "$2"
	else
		# (of course if pkeyutl fails *after* reading off the pipe ossl() will not do)
		tmp_file_new
		dk=$(echo "$ek" | ossl base64 -d | ossl pkeyutl -decrypt -inkey "$3")
		if [ $? -ne 0 ]; then
			act_block "$2"
		else
			echo "$es" | ossl enc -aes256 -pass "pass:$dk" -pbkdf2 -a -d | {
				printf '%s\n' '-----BEGIN SSH SIGNATURE-----'
				cat
				printf '\n%s\n' '-----END SSH SIGNATURE-----'
			} > "$tmp_file"

			p=$(ssh-keygen -Y find-principals -s "$tmp_file" -f "$4")
			if [ $? -eq 0 ]; then
				if [ -z "$MAGIC" ]; then
					act_allow "$2" "$p"
				elif printf '%s' "$MAGIC" |
						ssh-keygen -Y verify -n pokn -I "$p" -s "$tmp_file" -f "$4"; then
					act_allow "$2" "$p"
				else
					act_block "$2"
				fi
			else
				act_block "$2"
			fi
		fi
	fi
	;;
start-server)
	shift
	[ $# -eq 4 ] || [ $# -eq 5 ] || syno
	incrc
	v=
	if [ $# -eq 5 ]; then
		v=$1
		shift
	fi
	exec "$PORT_KNOCK_BIN" "$v" server "$@"
	;;
*)
	echo >&2 'Invalid command line: '$*
	syno
	;;
esac

exit 0
# s-sht-mode
