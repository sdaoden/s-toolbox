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
	if [ "x${SHELL}" = x ] || [ "${SHELL}" = /bin/sh ]; then
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
	[ $1 -eq 0 ] || { echo >&2 'bad '$2; exit 1; }
	[ -n "$REDIR" ] || echo ok $2
}

y() {
	[ $1 -ne 0 ] || { echo >&2 'bad '$2; exit 1; }
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
	sed -E -i'' '/.+\[debug\]: su_mem_.+(LINGER|LOFI|lofi).+/d' ERR
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
[ -n "$algo_rsa_sha1" ] &&
	ka=rsa-sha1 kf=pri-rsa.pem k=--key=$ka,I,$kf kR='key '$ka', I, '$kf \
	k2a=$ka k2f=$kf k2=--key=$ka,II,$kf k2R='key '$ka', II, '$kf
[ -n "$algo_rsa_sha256" ] &&
	ka=rsa-sha256 kf=pri-rsa.pem k=--key=$ka,I,$kf kR='key '$ka', I, '$kf \
	k2a=$ka k2f=$kf k2=--key=$ka,II,$kf k2R='key '$ka', II, '$kf
[ -n "$algo_ed25519_sha256" ] && ka=ed25519-sha256 kf=pri-ed25519.pem k=--key=$ka,I,$kf kR='key '$ka', I, '$kf
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
	echo no rsa-sha256, skip 4.1-4.6
else
	${PD} -# --key rsa-sha256,ed1,pri-rsa.pem > t4.1 2>ERR
	x $? 4.1
	e0 4.1
	${PD} -# --key=' rsa-sha256 ,  ed1  ,   pri-rsa.pem  ' > t4.2 2>ERR
	x $? 4.2
	e0 4.2
	cmp 4.3 t4.1 t4.2

	${PD} -# -k rsa-sha256,ed1,pri-rsa.pem > t4.4 2>ERR
	x $? 4.4
	e0 4.4
	${PD} -# -k' rsa-sha256 ,  ed1  ,   pri-rsa.pem  ' > t4.5 2>ERR
	x $? 4.5
	e0 4.5
	cmp 4.6 t4.4 t4.5
fi

if [ -z "$algo_rsa_sha1" ]; then
	echo no rsa-sha1, skip 5.1-5.6
else
	${PD} -# --key rsa-sha1,ed1,pri-rsa.pem > t5.1 2>ERR
	x $? 5.1
	e0 5.1
	${PD} -# --key=' rsa-sha1 ,  ed1  ,   pri-rsa.pem  ' > t5.2 2>ERR
	x $? 5.2
	e0 5.2
	cmp 5.3 t5.1 t5.2

	${PD} -# -k rsa-sha1,ed1,pri-rsa.pem > t5.4 2>ERR
	x $? 5.4
	e0 5.4
	${PD} -# -k' rsa-sha1 ,  ed1  ,   pri-rsa.pem  ' > t5.5 2>ERR
	x $? 5.5
	e0 5.5
	cmp 5.6 t5.4 t5.5
fi

${PD} -# --key rsax-sha256,no1.-,pri-rsa.pem > t6.1 2>&1
y $? 6.1
${PD} -# --key rsa-sha256x,no1.-,pri-rsa.pem > t6.2 2>&1
y $? 6.2
${PD} -# --key 'rsa-sha256,    ,pri-rsa.pem' > t6.3 2>&1
y $? 6.3
${PD} -# --key rsa-sha256,.no,pri-rsa.pem > t6.4 2>&1
y $? 6.4
${PD} -# --key rsa-sha256,-no,pri-rsa.pem > t6.5 2>&1
y $? 6.5
${PD} -# --key 'rsa-sha256,no1.-,pri-rsax.pem' > t6.6 2>&1
y $? 6.6
${PD} -# --key $ka,no1.-,$kf > t6.7 2>ERR
x $? 6.7
e0 6.7

${PD} -# --key $ka,this-is-a-very-long-selector-that-wraps-lines-i-guess,$kf > t6.8 2>ERR
x $? 6.8
e0 6.8
${PD} -# -R t6.8 > t6.9 2>ERR
x $? 6.9
e0 6.9
cmp 6.10 t6.8 t6.9
{ read -r i1; read i2; } < t6.9
[ -n "$i2" ]
x $? 6.11

${PD} -# --key ',,,' > t6.12 2>&1
y $? 6.12
${PD} -# --key 'rsa-sha256,,' > t6.13 2>&1
y $? 6.13
${PD} -# --key 'rsa-sha256,s,' > t6.14 2>&1
y $? 6.14
${PD} -# --key 'rsa-sha256,s' > t6.15 2>&1
y $? 6.15

${PD} -# > t6.16 2>ERR
x $? 6.16
e0 6.16
(	# needs at least one --key, except then
	unset SOURCE_DATE_EPOCH
	${PD} -# > t6.17 2>&1
	y $? 6.17
)
# }}}

# 4.* --milter-macro {{{
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
{ echo $kR; echo 'sign a@.b,,'; } > t8.17
cmp 8.17 t8.16 t8.17

${PD} -# $k --sign 'a@.b,,' > t8.18 2>ERR
x $? 8.18
e0 8.18
{ echo $kR; echo 'sign a@.b,,'; } > t8.19
cmp 8.19 t8.18 t8.19

${PD} -# $k --sign '.b,' > t8.20 2>ERR
x $? 8.20
e0 8.20
{ echo $kR; echo 'sign .b,,'; } > t8.21
cmp 8.21 t8.20 t8.21

${PD} -# $k --sign '.' > t8.22 2>ERR
x $? 8.22
e0 8.22
{ echo $kR; echo 'sign .,,'; } > t8.23
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

${PD} -# $k -S y@.,, --sign a@.b,,I -S x@.b,, > t8.32 2>ERR
x $? 8.32
e0 8.32
cat > t8.33 << _EOT
$kR
sign a@.b,, I
sign x@.b,,
sign y@.,,
_EOT
cmp 8.34 t8.32 t8.33

cat > t8.35.rc << '_EOT'
a@.b,, I
x@.b,,
y@.,,
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

${PD} -# --remove a-r,.de > t11.4 2>ERR
x $? 11.4
e0 11.4
echo 'remove a-r, .de' > t11.5
cmp 11.5 t11.4 t11.5

${PD} -# --remove a-r,,,.com,,,.de,,. > t11.6 2>ERR
x $? 11.6
e0 11.6
echo 'remove a-r, .com, .de, .' > t11.7
cmp 11.7 t11.7 t11.7

${PD} -# --remove '' > t11.8 2>ERR
y $? 11.8
eX 11.8
# }}}

# 100* --resource-file (yet; except recursion, and overwriting) {{{
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

${PD} -R t90.rc -# > t90 2>ERR
x $? 90
e0 90
cmp 91 t90 t90-x

printf '\n\\\n\\\n' > t92.rc
${PD} -R t92.rc -# > t92 2>ERR
x $? 92
e0 92
[ -s t92 ] && { echo >&2 'bad 93'; exit 1; }
echo ok 93
# }}}
# }}}

echo '=2: Going =' # {{{

##
if [ -z "$algo_ed25519_sha256" ]; then
	echo >&2 'Skipping further tests due to lack of Ed25519 algorithm'
	exit 0
fi

echo $kR > x.rc
echo 'header-seal from' >> x.rc

# 6376, 3.4.4/5 (empty body hash of 3.4.4: 47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=)
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
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\r\n'\
'  3hSuFU=; b=XZsTsoDGBj1ThBUusPXOlKZnJPfTWAcOXp1lLFITL65MW6zgXPLXB9Oum+nkomK\r\n'\
'  sG9vD5myIH0f+z0Y2hDBvCg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t201
cmp 201 t200 t201

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
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=unak6JHq0wL+Q1HP7dW1tjBx9FLA6DffoZ0qr\r\n'\
'  Lwbbpo=; b=dNyvWBMO6P6k/nYbpWlm8eK5L4jNb+pper49iOQ/yboY2P5ty2aKFBaRi3cTxx0\r\n'\
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
	seq 8888 | sed 's/$/\r/'
	printf '\0\0\167\235B'
	seq 8889 13421 | sed 's/$/\r/'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --sign 'y   ,auA.DE,I' > t204 2>ERR
x $? 204
e0sumem 204
printf \
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'SMFIC_HEADER SMFIR_CONTINUE\n'\
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=PzUIcKYLlFjDJtEAT+6JZpXkPgH2VFMvaxAEz\r\n'\
'  NP3cWk=; b=fGXDjaUMwMmfCW7ADJ1Qc/om2WB7fviw1TLyVj99nPCVXkPqO13ARXrbLzTutel\r\n'\
'  4+H2fECaR3nHU2uPAe2JNBA==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t205
cmp 205 t204 t205

# ..other order
{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\145\346B'
	seq 4532 | sed 's/$/\r/'
	printf '\0\0\335\265B'
	seq 4533 13421 | sed 's/$/\r/'
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
	seq 10 4532 | sed 's/$/\r/'
	printf '\0\0\335\265B'
	seq 4533 13421 | sed 's/$/\r/'
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
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=vq8fFHPPqqkcinB83aEumTVgnU+qPqNqWSUgU\r\n'\
'  EkP2L0=; b=fN/etAORxhK2pRauvaW4wCvStge7pxtnzuF8qBwFdi3/e/Jsd+gtOLcAaVjCOYz\r\n'\
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
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=2lM8tKY3+20Uu1AZLSBrCf59CqYv31qtqmmPj\r\n'\
'  4rBX7c=; b=YoBrDj6EgTKF6qEeNunu2NDYTJkUsro1jBCnLo5Pe8mEnh3GCGxsVu/XDg/nTvY\r\n'\
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
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=tHOTehVL0EWpeJdZjJlAZZd7rm5SEpYBE1axW\r\n'\
'  pHw9Ns=; b=4+ZdjuiWuqk9wb3bIyCcphmKF64N1D08sh167SUL/2CQTk10oZdgIf7SJFNEWpx\r\n'\
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
if command -v xz >/dev/null 2>&1; then :; else
	echo >&2 'No xz(1) available, skipping further tests'
	exit 0
fi

openssl base64 -d << '_EOT' | xz -d > t300.in
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
_EOT

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
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=1PQ35TgmN7Tb2dAok5uHCLKjLLkw6S2FvewVU\r\n'\
'  Qf7Du8=; b=kVqi56HEtdB738rjUi/xmqb6aPGFnttFJFz7GlrguSUTKNbmtnD2wpdVDkJlkOK\r\n'\
'  c6c+utnGZ/7TEMYR5dcJVCw==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t301
cmp 301 t300 t301
# }}}

echo '=2: Triggers =' # {{{

## Triggers
# We have Ed2559 due to '=2: Going ='

{
	printf '\0\0\0\014LFrom\0X@Y.Z\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k > t400 2>ERR
x $? 400
e0sumem 400
printf \
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=y.z; s=I;\r\n'\
' t=844221007; h=from:subject; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuF\r\n'\
'  U=; b=jzrEoivEWbECTM0xAnUjEFKtGZQmw6Ixn5YQ1RZJM7tgzgr/NNhgT/0BOmgFdG+Vd6+a\r\n'\
'  TO2AmTng22hbc1iPCg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t401
cmp 401 t400 t401

{
	printf '\0\0\0\014LFrom\0X@Y.Z\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k -!from > t402 2>ERR
x $? 402
e0sumem 402
printf \
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=y.z; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\r\n'\
'  3hSuFU=; b=VvdE1nxRMZ/ek/mwzcGMbfzAqE5Q598um9X2WQwTyG2GJ3LBBblUbg1JLO2iIZG\r\n'\
'  jwIMoRJjEDytj177XAEFpAg==\n'\
'SMFIC_BODYEOB SMFIR_ACCEPT\n' > t403
cmp 403 t402 t403

{
	printf '\0\0\0\014LFrom\0X@Y.Z\0'
	printf '\0\0\0\013LSubject\0s\0'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} $k -!from -d z.y > t404 2>ERR
x $? 404
e0sumem 404
printf \
'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=z.y; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\r\n'\
'  3hSuFU=; b=rjeI6gV+4JnSbi1JlaAsUkwbuCUo5E5w0QcdYPsLfrSRQnQDV+dBk4xrMopE1WP\r\n'\
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
{
	echo SMFIC_HEADER SMFIR_CONTINUE
	echo SMFIC_HEADER SMFIR_CONTINUE
	cat t404
} > t407
cmp 407 t406 t407

#.........

if [ -z "$k2a" ]; then
	echo >&2 'Only one key type available, skipping further tests'
	exit 0
fi

#echo $kR > x.rc
#echo $k2R >> x.rc
#echo 'header-seal from,subject,to' >> x.rc

#{
#	printf '\0\0\0
#	printf '\0\0\0\013LFrom\0 X@Y\0'
#	printf '\0\0\0\023LSubject\0 Y\t\r\n\tZ  \0'
#	printf '\0\0\0\01E'
#	printf '\0\0\0\01Q'
#} | ${PD} -R x.rc \
#	> t400 2>ERR
#x $? 400
#e0sumem 400



#.........


if [ -z "$algo_rsa_sha1" ] || [ -z "$algo_rsa_sha256" ] || [ -z "$algo_ed25519_sha256" ]; then
	echo >&2 'Only two key types available, skipping further tests'
	exit 0
fi



# }}}
)
exit $?

# s-sht-mode
