#!/bin/sh -
#@ Simple fancontrol script for Linux.
#@ Currently assumed control levels are forgotten with SIGUSR1.
#@ INT/HUP/QUIT/TERM cause exit, "turning off" fan (via "$FANOFF > $FANSTORE").
#@
#@   start() {
#@   	ebegin "Starting fancontrol"
#@   	start-stop-daemon --start --background --nicelevel -10 \
#@   		--make-pidfile --pidfile ${PID} \
#@   		--exec /etc/fancontrol.sh -- ${CONFIG}
#@   	eend ${?}
#@   }
#@   stop() {
#@   	ebegin "Stopping fancontrol"
#@   	start-stop-daemon --stop --pidfile ${PID}
#@   	eend ${?}
#@   }
#@
#@ Public Domain

## Generic fancontrol.sh settings and variables

# Predefined sets; with -z "$MODEL" an init() and a classify() must be
# provided.  The init() must provide $FANOFF ("turn off fan"), $FANMIN,
# $FANMAX and $FANSTORE (where to write the value to).
MODEL=
MODEL=MACBOOK_AIR_2011

# If set, no automatic calculation of six fan values in between $FANMIN and
# $FANMAX is transformed, and the members are taken as mandatory.
# May be set by $MODEL specific init().
# The number of entries actually also model specific ...
FANVALS=

# Noisy (in $DBGLOG)
DEBUG=0
DBGLOG=/tmp/fancontrol.dbg

# Whether we shall call reduxoneok[_$MODEL]() to check whether we can decrease
# fan speed if we would have stepped back *one* speed level ten times in a row.
# By default we only step back if we can step down two levels, or somewhat
# similar to that.
REDUXONEOK=1

# Sleeps until next classify()
SHORT=15 MEDIUM=20 LONG=30 VERYLONG=60

# Queried below: $(< ) possible (instead of cat(1))?
FASTCAT=0

# New fan value if we step, newlvl to step to (evtl.), new redux-at level
# (evtl.), and the sleep duration before next query
newfan= newlvl= lvl_rat=0 sleepdur=0

   lvl_curr=0 lvl_reduxat=0 lvl_reduxone=0
   # + $FANOFF, $FANMIN, $FANMAX
   fan1= fan2= fan3= fan4= fan5= fan6=

## Local environment settings

init() {
   FANOFF=0
   FANMIN=2000
   #FANMAX=`cat /sys/class/hwmon/hwmon1/device/fan1_max`
   #FANSTORE=/sys/class/hwmon/hwmon1/device/fan1_min
   echo >&2 'I need an init() function'
   exit 1
}

classify() {
   echo >&2 'I need a classify() function'
   exit 1
}

# Only if $REDUXONEOK
reduxoneok() { return 1; }

init_MACBOOK_AIR_2011() {
   FANOFF=0
   FANMIN=2000
   FANMAX=`cat /sys/class/hwmon/hwmon1/device/fan1_max`
   [ $FANMAX -eq 6500 ] && FANVALS='3000 3600 4200  5000 5750 6250'
   FANSTORE=/sys/class/hwmon/hwmon1/device/fan1_min

   CPU0=/sys/class/hwmon/hwmon0/temp2_input
   CPU1=/sys/class/hwmon/hwmon0/temp3_input
   GPU=/sys/class/hwmon/hwmon2/temp1_input
   FAN=/sys/class/hwmon/hwmon1/device/fan1_input
   t0= t1= t2=
}

classify_MACBOOK_AIR_2011() {
   if [ $FASTCAT -eq 0 ]; then
      eval t0=$(< $CPU0)
      eval t1=$(< $CPU1)
      eval t2=$(< $GPU)
      [ $DEBUG -ne 0 ] && eval fan=$(< $FAN)
   else
      t0=`cat $CPU0`
      t1=`cat $CPU1`
      t2=`cat $GPU`
      [ $DEBUG -ne 0 ] && fan=`cat $FAN`
   fi
   dbg "= fan=$fan,cpu0=$t0,cpu1=$t1,gpu=$t2"

   sleepdur=$LONG
   if [ $t0 -le 54000 ] && [ $t1 -le 54000 ] && [ $t2 -le 62000 ]; then
      newfan=$FANMIN newlvl=0 lvl_rat=0
   elif [ $t0 -le 58000 ] && [ $t1 -le 58000 ] && [ $t2 -le 65000 ]; then
      newfan=$fan1 newlvl=1 lvl_rat=0
   elif [ $t0 -le 62000 ] && [ $t1 -le 62000 ] && [ $t2 -le 68000 ]; then
      newfan=$fan2 newlvl=2 lvl_rat=0
   elif [ $t0 -le 66000 ] && [ $t1 -le 66000 ] && [ $t2 -le 72000 ]; then
      newfan=$fan3 newlvl=3 lvl_rat=1 sleepdur=$MEDIUM
   elif [ $t0 -le 71000 ] && [ $t1 -le 71000 ] && [ $t2 -le 76000 ]; then
      newfan=$fan4 newlvl=4 lvl_rat=2 sleepdur=$MEDIUM
   elif [ $t0 -le 74000 ] && [ $t1 -le 74000 ] && [ $t2 -le 79000 ]; then
      newfan=$fan5 newlvl=5 lvl_rat=3 sleepdur=$SHORT
   elif [ $t0 -le 77000 ] && [ $t1 -le 77000 ] && [ $t2 -le 81000 ]; then
      newfan=$fan6 newlvl=6 lvl_rat=4 sleepdur=$SHORT
   else
      newfan=$FANMAX newlvl=7 lvl_rat=4 sleepdur=$VERYLONG
   fi
}

