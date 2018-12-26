#!/bin/sh -
#@ Create BTRFS filesystem snapshots, send them to a ball, trim them down.
#@
#@ Synopsis: btrfs-snapshot.sh create|trim|setmounts
#@ Synopsis: btrfs-snapshot.sh receive [:BALL:]
#@
#@ This script assumes a BTRFS master volume under which some subvolumes exist
#@ as mount points, and a snapshots/ at the first level under which all those
#@ subvolumes are mirrored.  Otherwise the_worker() must be adjusted.
#@
#@ - the_worker() drives the logic, and may become adjusted, if simply
#@   setting other values for $THEVOL, $DIRS and $ACCUDIR does not suffice.
#@   (Maybe $UNPRIVU and $UNPRIVG may need a hand, too.)
#@
#@ - "create" creates some BTRFS snapshots,
#@ - then sends the (differences to the last) snaphot to $ACCUDIR/btrfs-snaps/
#@   (which has been created in create_setup(), and which is to be removed via
#@   trap by the_worker(), at least unless after create_ball()!), then
#@ - creates a(n optionally zstd(1) compressed) tarball of these sent streams
#@   of differences (the possibly empty $ACCUDIR/btrfs-snaps/) within $ACCUDIR.
#@
#@ - "receive" receives one or multiple $BALLS, which must have been created
#@   by "create", and merges them in snapshots/.
#@
#@ - "trim" deletes all but the last snaphost of each folder under snapshots/.
#@
#@ - "setmounts" throws away the $DIRS subvolumes, and recreates them from the
#@   latest corresponding entry from snapshots/.
#
# 2018 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
# Public Domain

# Top BTRFS volume..
THEVOL=/media/btrfs-master

# and the mount points within; we cd(1) to $THEVOL, these need to be relative.
DIRS='home x/doc x/m x/os x/p x/src var/cache/apk'

# ACCUDIR: where everything is stored, including the final target
ACCUDIR=/media/btrfs-master

# Shall the snapshot ball be compressed (non-empty)
DOZSTD=

# When receiving, we unpack the ball(s) under unprivileged accounts via su(1)
UNPRIVU=guest UNPRIVG=users

# Non-empty and we will not act().
DEBUG=

## 8< >8

# Will be set by "receive"
BALLS=

the_worker() { # Will run in subshell!
   echo '= Mounting '$THEVOL
   if cd && mount "$THEVOL"; then :; else
      echo 'Cannot mount '$THEVOL
      exit 1
   fi
   trap "cd; umount \"$THEVOL\"" EXIT
   cd "$THEVOL" || {
      echo 'Cannot cd to '$THEVOL
      exit 1
   }

   echo '= Checking mirrors for '$DIRS
   for d in $DIRS; do
      check_mirror "$d"
   done

   if [ $1 = create ]; then
      echo '= Setting up ball target mirrors for '$DIRS
      create_setup
      trap "cd; rm -rf \"$ACCUDIR\"/btrfs-snaps; umount \"$THEVOL\"" EXIT
      for d in $DIRS; do
         create_mirror "$d"
      done

      echo '= Creating snapshots for '$DIRS
      for d in $DIRS; do
         create_one "$d"
      done

      echo '= Sending snapshots and creating ball in '$ACCUDIR
      for d in $DIRS; do
         create_send "$d"
      done

      create_ball
      trap "cd; umount \"$THEVOL\"" EXIT
   elif [ $1 = receive ]; then
      echo '= Setting up ball receive environment'
      receive_setup
      trap "cd; rm -rf \"$ACCUDIR\"/btrfs-snaps; umount \"$THEVOL\"" EXIT

      echo '= Expanding ball(s) '$BALLS
      receive_expand

      echo '= Receiving snapshots from '$ACCUDIR'/btrfs-snaps'
      for d in $DIRS; do
         receive_one "$d"
      done
      act rm -rf "$ACCUDIR"/btrfs-snaps
      trap "cd; umount \"$THEVOL\"" EXIT

   elif [ $1 = trim ]; then
      echo '= Trimming snapshots for '$DIRS
      for d in $DIRS; do
         trim_one "$d"
      done
   elif [ $1 = setmounts ]; then
      echo '= Setting mount points '$DIRS' to newest snapshots'
      for d in $DIRS; do
         setmount_one "$d"
      done
   fi

   echo '= Unmounting '$THEVOL
   if cd && umount "$THEVOL"; then :; else
      echo '== Failed to umount '$THEVOL
   fi
   trap "" EXIT
   echo '= Done'
}

## 8< ----- >8

act() {
   if [ -n "$DEBUG" ]; then
      echo eval "$@"
      return
   fi
   eval "$@"
   if [ $? -ne 0 ]; then
      echo 'PANIC: '$*
      exit 1
   fi
}

check_mirror() {
   if [ -d "$1" ] && [ -d snapshots/"$1" ]; then :; else
      echo 'PANIC: cannot handle '$1
      exit 1
   fi
}

create_setup() {
   now=`date +%Y%m%dT%H%M%S`
   act mkdir "$ACCUDIR"/btrfs-snaps
}

create_mirror() {
   act mkdir -p "$ACCUDIR"/btrfs-snaps/"$1"
}

create_one() {
   echo '== Creating snapshot: '$1' -> snapshots/'$1'/'$now
   act btrfs subvolume snapshot -r "$1" snapshots/"$1"/"$now"
}

