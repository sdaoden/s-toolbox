#!/bin/sh
# real-periodic.sh: *real* periodic for FreeBSD and OpenBSD that ensures that
# the daily/weekly/monthly maintenance stuff is executed, even if your laptop
# is running only one hour a day.
# Invoke this once per hour in the roots crontab and disable the usual periodic
# stuff of your system instead.
# I.e., on my old FreeBSD 5.3 box the crontab entry is:
#
#	# Perform daily/weekly/monthly maintenance.
#	15	* * * *	root	/usr/bin/nice -n 15 real-periodic
#	#1	3 * * *	root	periodic daily
#	#15	4 * * 6	root	periodic weekly
#	#30	5 1 * *	root	periodic monthly
#
# Public Domain.

# Set to a path where you want the timestamp info to be stored
# Leave empty to choose a OS-dependent default location
DB_FILE=

#  --  >8  --  8<  --  #

case $(/usr/bin/uname -s) in
OpenBSD)
    _DB_FILE=/var/cron/real-periodic.stamp
    MONTHLY='/bin/sh /etc/monthly'
    WEEKLY='/bin/sh /etc/weekly'
    DAILY='/bin/sh /etc/daily'
    ;;
FreeBSD)
    _DB_FILE=/var/db/real-periodic.stamp
    MONTHLY='/usr/sbin/periodic monthly'
    WEEKLY='/usr/sbin/periodic weekly'
    DAILY='/usr/sbin/periodic daily'
    ;;
Darwin)
    echo 'Yes it probably would be better to use UNIX on Darwin.'
    echo 'But i am blinded by all the glitter..'
    exit 21
    ;;
*)
    echo 'Unsupported operating system'
    exit 42
    ;;
esac

[ x = x"$DB_FILE" ] && DB_FILE="$_DB_FILE"

# Current YearDay
yd=$(/bin/date +%j)
if [ $? -ne 0 ]; then
    echo 'Unable to execute /bin/date +%j.  Bailing out.'
    exit 1
fi
# Strip leading zeroes
yd=${yd#0*}
yd=${yd#0*}

# Last MonthWeekDay invocations
mwd='-42 -42 -42'
[ -s "$DB_FILE" ] && mwd=$(< "$DB_FILE")
lmonth=${mwd%% *}
    mwd=${mwd#* }
lweek=${mwd%% *}
    mwd=${mwd#* }
lday=${mwd%% *}
    mwd=${mwd#* }

# Check wether the year has changed
if [ $yd -lt $lmonth ] || [ $yd -lt $lweek ] || [ $yd -lt $lday ]; then
    echo 'I do think the year has turned over.  Restarting!'
    lmonth='-42'
    lweek='-42'
    lday='-42'
fi

i=$yd
i=$((i - 30))
if [ $i -ge $lmonth ]; then
    echo 'Invoking monthly periodical things.'
    lmonth=$yd
    eval $MONTHLY
fi

i=$yd
i=$((i - 7))
if [ $i -ge $lweek ]; then
    echo 'Invoking weekly periodical things.'
    lweek=$yd
    eval $WEEKLY
fi

if [ $yd -ne $lday ]; then
    echo 'Invoking daily periodical things.'
    lday=$yd
    eval $DAILY
fi

echo "$lmonth $lweek $lday" > "$DB_FILE"
/bin/chmod 0644 "$DB_FILE"

exit 0
# vim:set fenc=utf-8 filetype=sh syntax=sh ts=4 sts=4 sw=4 et tw=79:
