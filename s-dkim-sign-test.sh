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
	[ "$3" = seal ] && [ "$2" = '*' ] && allinc='-~'"$2"

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

	x=
	if [ "$3" = seal ]; then
		x='-~'"${2}boah"
		${PD} -# --header-$3 "$2"'!date,   !cc        ,   !subject , boah ' > t1.$1.7-fail 2>ERR
		y $? 1.$1.7-fail
	fi

	${PD} -# $x --header-$3 "$2"'!date,   !cc        ,   !subject , boah ' > t1.$1.7 2>ERR
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

	${PD} -# --header-$3="${2}!from" > t1.$1.11 2>&1
	y $? 1.$1.11
	${PD} -# --header-$3="  ,  ${2}" > t1.$1.12 2>&1
	y $? 1.$1.12
	${PD} -# --header-$3="from,!to" > t1.$1.13 2>&1
	y $? 1.$1.13
}
t1 1 '@' sign 1
t1 2 '*' sign 2
t1 3 '@' seal 1
t1 4 '*' seal 2
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

# 4.* --milter-macro-sign {{{
${PD} -# --milter-macro-sign oha > t7.1 2>ERR
x $? 7.1
e0 7.1
${PD} -# -Moha > t7.2 2>ERR
x $? 7.2
e0 7.2
cmp 7.3 t7.1 t7.2

${PD} -# --milter-macro-sign oha,,v1,,,v2,,, > t7.4 2>ERR
x $? 7.4
e0 7.4
${PD} -# -Moha,',,,,       v1   ,   v2     '  > t7.5 2>ERR
x $? 7.5
e0 7.5
cmp 7.6 t7.4 t7.5
echo 'milter-macro-sign oha, v1, v2' > t7.7
cmp 7.7 t7.5 t7.7

${PD} -# -Moha,'v1 very long value that sucks very much are what do you say?  ,'\
'v2 and another very long value that drives you up the walls ,   '\
'v3 oh noooooooooo, one more!,,' > t7.8 2>ERR
x $? 7.8
e0 7.8
i=0; while read -r l; do i=$((i + 1)); done < t7.8
[ $i -eq 4 ]
x $? 7.9
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
	echo >&2 only one key-algo type, skip 8.5-8.13
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
y $? 10.7

${PD} -# --ttl 29 > t10.8 2>&1
y $? 10.8
${PD} -# --ttl $((60*60*24*1000 + 1)) > t10.9 2>&1
y $? 10.9
# }}}

# 100* --resource-file (yet; except recursion, and overwriting) {{{
cat > t100.rc << '_EOT'
header-sign from , to
header-seal from , date
milter-macro-sign mms1
resource-file t101.rc
_EOT
cat > t101.rc << '_EOT'
header-sign from , date
header-seal from , subject
milter-macro-sign mms2 , v1 ,v2,,v3,,v4,,
resource-file t102.rc
_EOT
cat > t102.rc << '_EOT'


header-sign from , subject, date


header-\
   seal ,  \
	  	,	\
	 	,,\
from\
, subject , date ,,,,


milter\
-macro\
-sign	\
mms3

	 	# comment \
 	 	line \
  continue

_EOT
cat > t100-x << '_EOT'
milter-macro-sign mms3
header-sign from, subject, date
header-seal from, subject, date
_EOT

${PD} -R t100.rc -# > t100 2>ERR
x $? 100
e0 100
cmp 101 t100 t100-x
# }}}
# }}}

echo '=2: Going =' # {{{

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
#FIXME e0 200
printf 'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG\r\n'\
'  3hSuFU=; b=XZsTsoDGBj1ThBUusPXOlKZnJPfTWAcOXp1lLFITL65MW6zgXPLXB9Oum+nkomK\r\n'\
'  sG9vD5myIH0f+z0Y2hDBvCg==\n' > t201
cmp 201 t200 t201

# 6376, 3.4.5
{
	printf '\0\0\0\013LFrom\0 X@Y\0'
	printf '\0\0\0\030LSubject\0 Y\t \n \r\n \t Z  \0'
	printf '\0\0\0\021B C \r\nD \t E\r\n\r\n\r\n'
	printf '\0\0\0\01E'
	printf '\0\0\0\01Q'
} | ${PD} -R x.rc --key=$ka,this.is.a.very.long.selector,$kf \
	--sign .,dOEDel.de,this.is.a.very.long.selector \
	--sign '.y   ,auA.DE,I' \
	> t202 2>ERR
