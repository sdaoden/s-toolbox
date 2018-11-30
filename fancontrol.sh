#!/bin/sh -
#@ Simple fancontrol script, by default for Linux.
#@ Currently assumed control levels are forgotten with SIGUSR1.
#@ INT/HUP/QUIT/TERM cause exit, "turning off" fan.
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

# Predefined sets; see MACBOOK_AIR_2011 set for an example.
# - init_MODEL() must provide $FANOFF ("turn off fan"), $FANMIN, and $FANMAX.
#   It may adjust $REDUXONEOK, and set $FANVALS, as below.
# - classify_MODEL() is periodically called and must set $NEWFAN, $NEWLVL and
#   $SLEEPDUR, as below.
# - By default we step down only if the $NEWLVL is two levels below the current
#   one, but with $REDUXONEOK reduxoneok_MODEL() will be called with $1=current
#   level whenever we would have stepped down one level several successive
#   times: if that returns 0 then we will perform the step one level back.
# - fanadjust_MODEL(): called with $1=new RPM.  (Or $FANOFF.)
MODEL=
MODEL=MACBOOK_AIR_2011

# In general it is up to the MODEL how many levels exist, and which RPM values
# they use -- we only look for $NEWFAN, $NEWLVL, $SLEEPDUR and $REDUXONEOK.
# We also use $FANOFF and $FANMIN (and $FANMAX).
# After init_MODEL() is called we will calculate six fan speed levels.
   FAN1= FAN2= FAN3= FAN4= FAN5= FAN6=
# within the range $FANMIN..$FANMAX unless
   FANVALS=
# is set, in which case that string is split and that many FANxy are created.

# See $MODEL.
   REDUXONEOK=

# To be set within classify_MODEL().
# New fan RPM value shall we step, a numeric level assigned to that fan value
# (sequential decimal digits starting with 0), and the sleep duration before
# the next call to classify_MODEL().  Upon startup we are 0/$FANOFF/undef.
NEWFAN= NEWLVL= SLEEPDUR=0

# Noisy (in $DBGLOG).
DEBUG=0
DBGLOG=/tmp/fancontrol.dbg

# Set non-empty if shell supports $(< ) (instead of cat(1))?
FASTCAT=

## MODELs

# Hull

init() { echo >&2 'I need an init() function'; exit 1; }
classify() { echo >&2 'I need a classify() function'; exit 1; }
reduxoneok() { echo >&2 'Current level: '$1; return 1; } # Only if $REDUXONEOK
fanadjust() { echo >&2 'I would adjust fan to '$1; }

# MACBOOK_AIR_2011

init_MACBOOK_AIR_2011() {
   FANOFF=0
   FANMIN=2000
   FANMAX=`cat /sys/class/hwmon/hwmon1/device/fan1_max` # only once: no FASTCAT
   [ $FANMAX -eq 6500 ] && FANVALS='3000 3600 4200  5000 5750 6250'
   REDUXONEOK=1

   m_sleep1=15 m_sleep2=20 m_sleep3=30 m_sleep4=60 # -> $SLEEPDUR

   m_cpu0=/sys/class/hwmon/hwmon0/temp2_input
   m_cpu1=/sys/class/hwmon/hwmon0/temp3_input
   m_gpu=/sys/class/hwmon/hwmon2/temp1_input
   m_fan0=/sys/class/hwmon/hwmon1/device/fan1_input
   m_fan0store=/sys/class/hwmon/hwmon1/device/fan1_min
   m_t0= m_t1= m_t2= m_f0=
   dbg 'M Created MacBook Air 2011 settings'
}

classify_MACBOOK_AIR_2011() {
   if [ -n "$FASTCAT" ]; then
      eval m_t0=$(< $m_cpu0)
      eval m_t1=$(< $m_cpu1)
      eval m_t2=$(< $m_gpu)
      [ $DEBUG -ne 0 ] && eval m_f0=$(< $m_fan0)
   else
      m_t0=`cat $m_cpu0`
      m_t1=`cat $m_cpu1`
      m_t2=`cat $m_gpu`
      [ $DEBUG -ne 0 ] && m_f0=`cat $m_fan0`
   fi
   dbg "M fan0=$m_f0,cpu0=$m_t0,cpu1=$m_t1,gpu=$m_t2"

   SLEEPDUR=$m_sleep3
   if [ $m_t0 -gt 77000 ] || [ $m_t1 -gt 77000 ] || [ $m_t2 -gt 81000 ]; then
      NEWFAN=$FANMAX NEWLVL=7 SLEEPDUR=$m_sleep4
   elif [ $m_t0 -gt 74000 ] || [ $m_t1 -gt 74000 ] || [ $m_t2 -gt 79000 ]; then
      NEWFAN=$FAN6 NEWLVL=6 SLEEPDUR=$m_sleep1
   elif [ $m_t0 -gt 71000 ] || [ $m_t1 -gt 71000 ] || [ $m_t2 -gt 76000 ]; then
      NEWFAN=$FAN5 NEWLVL=5 SLEEPDUR=$m_sleep1
   elif [ $m_t0 -gt 66000 ] || [ $m_t1 -gt 66000 ] || [ $m_t2 -gt 72000 ]; then
      NEWFAN=$FAN4 NEWLVL=4 SLEEPDUR=$m_sleep2
   elif [ $m_t0 -gt 62000 ] || [ $m_t1 -gt 62000 ] || [ $m_t2 -gt 68000 ]; then
      NEWFAN=$FAN3 NEWLVL=3 SLEEPDUR=$m_sleep2
   elif [ $m_t0 -gt 58000 ] || [ $m_t1 -gt 58000 ] || [ $m_t2 -gt 65000 ]; then
      NEWFAN=$FAN2 NEWLVL=2
   elif [ $m_t0 -gt 52000 ] || [ $m_t1 -gt 52000 ] || [ $m_t2 -gt 62000 ]; then
      NEWFAN=$FAN1 NEWLVL=1
   else
      NEWFAN=$FANMIN NEWLVL=0
   fi
}

