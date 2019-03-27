#!/bin/sh -
#@ Adaptive fancontrol script (successor of fancontrol.sh).
#@ - Set $MODEL below, and use a start script like this OpenRC one:
#@   start() {
#@   	ebegin "Starting fancontrol"
#@   	start-stop-daemon --start --background --nicelevel -10 \
#@   		--make-pidfile --pidfile ${PID} \
#@   		--exec /root/fan-adaptive.sh -- ${CONFIG}
#@   	eend ${?}
#@   }
#@   restart() {
#@   	ebegin "Restarting fancontrol"
#@   	start-stop-daemon --signal USR2 --pidfile ${PID}
#@   	eend ${?}
#@   }
#@   stop() {
#@   	ebegin "Stopping fancontrol"
#@   	start-stop-daemon --stop --pidfile ${PID}
#@   	eend ${?}
#@   }
#@ - USR1 toggles debug flag (log to $DBGLOG below).
#@ - USR2 turns off fans and performs a complete reinit.
#@ - INT/HUP/QUIT/TERM cause exit, "turning off" fan.
#@ TODO If the logic would now that the model merges multiple
#@ TODO datasets to one fan, we could avoid useless actions.
#@ TODO When calculating sleeps, adaptions etc. we should pay
#@ TODO attention to the overall temperature percentage.
#
# 2018 - 2019 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
# Public Domain

# Predefined models; see MACBOOK_AIR_2011 set for an example.
# SIM simulates interactively, for testing only.
MODEL=SIM
MODEL=MACBOOK_AIR_2011

# Noisy (in $DBGLOG), can be toggled at runtime via SIGUSR1.
DEBUG=
DBGLOG=/tmp/fan-adaptive.log

# Set to non-empty if shell truly supports $(< ) (instead of cat(1))?
FASTCAT=

## MODELs

# Models need to provide three functions, where "MODEL" is the model name:
# init_MODEL(), status_MODEL() and adjust_MODEL().
# MACBOOK_AIR_2011 is a good template, and almost generic.  Unfortunately Linux
# does not provide generic accessors, so adjustments are due.
#
# In general we work on $fc_no datasets.  A dataset consists of the constant
# members $fc_temp_min_NO and $fc_temp_max_NO.
# All these have to be initialized by init_MODEL() when called with $1=0.
#
# The temperature range min-max is subdivided in $fc_level_no_NO levels for
# each dataset, then init_MODEL() is called again with $1=1.  It could for
# example use this opportunity to subdivide the available fan rotation speeds
# for $fc_level_no_NO sublevels (for each dataset).
#
# A dataset also contains the dynamic member $fc_temp_curr_NO, which has to
# be set by status_MODEL().
#
# adjust_MODEL() will be called whenever any of the datasets entered
# a different level.  If $fc_level_new_NO is 0 then fans shall be turned off,
# otherwise appropriate steps have to be taken.  adjust_MODEL() has to update
# $fc_level_curr_NO to $fc_level_new_NO once the work is done (only).
#
# init_MODEL() also needs to set $fc_sleep_min and $fc_sleep_max, used to
# decide how much we can spread our status_MODEL() interval.  The used sleep
# is dynamically chosen in between MIN and MAX (as $fc_sleep_curr).
#
# The state machine also tracks:
# - $fc_temp_percent: the maximum temperature percentage of all datasets.
#   This is used to calculate the next sleep time.
#   The value of the former status round is in $fc_temp_percent_old.
# - $fc_level_max: number of levels in dataset with highest value.

# SIM, the test simulator

init_SIM() {
   if [ $1 -eq 0 ]; then
      printf '= init_SIM(): number of datasets: '
      read fc_no
      printf ' > sleep: min. max.: '
      read fc_sleep_min fc_sleep_max
      i=1
      while [ $i -le $fc_no ]; do
         printf ' > Dataset '$i': temp-min temp-max: '
         eval read fc_temp_min_$i fc_temp_max_$i
         i=$((i + 1))
      done
   fi
}

status_SIM() {
   printf '= status_SIM():\n'
   i=1
   while [ $i -le $fc_no ]; do
      printf ' > Dataset '$i': temp-curr: '
      eval read fc_temp_curr_$i
      i=$((i + 1))
   done
}

adjust_SIM() {
   printf '= adjust_SIM():\n'
   i=1
   while [ $i -le $fc_no ]; do
      eval j=\$fc_level_curr_$i k=\$fc_level_new_$i \
      printf ' - Dataset '$i': level '$j' <-> '$k'\n'
      eval fc_level_curr_$i=$k
      i=$((i + 1))
   done
}

# MACBOOK_AIR_2011

init_MACBOOK_AIR_2011() {
   if [ $1 -eq 0 ]; then
      fc_no=3 fc_sleep_min=10 fc_sleep_max=40 \
         mac_maxlvl_old=0 mac_fanspeed=0

      i=
      for d in /sys/class/hwmon/hwmon*; do
         if [ -f $d/device/fan1_input ]; then
            i=$d
            break
         fi
      done
      if [ -z "$i" ]; then
         echo >&2 '! MACBOOK_AIR_2011: no fan in /sys/class/hwmon/?'
         exit 1
      fi
      mac_fan_control=$i/device/fan1_min
      mac_fan_min=2000 #`cat $mac_fan_control`
      mac_fan_max=`cat $i/device/fan1_max`

      i=
      for d in /sys/class/hwmon/hwmon*; do
         if [ -f $d/temp1_crit_hyst ] && [ -f $d/temp1_input ]; then
            i=$d
            break
         fi
      done
      if [ -z "$i" ]; then
         echo >&2 '! MACBOOK_AIR_2011: cannot find GPU in /sys/class/hwmon/?'
         exit 1
      fi
      mac_input_1=$i/temp1_input
      fc_temp_max_1=$((`cat $i/temp1_max`))
         fc_temp_min_1=$((fc_temp_max_1 - (40 * (fc_temp_max_1 / 100)) ))
         fc_temp_min_1=$((fc_temp_min_1 / 1000))
         fc_temp_max_1=$((fc_temp_max_1 - (15 * (fc_temp_max_1 / 100)) ))
         fc_temp_max_1=$((fc_temp_max_1 / 1000))

      i=
      for d in /sys/class/hwmon/hwmon*; do
         if [ -f $d/temp2_input ] && [ -f $d/temp3_input ]; then
            i=$d
            break
         fi
      done
      if [ -z "$i" ]; then
         echo >&2 '! MACBOOK_AIR_2011: cannot find CPUs in /sys/class/hwmon/?'
         exit 1
      fi
      mac_input_2=$i/temp2_input
         fc_temp_max_2=$((`cat $i/temp2_max`))
            fc_temp_min_2=$((fc_temp_max_2 - (52 * (fc_temp_max_2 / 100)) ))
            fc_temp_min_2=$((fc_temp_min_2 / 1000))
            fc_temp_max_2=$((fc_temp_max_2 - (25 * (fc_temp_max_2 / 100)) ))
            fc_temp_max_2=$((fc_temp_max_2 / 1000))
      mac_input_3=$i/temp3_input
         fc_temp_max_3=$((`cat $i/temp3_max`))
            fc_temp_min_3=$((fc_temp_max_3 - (52 * (fc_temp_max_3 / 100)) ))
            fc_temp_min_3=$((fc_temp_min_3 / 1000))
            fc_temp_max_3=$((fc_temp_max_3 - (25 * (fc_temp_max_3 / 100)) ))
            fc_temp_max_3=$((fc_temp_max_3 / 1000))

      dbg ' = MACBOOK_AIR_2011: fan min='$mac_fan_min', max='$mac_fan_max
   fi
}

status_MACBOOK_AIR_2011() {
   i=1
   while [ $i -le $fc_no ]; do
      eval j=\$mac_input_$i
      if [ -n "$FASTCAT" ]; then
         k=$(< $j)
      else
         k=`cat $j`
      fi
      k=$((k / 1000))
      eval fc_temp_curr_$i=$k
      i=$((i + 1))
   done
}

