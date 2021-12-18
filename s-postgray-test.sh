#!/bin/sh -
#@ s-postgray test

KEEP_TESTS=
REDIR= #'2>/dev/null'

PG=../s-postgray
DEFER_MSG='DEFER_IF_PERMIT 4.2.0 Cannot hurry love'

###

LC_ALL=C SOURCE_DATE_EPOCH=844221007
export LC_ALL SOURCE_DATE_EPOCH

mkdir .test || exit 1
trap "trap '' EXIT; [ -z \"$KEEP_TESTS\" ] && rm -rf ./.test" EXIT
trap 'exit 1' HUP INT TERM

(
cd ./.test || exit 2
pwd=$(pwd) || exit 3

### First of all fetch+adjust compile time defaults, create some resources {{{

$PG --list-values > ./def || exit 4
PGX="$PG --store-path='$pwd' --defer-msg='$DEFER_MSG'"
PGx="$PG -s'$pwd' -m '$DEFER_MSG'"
LV=--list-values

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

eval $PGX $LV > ./tdef1 || exit 1
sed '/^defer-msg/,$d' < def > ./defx || exit 2
echo 'defer-msg='"$DEFER_MSG" >> ./defx
echo 'store-path='"$pwd"'' >> ./defx
cmp -s tdef1 defx || exit 3

eval $PGx $LV > ./tdef2 || exit 4
cmp -s tdef2 defx || exit 5
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
allow-file=x.a2
limit-delay 8
master-timeout 5
defer-msg=$DEFER_MSG
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
		# Comment		
_EOT
2a03:2880:33:5f06::
   # Comment !!
193.92.150.2/24
193.95.150.100/28
195.90.111.99/22
_EOT
# }}}

### }}} After that we can work with adjusted defaults defx!

##
echo '=1: options=' # {{{

adj_def() {
   sed -Ee 's|^'"$1"'=.*$|'"$1"'='"$2"'|' < ./defx > ./${3}x || exit 100
   cmp -s $3 ${3}x || exit 101
}

t() {
   t=$1 o=$2 v=$3
   shift 3
   eval "$PGX" "$@" "$LV" > ./$t $REDIR; adj_def $o $v $t || exit $?
   [ -n "$REDIR" ] || echo ok $t
   eval "$PGX" -R ./defx "$@" "$LV" > ./$t.2 $REDIR;\
      adj_def $o $v $t.2 || exit $?
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

t 1.19 master-timeout 0 --master-timeout=0
t 1.20 master-timeout 5 -t 5
# }}}

##
echo '=2: resource files=' # {{{

adj_def() {
   t=$1
   shift
   cat < ./defx > ./${t}x
   while [ $# -gt 0 ]; do
      sed -i'' -Ee 's|^'"$1"'=.*$|'"$1"'='"$2"'|' ${t}x || exit 100
      shift 2
   done
   cmp -s $t ${t}x || exit 101
   [ -n "$REDIR" ] || echo ok $t
}

cat > ./2.rc1 <<'_EOT'; cat > ./2.rc2 <<'_EOT'
  # Comment 1
   4-mask           31   
6-mask=127
count 3
resource-file 2.rc2
delay-min         4
#comment2
      gc-rebalance=2
      gc-timeout	7200  	   
limit-delay=10405
_EOT
delay-max=5
limit=11000
master-timeout=9
#comment3
_EOT

eval $PGX -R 2.rc1 -t 10 $LV > ./2.0 $REDIR
   adj_def 2.0 \
      4-mask 31 6-mask 127 \
      count 3 \
      delay-max 5 delay-min 4 \
      gc-rebalance 2 gc-timeout 7200 \
      limit 11000 limit-delay 10405 \
      master-timeout 10 || exit $?
# }}}

##
echo '=3: white lists, check=' # {{{

cat > ./3.xx <<'_EOT'; cat defx >> ./3.xx;
= exact.match
= also.exact.match
~ (*.)?domain.and.subdomain
~ (*.)?d.a.s
= 127.0.0.0 (/24)
~ 2a03:2880:20:4f00::/56
= 2a03:2880:20:6f06:: (/64)
= 2a03:2880:33:5f06:: (/64)
= 193.92.150.0 (/24)
= 193.95.150.0 (/24)
~ 195.90.108.0/22
_EOT

eval $PGX --allow-check --4-mask 24 --6-mask 64 \
   -a exact.match \
   --allow also.exact.match \
   -a.domain.and.subdomain \
   --allow=.d.a.s \
   -a 127.0.0.1 \
   -a 2a03:2880:20:4f06:face:b00c:0:14/56 \
   -a 2a03:2880:20:6f06:face:b00c:0:14/66 \
   -a 2a03:2880:33:5f06:: \
   -a 193.92.150.2/24 \
   -a 193.95.150.100/28 \
   -a 195.90.111.99/22 \
   \
   $LV > ./3.0 $REDIR
cmp -s 3.0 3.xx || exit 101
[ -n "$REDIR" ] || echo ok 3.0

eval $PGX --allow-check -424 -664 -A x.a1 -A x.a2 $LV > ./3.1 $REDIR
cmp -s 3.1 3.xx || exit 101
[ -n "$REDIR" ] || echo ok 3.1

echo 'allow-file=x.a1' >> ./defx
echo 'resource-file=3.r1' >> ./defx
echo 'allow-file=x.a2' >> ./3.r1

eval $PGX --allow-check -R ./defx --4-mask=24 --6-mask 64 $LV > ./3.2 $REDIR
cmp -s 3.2 3.xx || exit 101
[ -n "$REDIR" ] || echo ok 3.2
# }}}

### Configuration seems to work, go for the real thing!!  (./defx clobbered)

##
echo '=4: white lists=' # {{{

# A block, the latter two are optional (for us)
#recipient=root@localhost
#sender=steffen@kent
#client_address=127.0.0.1
#client_name=localhost
#request=smtpd_access_policy
#instance=2cf5.61c38318.aacaa.0

cat <<'_EOT' | eval $PG -R ./x.rc -t 1 > ./4.0 $REDIR; cat > ./4.0x <<'_EOT'
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
client_address=193.92.150.001
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
action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

action=DUNNO

_EOT

cmp -s 4.0 4.0x || exit 101
[ -n "$REDIR" ] || echo ok 4.0

eval $PG -R ./x.rc --shutdown $REDIR
# }}}

##
echo '=5: gray basics (slow: needs sleeping)=' # {{{

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
action=$DEFER_MSG

action=$DEFER_MSG

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

# Force master restart, gray DB load
eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101
# ..but sleep a bit so times are adjusted!
xsleep 1

sed -i'' '3,$d' ./5.x
sed -i'' '3,$d' ./5.xx

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

# While here, let's check at least once "instance" and "reqest"!
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

action=$DEFER_MSG

action=DUNNO

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
# }}}

##
echo '=6: gray parallel (this takes quite some time)=' # {{{

rm -f *.db

# max1: X*2  max2: max 255*255
#max1=32 max2=16
#max1=6 max2=421
max1=4 max2=24

cat > ./6.rc <<_EOT
4-mask 24
count 1
delay-min 2
delay-max 720
gc-timeout 1440
defer-msg=all the same
store-path=$pwd
limit $((max2 * max1))
_EOT

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

echo ===================DONE WAITING
i=0
while [ $i -lt $max1 ]; do
   cmp -s ./6.$i ./6.${i}x || exit 101
   [ -n "$REDIR" ] || echo ok 6.$i
   i=$((i + 1))
done



eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 0 ] || exit 101
# }}}

##
echo '=X.Y: shutdown request without server='
eval $PG -R ./x.rc --shutdown $REDIR
[ $? -eq 75 ] || exit 101
[ -n "$REDIR" ] || echo ok X.Y
)
exit $?

# s-it-mode