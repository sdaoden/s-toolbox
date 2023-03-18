#!/bin/sh -
#@ s-postgray test

KEEP_TESTS=
REDIR= #'2>/dev/null'

PG=../s-postgray

MSG_ALLOW=xDUNNO
MSG_BLOCK=xREJECT
MSG_DEFER='DEFER_IF_PERMIT 4.2.0 Cannot hurry love'

###

LC_ALL=C SOURCE_DATE_EPOCH=844221007
export LC_ALL SOURCE_DATE_EPOCH

s4= s5= s6= s7= s8=
while [ $# -gt 0 ]; do
	case $1 in
	4) s4=y;;
	5) s5=y;;
	6) s6=y;;
	7) s7=y;;
	8) s8=y;;
	*)
		echo >&2 'No such test to skip: '$1
		echo >&2 'Synopsis: '$0' [:test major number to skip, eg 5:]'
		echo >&2 'First three test series cannot be skipped'
		exit 64
		;;
	esac
	shift
done

[ -d .test ] || mkdir .test || exit 1
trap "trap '' EXIT; [ -z \"$KEEP_TESTS\" ] && rm -rf ./.test" EXIT
trap 'exit 1' HUP INT TERM

(
cd ./.test || exit 2
pwd=$(pwd) || exit 3

### First of all fetch+adjust compile time defaults, create some resources {{{

$PG --test-mode > ./def || exit 4
PGX="$PG --store-path='$pwd' "\
"--msg-allow='$MSG_ALLOW' "\
"--msg-block='$MSG_BLOCK' "\
"--msg-defer='$MSG_DEFER'"
PGx="$PG -s'$pwd' -m '$MSG_DEFER' "\
"--msg-allow='$MSG_ALLOW' --msg-block='$MSG_BLOCK'"

__xsleep=
if ( sleep .1 ) >/dev/null 2>&1; then
	xsleep() { eval sleep "$1.2"; }
	delay() { sleep .5; }
	sdelay() { sleep .1; }
else
	xsleep() { sleep $1; }
	delay() { sleep 1; }
	sdelay() { sleep 1; }
fi

echo '=def: calibration=' # {{{

eval $PGX -# > ./tdef1 || exit 1
sed '/^store-path/,$d' < def > ./defx || exit 2
echo 'store-path '"$pwd"'' >> ./defx
echo 'msg-allow '"$MSG_ALLOW" >> ./defx
echo 'msg-block '"$MSG_BLOCK" >> ./defx
echo 'msg-defer '"$MSG_DEFER" >> ./defx
cmp -s tdef1 defx || exit 3

eval $PGx -# > ./tdef2 || exit 4
cmp -s tdef2 defx || exit 5

echo '=def: shutdown request without server='
eval $PGx --shutdown $REDIR
[ $? -eq 75 ] || exit 6
# }}}

# And some explicit resources {{{

cat > ./x.rc <<_EOT
4-mask 24
6-mask 64

count 2
delay-max 3
allow-file=x.a1
delay-min 1
gc-rebalance 2
gc-timeout 7
limit 10
	# Comment
allow-file=x.a2
	limit-delay 8	  

server-timeout 5
 msg-block=$MSG_BLOCK
 msg-defer=$MSG_DEFER
 msg-allow=$MSG_ALLOW
	# Comment
	store-path=$pwd	
_EOT

cat > ./x.a1 <<'_EOT'; cat > ./x.a2 <<'_EOT'
# Comment
	exact.match
   also.exact.match
.domain.and.subdomain 
				.d.a.s	 

	127.0.0.1 
	  2a03:2880:20:4f06:face:b00c:0:14/56		 

	2a03:2880:20:6f06:face:b00c:0:14/66	
	  2a03:2880:20:8f06:face:b00c:0:14/128
   # Comment		
_EOT
2a03:2880:33:5f06::
	# Comment !!
193.92.150.2/24
193.95.150.100/28
  195.90.112.99/32  
195.90.111.99/22
_EOT
# }}}

### }}} After that we can work with adjusted defaults defx!

##
echo '=1: options=' # {{{

adj_def() {
	sed -Ee 's|^'"$1"' .*$|'"$1"' '"$2"'|' < ./defx > ./${3}x || exit 100
	cmp -s $3 ${3}x || exit 101
}

t() {
	t=$1 o=$2 v=$3
	shift 3
	eval "$PGX" -# "$@" > ./$t $REDIR; adj_def $o $v $t || exit $?
	[ -n "$REDIR" ] || echo ok $t
	eval "$PGX" -# -R ./defx "$@" > ./$t.2 $REDIR;\
		adj_def $o $v $t.2 || exit $?
	eval $PGx --shutdown $REDIR
	[ $? -eq 75 ] || exit 101
	[ -n "$REDIR" ] || echo ok $t.2
}

t 1.1 4-mask 11 --4-mask=11
t 1.2 4-mask 13 -413
t 1.3 6-mask 100 --6-mask=100
t 1.4 6-mask 99 -6 99

t 1.5 count 7 --count 7
t 1.6 count 8 -c 8
t 1.7 delay-max 1111 --delay-max 1111
t 1.8 delay-max 1000 -D1000
t 1.9 delay-min 42 --delay-min 42
t 1.10 delay-min 44 -d 44
t 1.11 gc-rebalance 9 --gc-rebalance=9
t 1.12 gc-rebalance 10 -G10
t 1.13 gc-timeout 12000 --gc-timeout=12000
t 1.14 gc-timeout 23456 -g 23456
t 1.15 limit 300000 --limit 300000
t 1.16 limit 333333 -L 333333
t 1.17 limit-delay 300000 --limit-delay 300000
t 1.18 limit-delay 333333 -l 333333

t 1.19 server-timeout 0 --server-timeout=0
t 1.20 server-timeout 5 -t 5

# TODO No tests for boolean options!
# }}}

##
echo '=2: resource files=' # {{{

adj_def() {
	t=$1
	shift
	cat < ./defx > ./${t}x
	while [ $# -gt 0 ]; do
		sed -i'' -Ee 's|^'"$1"' .*$|'"$1"' '"$2"'|' ${t}x || exit 100
		shift 2
	done
	cmp -s $t ${t}x || exit 101
	[ -n "$REDIR" ] || echo ok $t
}

cat > ./2.rc1 <<'_EOT'; cat > ./2.rc2 <<'_EOT'
  # Comment 1
	4-mask			  31	 
6-mask=127
count 3
resource-file 2.rc2
delay-min			4
#comment2
	  gc-rebalance=2
   	gc-timeout	7200			
limit-delay=10405
_EOT
delay-max=5
limit=11000
server-timeout=9
#comment3
_EOT

eval $PGX -# -R 2.rc1 -t 10 > ./2.0 $REDIR
	adj_def 2.0 \
		4-mask 31 6-mask 127 \
		count 3 \
		delay-max 5 delay-min 4 \
		gc-rebalance 2 gc-timeout 7200 \
		limit 11000 limit-delay 10405 \
		server-timeout 10 || exit $?
eval $PGx --shutdown $REDIR
[ $? -eq 75 ] || exit 101
# }}}

##
echo '=3: allow and block, check=' # {{{

cat > ./3.zz <<'_EOT'
allow exact.match
allow also.exact.match
allow .domain.and.subdomain
allow .d.a.s
allow 127.0.0.0
allow 2a03:2880:20:4f00::/56
allow 2a03:2880:20:6f06::
allow 2a03:2880:20:8f06::
allow 2a03:2880:33:5f06::
allow 193.92.150.0
allow 193.95.150.0
allow 195.90.112.0
allow 195.90.108.0/22
_EOT

cat 3.zz defx > ./3.0x
sed -e 's/^allow /block /' < ./3.zz > ./3.2x
cat defx >> ./3.2x

ab() {
	eval $PGX --test-mode --4-mask 24 --6-mask 64 \
		-$2 exact.match \
		--$3 also.exact.match \
		-${2}.domain.and.subdomain \
		--$3=.d.a.s \
		-$2 127.0.0.1 \
		-$2 2a03:2880:20:4f06:face:b00c:0:14/56 \
		-$2 2a03:2880:20:6f06:face:b00c:0:14/66 \
		-$2 2a03:2880:20:8f06:face:b00c:0:14/128 \
		-$2 2a03:2880:33:5f06:: \
		-$2 193.92.150.2/24 \
		-$2 193.95.150.100/28 \
		-$2 195.90.112.99/32 \
		-$2 195.90.111.99/22 \
		\
		> ./3.$1 $REDIR
	cmp -s 3.$1 3.${1}x || exit 101
	eval $PGX --shutdown $REDIR
	[ $? -eq 75 ] || exit 102
	[ -n "$REDIR" ] || echo ok 3.${1}

	i=$(($1 + 1))
	eval $PGX --test-mode -424 -664 -$4 x.a1 -$4 x.a2 > ./3.$i $REDIR
	cmp -s 3.$i 3.${1}x || exit 101
	eval $PGX --shutdown $REDIR
	[ $? -eq 75 ] || exit 102
	[ -n "$REDIR" ] || echo ok 3.${i}
}

ab 0 a allow A
ab 2 b block B

echo 'allow-file=x.a1' >> ./defx
echo 'resource-file=3.r1' >> ./defx
echo 'allow-file=x.a2' > ./3.r1

eval $PGX --test-mode -R ./defx --4-mask=24 --6-mask 64 > ./3.4 $REDIR
cmp -s 3.4 3.0x || exit 101
eval $PGX --shutdown $REDIR
[ $? -eq 75 ] || exit 102
[ -n "$REDIR" ] || echo ok 3.4
# }}}

### Configuration seems to work, go for the real thing!!  (./defx clobbered)

##
echo '=4: allow and block=' # {{{
if [ -n "$s4" ]; then
	echo 'skipping 4'
else

cat <<'_EOT' > ./4.x
recipient=x@y
sender=y@z
client_address=127.0.0.1
client_name=xy

recipient=x@y
sender=y@z
client_address=2a03:2880:33:5f06::
client_name=xy


recipient=x@y
sender=y@z
client_address=193.92.150.243
client_name=xy

recipient=x@y
sender=y@z
client_address=193.92.150.1
client_name=xy

recipient=x@y
sender=y@z
client_address=2a03:2880:20:4f00::
client_name=xy

recipient=x@y
sender=y@z
client_address=2a03:2880:20:4fff:ffff:ffff:ffff:ffff
client_name=xy

recipient=x@y
sender=y@z
client_address=2a03:2880:20:4f01:1::
client_name=xy

recipient=x@y
sender=y@z
client_address=193.95.150.100
client_name=xy

recipient=x@y
sender=y@z
client_address=2a03:2880:20:6f06:b000:b00c:0:14
client_name=xy

recipient=x@y
sender=y@z
client_address=195.90.108.1
client_name=xy



recipient=x@y
sender=y@z
client_address=200.200.200.200
client_name=exact.match

recipient=x@y
sender=y@z
client_address=200.200.200.200
client_name=also.exact.match


recipient=x@y
sender=y@z
client_address=200.200.200.200
client_name=domain.and.subdomain

recipient=x@y
sender=y@z
client_address=200.200.200.200
client_name=dwarf.domain.and.subdomain

recipient=x@y
sender=y@z
client_address=200.200.200.200
client_name=dwarf.dwarf.domain.and.subdomain

recipient=x@y
sender=y@z
client_address=200.200.200.200
client_name=d.a.s

recipient=x@y
sender=y@z
client_address=200.200.200.200
client_name=a.b.c.d.e.f.d.a.s

_EOT

: > ./4.0x
: > ./4.1x
i=0
while [ $i -lt 17 ]; do
	printf 'action=xDUNNO\n\n' >> ./4.0x
	printf 'action=xREJECT\n\n' >> ./4.1x
	i=$((i + 1))
done

sed -e 's/^allow/block/' < ./x.rc > ./y.rc

< ./4.x eval $PG -R ./x.rc > ./4.0 $REDIR
cmp -s 4.0 4.0x || exit 101
eval $PG -R ./x.rc --shutdown $REDIR
[ $? -ne 75 ] || exit 102
[ -n "$REDIR" ] || echo ok 4.0

< ./4.x eval $PG -R ./y.rc -t 1 > ./4.1 $REDIR
cmp -s 4.1 4.1x || exit 101
[ -n "$REDIR" ] || echo ok 4.1

eval $PG -R ./x.rc --shutdown $REDIR
[ $? -ne 75 ] || exit 102

printf \
	'recipient=x@y\nsender=y@z\nclient_address=200.200.200.200\n'\
'client_name=and.subdomain\n\n'\
	| eval $PG -R ./x.rc > ./4.2 $REDIR
printf 'action='"$MSG_DEFER"'\n\n' > ./4.2x
cmp -s ./4.2 ./4.2x || exit 101
[ -n "$REDIR" ] || echo ok 4.2

printf \
	'recipient=x@y\nsender=y@z\nclient_address=200.200.201.200\n'\
'client_name=subdomain.\n\n'\
	| eval $PG -R ./x.rc > ./4.3 $REDIR
printf 'action='"$MSG_DEFER"'\n\n' > ./4.3x
cmp -s ./4.3 ./4.3x || exit 101
[ -n "$REDIR" ] || echo ok 4.3

# root label -> error (aka unhandled aka DUNNO)
printf \
	'recipient=x@y\nsender=y@z\nclient_address=200.200.202.200\n'\
'client_name=.\n\n'\
	| eval $PG -R ./x.rc > ./4.4 $REDIR
printf 'action=DUNNO\n\n' > ./4.4x
cmp -s ./4.4 ./4.4x || exit 101
[ -n "$REDIR" ] || echo ok 4.4

eval $PG -R ./x.rc --shutdown $REDIR
[ $? -ne 75 ] || exit 102

# Let's just test --once mode here and now
printf \
	'recipient=x@y\nsender=y@z\nclient_address=200.200.202.200\n'\
'client_name=.\n\n'\
	'recipient=x@y\nsender=y@z\nclient_address=200.200.203.200\n'\
'client_name=.\n\n'\
	| eval $PG -R ./x.rc --once > ./4.5 $REDIR
printf 'action=DUNNO\n\n' > ./4.5x
cmp -s ./4.5 ./4.5x || exit 101
[ -n "$REDIR" ] || echo ok 4.5

eval $PG -R ./x.rc --shutdown $REDIR
[ $? -ne 75 ] || exit 102
fi
# }}}

##
echo '=5: gray basics (slow: needs sleeping)=' # {{{
if [ -n "$s5" ]; then
	echo 'skipping 5'
else

# Honour --delay-min and --count
cat <<'_EOT' | eval $PG -R ./x.rc > ./5.0 $REDIR; cat > ./5.x <<_EOT
recipient=x@y
sender=y@z
client_address=127.1.2.2
client_name=xy

recipient=x@y
sender=y@z
client_address=127.1.2.3
client_name=xy

_EOT
action=$MSG_DEFER

action=$MSG_DEFER

_EOT

cmp -s ./5.0 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.0
xsleep 1

cat <<'_EOT' | eval $PG -R ./x.rc > ./5.1 $REDIR
recipient=x@y
sender=y@z
client_address=127.1.2.4
client_name=xy

recipient=x@y
sender=y@z
client_address=127.1.2.5
client_name=xy

_EOT

cmp -s ./5.1 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.1
xsleep 1

cat <<'_EOT' | eval $PG -R ./x.rc > ./5.2 $REDIR; cat > ./5.xx <<_EOT
recipient=x@y
sender=y@z
client_address=127.1.2.7
client_name=xy

recipient=x@y
sender=y@z
client_address=127.1.2.8
client_name=xy

_EOT
action=DUNNO

action=DUNNO

_EOT

cmp -s ./5.2 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.2

# Force server restart, gray DB load
eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101
# ..but sleep a bit so times are adjusted!
xsleep 1

sed -i'' -e '3,$d' ./5.x
sed -i'' -e '3,$d' ./5.xx

#
printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.3 $REDIR
cmp -s ./5.3 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.3

xsleep 1

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.4 $REDIR
cmp -s ./5.4 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.4

#
# DB load after --gc-timeout
eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101

xsleep 7
# ..and try it with two, --gc-timeout cleanup kicks in (several times), timing
# out one of them

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.5 $REDIR
cmp -s ./5.5 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.5

xsleep 1

printf \
	'recipient=x@y\nsender=y@z\nclient_address=128.1.1.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.6 $REDIR
cmp -s ./5.6 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.6

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.7 $REDIR
cmp -s ./5.7 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.7

xsleep 1

printf \
	'recipient=x@y\nsender=y@z\nclient_address=128.1.1.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.8 $REDIR
cmp -s ./5.8 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.8

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.9 $REDIR
cmp -s ./5.9 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.9

printf \
	'recipient=x@y\nsender=y@z\nclient_address=128.1.1.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.10 $REDIR
cmp -s ./5.10 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.10

xsleep 1

printf \
	'recipient=x@y\nsender=y@z\nclient_address=128.1.1.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.11 $REDIR
cmp -s ./5.11 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.11

xsleep 3

printf \
	'recipient=x@y\nsender=y@z\nclient_address=128.1.1.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.12 $REDIR
cmp -s ./5.12 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.12

xsleep 3

printf \
	'recipient=x@y\nsender=y@z\nclient_address=128.1.1.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.13 $REDIR
cmp -s ./5.13 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.13

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.14 $REDIR
cmp -s ./5.14 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.14

xsleep 1

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.15 $REDIR
cmp -s ./5.15 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.15

xsleep 1

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.16 $REDIR
cmp -s ./5.16 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.16

# this will be delay-max at time
printf \
	'recipient=x@y\nsender=y@z\nclient_address=130.0.0.0\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.17 $REDIR
cmp -s ./5.17 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.17

# One more reload cycle
eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101

xsleep 1

printf \
	'recipient=x@y\nsender=y@z\nclient_address=127.1.2.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.18 $REDIR
cmp -s ./5.18 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.18

printf \
	'recipient=x@y\nsender=y@z\nclient_address=128.1.1.1\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.19 $REDIR
cmp -s ./5.19 ./5.xx || exit 101
[ -n "$REDIR" ] || echo ok 5.19

# While here, let's check at least once "instance" and "request"!
cat <<'_EOT' | eval $PG -R ./x.rc > ./5.20 $REDIR; cat <<_EOT > 5.20x
recipient=x@y
sender=y@z
client_address=128.1.1.1
client_name=xy

request=smtpd_access_policy_nono
recipient=x@y
sender=y@z
client_address=2.2.2.2
client_name=xy
instance=dietcurd.10

recipient=x@y
sender=y@z
client_address=1.1.1.1
client_name=xy
instance=dietcurd.10

recipient=x@y
sender=y@z
client_address=1.1.1.1
client_name=xy
instance=dietcurd.10

_EOT
action=DUNNO

action=DUNNO

action=$MSG_DEFER

action=$MSG_DEFER

_EOT

cmp -s ./5.20 ./5.20x || exit 101
[ -n "$REDIR" ] || echo ok 5.20

xsleep 2

printf \
	'recipient=x@y\nsender=y@z\nclient_address=130.0.0.0\nclient_name=xy\n\n'\
	| eval $PG -R ./x.rc > ./5.21 $REDIR
cmp -s ./5.21 ./5.x || exit 101
[ -n "$REDIR" ] || echo ok 5.21

eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101
fi
# }}}

##
echo '=6: gray parallel (this takes quite some time)=' # {{{
if [ -n "$s6" ]; then
	echo 'skipping 6'
else

rm -f *.db

# max1: X*2  max2: max 255*255
#max1=32 max2=16
#max1=6 max2=421
max1=4 max2=24

cat > ./6.rc <<_EOT
4-mask 24
count 1
msg-defer=all the same
delay-min 2
delay-max 72
gc-timeout 144
server-timeout 72
store-path=$pwd
limit $((max2 * max1))
limit-delay=0
_EOT

i=0
while [ $i -lt $max1 ]; do
	: > ./6.${i}x
	i=$((i + 1))
done
i=0
while [ $i -lt $max1 ]; do
	(
		j=0
		while [ $j -lt $max2 ]; do
			j1=$((j / 256))
			j2=$((j % 256))
			printf 'recipient=x@y\nsender=y@z\nclient_name=xy\n'\
'client_address='$i.$j1.$j2.$j2'\ninstance=hey'$i'.'$j'\n\n'
			printf "action=all the same\n\n" >> ./6.${i}x
			while :; do
				[ -f ./6.${i}syncx ] && break
				sdelay
			done
			rm -f ./6.${i}syncx
			j=$((j + 1))
		done
		echo > ./6.${i}okx

		# Find our partner, and wait for it
		[ $((i % 2)) -eq 0 ] && k=$((i + 1)) || k=$((i - 1))

		while :; do
			[ -f ./6.${k}okx ] && break
			delay
		done

		xsleep 2

		j=0
		while [ $j -lt $max2 ]; do
			j1=$((j / 256))
			j2=$((j % 256))
			printf 'recipient=x@y\nsender=y@z\nclient_name=xy\n'\
'client_address='$k.$j1.$j2.$j2'\ninstance=hey'$i'.'$j'\n\n'
			printf 'action=DUNNO\n\n' >> ./6.${i}x
			while :; do
				[ -f ./6.${i}syncx ] && break
				sdelay
			done
			rm -f ./6.${i}syncx
			j=$((j + 1))
		done
	) | eval $PG -R ./6.rc $REDIR | {
		while :; do
			read a || break
			read e || break
			echo $a
			echo $e
			echo > ./6.${i}syncx
		done
		echo > ./6.${i}ok
	} > ./6.$i &

	i=$((i + 1))
done

# Wait for all
while :; do
	i=0
	while [ $i -lt $max1 ]; do
		[ -f ./6.${i}ok ] || break
		i=$((i + 1))
	done
	[ $i -eq $max1 ] && break
	delay
done

i=0
while [ $i -lt $max1 ]; do
	cmp -s ./6.$i ./6.${i}x || exit 101
	[ -n "$REDIR" ] || echo ok 6.$i
	i=$((i + 1))
done

eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101
fi
# }}}

##
echo '=7: gray --focus-sender=' # {{{
if [ -n "$s7" ]; then
	echo 'skipping 7'
else

rm -f *.db

# Without -f!
cat <<'_EOT' | eval $PG -R ./x.rc > ./7.0 $REDIR; cat > ./7.x <<_EOT
recipient=x1@y
sender=y@z
client_address=127.1.2.2
client_name=xy

recipient=x2@y
sender=y@z
client_address=127.1.2.3
client_name=xy

_EOT
action=$MSG_DEFER

action=$MSG_DEFER

_EOT

cmp -s ./7.0 ./7.x || exit 101
[ -n "$REDIR" ] || echo ok 7.0

# save+reload (without -f still!)
eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101

xsleep 1
printf 'action=%s\n\n' "$MSG_DEFER" > 7.xx

printf \
	'recipient=x3@y\nsender=y@z\nclient_address=127.1.2.4\nclient_name=xy\n\n'\
	| eval $PG -f -R ./x.rc > ./7.1 $REDIR
cmp -s ./7.1 ./7.xx || exit 101
[ -n "$REDIR" ] || echo ok 7.1

xsleep 1
printf 'action=%s\n\n' "DUNNO" > 7.xx

printf \
	'recipient=x4@y\nsender=y@z\nclient_address=127.1.2.5\nclient_name=xy\n\n'\
	| eval $PG -f -R ./x.rc > ./7.2 $REDIR
cmp -s ./7.2 ./7.xx || exit 101
[ -n "$REDIR" ] || echo ok 7.2

eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101
fi
# }}}

##
echo '=8: --startup, more --shutdown' # {{{
if [ -n "$s8" ]; then
	echo 'skipping 8'
else
	rm -f *.db

	i=0 j=
	doit() {
		j=$((i + 1))
		eval $PG -R ./x.rc --server-timeout=1 --startup > ./8.$j $REDIR
		[ $? -eq 0 ] || exit 101
		[ -n "$REDIR" ] || echo ok 8.$i
		[ -s ./8.$j ] && exit 101
		[ -n "$REDIR" ] || echo ok 8.$j

		i=$((j + 1))
		j=$((i + 1))

		eval $PG -R ./x.rc --server-timeout=1 --startup > ./8.$j $REDIR
		[ $? -eq 75 ] || exit 101
		[ -n "$REDIR" ] || echo ok 8.$i
		[ -s ./8.$j ] && exit 101
		[ -n "$REDIR" ] || echo ok 8.$j

		i=$((j + 1))
		j=$((i + 1))
		sleep 2

		eval $PG -R ./x.rc --shutdown > ./8.$j $REDIR
		[ $? -eq 0 ] || exit 101
		[ -n "$REDIR" ] || echo ok 8.$i
		[ -s ./8.$j ] && exit 101
		[ -n "$REDIR" ] || echo ok 8.$j

		i=$((j + 1))
		j=$((i + 1))

		eval $PG -R ./x.rc --shutdown > ./8.$j $REDIR
		[ $? -eq 75 ] || exit 101
		[ -n "$REDIR" ] || echo ok 8.$i
		[ -s ./8.$j ] && exit 101
		[ -n "$REDIR" ] || echo ok 8.$j
	}
	doit
	doit
	doit
fi
# }}}
)

exit $?

# s-sht-mode