adjust_MACBOOK_AIR_2011() {
   # Only has one fan, so use maximum
   i=1
   lvlmax=0
   while [ $i -le $fc_no ]; do
      eval j=\$fc_level_curr_$i k=\$fc_level_new_$i
      [ $k -gt $lvlmax ] && lvlmax=$k
      eval fc_level_curr_$i=$k
      i=$((i + 1))
   done

   adj=
   if [ $lvlmax -eq 0 ]; then
      adj=0
   elif [ $lvlmax -ne $mac_maxlvl_old ]; then
      i=$lvlmax
      if [ $i -gt $(( fc_level_max / 2 )) ]; then
         i=$((i + 1))
      elif [ $i -gt 1 ]; then
         i=$((i - 1))
      fi
      adj=$(( (((mac_fan_max - mac_fan_min) / fc_level_max) * i) +mac_fan_min))
      adj=$(( (adj - (adj % 100)) ))
      [ $adj -gt $mac_fan_max ] && adj=$mac_fan_max
      [ $adj -eq $mac_fanspeed ] && adj=
   fi

   if [ -n "$adj" ]; then
      dbg ' = MACBOOK_AIR_2011: fan to '$adj
      mac_fanspeed=$adj
      [ $MODEL != SIM ] && echo $adj > $mac_fan_control
   else
      dbg ' = MACBOOK_AIR_2011: equal fan speed would result, not adjusting'
   fi

   mac_maxlvl_old=$lvlmax
}

##  --  >8  - -  8<  --  ##

dbg() {
   if [ -n "$DEBUG" ]; then
      echo "$*" >> $DBGLOG
   fi
}

init() {
   dbg '+ Startup: init of model '$MODEL
   eval init_$MODEL 0

   fc_level_max=0
   i=1
   while [ $i -le $fc_no ]; do
      eval fc_level_no_$i=0 \
         fc_level_curr_$i=0 fc_level_new_$i=0 \
         fc_adjust_$i=0 fc_trend_$i=0 fc_temp_old_$i=0 \
         j=\$fc_temp_min_$i k=\$fc_temp_max_$i

      # We need some tolerance in the temperature range of levels in order
      # to avoid switching them too often
      l=$((k - j))
      m=100
      while [ $((l / m)) -lt 2 ] && [ $m -gt 10 ]; do
         m=$((m - 1))
      done
      if [ $m -ge 20 ]; then
         while [ $((l / m)) -lt 3 ] && [ $m -gt 10 ]; do
            m=$((m - 1))
         done
      fi
      eval fc_level_no_$i=$m
      [ $m -gt $fc_level_max ] && fc_level_max=$m
      i=$((i + 1))
   done

   fc_temp_percent=0 fc_temp_percent_old=0

   eval init_$MODEL 1

   if [ -n "$DEBUG" ]; then
      dbg '+ Datasets: '$fc_no
      dbg ' - Sleep: min. '$fc_sleep_min', max. '$fc_sleep_max' seconds'
      i=1
      while [ $i -le $fc_no ]; do
         eval j=\$fc_temp_min_$i k=\$fc_temp_max_$i l=\$fc_level_no_$i
         dbg ' - Dataset '$i' temp. '$j' to '$k', subdivided in '$l' levels'
         i=$((i + 1))
      done
   fi

   fc_first_time=1
}

