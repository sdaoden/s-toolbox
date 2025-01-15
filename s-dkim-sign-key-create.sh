#!/bin/sh -
#@ s-dkim-sign-key-create.sh: create keys for DKIM usage.
syno() {
	echo >&2 '  '$0' [ed25519|rsa[:BITS]] FILENAME-PREFIX'
	echo >&2
	echo >&2 'Please see manual for more.'
	exit 64 # EX_USAGE
}
#
# 2024 - 2025 Steffen Nurpmeso <steffen@sdaoden.eu>
# Public Domain

RSA_DEFBITS=2048
RSA_MINBITS=1024
ALGO_PARAM_DEF=ed25519

: ${SHELL:=/bin/sh}
: ${AWK:=awk}
: ${OPENSSL:=openssl}

#  --  >8  --  8<  --  #

# For heaven's sake auto-redirect on SunOS/Solaris
if [ -z "$__DKIM_KEY_CREATE_UP" ] && [ -d /usr/xpg4 ]; then
	__DKIM_KEY_CREATE_UP=y
	if [ "x$SHELL" = x/bin/sh ]; then
		echo >&2 'SunOS/Solaris, redirecting through $SHELL=/usr/xpg4/bin/sh'
		PATH=/usr/xpg4/bin:${PATH} SHELL=/usr/xpg4/bin/sh
		export __DKIM_KEY_CREATE_UP PATH SHELL
		exec $SHELL "$0" "$@"
	fi
fi

LC_ALL=C
EX_USAGE=64 EX_DATAERR=65 EX_CANTCREAT=73

export LC_ALL

if [ $# -eq 0 ] || [ $# -gt 2 ]; then
	syno
elif [ $# -eq 1 ]; then
	if [ "$1" = -h ] || [ "$1" = --help ]; then
		syno
	fi
	algo=$ALGO_PARAM_DEF
	prefix=$1
else
	algo=$1
	prefix=$2
fi

off=0
case $algo in
ed25519) opt= off=16;; # skip ASN.1 structure (Hanno Böck - thanks!)
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
	opt="-pkeyopt rsa_keygen_bits:$bits";;
*) syno;;
esac

# We do not want to overwrite
(
	set -C
	> "$prefix"-dkim-pri-$algo.pem
	> "$prefix"-dkim-dns-$algo.txt
) || exit $EX_CANTCREAT

x=
while :; do
	$OPENSSL genpkey -out "$prefix"-dkim-pri-$algo.pem -outform PEM -algorithm $algo $opt
	[ $? -eq 0 ] && break

	echo >&2
	echo >&2 '$OPENSSL='$OPENSSL' genpkey seems incompatible; is it an old version?'
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

$OPENSSL pkey -pubout -outform PEM < "$prefix"-dkim-pri-$algo.pem |
$AWK -v off=$off '
	BEGIN{on=0}
	/^-+BEGIN PUBLIC KEY-+$/{on=1;next}
	/^-+END PUBLIC KEY-+$/{exit}
	{
		if(on){
			if(off == 0)
				printf $1
			else{
				l = length($1)
				if(off - l < 0){
					printf substr($1, off + 1)
					off = l
				}
				off -= l
			}
		}
	}
	{next}
	END{printf "\n"}
' | {
	read pem
	a=$algo
	[ $a = rsa ] && a='rsa; h=sha256'
	echo 'v=DKIM1; k='$a'; p='$pem
} > "$prefix"-dkim-dns-$algo.txt || exit $EX_DATAERR

if [ -t 0 ]; then
	echo Private key: $prefix-dkim-pri-$algo.pem
	echo DNS entry: "$prefix"-dkim-dns-$algo.txt
	echo '(To be stored in a SELECTOR._domainkey.DOMAIN record,'
	echo 'for example foo.bar._domainkey.example.com.)'
	echo 'For testing add "; t=y" to the record.'
	echo 'For only exact domain matches (no subdomains), add "; t=[y:]s".'
fi

exit 0
# s-sht-mode