create_send() {
   (
   mydir=$1
   cd snapshots/"$mydir" || exit 11
   i=`find . -maxdepth 1 -type d -not -path . | wc -l`
   if [ $i -eq 0 ]; then
      echo '== No snapshots to send in snapshots/'$mydir
      return
   fi

   if [ $i -eq 1 ]; then
      set -- `find . -maxdepth 1 -type d -not -path .`
      this=`basename "$1"`
      target="$mydir"/"$this"
      echo '== '$mydir': without parent to '$ACCUDIR'/btrfs-snaps/'$target
   else
      set -- `find . -maxdepth 1 -type d -not -path . | sort | tail -n 2`
      parent=`basename "$1"` this=`basename "$2"`
      target="$mydir"/"$this"
      echo '== '$mydir': with parent '$parent''\
'to '$ACCUDIR'/btrfs-snaps/'$target
      parent=' -p '"$parent"
   fi
   if command -v chattr >/dev/null 2>&1; then
      act touch "$ACCUDIR"/btrfs-snaps/"$target"
      act chattr +C "$ACCUDIR"/btrfs-snaps/"$target"
   fi
   act btrfs send $parent "$this" ">" "$ACCUDIR"/btrfs-snaps/"$target"
   ) || exit $?
}

create_ball() {
   (
   act cd "$ACCUDIR"
   ext=tar
   [ -n "$DOZSTD" ] && ext=${ext}.zst
   echo '== In '"$ACCUDIR"', creating ball btrfs-snaps_'${now}.${ext}
   if command -v chattr >/dev/null 2>&1; then
      act touch btrfs-snaps_$now.${ext}
      act chattr +C btrfs-snaps_$now.${ext}
   fi
   if [ -n "$DOZSTD" ]; then
      act tar -c -f - btrfs-snaps "|" \
         zstd -zc -T0 -19 ">" btrfs-snaps_$now.${ext}
   else
      act tar -c -f - btrfs-snaps ">" btrfs-snaps_$now.${ext}
   fi
   act rm -rf btrfs-snaps
   ) || exit $?
}

receive_setup() {
   for f in $BALLS; do
      if [ -f "$f" ]; then :; else
         echo 'No such ball to receive: '$f
         exit 1
      fi
   done
   act mkdir "$ACCUDIR"/btrfs-snaps
}

receive_expand() {
   (
   act cd "$ACCUDIR"/btrfs-snaps
   for f in $BALLS; do
      act chown ${UNPRIVU}:${UNPRIVG} .
      if [ "$f" != "${f%.zst}" ]; then
         act su -s /bin/sh $UNPRIVU -c '"zstd -dc < "\"'"$f"'\"" | tar -xf -"'
      else
         act su -s /bin/sh $UNPRIVU -c '"< "\"'"$f"'\"" tar -xf -"'
      fi
   done
   ) || exit $?
}

receive_one() {
   (
   mydir=$1
   cd snapshots/"$mydir" || exit 11
   find "$ACCUDIR"/btrfs-snaps/btrfs-snaps/"$mydir" -type f -print | sort |
   while read f; do
      echo '== '$mydir': receiving snapshot: '$f
      act btrfs receive . "<" $f
   done
   ) || exit $?
}

trim_one() {
   (
   mydir=$1
   cd snapshots/"$mydir" || exit 11
   i=`find . -maxdepth 1 -type d -not -path . | wc -l`
   if [ $i -le 1 ]; then
      echo '== No snapshots to trim in snapshots/'$mydir
      return
   fi

   echo '== Trimming snapshots in snapshots/'$mydir
   tail=`find . -maxdepth 1 -type d -not -path . | sort | tail -n 1`
   find . -maxdepth 1 -type d -not -path . -not -path "$tail" -print |
   while read d; do
      echo '=== Deleting '$d
      act btrfs subvolume delete "$d"
   done
   ) || exit $?
}

setmount_one() {
   (
   mydir=$1
   cd snapshots/"$mydir" || exit 11
   i=`find . -maxdepth 1 -type d -not -path . | wc -l`
   if [ $i -eq 0 ]; then
      echo '== No mount point to set from snapshots/'$mydir
      return
   fi

   tail=`find . -maxdepth 1 -type d -not -path . | sort | tail -n 1`
   echo '== Setting mount point of '$mydir' to '$tail
   if < /etc/mtab grep -q ' /'"$mydir"' btrfs'; then
      act umount -f /"$mydir"
   fi
   act btrfs subvolume delete "$THEVOL/$mydir"
   act btrfs subvolume snapshot "$tail" "$THEVOL/$mydir"
   act mount /"$mydir"
   ) || exit $?
}

mytee() {
   while read l; do
      echo "$l"
      echo >&2 "$l"
   done
}

syno() {
   echo 'Synopsis: btrfs-snapshot.sh create|trim|setmounts'
   echo 'Synopsis: btrfs-snapshot.sh receive [:BALL:]'
   exit $1
}

cmd=$1
if [ "$cmd" = receive ]; then
   shift
   BALLS="$@"
else
   [ $# -ne 1 ] && syno 1
   [ "$cmd" = help ] && syno 0
   [ "$cmd" != create ] && [ "$cmd" != trim ] && [ "$cmd" != setmounts ] &&
      syno 1
fi

( the_worker "$cmd" ) 2>&1 | mytee | mail -s 'BTRFS snapshot management' root

# s-sh-mode