status() {
   dbg '+ Status update'

   eval status_$MODEL

   eval fc_temp_percent_old=\$fc_temp_percent
   need_adjust=0 fc_temp_percent=0

   i=1
   while [ $i -le $fc_no ]; do
      # Calculate temp level
      eval curr=\$fc_temp_curr_$i old=\$fc_temp_old_$i \
         max=\$fc_temp_max_$i min=\$fc_temp_min_$i \
         olvl=\$fc_level_curr_$i \
         adj=\$fc_adjust_$i trend=\$fc_trend_$i

      if [ $curr -ge $max ]; then
         dbg ' ! Dataset '$i' at maximum'
         eval nlvl=\$fc_level_no_$i
         xnlvl=$nlvl fc_temp_percent=100 adj=0 trend=0
      elif [ $curr -le $min ]; then
         dbg ' ! Dataset '$i' at minimum'
         nlvl=0 xnlvl=0 adj=0 trend=0
      else
         nlvl=$(( ((curr - min) * 1000) / (((max - min) * 1000) / 100) ))
         [ $nlvl -gt $fc_temp_percent ] && fc_temp_percent=$nlvl
         eval lno=\$fc_level_no_$i
         nlvl=$(( (nlvl * lno) / 100 ))
         xnlvl=$nlvl

         # Unchanged?
         if [ $fc_first_time -eq 1 ] || [ $olvl -eq $nlvl ]; then
            adj=0 trend=0
         # Heated?  Possibly apply adaptive changes
         elif [ $olvl -lt $nlvl ]; then
            adj=0
            if [ $trend -lt 0 ]; then
               trend=0
            else
               trend=$((trend + 1))
               if [ $trend -ge 3 ]; then
                  dbg ' . Dataset '$i' heats 3rd+ time in row, adaption'
                  trend=0
                  adj=$((adj + 1))
               fi
            fi

            j=$((nlvl - olvl))
            if [ $j -ge 3 ]; then
               dbg ' . Dataset '$i' heated up 3+ levels, adaption'
               adj=$((adj + 2))
            elif [ $j -ge 2 ]; then
               dbg ' . Dataset '$i' heated up 2+ levels, adaption'
               adj=$((adj + 1))
            fi

            nlvl=$((nlvl + adj))
            [ $nlvl -gt $lno ] && nlvl=$lno
         # Cooled down; but do not be too eager in lowering level
         elif [ $adj -gt 0 ]; then
            adj=$((adj - 1)) trend=0 nlvl=$olvl
         elif [ $trend -gt 0 ]; then
            trend=0 nlvl=$olvl
         else
            trend=$((trend - 1))
            # Step down anyway if wanted quite often
            if [ $trend -le -5 ]; then
               trend=0
            # Or if temperature fell a lot
            elif [ $((olvl - nlvl)) -gt $((lno / 4)) ]; then
               dbg ' . Dataset '$i' cooled down a lot, adaption'
               trend=0
               nlvl=$((nlvl + 1))
            else
               nlvl=$olvl
            fi
         fi
      fi

      dbg ' - Dataset '$i' temp '$old'->'$curr' of '$min'/'$max'; level '\
$olvl'->'$nlvl'('$xnlvl'; trend '$trend', adjust '$adj')'
      eval fc_level_new_$i=$nlvl fc_adjust_$i=$adj fc_trend_$i=$trend \
         fc_temp_old_$i=$curr
      [ $olvl -ne $nlvl ] && need_adjust=1
      i=$((i + 1))
   done

   if [ $fc_temp_percent -ge 80 ]; then
      fc_sleep_curr=$fc_sleep_min
   elif [ $fc_temp_percent -le 25 ]; then
      fc_sleep_curr=$fc_sleep_max
   else
      fc_sleep_curr=$(( fc_sleep_max - \
            ((fc_temp_percent * (fc_sleep_max - fc_sleep_min)) / 100) ))
   fi

   dbg ' = fc_temp_percent='$fc_temp_percent\
', fc_sleep_curr='$fc_sleep_curr', adjust='$need_adjust
   fc_first_time=0
   [ $need_adjust -ne 0 ] && eval adjust_$MODEL
}

fanoff() {
   dbg '+ Fan(s) off'
   i=1
   while [ $i -le $fc_no ]; do
      eval fc_level_new_$i=0 fc_trend_$i=0
      i=$((i + 1))
   done

   eval adjust_$MODEL
   fc_first_time=1
}

if ( echo $(( 10 - 10 / 10 )) ) >/dev/null 2>&1; then :; else
   echo >&2 'Shell cannot do arithmetic, bailing out'
   exit 1
fi

# Problem: busybox sh(1) succeeds the first but it is a fake
if ( $(< /dev/null) ) >/dev/null 2>&1 &&
      [ -f /etc/fstab ] && command -v cksum >/dev/null 2>&1 &&
      [ "`{ i=\`cat /etc/fstab\`; echo $i; } | cksum`" = \
         "`{ i=$(< /etc/fstab); echo $i; } | cksum`" ]; then
   dbg '= Enabling FASTCAT for this shell'
   FASTCAT=yes
fi

init

trap 'dbg "= EXIT trap"; fanoff' EXIT
trap 'trap "" INT HUP QUIT TERM; exit 1' INT HUP QUIT TERM
trap 'dbg "= Received SIGUSR1"; [ -z "$DEBUG" ] && DEBUG=1 || DEBUG=' USR1
trap 'dbg "= Received SIGUSR2, fanoff, reinit"; fanoff; init' USR2

while [ 1 -eq 1 ]; do
   status

   # The way the shell handles signals is complicated, only mksh was able
   # to always honour signals regardless of what.  bash(1) documents the
   # following approach to always work, and that seems to be portable behaviour
   [ $MODEL = SIM ] && continue
   sleep $fc_sleep_curr &
   wait
done

# s-sh-mode
