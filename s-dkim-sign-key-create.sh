#!/bin/sh -
#@ s-dkim-sign-key-create.sh: create keys for DKIM usage.
syno() { echo >&2 'SYNOPSIS: '$0' [ed25519|rsa[:BITS]] FILENAME-PREFIX'; exit 64; } # EX_USAGE
#@
#@ 2024 Steffen Nurpmeso <steffen@sdaoden.eu>
#@ Public Domain

RSA_DEFBITS=2048
RSA_MINBITS=1024
ALGO_PARAM_DEF=ed25519

#  --  >8  --  8<  --  #

# For heaven's sake auto-redirect on SunOS/Solaris
if [ -z "${__DKIM_KEY_CREATE_UP}" ] && [ -d /usr/xpg4 ]; then
	if [ "x${SHELL}" = x ] || [ "${SHELL}" = /bin/sh ]; then
		echo >&2 'SunOS/Solaris, redirecting through $SHELL=/usr/xpg4/bin/sh'
		__DKIM_KEY_CREATE_UP=y PATH=/usr/xpg4/bin:${PATH} SHELL=/usr/xpg4/bin/sh
		export __DKIM_KEY_CREATE_UP PATH SHELL
		exec /usr/xpg4/bin/sh "${0}" "${@}"
	fi
fi

LC_ALL=C
EX_USAGE=64 EX_DATAERR=65 EX_CANTCREAT=73

export LC_ALL

if [ $# -eq 0 ] || [ $# -gt 2 ]; then
	syno
elif [ $# -eq 1 ]; then
	algo=$ALGO_PARAM_DEF
	prefix=$1
else
	algo=$1
	prefix=$2
fi

case $algo in
ed25519) opt=;;
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

openssl genpkey -quiet \
	-out "$prefix"-dkim-pri-$algo.pem -outform PEM \
	-algorithm $algo $opt || exit $EX_DATAERR

openssl pkey -pubout < "$prefix"-dkim-pri-$algo.pem | awk '
	BEGIN{on=0}
	/^-+BEGIN PUBLIC KEY-+$/{on=1;next}
	/^-+END PUBLIC KEY-+$/{on=0;exit}
	{if(on) printf $1}
	{next}
	END{printf "\n"}
' | {
	read pem;
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
