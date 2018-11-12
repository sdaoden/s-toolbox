#!/bin/sh -
#@ Simple fancontrol script, by default for an MacBook Air.
#
# Public Domain.

## Generic fancontrol.sh settings and variables

# Whether the default "off" speed shall be 0 rather thank original value
OFFIS0=1
# If defined used in favour of calculation; plus: off=0, max=$FANMAX-500
FANVALS='2000 3000 4000 5000'
# Whether we shall decrease fan speed if we would have stepped back *one* speed
# level ten times in a row.  By default we only step back if we can step down
# two levels, or somewhat similar to that.
REDUXONEOK=1
# Sleeps until next classify()
SHORT=30 LONG=30 VERYLONG=60

# Queried below: $(< ) possible (instead of cat(1))?
FASTCAT=0

#
DEBUG=0

# New fan value if we step, newlvl to step to (evtl.), new redux-at level
# (evtl.), and the sleep duration before next query
newfan= newlvl= lvl_rat=0 sleepdur=0

lvl_curr=0 lvl_reduxat=0 lvl_reduxone=0
fan1= fan2= fan3= fan4= fanmax=

## Local environment settings

# These are needed by the generics (the former only if -z $FANVALS)
FANMINVAL=2000
FANMAX=/sys/class/hwmon/hwmon1/device/fan1_max
FANSTORE=/sys/class/hwmon/hwmon1/device/fan1_min

CPU0=/sys/class/hwmon/hwmon0/temp2_input
CPU1=/sys/class/hwmon/hwmon0/temp3_input
GPU=/sys/class/hwmon/hwmon2/temp1_input
FAN=/sys/class/hwmon/hwmon1/device/fan1_input

t0= t1= t2=

classify() {
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
   if [ $t0 -le 50000 ] && [ $t1 -le 50000 ] && [ $t2 -le 60000 ]; then
      newfan=0 newlvl=0 lvl_rat=0
   elif [ $t0 -le 55000 ] && [ $t1 -le 55000 ] && [ $t2 -le 64000 ]; then
      newfan=$fan1 newlvl=1 lvl_rat=0
   elif [ $t0 -le 60000 ] && [ $t1 -le 60000 ] && [ $t2 -le 68000 ]; then
      newfan=$fan2 newlvl=2 lvl_rat=0
   elif [ $t0 -le 64000 ] && [ $t1 -le 64000 ] && [ $t2 -le 72000 ]; then
      newfan=$fan3 newlvl=3 lvl_rat=1 sleepdur=$SHORT
   elif [ $t0 -le 69000 ] && [ $t1 -le 69000 ] && [ $t2 -le 78000 ]; then
      newfan=$fan4 newlvl=4 lvl_rat=2 sleepdur=$SHORT
   else
      newfan=$fanmax newlvl=5 lvl_rat=3 sleepdur=$VERYLONG
   fi
}

# Only if $REDUXONEOK
#reduxoneok() { return 1; }
reduxoneok() {
   if [ $lvl_curr -ne 2 ]; then
      return 1
   fi
   if [ $t0 -le 53000 ] && [ $t1 -le 53000 ] && [ $t2 -le 62000 ]; then
      return 0
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
      echo >&2 $*
   fi
}

fanmax=$((`cat $FANMAX` - 500))
if [ $fanmax -lt 0 ]; then
   echo >&2 'Cannot deal with fan, max rpm to small'
   exit 2
fi
if [ -z "$FANVALS" ]; then
   fanval() {
      i=$1 x=$2
      while [ $i -lt $x ]; do
         i=$(($i + 250))
      done
      if [ $i -eq 0 ]; then
         i=$FANMINVAL
      fi
      if [ $i -gt $fanmax ]; then
         i=$fanmax
      fi
      echo $i
   }
   fan1=`fanval $FANMINVAL $(($fanmax / 4))`
   fan2=`fanval $fan1 $(($fan1 + $fanmax / 4))`
   fan4=`fanval $fan2 $(($fan2 + $fanmax / 4))`
   fan3=`fanval $fan2 $(($fan2 + (($fan4 - $fan2) / 2)))`
else
   set -- $FANVALS
   i=1
   for j
   do
      eval fan${i}=$j
      i=$((i + 1))
   done
fi
dbg "= fan1=$fan1,fan2=$fan2,fan3=$fan3,fan4=$fan4,fanmax=$fanmax"

while [ 1 -eq 1 ]; do
   classify

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
         if [ $lvl_reduxone -ge 10 ] && reduxoneok; then
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
   sleep $sleepdur
done

# s-sh-mode