reduxoneok_MACBOOK_AIR_2011() {
   if [ $lvl_curr -eq 2 ]; then
      if [ $t0 -le 56000 ] && [ $t1 -le 56000 ] && [ $t2 -le 63000 ]; then
         return 0
      fi
   elif [ $lvl_curr -eq 3 ]; then
      if [ $t0 -le 60000 ] && [ $t1 -le 60000 ] && [ $t2 -le 66000 ]; then
         return 0
      fi
   fi
   return 1
}

## 8< ----- >8

if ( echo $(( 10 - 10 / 10 )) ) >/dev/null 2>&1; then :; else
   echo >&2 'Shell cannot do arithmetic, bailing out'
   exit 1
fi
if ( $(< /dev/null) ) >/dev/null 2>&1; then
   FASTCAT=1
fi

dbg() {
   if [ $DEBUG -ne 0 ]; then
      echo $* >> $DBGLOG
   fi
}

initfun=init classifyfun=classify reduxoneokfun=reduxoneok
if [ -n "${MODEL}" ]; then
   initfun=${initfun}_${MODEL}
   classifyfun=${classifyfun}_${MODEL}
   reduxoneokfun=${reduxoneokfun}_${MODEL}
fi
echo $initfun/$classifyfun/$reduxoneokfun

$initfun

# Query our states
if [ -n "$FANVALS" ]; then
   msg= i=1
   set -- $FANVALS
   for j
   do
      eval fan${i}=$j
      msg="${msg}fan${i}=$j,"
      i=$((i + 1))
   done
   dbg "= FANMIN=$FANMIN,${msg}FANMAX=$FANMAX"

else
   if [ $FANMAX -lt 500 ]; then
      echo >&2 'Cannot deal with fan, max rpm to small'
      exit 2
   fi
   i=$((($FANMAX - $FANMIN) / 8))
   i=$(($i + (-$i % 50)))
   fan1=$(($FANMIN + $i))
   fan2=$(($fan1 + $i + $i / 2))
   fan3=$(($fan2 + $i + $i / 2))

   i=$((($FANMAX - $fan3 + $i) / 4))
   i=$(($i + (-$i % 50)))
   fan4=$(($fan3 + $i))
   fan5=$(($fan4 + $i))
   fan6=$(($fan5 + $i))
   dbg "= FANMIN=$FANMIN,\
fan1=$fan1,fan2=$fan2,fan3=$fan3,fan4=$fan4,fan5=$fan5,fan6=$fan6,\
FANMAX=$FANMAX"
fi

trap "echo $FANOFF > $FANSTORE" EXIT
trap "trap \"\" INT HUP QUIT TERM; exit 1" INT HUP QUIT TERM
trap "echo $FANMIN > $FANSTORE; lvl_curr=0 lvl_reduxat=0 init=" USR1

while [ 1 -eq 1 ]; do
   $classifyfun

   i=
   if [ $newlvl -eq $lvl_curr ]; then
      lvl_reduxone=0
   elif [ $newlvl -gt $lvl_curr ]; then
      dbg "+ increasing fan min: $newfan"
      i=1
   elif [ $newlvl -le $lvl_reduxat ]; then
      dbg "+ decreasing fan min: $newfan"
      i=1
   elif [ $newlvl -lt $lvl_curr ]; then
      lvl_reduxone=$(($lvl_reduxone + 1))
      if [ $REDUXONEOK -ne 0 ]; then
         if [ $lvl_reduxone -ge 10 ] && $reduxoneokfun; then
            dbg "+ reduxone limit, decreasing fan min: $newfan"
            i=1
         fi
      fi
   fi

   if [ -n "$i" ]; then
      echo $newfan > $FANSTORE
      lvl_curr=$newlvl lvl_reduxat=$lvl_rat lvl_reduxone=0
   fi
   dbg "_ sleep=$sleepdur,lvl_curr=$lvl_curr,lvl_reduxat=$lvl_reduxat,\
lvl_reduxone=$lvl_reduxone"
   # The way the shell handles signals is complicated, only mksh was able
   # to always honour signals regardless of what.  bash(1) documents the
   # following approach to always work, and that seems to be portable behaviour
   sleep $sleepdur &
   wait
done

# s-sh-mode