reduxoneok_MACBOOK_AIR_2011() {
   if [ $1 -eq 2 ]; then
      if [ $m_t0 -le 56000 ] && [ $m_t1 -le 56000 ] && [ $m_t2 -le 63000 ]; then
         return 0
      fi
   elif [ $1 -eq 3 ]; then
      if [ $m_t0 -le 60000 ] && [ $m_t1 -le 60000 ] && [ $m_t2 -le 66000 ]; then
         return 0
      fi
   fi
   return 1
}

fanadjust_MACBOOK_AIR_2011() {
   dbg "M fanadjust: $1"
   echo $1 > $m_fan0store
}

## 8< ----- >8

lvl_curr=0 lvl_reduxone=0

dbg() {
   if [ $DEBUG -ne 0 ]; then
      echo $* >> $DBGLOG
   fi
}

if ( echo $(( 10 - 10 / 10 )) ) >/dev/null 2>&1; then :; else
   echo >&2 'Shell cannot do arithmetic, bailing out'
   exit 1
fi

if ( $(< /dev/null) ) >/dev/null 2>&1 &&
      [ -f /etc/fstab ] && command -v cksum >/dev/null 2>&1 &&
      [ "`{ i=\`cat /etc/fstab\`; echo $i; } | cksum`" = \
         "`{ i=$(< /etc/fstab); echo $i; } | cksum`" ]; then
   dbg '= Enabling FASTCAT for this shell'
   FASTCAT=yes
fi

initfun=init classifyfun=classify \
   reduxoneokfun=reduxoneok fanadjustfun=fanadjust
if [ -n "${MODEL}" ]; then
   initfun=${initfun}_${MODEL}
   classifyfun=${classifyfun}_${MODEL}
   reduxoneokfun=${reduxoneokfun}_${MODEL}
   fanadjustfun=${fanadjustfun}_${MODEL}
fi

$initfun

# Query our states
if [ -n "$FANVALS" ]; then
   msg= i=1
   set -- $FANVALS
   for j
   do
      eval FAN${i}=$j
      msg="${msg}FAN${i}=$j,"
      i=$((i + 1))
   done
   dbg "= FANMIN=$FANMIN,${msg}FANMAX=$FANMAX"
else
   i=$((($FANMAX - $FANMIN)))
   if [ $FANMAX -lt 500 ] || [ $i -lt 500 ]; then
      echo >&2 'Cannot deal with FANMAX/FANMIN values, bailing out'
      exit 2
   fi
   i=$((($FANMAX - $FANMIN) / 8))
   i=$(($i + (-$i % 50)))
   FAN1=$(($FANMIN + $i))
   FAN2=$(($FAN1 + $i + $i / 2))
   FAN3=$(($FAN2 + $i + $i / 2))

   i=$((($FANMAX - $FAN3 + $i) / 4))
   i=$(($i + (-$i % 50)))
   FAN4=$(($FAN3 + $i))
   FAN5=$(($FAN4 + $i))
   FAN6=$(($FAN5 + $i))
   dbg "= FANMIN=$FANMIN,\
FAN1=$FAN1,FAN2=$FAN2,FAN3=$FAN3,FAN4=$FAN4,FAN5=$FAN5,FAN6=$FAN6,\
FANMAX=$FANMAX"
fi

trap "dbg '= EXIT trap'; $fanadjustfun $FANOFF" EXIT
trap "trap \"\" INT HUP QUIT TERM; exit 1" INT HUP QUIT TERM
trap "dbg '= Received SIGUSR1'; $fanadjustfun $FANMIN; lvl_curr=0" USR1

while [ 1 -eq 1 ]; do
   $classifyfun
   dbg "- NEWFAN=$NEWFAN,NEWLVL=$NEWLVL,SLEEPDUR=$SLEEPDUR,\
lvl_curr=$lvl_curr,lvl_reduxone=$lvl_reduxone"

   i=
   if [ $NEWLVL -eq $lvl_curr ]; then
      lvl_reduxone=0
   elif [ $NEWLVL -gt $lvl_curr ]; then
      dbg "+ increasing fan min: $NEWFAN"
      i=1
   elif [ $NEWLVL -lt $lvl_curr ]; then
      i=$(($lvl_curr - 2))
      if [ $i -ge $NEWLVL ]; then
         dbg "+ decreasing fan min: $NEWFAN"
         i=1
      else
         i=
         lvl_reduxone=$(($lvl_reduxone + 1))
         if [ $REDUXONEOK -ne 0 ]; then
            if [ $lvl_reduxone -ge 10 ] && $reduxoneokfun; then
               dbg "+ reduxone limit, decreasing fan min: $NEWFAN"
               i=1
            fi
         fi
      fi
   fi

   if [ -n "$i" ]; then
      $fanadjustfun $NEWFAN
      lvl_curr=$NEWLVL lvl_reduxone=0
   fi
   # The way the shell handles signals is complicated, only mksh was able
   # to always honour signals regardless of what.  bash(1) documents the
   # following approach to always work, and that seems to be portable behaviour
   sleep $SLEEPDUR &
   wait
done

# s-sh-mode
