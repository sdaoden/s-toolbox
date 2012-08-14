#!/bin/sh -
# real-periodic.sh: *real* periodic for *BSD that ensures that the
# daily/weekly/monthly maintenance stuff is executed, even if your laptop
# is running only one hour a day.
# Invoke this once per hour in the roots crontab and disable the usual periodic
# stuff of your system instead.
# I.e., on my old FreeBSD 5.3 box the crontab entry is:
#
#   # Perform daily/weekly/monthly maintenance.
#   15  * * * * root    /usr/bin/nice -n 15 real-periodic
#   #1  3 * * * root    periodic daily
#   #15 4 * * 6 root    periodic weekly
#   #30 5 1 * * root    periodic monthly
#
# Public Domain.

# Set to a path where you want the timestamp info to be stored
# Leave empty to choose a OS-dependent default location
DB_FILE=

#  --  >8  --  8<  --  #
_DB_FILE=/var/cron/real-periodic.stamp

case `/usr/bin/uname -s` in
FreeBSD)
   _DB_FILE=/var/db/real-periodic.stamp
   MONTHLY='/usr/sbin/periodic monthly'
   WEEKLY='/usr/sbin/periodic weekly'
   DAILY='/usr/sbin/periodic daily'
   ;;
NetBSD)
   MONTHLY='/bin/sh /etc/monthly 2>&1 | tee /var/log/monthly.out | sendmail -t'
   WEEKLY='/bin/sh /etc/weekly 2>&1 | tee /var/log/weekly.out | sendmail -t'
   DAILY='/bin/sh /etc/daily 2>&1 | tee /var/log/daily.out | sendmail -t'
   ;;
OpenBSD)
   MONTHLY='/bin/sh /etc/monthly'
   WEEKLY='/bin/sh /etc/weekly'
   DAILY='/bin/sh /etc/daily'
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

[ -z "${DB_FILE}" ] && DB_FILE="${_DB_FILE}"

# Current YearDay
yd=`/bin/date +%j`
[ $? -ne 0 ] && {
   echo 'Unable to execute /bin/date +%j.  Bailing out.'
   exit 1
}
# Strip leading zeroes
yd=`echo ${yd} | sed 's/^0*//'`

# Last MonthWeekDay invocations
mwd='-42 -42 -42'
[ -s "${DB_FILE}" ] && mwd=`cat "${DB_FILE}"`
set -- ${mwd}
lmonth=$1 lweek=$2 lday=$3

# Check wether the year has changed
if [ ${yd} -lt ${lmonth} ] || [ ${yd} -lt ${lweek} ] || \
      [ ${yd} -lt ${lday} ]; then
   echo 'I do think the year has turned over.  Restarting!'
   lmonth=-42 lweek=-42 lday=-42
fi

i=`expr ${yd} - 30`
[ ${i} -ge ${lmonth} ] && {
   echo 'Invoking monthly periodical things.'
   lmonth=${yd}
   eval ${MONTHLY}
}

i=`expr ${yd} - 7`
[ ${i} -ge ${lweek} ] && {
   echo 'Invoking weekly periodical things.'
   lweek=${yd}
   eval ${WEEKLY}
}

[ ${yd} -ne ${lday} ] && {
   echo 'Invoking daily periodical things.'
   lday=${yd}
   eval ${DAILY}
}

echo "${lmonth} ${lweek} ${lday}" > "${DB_FILE}"
/bin/chmod 0644 "${DB_FILE}"

exit 0
# vim:set fenc=utf-8 syntax=sh ts=8 sts=3 sw=3 et tw=79:
