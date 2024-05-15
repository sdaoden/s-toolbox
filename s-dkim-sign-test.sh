#!/bin/sh -
#@ s-dkim-sign test
#@ NOTE: with SOURCE_DATE_EPOCH it is allowed to specify *no*keys*!

: ${KEEP_TESTS:=}
: ${SANITIZER:=}
REDIR= #'2>/dev/null'

: ${PDARGS:=}
: ${PD:=../s-dkim-sign $PDARGS}
: ${AWK:=awk}

###

: ${PDKC:=./s-dkim-sign-key-create.sh}
if [ 0 -eq 1 ]; then ${PDKC} ed25519 t; ${PDKC} rsa:2048 t; exit; fi

###

# For heaven's sake auto-redirect on SunOS/Solaris
if [ -z "${__DKIM_KEY_CREATE_UP}" ] && [ -d /usr/xpg4 ]; then
	if [ "x${SHELL}" = x ] || [ "x${SHELL}" = x/bin/sh ]; then
		echo >&2 'SunOS/Solaris, redirecting through $SHELL=/usr/xpg4/bin/sh'
		__DKIM_KEY_CREATE_UP=y PATH=/usr/xpg4/bin:${PATH} SHELL=/usr/xpg4/bin/sh
		export __DKIM_KEY_CREATE_UP PATH SHELL
		exec /usr/xpg4/bin/sh "${0}" "${@}"
	fi
fi

LC_ALL=C SOURCE_DATE_EPOCH=844221007
export LC_ALL SOURCE_DATE_EPOCH

[ -d .test ] || mkdir .test || exit 1
trap "trap '' EXIT; [ -z \"$KEEP_TESTS\" ] && rm -rf ./.test" EXIT
trap 'exit 1' HUP INT TERM

(
cd ./.test || exit 2
#pwd=$(pwd) || exit 3
pwd=. #$(pwd) || exit 3

### First of all create some resources {{{

x() {
	[ $1 -eq 0 ] || { echo >&2 'bad '$2': '$1; exit 1; }
	[ -n "$REDIR" ] || echo ok $2
}

y() {
	[ $1 -ne 0 ] || { echo >&2 'bad '$2': '$1; exit 1; }
	[ -n "$REDIR" ] || echo ok $2
}

cmp() {
	[ -n "$SANITIZER" ] && { echo '$SANITIZER, fake ok '$1; return 0; }
	command cmp -s "$2" "$3"
	x $? $1
}

e0() {
	if [ -n "$SANITIZER" ] && [ -s ERR ]; then
		echo >&2 'ERR bad, but $SANITIZER fake ok, save 'err-$1
		cp -f ERR err-$1
		return 0
	fi
	[ -s ERR ] && { echo >&2 'ERR bad '$1; exit 1; }
}

e0sumem() {
	sed -E -i'' -e '/.+\[debug\]: su_mem_.+(LINGER|LOFI|lofi).+/d' ERR
	e0 "$@"
}

eX() {
	[ -s ERR ] || { echo >&2 'ERR bad '$1; exit 1; }
	[ -n "$SANITIZER" ] && cp -f ERR err-$1
}

unfold() {
	hot= cl= foll=
	while read l; do
		if [ -z "$hot" ]; then
			[ "$l" = "${l#*$1}" ] && continue
			hot=y
		fi

		[ -n "$foll" ] && l=${l##* }
		[ "$l" != "${l%*\\}" ] && foll=y || foll=
		l=${l%*\\}
		cl="$cl$l"
	done
	[ -z "$hot" ] && { echo >&2 'IMPL ERROR'; exit 1; }
	[ $# -gt 0 ] && cl=${cl#$1* }
	echo $cl
}

coas_del() {
	while read l; do
		while [ "$l" != "${l#*,}" ]; do
			l1=${l##*,}
			l2=${l%,*}
			l="$l2 $l1"
		done
		echo $l
	done
}

coas_add() { # FIXME NOT NEEDED
	while read l; do
		while [ "$l" != "${l#* }" ]; do
			l1=${l##* }
			l2=${l% *}
			l="$l2,$l1"
		done
		echo $l
	done
}

cat > pri-ed25519.pem <<'_EOT'
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIM1VJDmiFlLrQ0iZj7txAA9SYAyeydrJDO1ytjSbkhKs
-----END PRIVATE KEY-----
_EOT
cat > pri-rsa.pem <<'_EOT'
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC1ooNyIS9gBQM/
eTdZSccSvzZkRl8Xu0JWSuuGwQL9Atq4hgsz65mUjJk09v1Kzy6M/hgl2Il+M48O
sBvL8ZgDcQuoLqczuWPzM3xfxyg9Jp4hUYwS3HdB5V8HnNe/n3YXzK2edR9nfFRA
Ote1XascgpNhZalr+Eg94Ceaf+f23CgiOlkgigE2RM7eq+E677X018TFkInTAiIv
Ng1dhNVpJhDHoxVRAkLvHpDz5f+e8IM47kgRp9QUGCMhVGw4kCO0EX8P4QDf99EH
QWW08jPkf4AFU+doDOieXSypxvWU28l085SjCbOYrrMk9mgG/keAU3Wrlu040BHj
B2Nyd1qXAgMBAAECggEABxE5uBkedMf9Jl0bEDhUrKAQB7rNPGkm3aCwpV+hNCMG
S6O7j9uc8DDATVVG6cBB+W5xlhdk0ipDaLjle/v8hDXD1FlsXBDcmLvqHPfs0uRL
xtQbdShq439/QRaTNnuH5skqAD5iaG5oAM/JUN9CJyvVfDaubusMNIwiPlq3td0u
FFHzFyRH5U0/GxGUubWBvCQ4lif1eVwczlf0pROQTi87ZmOAw3SZhAcAJos0OS1F
IQCnP4mFI0ol8AstscaJRYnlejO8T7XZtxJMDWlAbINuX7Z97mX1fsddDk3wD+NB
+VZU2f9k/AXxwN7gI9XFmd6Zdc5ni0yUe91cZFprgQKBgQD/qKsyX6MdFhzlGGVb
B7uZCcdZaWdxykGhnQ8kjX0RDHpokL0EDhGJxfjkum42nwcKp48azXmr9I13ufiJ
4hnSRkYzdyMmSLhchBe2FCcm3sQErVKw+JFZHN1LUcmExihMoUvG9EW9qr2IFwMW
7E96Ro83VWdYbrn/r1AC/NRPdwKBgQC14I8CgLbMrP3oicU9YveILB9ntUEGO5eG
jHQctk8bhxUcTkzA2f562soY5QCknpUcYWf8dOTNfPpiGSRLDScam3Snvyuhn6oh
GCTBICkI1FqdXLyUg5J17qPWVXsYR3DXUh5yscCmRsvYP+Hyqg06FjUmzd3tXXMO
V6wbax1V4QKBgQCU+IepNqkpTbVQmUKWJI9fwZ7zrsOkPqK3tXkZZ4i04nyBabV6
I2h8y2sYfLm0Aj5sKu7sQ0beuAWm+iqkzacWK/TEEGve5wjmf+IBKwUVVUELKKPC
k1S+hF8+gE3YnE7nOCWbrMLmnhMKtb4LIW++ZFcXeyBZG0wufM02sHRWSQKBgBke
QUHsOtK7lXl3BXl74Im65j9xZeCRfFTFsweAGh7IIh89pRYBRUb8TmrvvY3+pMM9
pJnWHv9OIlpH9J4029Ct5YeBPGpe3aUia3kMkv44LaeL9jNglGqbIZ9pQM3Sl//0
xGW8rMmJ/38HG5Ji79600HRifCLbBBfX/dnviiahAoGANioMZhSwzInLGH9fMTSH
69dZUyDDr7vgzubZt2SI3l0IREU094loE3umDMbnRD7m+Ha/VxgqxT+xf3ANWKh+
kCNew47RxSpVDxYRRmPplO7zjnwqUsb/ctXHSHHzIRaaCa7G49Rsuo50jGctx1p1
NNVmLx++OAZkFka7dwWZ9Ts=
-----END PRIVATE KEY-----
_EOT

### }}}

algos=$(${PD} -h 2>/dev/null | grep -F Algorithms:)
algo_ed25519_sha256= algo_rsa_sha256= algo_rsa_sha1=
[ "$algos" != "${algos#* ed25519-sha256}" ] && algo_ed25519_sha256=y
[ "$algos" != "${algos#* rsa-sha256}" ] && algo_rsa_sha256=y
[ "$algos" != "${algos#* rsa-sha1}" ] && algo_rsa_sha1=y

ka= kf= k= kR= k2a= k2f= k2= k2R=
# we cannot do "x=y z=$x" due to {Free,Net}BSD sh(1)
if [ -n "$algo_rsa_sha1" ]; then
	ka=rsa-sha1 kf=pri-rsa.pem
	k=--key=$ka,I,$kf kR='key '$ka', I, '$kf k2a=$ka k2f=$kf k2=--key=$ka,II,$kf k2R='key '$ka', II, '$kf
fi
if [ -n "$algo_rsa_sha256" ]; then
	ka=rsa-sha256 kf=pri-rsa.pem
	k=--key=$ka,I,$kf kR='key '$ka', I, '$kf k2a=$ka k2f=$kf k2=--key=$ka,II,$kf k2R='key '$ka', II, '$kf
fi
if [ -n "$algo_ed25519_sha256" ]; then
	ka=ed25519-sha256 kf=pri-ed25519.pem
	k=--key=$ka,I,$kf kR='key '$ka', I, '$kf
fi
[ -z "$k" ] && { echo >&2 no keys to test; exit 78; } # EX_CONFIG
[ $k2a = $ka ] && k2a= k2f= k2= k2R=

##
echo '=1: options=' # {{{

# 1.* --header-(sign|seal) (+ --resource-file with \ follow-ups) {{{
t1() {
	${PD} --header-${3}-show 2>ERR |
		${AWK} 'BEGIN{i=1}{if(i++ == '$4') {sub("^.+:[[:space:]]*", ""); print; exit;}}' > t1.$1.1 2>&1
	x $? 1.$1.1
	e0 ERR

	allinc=
	if [ "$3" = seal ]; then
		if [ "$2" = '*' ] || [ "$2" = '+' ]; then
			allinc='-~*'
		fi
	fi

	${PD} --test-mode $allinc --header-${3}="$2" > t1.$1.2 2>ERR
	x $? 1.$1.2
	e0 1.$1.2

	${PD} -# $allinc --header-$3="$2" > t1.$1.3 2>ERR
	x $? 1.$1.3
	e0 1.$1.3

	cmp 1.$1.4 t1.$1.2 t1.$1.3

	unfold header-$3 < t1.$1.2 | coas_del > t1.$1.5
	cmp 1.$1.5 t1.$1.5 t1.$1.1

	read hl < t1.$1.5
	hl=${hl% cc *}' '${hl#* cc }
	hl=${hl% subject *}' '${hl#* subject }
	hl=${hl% date *}' '${hl#* date }
	echo $hl boah > t1.$1.6
	x $? 1.$1.6

	if [ "$3" = seal ]; then
		[ -z "$allinc" ] && allinc='-~*'
		allinc=${allinc}boah
		${PD} -# --header-$3 "$2"'!dATe,   !cC        ,   !suBJect , bOah ' > t1.$1.7-fail 2>ERR
		y $? 1.$1.7-fail
	fi

	${PD} -# $allinc --header-$3 "$2"'!DatE,   !Cc        ,   !sUbjECt , boAh ' > t1.$1.7 2>ERR
	x $? 1.$1.7
	e0 1.$1.7

	unfold header-$3 < t1.$1.7 | coas_del > t1.$1.8
	cmp 1.$1.8 t1.$1.6 t1.$1.8

	printf '\\\n   \t\t\t    \\\n\\\n\\\nheader-\\\n  \t \\\n\t '$3'\t \\\n\t from\n' > t1.$1.9.rc
	${PD} -# -R t1.$1.9.rc > t1.$1.9 2>ERR
	x $? 1.$1.9
	e0 1.$1.9

	unfold header-$3 < t1.$1.9 | coas_del > t1.$1.10
	read hl < t1.$1.10
	[ "$hl" = from ]
	x $? 1.$1.10

	${PD} -# --header-$3="${2}!frOM" > t1.$1.11 2>&1
	y $? 1.$1.11
	${PD} -# --header-$3="  ,  ${2}" > t1.$1.12 2>&1
	y $? 1.$1.12
	${PD} -# --header-$3="FRom,!tO" > t1.$1.13 2>&1
	y $? 1.$1.13
}
t1 1 '@' sign 1
t1 2 '*' sign 2
t1 3 '@' seal 1
t1 4 '*' seal 2
t1 5 '+' seal 3

# seal-must-be-included-in-sign
${PD} -# --header-sign=@ --header-seal=* > t1.5 2>&1
y $? 1.5
${PD} -# --header-sign=@ --header-seal=@ > t1.6 2>&1
x $? 1.6
${PD} -# --header-sign=* --header-seal=@ > t1.7 2>&1
x $? 1.7
${PD} -# --header-sign=* --header-seal=* > t1.8 2>&1
x $? 1.8
${PD} -# --header-sign=* --header-seal=*,au > t1.9 2>&1
y $? 1.9
${PD} -# --header-sign=*,au --header-seal=*,au > t1.10 2>&1
x $? 1.10
${PD} -# --header-sign=@ --header-seal=+ > t1.11 2>&1
y $? 1.11
${PD} -# --header-sign=* --header-seal=+ > t1.12 2>&1
x $? 1.12
# }}}

# 3.* --key {{{
if [ -z "$algo_ed25519_sha256" ]; then
	echo >&2 no ed25519-sha256, skip 3.1-3.6
else
	${PD} -# --key ed25519-sha256,ed1,pri-ed25519.pem > t3.1 2>ERR
	x $? 3.1
	e0 3.1
	${PD} -# --key=' ed25519-sha256 ,  ed1  ,   pri-ed25519.pem  ' > t3.2 2>ERR
	x $? 3.2
	e0 3.2
	cmp 3.3 t3.1 t3.2

	${PD} -# -k ed25519-sha256,ed1,pri-ed25519.pem > t3.4 2>ERR
	x $? 3.4
	e0 3.4
	${PD} -# -k' ed25519-sha256 ,  ed1  ,   pri-ed25519.pem  ' > t3.5 2>ERR
	x $? 3.5
	e0 3.5
	cmp 3.6 t3.4 t3.5
fi

if [ -z "$algo_rsa_sha256" ]; then
	echo no rsa-sha256, skip 3.7-3.12
	4.1-4.6
else
	${PD} -# --key rsa-sha256,ed1,pri-rsa.pem > t3.7 2>ERR
	x $? 3.7
	e0 3.7
	${PD} -# --key=' rsa-sha256 ,  ed1  ,   pri-rsa.pem  ' > t3.8 2>ERR
	x $? 3.8
	e0 3.8
	cmp 3.9 t3.7 t3.8

	${PD} -# -k rsa-sha256,ed1,pri-rsa.pem > t3.10 2>ERR
	x $? 3.10
	e0 3.10
	${PD} -# -k' rsa-sha256 ,  ed1  ,   pri-rsa.pem  ' > t3.11 2>ERR
	x $? 3.11
	e0 3.11
	cmp 3.12 t3.10 t3.11
fi

if [ -z "$algo_rsa_sha1" ]; then
	echo no rsa-sha1, skip 3.13-3.18
else
	echo '--key: RFC 8301 forbids usage of SHA-1: rsa-sha1' > t3.sha1-err

	${PD} -# --key rsa-sha1,ed1,pri-rsa.pem > t3.13 2>ERR
	x $? 3.13
	cmp 3.13-err ERR t3.sha1-err
	${PD} -# --key='rsa-sha1 ,  ed1  ,   pri-rsa.pem  ' > t3.14 2>ERR
	x $? 3.14
	cmp 3.14-err ERR t3.sha1-err
	cmp 3.15 t3.13 t3.14

	${PD} -# -k rsa-sha1,ed1,pri-rsa.pem > t3.16 2>ERR
	x $? 3.16
	cmp 3.16-err ERR t3.sha1-err
	${PD} -# -k'rsa-sha1 ,  ed1  ,   pri-rsa.pem  ' > t3.17 2>ERR
	x $? 3.17
	cmp 3.17-err ERR t3.sha1-err
	cmp 3.18 t3.16 t3.17
fi

${PD} -# --key rsax-sha256,no1.-,pri-rsa.pem > t3.20 2>&1
y $? 3.20
${PD} -# --key rsa-sha256x,no1.-,pri-rsa.pem > t3.21 2>&1
y $? 3.21
${PD} -# --key 'rsa-sha256,    ,pri-rsa.pem' > t3.22 2>&1
y $? 3.22
${PD} -# --key rsa-sha256,.no,pri-rsa.pem > t3.23 2>&1
y $? 3.23
${PD} -# --key rsa-sha256,-no,pri-rsa.pem > t3.24 2>&1
y $? 3.24
${PD} -# --key 'rsa-sha256,no1.-,pri-rsax.pem' > t3.25 2>&1
y $? 3.25
${PD} -# --key $ka,no1.-,$kf > t3.26 2>ERR
x $? 3.26
e0 3.26

${PD} -# --key $ka,this-is-a-very-long-selector-that-wraps-lines-i-guess,$kf > t3.30 2>ERR
x $? 3.30
e0 3.30
${PD} -# -R t3.30 > t3.31 2>ERR
x $? 3.31
e0 3.31
cmp 3.32 t3.30 t3.31
{ read -r i1; read i2; } < t3.31
[ -n "$i2" ]
x $? 3.33

${PD} -# --key ',,,' > t3.34 2>&1
y $? 3.34
${PD} -# --key 'rsa-sha256,,' > t3.35 2>&1
y $? 3.35
${PD} -# --key 'rsa-sha256,s,' > t3.36 2>&1
y $? 3.36
${PD} -# --key 'rsa-sha256,s' > t3.37 2>&1
y $? 3.37

${PD} -# > t3.40 2>ERR
x $? 3.40
e0 3.40
(	# needs at least one --key, except then
	unset SOURCE_DATE_EPOCH
	${PD} -# > t3.41 2>&1
	y $? 3.41
)
# }}}

# 5.* --domain-name {{{
${PD} -# --domain-name my.dom.ain > t5.1 2>&1
x $? 5.1
${PD} -# -d my.dom.ain > t5.2 2>&1
x $? 5.2
cmp 5.3 t5.1 t5.2
echo 'domain-name my.dom.ain' > t5.4
cmp 5.4 t5.2 t5.4

${PD} -# --domain-name .mydom > t5.5 2>&1
y $? 5.5
${PD} -# --domain-name -mydom > t5.6 2>&1
y $? 5.6
${PD} -# --domain-name 1.dom > t5.7 2>&1
x $? 5.7
# }}}

# 7.* --milter-macro {{{
${PD} -# --milter-macro sign,oha > t7.1 2>ERR
x $? 7.1
e0 7.1
${PD} -# -M'   sign  ,     oha ,,,' > t7.2 2>ERR
x $? 7.2
e0 7.2
cmp 7.3 t7.1 t7.2

${PD} -# --milter-macro sign,oha,,v1,,,v2,,, > t7.4 2>ERR
x $? 7.4
e0 7.4
${PD} -# -Msign,oha,',,,,       v1   ,   v2     '  > t7.5 2>ERR
x $? 7.5
e0 7.5
cmp 7.6 t7.4 t7.5
echo 'milter-macro sign, oha, v1, v2' > t7.7
cmp 7.7 t7.5 t7.7

${PD} -# -Msign,oha,'v1 very long value that sucks very much are what do you say?  ,'\
'v2 and another very long value that drives you up the walls ,   '\
'v3 oh noooooooooo, one more!,,' > t7.8 2>ERR
x $? 7.8
e0 7.8
i=0; while read -r l; do i=$((i + 1)); done < t7.8
[ $i -eq 4 ]
x $? 7.9

${PD} -# --milter-macro no,oha > t7.10 2>ERR
y $? 7.10
eX 7.10

${PD} -# --milter-macro sign,,oha > t7.11 2>ERR
y $? 7.11
eX 7.11

${PD} -# --milter-macro sign > t7.12 2>ERR
y $? 7.12
eX 7.12

${PD} -# --milter-macro sign,,,, > t7.13 2>ERR
y $? 7.13
eX 7.13
# }}}

# 8.* --sign {{{
${PD} -# $k --sign a@b,b,I > t8.1 2>ERR
x $? 8.1
e0 8.1
${PD} -# $k -S '      a@b  ,  b  ,  I '  > t8.2 2>ERR
x $? 8.2
e0 8.2
cmp 8.3 t8.1 t8.2
{ echo $kR; echo 'sign a@b, b, I'; } > t8.4
cmp 8.4 t8.2 t8.4

if [ -z "$k2a" ]; then
	echo >&2 'only one key-algo type, skip 8.5-8.13'
else
	${PD} -# $k $k2 --sign 'a@b,b,I:II' > t8.5 2>ERR
	x $? 8.5
	e0 8.5
	${PD} -# $k $k2 -S '      a@b  ,  b  ,  ::I :::II:::	 ::'  > t8.6 2>ERR
	x $? 8.6
	e0 8.6
	cmp 8.7 t8.5 t8.6
	{ echo $kR; echo $k2R; echo 'sign a@b, b, I:II'; } > t8.8
	cmp 8.8 t8.6 t8.8

	${PD} -# $k --sign 'a@b,b,I:II' > t8.9 2>/dev/null
	y $? 8.9
	{ echo $kR; echo 'sign a@b, b, I'; } > t8.10
	cmp 8.11 t8.9 t8.10

	${PD} -# -R t8.5 > t8.12 2>ERR
	x $? 8.12
	e0 8.12
	cmp 8.13 t8.5 t8.12
fi


${PD} -# $k --sign a@.b,,I > t8.14 2>ERR
x $? 8.14
e0 8.14
{ echo $kR; echo 'sign a@.b,, I'; } > t8.15
cmp 8.15 t8.14 t8.15

${PD} -# $k --sign 'a@.b ,    ,   :::::: : ' > t8.16 2>ERR
x $? 8.16
e0 8.16
{ echo $kR; echo 'sign a@.b'; } > t8.17
cmp 8.17 t8.16 t8.17

${PD} -# $k --sign 'a@.b' > t8.18 2>ERR
x $? 8.18
e0 8.18
{ echo $kR; echo 'sign a@.b'; } > t8.19
cmp 8.19 t8.18 t8.19

${PD} -# $k --sign '.b,' > t8.20 2>ERR
x $? 8.20
e0 8.20
{ echo $kR; echo 'sign .b'; } > t8.21
cmp 8.21 t8.20 t8.21

${PD} -# $k --sign '.' > t8.22 2>ERR
x $? 8.22
e0 8.22
{ echo $kR; echo 'sign .'; } > t8.23
cmp 8.23 t8.22 t8.23

#
${PD} -# $k --sign ',,' > t8.24 2>&1
y $? 8.24

if [ -z "$SANITIZER" ]; then
	${PD} -# --sign 'a;b@.,,' > t8.25 2>&1
	y $? 8.25
	echo '--sign: spec failed parse (need quoting?): a;b@.' > t8.26
	cmp 8.26 t8.25 t8.26

	${PD} -# --sign 'a;b@.,,' > t8.27 2>&1
	y $? 8.27
	echo '--sign: spec failed parse (need quoting?): a;b@.' > t8.28
	cmp 8.28 t8.27 t8.28

	${PD} -# --sign 'a";"b@.,,' > t8.29 2>&1
	y $? 8.29
	cat > t8.30 <<-'_EOT'
	--sign: bogus input <a";"b@.>
	  Parsed: group display <> display <> local-part <"a;b"> domain <.>
	_EOT
	cmp 8.30 t8.29 t8.30
else
	echo >&2 '$SANITIZER, skipping 8.25-8.29'
fi

${PD} -# --sign ',' > t8.31 2>&1
y $? 8.31

${PD} -# $k -S y@.,, --sign a@.b,,I -S x@.b,, -S .n.o,y.e.s > t8.32 2>ERR
x $? 8.32
e0 8.32
cat > t8.33 << _EOT
$kR
sign a@.b,, I
sign .n.o, y.e.s
sign x@.b
sign y@.
_EOT
cmp 8.34 t8.32 t8.33

cat > t8.35.rc << '_EOT'
a@.b,, I
x@.b,
y@.,,
.n.o, y.e.s
_EOT
${PD} -# $k -s t8.35.rc > t8.35 2>ERR # --sign-file
x $? 8.35
e0 8.35
cmp 8.36 t8.32 t8.35
# }}}

# 9.* --client {{{
${PD} -# --client=pass,. > t9.1 2>ERR
x $? 9.1
e0 9.1
${PD} -# -C '  pass    ,      .  '  > t9.2 2>ERR
x $? 9.2
e0 9.2
cmp 9.3 t9.1 t9.2
echo 'client pass, .' > t9.4
cmp 9.4 t9.2 t9.4

${PD} -# --client=. > t9.5 2>ERR
x $? 9.5
e0 9.5
${PD} -# -C '        .  '  > t9.6 2>ERR
x $? 9.6
e0 9.6
cmp 9.7 t9.5 t9.6
echo 'client sign, .' > t9.8
cmp 9.8 t9.8 t9.6

cat > t9.9.rc << '_EOT'; cat > t9.10 << '_EOT'
client .dom.ain,

client s, dom.ain

client ya.dom.ain
client 127.0.0.1

     client \
p,\
.dom.ain

client 2a03:2880:20:6f06:face:b00c:0:14/66
client sign 	  , 	  2a03:3000:20:6f06::/80
client p 	 , 	 , 192.168.0.1/24
client pass 	 , 	 192.168.0.1/24

_EOT
--client: invalid action: .dom.ain, 
--client: domain name yet seen: dom.ain
--client: address masked, should be 2a03:2880:20:6f06:c000::/66 not 2a03:2880:20:6f06:face:b00c:0:14/66
--client: invalid domain (CIDR notation?): p, , 192.168.0.1/24
--client: address masked, should be 192.168.0.0/24 not 192.168.0.1/24
client sign, 127.0.0.1
client pass, .dom.ain
client sign, ya.dom.ain

client sign, 2a03:2880:20:6f06:c000::/66
client sign, 2a03:3000:20:6f06::/80
client pass, 192.168.0.0/24
_EOT

${PD} -# -R t9.9.rc > t9.9 2>&1
y $? 9.9
cmp 9.10 t9.9 t9.10

cat > t9.11-1 << '_EOT'; cat > t9.11-2 << '_EOT'
ya.dom.ain
127.0.0.1
2a03:2880:20:6f06:c000::/66
2a03:3000:20:6f06::/80
_EOT
.dom.ain
192.168.0.0/24
_EOT
${PD} -# -c t9.11-1 -c pass,t9.11-2 > t9.11 2>ERR # --client-file
x $? 9.11
e0 9.11
${PD} -# -c sign,t9.11-1 -c p,t9.11-2 > t9.12 2>ERR
x $? 9.12
e0 9.12
cmp 9.13 t9.11 t9.12

cat > t9.14 << '_EOT'
client sign, 127.0.0.1
client pass, .dom.ain
client sign, ya.dom.ain

client sign, 2a03:2880:20:6f06:c000::/66
client sign, 2a03:3000:20:6f06::/80
client pass, 192.168.0.0/24
_EOT
cmp 9.14 t9.12 t9.14
# }}}

# 10.* --ttl {{{
${PD} -# --ttl 30 > t10.1 2>&1
x $? 10.1
${PD} -# -t 30 > t10.2 2>&1
x $? 10.2
cmp 10.3 t10.1 t10.2

${PD} -# --ttl $((60*60*24*1000)) > t10.4 2>ERR
x $? 10.4
e0 10.4
${PD} -# -t $((60*60*24*1000)) > t10.5 2>ERR
x $? 10.5
e0 10.5
cmp 10.6 t10.4 t10.5
[ -s t10.4 ]
x $? 10.7

${PD} -# --ttl 29 > t10.8 2>&1
y $? 10.8
${PD} -# --ttl $((60*60*24*1000 + 1)) > t10.9 2>&1
y $? 10.9
# }}}

# 11.* --remove {{{
${PD} -# --remove a-r > t11.1 2>ERR
x $? 11.1
e0 11.1
${PD} -# -r'   a-r , ,,, ,, , ,     ' > t11.2 2>ERR
x $? 11.2
e0 11.2
cmp 11.3 t11.1 t11.2

${PD} -# --remove a-r,!,.de > t11.4 2>ERR
x $? 11.4
e0 11.4
echo 'remove a-r, !, .de' > t11.5
cmp 11.5 t11.4 t11.5

${PD} -# --remove a-r,!,,.com,,,.de,,.du > t11.6 2>ERR
x $? 11.6
e0 11.6
echo 'remove a-r, !, .com, .de, .du' > t11.7
cmp 11.7 t11.7 t11.7

${PD} -# --remove a-r,. > t11.8 2>ERR
x $? 11.8
e0 11.8
echo 'remove a-r, .' > t11.9
cmp 11.9 t11.8 t11.9

${PD} -# --remove 'a-r, ., !' > t11.10 2>ERR
y $? 11.10
eX 11.11

${PD} -# --remove '' > t11.12 2>ERR
y $? 11.12
eX 11.12
# }}}

# 90* --resource-file (yet; except recursion, and overwriting) {{{
cat > t90.rc << '_EOT'
header-sign from , to
header-seal from , date
milter-macro sign, mms1
resource-file t90-1.rc
_EOT
cat > t90-1.rc << '_EOT'
header-sign from , date
header-seal from , subject
milter-macro sign , mms2 , v1 ,v2,,v3,,v4,,
resource-file t90-2.rc
_EOT
cat > t90-2.rc << '_EOT'


header-sign from , subject, date


header-\
   seal ,  \
	  	,	\
	 	,,\
from\
, subject , date ,,,,


milter\
-macro \
sign	\
,mms3

	 	# comment \
 	 	line \
  continue

_EOT
cat > t90-x << '_EOT'
milter-macro sign, mms3
header-sign from, subject, date
header-seal from, subject, date
_EOT

${PD} -# -R t90.rc > t90 2>ERR
x $? 90
e0 90
cmp 91 t90 t90-x

printf '\n\\\n\\\n' > t92.rc
${PD} -# -R t92.rc > t92 2>ERR
x $? 92
e0 92
[ -s t92 ] && { echo >&2 'bad 93'; exit 1; }
echo ok 93
# }}}
# }}}

echo '=2: Going =' # {{{

# 6376, 3.4.4/5 (empty body hash of 3.4.4: 47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=)
if [ -n "$algo_rsa_sha256" ]; then
	echo 'key=rsa-sha256,I,pri-rsa.pem' > x.rc
	echo 'header-seal from' >> x.rc
	{
		printf '\0\0\0\013LFrom\0 X@Y\0'
		printf '\0\0\0\023LSubject\0 Y\t\r\n\tZ  \0'
		printf '\0\0\0\01E'
		printf '\0\0\0\01Q'
	} | ${PD} -R x.rc > t200-rsa 2>ERR
	x $? 200-rsa
	e0sumem 200-rsa
printf \
'DKIM-Signature:v=1; a=rsa-sha256; c=relaxed/relaxed; d=y; s=I;\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=fkhliqdp/tDI3ksZmswguuA7qiBhMFRSPTH3aTUYRDB809kCZHRv+ZvxbupCFmv\n'\
'  WgNQWPVz04I+eGiyIYwguZ2GhiMKHZNyln3Ih1M062NA4g8mSQ72HcB1xtL6EKmdzrUf1hVxEn\n'\
'  /P/QdYdhXVnK/4tGbuh9MH+CvlGW4/5lddPlO31pnwa1k/q3B4s4qvsVFBPRAdbxsUynUtdKU6\n'\
'  zVAsn1S4anqRbW+gNLZX1JikJUnyWHTmYIsx7dhhc7AJQMZPi1U5nO20Xbboci/5jj/8XC4Stm\n'\
'  lzJut4dfIs1xsgBB21snyvCj3uYQBcK/YEWCGoDLSQ/VsK8VZKUgUo2QA==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t201-rsa
	cmp 201-rsa t200-rsa t201-rsa
else
	echo >&2 'RSA not supported, skipping tests t200-rsa,t201-rsa'
fi

if [ -z "$algo_ed25519_sha256" ]; then
	echo >&2 'Skipping further tests due to lack of Ed25519 algorithm'
	exit 0
fi

echo $kR > x.rc
echo 'header-seal from' >> x.rc

# same
{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\023LSubject\0 Y\t\r\n\tZ  \0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --key=$ka,this.is.a.very.long.selector,$kf \
	--sign .,dOEDel.de,this.is.a.very.long.selector \
	--sign '.y   ,auA.DE,I' \
	> t200 2>ERR
x $? 200
e0sumem 200
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=XZsTsoDGBj1ThBUusPXOlKZnJPfTWAcOXp1lLFITL65MW6zgXPLXB9Oum+nkomK\n'\
'  sG9vD5myIH0f+z0Y2hDBvCg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t201
cmp 201 t200 t201

# same, mixed
if [ -n "$algo_rsa_sha256" ]; then
	echo 'key=big_ed-sha256,III,pri-ed25519.pem' >> x.rc
	echo 'key=rsa-sha256,II,pri-rsa.pem' >> x.rc
	{
		printf '\0\0\0\013LFrom\0 X@Y\0'
		printf '\0\0\0\023LSubject\0 Y\t\r\n\tZ  \0'
		printf '\0\0\0\01E'
		printf '\0\0\0\01Q'
	} | ${PD} -R x.rc > t200-mix 2>ERR
	x $? 200-mix
	e0sumem 200-mix
printf \
'DKIM-Signature:v=1; a=rsa-sha256; c=relaxed/relaxed; d=y; s=II;\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=EiRf59wANQ8MN5c1KnfdI51skZJTYzbCJc/nWwZoh6arCkR3kR7CucW/fHmctkK\n'\
'  NGCXK0nEU8jnuJa4YGx7XCLzkqXc9gULecHnvdaOLx7Guutfm8nBHV/6dyBTfEEdKa+oaTEKs8\n'\
'  LEDbxy/9hDswjMszKyaYyPq79SFXYH60yJJwAZTglcNhZwd092xql7fLlij53s77Q5Zqye0yLy\n'\
'  Z+JiGPpSILrADTMH5ROyCB/j15l1CNnWR7EPR3txs9+/5GksQTkXtdjdr3cwMr0e0me8ucEZZG\n'\
'  1SP7XjhkcYPnKLohhgudi8Kw1/9sSsJt0Q+9eJELtNsMKsKPK1rXm1JYg==\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=y; s=III;\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=85yrMYJLX8wAGK9hUNn8Q81UK1cN8w4ic9dDPDrjzL/wUbGIcgUkXQ008ct87ey\n'\
'  47lfcOJeoiTW6tluyeg0yCw==\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=y; s=I;\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=Wv2zq8YuDiqQSIKGINHUyLMvHXERzRO9N5ZQulDIeHrHSvbg4IQSJI+CJTCOUzF\n'\
'  eXLutbxP4RFxirZtJKsbsDg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t201-mix
	cmp 201-mix t200-mix t201-mix
else
	echo >&2 'RSA not supported, skipping tests t200-mix,t201-mix'
fi

##
echo $kR > x.rc
echo 'header-seal from' >> x.rc

# 6376, 3.4.5; also (contrary to RFC 6376): header continuation line: lonely \n / \r is WSP!!
{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\022B \tC \r\nD \t E\r\n\r\n\r\n'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --key=$ka,this.is.a.very.long.selector,$kf \
	--sign .,dOEDel.de,this.is.a.very.long.selector \
	--sign 'y   ,auA.DE,I' \
	> t202 2>ERR
x $? 202
e0sumem 202
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=unak6JHq0wL+Q1HP7dW1tjBx9FLA6DffoZ0qr\n'\
'  Lwbbpo=; b=dNyvWBMO6P6k/nYbpWlm8eK5L4jNb+pper49iOQ/yboY2P5ty2aKFBaRi3cTxx0\n'\
'  r5z965vlchM5kwa9gN3QtDA==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t203
cmp 203 t202 t203

## seq 13421 > a.txt

if command -v seq >/dev/null 2>&1; then :; else
	echo >&2 'No seq(1) available, skipping further tests'
	exit 0
fi

{
printf '\0\0\0\013LFrom\0 X@Y\0'
printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
printf '\0\0\313\376B'
seq 8888 | ${AWK} '{sub("$", "\r"); print}'
printf '\0\0\167\235B'
seq 8889 13421 | ${AWK} '{sub("$", "\r"); print}'
printf '\0\0\0\01E'
printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t204 2>ERR
x $? 204
e0sumem 204
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=PzUIcKYLlFjDJtEAT+6JZpXkPgH2VFMvaxAEz\n'\
'  NP3cWk=; b=fGXDjaUMwMmfCW7ADJ1Qc/om2WB7fviw1TLyVj99nPCVXkPqO13ARXrbLzTutel\n'\
'  4+H2fECaR3nHU2uPAe2JNBA==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t205
cmp 205 t204 t205

# ..other order
{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\145\346B'
	seq 4532 | ${AWK} '{sub("$", "\r"); print}'
	printf '\0\0\335\265B'
	seq 4533 13421 | ${AWK} '{sub("$", "\r"); print}'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t206 2>ERR
x $? 206
e0sumem 206
cmp 207 t204 t206

# ..and bytewise
{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B3\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B4\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B5\0\0\0\003B\r\n'
	printf '\0\0\0\002B6\0\0\0\003B\r\n'
	printf '\0\0\0\002B7\0\0\0\003B\r\n'
	printf '\0\0\0\002B8\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B9\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\145\313B'
	seq 10 4532 | ${AWK} '{sub("$", "\r"); print}'
	printf '\0\0\335\265B'
	seq 4533 13421 | ${AWK} '{sub("$", "\r"); print}'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t208 2>ERR
x $? 208
e0sumem 208
cmp 209 t204 t208

# Special \r\n cases
{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2\0\0\0\002B\r'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t210 2>ERR
x $? 210
e0sumem 210
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=vq8fFHPPqqkcinB83aEumTVgnU+qPqNqWSUgU\n'\
'  EkP2L0=; b=fN/etAORxhK2pRauvaW4wCvStge7pxtnzuF8qBwFdi3/e/Jsd+gtOLcAaVjCOYz\n'\
'  5HZ9haXpkFxcFZSK6V9RMBQ==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t211
cmp 211 t210 t211

{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2\0\0\0\002B\r\0\0\0\003B\r\n'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t212 2>ERR
x $? 212
e0sumem 212
cmp 213 t211 t212

{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2\0\0\0\002B\n'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t214 2>ERR
x $? 214
e0sumem 214
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=2lM8tKY3+20Uu1AZLSBrCf59CqYv31qtqmmPj\n'\
'  4rBX7c=; b=YoBrDj6EgTKF6qEeNunu2NDYTJkUsro1jBCnLo5Pe8mEnh3GCGxsVu/XDg/nTvY\n'\
'  yNRzrLkoCBVJNyLeKfpWyDQ==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t215
cmp 215 t214 t215

{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2\0\0\0\002B\n\0\0\0\003B\r\n'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t216 2>ERR
x $? 216
e0sumem 216
cmp 217 t215 t216

{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t218 2>ERR
x $? 218
e0sumem 218
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=tHOTehVL0EWpeJdZjJlAZZd7rm5SEpYBE1axW\n'\
'  pHw9Ns=; b=4+ZdjuiWuqk9wb3bIyCcphmKF64N1D08sh167SUL/2CQTk10oZdgIf7SJFNEWpx\n'\
'  Ko3cRzU+C/b0pgefVEKTAAQ==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t219
cmp 219 t218 t219

{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t220 2>ERR
x $? 220
e0sumem 220
cmp 221 t218 t220

## canon test with holes

if command -v dd >/dev/null 2>&1; then :; else
	echo >&2 'No dd(1) available, skipping further tests'
	exit 0
fi
if command -v openssl >/dev/null 2>&1; then :; else
	echo >&2 'No openssl(1) available, skipping further tests'
	exit 0
fi
if command -v zstd >/dev/null 2>&1; then :; else
	echo >&2 'No zstd(1) available, skipping further tests'
	exit 0
fi

# b64 {{{
openssl base64 -d << '_EOT' | zstd -d > t300.in
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
8fX4elzZAVQAACUNM4DSVAEAAgFUAAAlGjOBolQBAAIBVAEAEg0IBOAPyRJ/AAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKA0VQBAAIBVAAAJQ00gNJUAQACAVQAADUa
NIGjVAEAAgFUAAAVDTSA0VQBAAIBVAEAIg0IBOAPFRr///////9/AAAAAAAAAAAA
AAAAAAAAAAAAAASA0lQBAAIBVAAAZTQ1g0ZUAQACAVQBABINCATgD1ET////////
////////PwAAAAAAAAAAAAAAAAACgNFUAQACAVQAACUNNoDSVAEAAgFUAAA1GjaB
o1QBAAIBVAAAFQ02gNFUAQACAVQBABINCATgDxkb////////////////////////
HwAAAAAAAAACgNFUAQACAVQAADUaN4GjVAEAAgHcAAAlGjeBo6gh/AHh778BEeQf
SSYHCBoZLUkGQRBUAQASDQgE4A/ZE////////////////////////////////w8A
AoDRVAEAAgFUAAAlDTiA0lQBAAIBVAAANRo4gaNUAQACAVQBABINCATgDx0c////
/wMAAAAAAAAAAAAAAAAAAAAAAAAAAAACgNFUAQACAVQAACUNOYDSVAEAAgFUAAA1
GjmBo1QBAAIBVAAAFQ05gNFUAQACAXwFACaSHAqwuQFka7bPcDNACgAQACQA////
////////AysjGxMLAyuaof///////39iYWBFYcJcGdmYWBhYERgwV0Y2JhYGVlRT
c2VkY2JhYEU0NANT5srIxsTCwIrIkLkysjGxMLCiMWOujGxMLAysSIyYKyMbC4DS
qBC4PuDXIIQfgWq1i45qtRMd1WoXHdVqJzqq1S46qtVOdFSrXXRUq50vBwQBAAAA
AAAAAACAomFkOAA60YgVCbDrJBSxeMgzeFcBXwFPAYWzq6Przcnx4uDOzMrIamNi
tDCwK6sqqtaUFCsK6sioiKg0JEQKArpaq9R2KmWj0BubGprOjAwnBubEpISkMiJC
CQE5GovEcigkg5zbruk+y4yAmNuu6T7LDACY267pPsuMg5Pbruk+ywwDk9uu6T7L
jIKS267pPss8gG67pvssMwqV267pPsuMgZHbruk+ywwBkduu6T7LDALltmu6zzIj
IOS2a7rPMgMA5LZrus8y4+B42zXdZ5lhYLztmu6zzCgo3nZN91lmEBBvu6b7LDMK
5W3XdJ9lxsDwtmu6zzJDQHjbNd1nmUEgb7um+ywzAoK3XdN9lhkAwNuu6T7LjIOL
267pPssMA4vbruk+y4yCituu6T7LDAKK267pPsuMQuO2a7rPMmNg4rZrus8yQ0Di
tmu6zzKDwLjtmu6zzAiIuO2a7rPMAIC47Zrus8w4OLjtmu6zzLDbNd1HghEBcbdd
030ECAEAd9s13UeOFwdnt13TfcRoYWB22zXdR4oVBWW3XdN9hEhBQHbbNd1Hykah
dts13UeGEwNjt13TfUQoISB22zXdR0gGgXbbNd1HghEBYbdd030ECAEAdts13UeO
FwdXt13TfcRoYWB12zXdR4oVBVW3XdN9hEhBQHXbNd1Hykahdds13UeGEwNTt13T
fUQoISB12zXdR0gGgXXbNd1HghEBUbdd030ECAEAdds13UeOFwdHt13TfcRoYWB0
2zXdR4oVBUW3XdN9hEhBQHTbNd1HykahdNs13UeGEwNDt13TfUQoISB02zXdR0gG
gXTbNd1HghEBQbdd030ECDEAwW3XdB85Xhxcb7um+4jRwsB62zXdR4oVBdXbruk+
QqQgoN52TfeRslFob7um+8hwYmB62zXdR4QSAtLbruk+QjII7G3XdB8JRgREb7um
+wgQAgLTfZYZAiK3XdN9lhkEym3XdJ9lRkDIbdd0n2UGAMht13SfZcbB8bZrus8y
w8B42zXdZ5lRULztmu6zzCAg3nZN91lmFMrbruk+y4yB4W3XdJ9lhoDwtmu6zzKD
QN52TfdZZgQEb7um+ywzAIC3XdN9lhkHF7dd032WGQYWt13TfZYZBRW3XdN9lhkE
FLdd032WGYXGbdd0n2XGwMRt13SfZYaAxG3XdJ9lBoFx2zXdZ5kREHHbNd1nmQEA
cds13WeZcXBw2zXdZ5lhYHDbNd1nmVFQcNs13WeZQUBw2zXdZ5lRKNx2TfdZZgwM
3HZN91lmCAjcdk33WWYQCLdd032WGQEBt11Tn2UeA0Dcdk33kePFwd1t13QfMVoY
2N12TfeRYkVB3W3XdB8hUhDQ3XZN95GyUejddk33keHEwNxt13QfEUoIyN12TfcR
kkHgXc8yo9C67Zrus8wYmLrtmu6zzBCQuu2a7rPMILBuu6b7LDMCom67pvssMwCg
brum+ywzDo5uu6b7LDMMjG67pvssMwqKbrum+ywzCIhuu6b7LDMKpduu6T7LjIGh
267pPssMAaHbruk+ywwC6bZrus8yIyDotmu6z0KIASjOro6uN3e9Rlxvu6b7LDMM
rLdd032WGQXV267pPssMAupt13SfZUahve2a7rPMGJjedk33WWYISG+7pvssMwjs
bdd0n2VGQPS2a7rPMgMAets13WeZcXBz2zXdZ5lhYHPbNd1nmVFQc9s13WeZQUBz
2zXdZ5lR6Nx2TfdZZgzM3HZN91lmCMjcdk33WWYQOLdd032WGQExt13TfZYZADC3
XdN9lhkHJ7dd032WGQYmt13TfZYZBSW3XdN9lhkEJLdd032WGYXKbdd0n2XGwMht
V4aLqCOgce5j48/GvgEjkGHuBxGZvcQhmVgbQb6PEwktb3J8FgwGIe/nfBILKTpe
C+0iEOl1HsAN2E5nqAuJbsK7uuAJo72qUtLVDbO9FYWs3zNKtyt1rFYmRnHX11ml
y5helxVTo8jw+y6pZU2P0cqrKGT9HqN0u1LHamViFLu+TlW6jOl1WTE1iozfd0kt
1vQYrbyKQtbvGaVbK3WsViZGsevrrNJlTC+XFVOjyPh9l9SypsfQyqsoZP2eUbpd
qWO1MmIUu77OKl3G9MoC/NkINw1+vFl2yeJDM+BkDAU/3iy7ZPGhGXAyhkEfb5Zd
svjQDDgZw+DHM8suWXxoBpyMYfDjTWWXLD40A07GMPjxZtlFFh+aASdjGPx4s+yS
ig/NgJMxDH68WXbJ4oMmXsBG3DT48WbZJYsPjQEnYxj8eLPsksWHJvI2ApQ5lAkl
VNCoJmqhqzPM9ioKWb9nlG5nqOu+YbZXUcj6PaN0u1KH1crEKHZ9nVW6jOnVsmJq
FBm/75Ja1vQYrXQVhazfM0q3K3WsVkaMYtfXWaXLmF6XFVND3VECNA4Ah3RVVABU
AFMAdts13WeZUajddk33WWYMjN12TfdZZgiI3XZN91lmEGi3XdN9lhkBYbdd032W
GQBgt13TfZYZB1e3XdN9lhkGVrdd032WGQVVt13TfZYZBFS3XdMNzzKDgO62a7rP
MqPQu+2a7rPMGJi77Zrus8wQkLvtmu6zzCDwbrum+ywzAuJuu6b7LDMA4G67pvss
Mw7Obrum+ywzDMxuu6b7LDMKym67pvssMwgo2zXdZ5lBQHDbNd1nmVEo3HZN91lm
DAzcdk33WWYICNx2TfdZZhAIt13TfZYZAQG3XdN9lnkMALztmu6zzDi4u+2a7rPM
MLC77Zrus8woqLvtmm7LjIKK267pPssMAorbruk+y4xC47Zrus8yY2Ditmu6zzJD
QOK2a7rPMoPAuO2a7rPMCIi47Zrus8wAgLjtmu6zzDg4uO2a7rPMMDC47Zrus8wo
KLiBo9gAIRz5AfN/l/RmpcdlzWkocn3fSrpc6bOysioarb7nkt6s9LisOQ1Fru9b
SZdHeY2yKtf3raTLlT4rK6ui0ep7LunNSo/LmtNQ5Pq+lXS50mdlZVU0Wn3PJb1Z
6XFZcxqKXN+3ki5X+nTYArwMAMbyWQvApQMpXEmJnzVwAVkAVABUALctrulZDgeP
XCwiFcpEEhJk+rrSll3VaOjwNIUlOYrBwNnnyTpu02Jho8sSVdQkhYImHg6JBmOh
iAgx4cFBQgPDgkJIH49Mh7PRxISZ/76853c9Hj5+RAED8fDxbYtrepbDwSMXi0iF
MpGEBJm+rrRlVzUaOjxNYUmOYjBw9nmyjtu0WNjoskQVNUkxTdM0TdM0TdM0TdM0
TdM0fTwyHc5GExNm/vvynt/1ePg4/K7Hw8e3La7pWQ4Hj1wsIhXKRBISZPq60pZd
1Wjo8DSFJTmKwcDZ58k6btNiYaPLElXUJAVFURRFURRFURRFURRFURT18ch0OBtN
TJj578t7ftcDvrzndz0ePr5tcU3Pcjh45GIRqVAmkpAg09eVtuyqRkOHpyksyVEM
Bs4+T9ZxmxYLG12WqKImKaqqqqqqqqqqqqqqqqqqqqqPR6bD2Whiwsx/X94HgaOo
IQg/4e8bETD4A1CzswIU6AqcdaXIq2CugAKuilgrGBDUugB7XX/VlcjezAoApvNO
CrBVB0K27cTDcB5ZAFkAQQAeBr+tRpvJYi4M7FpVUU1JRVmhQE2jIqIhoSApEKBn
U0MzIxPjhAGzTEpIRkRClCBAjkUFxYREhBECxM6SHMVQA0mSJEmSJEmSJEmSJEmS
JLlrepZjD4PfFtf0LMceBr+tRpvJYi4M7FpVUU1JRVmhQE2jIqIhoSCJAD2bGpoZ
mRgnDJhlUkIyIhKiBAFyLCooJiQijBAgdpbkKIYayrIsy7Isy7Isy7Isy7Isy13T
sxwH7s4555xzzjnnnHPOOeecc84555xzzjnnnHPOOeecc84555xzzjnnnHPOOeec
c84555xzzjnnnHPOOeecc8455wsgQIAAAWJ3d3d3d3d3d3d3d3d3d3d3d3d3d3d3
d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3d3cPgaPs4R9QVVVV3tgdEssb21dAAVvB
WVcUFzEMrAMAJtoaBfA5UmIPGwAaABQAERERERERERERERERERERERERERERERER
EREDbdu2LSIiIiIiIiIiIiIiIiIiIiIiIiIiIgLbtm3btm3btm3btm3btm3btm3b
NpmZmZmZmZlt27Zt27Zt27Zt27Zt2wKA0VQCAAIBhQYABt4pG2BtshyssL6mkwtg
MnQIXIs3vSOpEgcCMhmLBxcAEwAVAG3btm3btm3btm3btm3btm3btm3btm0b////
///////ftm3btm3btm3bBv//////////////xilIEDDO////AQCJAwhm8WAWiGNx
CHgwTcM8OCAoCwwNTeNBYaEMnGMolZOSQbJEHBERSJMsj4REoUjOUyBxnud5nud5
nud5nud5nuf5/wGA0qggRHfgaTsRIPj2/+/VKMWSDNnosm1cnb5B/hBt27brui5n
PQj3gns=
_EOT
#}}}

{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\002\110B'
	dd bs=1 count=583 < t300.in 2>/dev/null
	printf '\0\0\366\241B'
	dd bs=1 skip=583 count=63136 < t300.in 2>/dev/null
	printf '\0\0\113\111B'
	dd bs=1 skip=63719 < t300.in 2>/dev/null
	printf '\0\0\0\012B\t \t\r\n\r\n\r\n'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE' > t300 2>ERR
x $? 300
e0sumem 300
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=1PQ35TgmN7Tb2dAok5uHCLKjLLkw6S2FvewVU\n'\
'  Qf7Du8=; b=kVqi56HEtdB738rjUi/xmqb6aPGFnttFJFz7GlrguSUTKNbmtnD2wpdVDkJlkOK\n'\
'  c6c+utnGZ/7TEMYR5dcJVCw==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t301
cmp 301 t300 t301

{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\002B1\0\0\0\002B\r\0\0\0\002B\n'
	printf '\0\0\0\002B2'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t218 2>ERR
x $? 218
e0sumem 218
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\n'\
' t=844221007; h=from:subject:from; bh=tHOTehVL0EWpeJdZjJlAZZd7rm5SEpYBE1axW\n'\
'  pHw9Ns=; b=4+ZdjuiWuqk9wb3bIyCcphmKF64N1D08sh167SUL/2CQTk10oZdgIf7SJFNEWpx\n'\
'  Ko3cRzU+C/b0pgefVEKTAAQ==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t219
cmp 219 t218 t219
# }}}

echo '=4: Triggers =' # {{{

## Triggers
# We have Ed2559 due to '=2: Going ='

# (localhost 410+)
{
	printf '\0\0\0\014LFrom\0X@Y.Z\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -S y.z $k > t400 2>ERR
x $? 400
e0sumem 400
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=y.z; s=I;\n'\
' t=844221007; h=from:subject; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuF\n'\
'  U=; b=jzrEoivEWbECTM0xAnUjEFKtGZQmw6Ixn5YQ1RZJM7tgzgr/NNhgT/0BOmgFdG+Vd6+a\n'\
'  TO2AmTng22hbc1iPCg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t401
cmp 401 t400 t401

{
	printf '\0\0\0\014LFrom\0X@Y.Z\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -S y.z $k -!from > t402 2>ERR
x $? 402
e0sumem 402
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=y.z; s=I;\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=VvdE1nxRMZ/ek/mwzcGMbfzAqE5Q598um9X2WQwTyG2GJ3LBBblUbg1JLO2iIZG\n'\
'  jwIMoRJjEDytj177XAEFpAg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t403
cmp 403 t402 t403

{
	printf '\0\0\0\014LFrom\0X@Y.Z\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -S y.z $k -!from -d z.y > t404 2>ERR
x $? 404
e0sumem 404
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=z.y; s=I;\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=rjeI6gV+4JnSbi1JlaAsUkwbuCUo5E5w0QcdYPsLfrSRQnQDV+dBk4xrMopE1WP\n'\
'  G+uw7IEl8XEobd0Va3UAiAg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t405
cmp 405 t404 t405

{
	printf '\0\0\0\014LFrom\0X@Y.Z\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k -!from -d not.me -S.,z.y > t406 2>ERR
x $? 406
e0sumem 406
cmp 407 t404 t406

### Real thing!!

{
	printf '\0\0\0\015O\0\0\0\6\0\0\1\377\0\37\377\377'
	printf '\0\0\0\140DC'\
'j\0sdaoden.eu\0{daemon_name}\0sign\0{daemon_addr}\0\06127.0.0.1\0v\0Micky Mouse\0_\0localhost [127.0.0.1]\0'
	printf '\0\0\0\022LFrom\0X@localhose\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k > t410 2>ERR
x $? 410
e0sumem 410
printf \
'OPTNEG NR_CONN=0 NR_HDR=0\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=localhose; s=I;\n'\
' t=844221007; h=from:subject; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuF\n'\
'  U=; b=t1XwGpSMAnIvXTYtW92ir792XpEDiI/xuw0ksxT1AjQEkmmud0WqDxOKk6eIqYLZqjhj\n'\
'  BdteiqJOZc0GPxvZCw==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t411
cmp 411 t410 t411

{
	printf '\0\0\0\015O\0\0\0\6\0\0\1\377\0\37\377\377'
	printf '\0\0\0\140DC'\
'j\0sdaoden.eu\0{daemon_name}\0sign\0{daemon_addr}\0\06127.0.0.1\0v\0Micky Mouse\0_\0localhost [127.0.0.1]\0'
	printf '\0\0\0\022LFrom\0X@localhose\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k --domain-name=sdaoden.eu > t412 2>ERR
x $? 412
e0sumem 412
printf \
'OPTNEG NR_CONN=0 NR_HDR=0\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=sdaoden.eu;\n'\
' s=I; t=844221007; h=from:subject; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=FMbNkXvqm2U2sAD/1dl/WTzIUUXedG3N0prqmDeyBC6VSEbXOcuGjQknPMff1F6\n'\
'  kUuRR7C5eOH1a9mDYj3VqDw==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t413
cmp 413 t412 t413

{
	printf '\0\0\0\015O\0\0\0\6\0\0\1\377\0\37\377\377'
	printf '\0\0\0\140DC'\
'j\0sdaoden.eu\0{daemon_name}\0sign\0{daemon_addr}\0\06127.0.0.1\0v\0Micky Mouse\0_\0localhost [127.0.0.1]\0'
	printf '\0\0\0\022LFrom\0X@localhose\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k --domain-name=sdaoden.eu --sign localhose > t414 2>ERR
x $? 414
e0sumem 414
printf \
'OPTNEG NR_CONN=0 NR_HDR=1\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=sdaoden.eu;\n'\
' s=I; t=844221007; h=from:subject; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=FMbNkXvqm2U2sAD/1dl/WTzIUUXedG3N0prqmDeyBC6VSEbXOcuGjQknPMff1F6\n'\
'  kUuRR7C5eOH1a9mDYj3VqDw==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t415
cmp 415 t414 t415

{
	printf '\0\0\0\015O\0\0\0\6\0\0\1\377\0\37\377\377'
	printf '\0\0\0\140DC'\
'j\0sdaoden.eu\0{daemon_name}\0sign\0{daemon_addr}\0\06127.0.0.1\0v\0Micky Mouse\0_\0localhost [127.0.0.1]\0'
	printf '\0\0\0\022LFrom\0X@localhose\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k --domain-name=sdaoden.eu --sign .localhose,sdaoden.eu > t416 2>ERR
x $? 416
e0sumem 416
printf \
'OPTNEG NR_CONN=0 NR_HDR=1\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=sdaoden.eu;\n'\
' s=I; t=844221007; h=from:subject; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=FMbNkXvqm2U2sAD/1dl/WTzIUUXedG3N0prqmDeyBC6VSEbXOcuGjQknPMff1F6\n'\
'  kUuRR7C5eOH1a9mDYj3VqDw==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t417
cmp 417 t416 t417

{
	printf '\0\0\0\015O\0\0\0\6\0\0\1\377\0\37\377\377'
	printf '\0\0\0\140DC'\
'j\0sdaoden.eu\0{daemon_name}\0sign\0{daemon_addr}\0\06127.0.0.1\0v\0Micky Mouse\0_\0localhost [127.0.0.1]\0'
	printf '\0\0\0\022LFrom\0X@localhose\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k --milter-macro sign,'{daemon_name}',sigh --domain-name=sdaoden.eu --sign .localhose,sdaoden.eu > t418 2>ERR
x $? 418
e0sumem 418
printf \
'OPTNEG NR_CONN=1 NR_HDR=1\n'\
'--milter-macro BAD\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t419
cmp 419 t418 t419

{
	printf '\0\0\0\015O\0\0\0\6\0\0\1\377\0\37\377\377'
	printf '\0\0\0\140DC'\
'j\0sdaoden.eu\0{daemon_name}\0sign\0{daemon_addr}\0\06127.0.0.1\0v\0Micky Mouse\0_\0localhost [127.0.0.1]\0'
	printf '\0\0\0\022LFrom\0X@localhose\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k --milter-macro sign,'{daemon_name}',sign --domain-name=sdaoden.eu --sign .localhose,sdaoden.eu > t420 2>ERR
x $? 420
e0sumem 420
printf \
'OPTNEG NR_CONN=1 NR_HDR=1\n'\
'--milter-macro OK\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=sdaoden.eu;\n'\
' s=I; t=844221007; h=from:subject; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\n'\
'  3hSuFU=; b=FMbNkXvqm2U2sAD/1dl/WTzIUUXedG3N0prqmDeyBC6VSEbXOcuGjQknPMff1F6\n'\
'  kUuRR7C5eOH1a9mDYj3VqDw==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t421
cmp 421 t420 t421

#.........
# TODO massively incomplete

#if [ -z "$k2a" ]; then
#	echo >&2 'Only one key type available, skipping further tests'
#	exit 0
#fi

#echo xxx without sign ALL keys

#echo $kR > x.rc
#echo $k2R >> x.rc
#.........

#if [ -z "$algo_rsa_sha1" ] || [ -z "$algo_rsa_sha256" ] || [ -z "$algo_ed25519_sha256" ]; then
#	echo >&2 'Only two key types available, skipping further tests'
#	exit 0
#fi

# }}}
)
exit $?

# s-sht-mode