x $? 202
#FIXME e0 202
printf 'DKIM-Signature:v=1; a=ed25519-sha256; c=relaxed/relaxed; d=aua.de; s=I;\r\n'\
' t=844221007; h=from:subject:from; bh=znUs9MtDElAZOFfJOcfNaDGLIUjGiZT2bsWl2\r\n'\
'  vN/Hd4=; b=F+WrG/cn3KYJYaqBA5smNEOGpShufAnWy0GTBIem+6LDxsiLTh1/jniVAWp14Oj\r\n'\
'  aXlkK7u5yDdoqipP65z3wAA==\n' > t203
cmp 203 t202 t203

#seq 13421 > a.txt
#DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=sdaoden.eu;
# s=citron; t=1709768093; h=date:author:from:to:subject:message-id:author:
#  from:subject:date:to:cc:in-reply-to:references:message-id;
# bh=KZugNeJGuvNuPdVmP6GYqXtd3nXjKJkmJDF/Bo1MHco=;
# b=HB/dkaeg6VtSrBsnfIIKkhNJcLjLKybpIDuql6b9ime/gNUyeWwzKr7l7628DKveDy04lKk5
#  WlzLk/jQhApmGmeyOwDr6EkFVSVwlj8abjBuNxbtMYT+qZohsuR3FpqmFWtnBsvPhqGsl1jJQD
#  eTnNOxDM+lt98yZL3y86kEAD1Zd7mTFAG9oyeKf7U7zWJmGu//un8BIiyga1P7jIfLYWMkUSHQ
#  xByRQbetZk3FWUm7oOwaAobsUV1v5yh0iYWKrrWTrNo6hpCN83ORKThzXZZKDShwZr4mPzieiA
#  gSisSGL9aav777xAWOIWCUbZDzeEgBAV1vniocsXB3UQsQMg==
#DKIM-Signature: v=1; a=ed25519-sha256; c=relaxed/relaxed; d=sdaoden.eu;
# s=orange; t=1709768093; h=date:author:from:to:subject:message-id:author:
#  from:subject:date:to:cc:in-reply-to:references:message-id;
# bh=KZugNeJGuvNuPdVmP6GYqXtd3nXjKJkmJDF/Bo1MHco=;
# b=6BtKiQTdFM6tXGDtzmL8W9saJCVIeJN4yy8zI2x0CwNg6CwrkkFoFo0rczAilE+bXooSQWkt
#  BhX/LyCwR2HDCA==


############
#DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=sdaoden.eu;
# s=citron; t=1709768257; h=date:author:from:to:subject:message-id:author:
#  from:subject:date:to:cc:in-reply-to:references:message-id;
# bh=1PQ35TgmN7Tb2dAok5uHCLKjLLkw6S2FvewVUQf7Du8=;
# b=YLEaXAXuBNW3sQCA/dO+a+yxX+hpt5aQqKzf72EQOSuR9Q0yB/emH4TdJU0355j7kLQAZMl9
#  cuKJMnKgiVTpkdqEgbnZGGG9ggUQS3EEzzMdnF/VcVbZlpDaufTO6uvHbW/gnpkPTjdldQ27F0
#  qv/dz2YVnf/n/z5r7Z17GXi6hMQ6Uxq9kgN8M4q+ElxoPE0DSpQK7UbNn+mojkiYtHrnk2MG/s
#  C7pnxFKIE91UqUbxMtgHsaQImbu0mLWuf5f/oWiB+dHgQYhemGPIxtl4g65nuhoy9AqZgYWZdG
#  SP34BUbi6JIaUGE2M8NaZwxzQgboTREyM5XEyP3pfegrd1LA==
#DKIM-Signature: v=1; a=ed25519-sha256; c=relaxed/relaxed; d=sdaoden.eu;
# s=orange; t=1709768257; h=date:author:from:to:subject:message-id:author:
#  from:subject:date:to:cc:in-reply-to:references:message-id;
# bh=1PQ35TgmN7Tb2dAok5uHCLKjLLkw6S2FvewVUQf7Du8=;
# b=H0dPhE8BR+fHxWgfhGwuiFuqHyI4DhZjOYl7+Z473qlOQU6M3JTtO4ZJ5vT2Fhi+IVBVO9ZL
#  gRCwZ5U4pB7kBw==

#openssl base64 < YYY.xz > az
openssl base64 -d << '_EOT' > dat.xz
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
6+hMYLHEZ/sCAAAAAARZWg==
_EOT


#} | ${PD} -R x.rc --key=$ka,this.is.a.very.long.selector,$kf --sign .,doedel.de,I --debug > t200 2>&1 || exit 1


#cmp 2.3 2_1.out 2_2.out

#eval $PG -R ./9.rc --status $REDIR
#[ $? -eq 0 ] || exit 101

# }}}

)
exit $?

# s-sht-mode
