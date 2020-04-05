#!/bin/sh -
#@ Create BTRFS filesystem snapshots, send them to a ball, trim them down.
#@ The configuration is read from /root/$HOSTNAME/btrfs-snapshot.
#@ TODO (Instead) We should offer command line arguments, to a config file
#@ TODO and/or to set the vars directly: THEVOL,DIRS,ACCUDIR,DOZST,UNPRIV*.
#@
#@ Synopsis: btrfs-snapshot.sh create|trim|setmounts
#@ Synopsis: btrfs-snapshot.sh create-ball
#@ Synopsis: btrfs-snapshot.sh receive-ball [:BALL:]
#@ Synopsis: btrfs-snapshot.sh clone-to-cwd|sync-to-cwd
#@
#@ This script assumes a BTRFS master volume under which some subvolumes exist
#@ as mount points, and a snapshots/ at the first level under which all those
#@ subvolumes are mirrored.  Otherwise the_worker() must be adjusted.
#@
#@ - "create" creates some BTRFS snapshots,
#@
#@ - "trim" deletes all but the last snaphost of each folder under snapshots/.
#@
#@ - "setmounts" throws away the $DIRS subvolumes, and recreates them from the
#@   latest corresponding entry from snapshots/.
#@
#@ - "create-ball" sends the (differences to the last) snaphot to
#@   $ACCUDIR/btrfs-snaps/, creates a(n optionally zstd(1) compressed) tarball
#@   of these sent streams of differences (the possibly empty
#@   $ACCUDIR/btrfs-snaps/) within $ACCUDIR.
#@
#@ - "receive-ball" receives one or multiple $BALLS, which must have been
#@   created by "create-ball", and merges them in snapshots/.
#@   The ball(s) is/are expanded in the root of the target first!
#@   A ball can also be split(1)ted up into subfiles, for example to store it
#@   on a VFAT partition: if a BALL is a directory we will join all files via
#@   a cat(1) * glob, and expand the output behind a pipe instead.
#@      i=${1%%.*}
#@      mkdir "$i".split || exit 7
#@      cd "$i".split
#@      < "$1" split -a 4 -b 2000000000 -d - || exit 8
#@      cd ..
#@    ->
#@      btrfs-snapshot.sh receive-ball "$i".split
#@
#@ - "clone-to-cwd" and "sync-to-cwd" need one existing snapshot (series),
#@   and will clone all the latest snapshots to the CWD.
#@   clone-to-cwd creates the necessary hierarchy first, sync-to-cwd skips
#@   non-existing directories.
#@   Only the difference to the last snapshot which is present in both trees is
#@   synchronized: for the target this must be the last.
#@
#@ + the_worker() drives the logic, and may become adjusted, if simply
#@   setting other values for $THEVOL, $DIRS and $ACCUDIR does not suffice.
#@   (Maybe $UNPRIVU and $UNPRIVG may need a hand, too.)
#
# 2018 - 2020 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
# Public Domain

: ${HOSTNAME:=`hostname`}

if [ -f /root/${HOSTNAME}/btrfs-snapshot ]; then
   # Top BTRFS volume..
   #THEVOL=/media/btrfs-master

   # the mount points within; we cd(1) to $THEVOL, these need to be relative.
   #DIRS='home x/doc x/m x/m-mp4 x/os x/p x/src var/cache/apk'

   # ACCUDIR: where everything is stored, including the final target
   #ACCUDIR=/media/btrfs-master

   # Shall the snapshot ball be compressed (non-empty)
   #DOZSTD=

   # When receiving, we unpack ball(s) under unprivileged accounts via su(1)
   #UNPRIVU=guest UNPRIVG=guest

   . /root/${HOSTNAME}/btrfs-snapshot
else
   logger -s -t root/btrfs-snapshot.sh \
         -i "no config /root/${HOSTNAME}/btrfs-snapshot"
   exit 1
fi

# Non-empty and we will not act().
DEBUG=

## 8< >8

# Will be set by "receive-ball"
BALLS=

the_worker() { # Will run in subshell!
   if [ $1 = clone-to-cwd ] || [ $1 = sync-to-cwd ]; then
      CLONEDIR=`pwd`
   fi

   if grep -q -E ' '$THEVOL /etc/mtab; then
      echo '= '$THEVOL' is already mounted'
      UMOUNT=cd
   else
      echo '= Mounting '$THEVOL
      if cd && mount "$THEVOL"; then :; else
         echo 'Cannot mount '$THEVOL
         exit 1
      fi
      UMOUNT="cd && umount \"$THEVOL\""
      trap "$UMOUNT" EXIT
   fi

   cd "$THEVOL" || {
      echo 'Cannot cd to '$THEVOL
      exit 1
   }

   echo '= Checking mirrors for '$DIRS
   for d in $DIRS; do
      check_mirror "$d"
   done

   if [ $1 = create ]; then
      echo '= Creating snapshots for '$DIRS
      create_setup
      for d in $DIRS; do
         create_one "$d"
      done
   elif [ $1 = create-ball ]; then
      echo '= Setting up ball target mirrors for '$DIRS
      create_setup
      create_ball_setup
      trap "cd; rm -rf \"$ACCUDIR\"/btrfs-snaps; $UMOUNT" EXIT
      for d in $DIRS; do
         create_mirror "$d"
      done

      echo '= Sending snapshots and creating ball in '$ACCUDIR
      for d in $DIRS; do
         create_send "$d"
      done

      create_ball
      trap "$UMOUNT" EXIT
   elif [ $1 = receive-ball ]; then
      echo '= Setting up ball receive environment'
      receive_setup
      trap "cd; rm -rf \"$ACCUDIR\"/btrfs-snaps; $UMOUNT" EXIT

      echo '= Expanding ball(s) '$BALLS
      receive_expand

      echo '= Receiving snapshots from '$ACCUDIR'/btrfs-snaps'
      for d in $DIRS; do
         receive_one "$d"
      done
      act rm -rf "$ACCUDIR"/btrfs-snaps
      trap "$UMOUNT" EXIT
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
   elif [ $1 = clone-to-cwd ]; then
      echo '= Creating or updating a clone in '$CLONEDIR
      clone_to_cwd 1
   elif [ $1 = sync-to-cwd ]; then
      echo '= Synchronizing a clone in '$CLONEDIR
      clone_to_cwd 0
   fi

   if eval $UMOUNT; then :; else
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
}

create_ball_setup() {
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

   set -- `find . -maxdepth 1 -type d -not -path . | sort`
   if [ $# -eq 0 ]; then
      echo '== No snapshots to send in snapshots/'$mydir
      exit 0
   fi
   while [ $# -gt 2 ]; do
      shift
   done

   if [ $# -eq 1 ]; then
      parent=
      i='without parent'
      this=`basename "$1"`
   else
      parent=`basename "$1"`
      i='with parent '$parent
      parent=' -p '$parent
      this=`basename "$2"`
   fi
   target="$ACCUDIR"/btrfs-snaps/"$mydir"/"$this"
   echo '== '$mydir': '$i' to '$target

   if command -v chattr >/dev/null 2>&1; then
      act touch "$target"
      act chattr +C "$target"
   fi
   act btrfs send $parent "$this" ">" "$target"
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
   act chown -R ${UNPRIVU}:${UNPRIVG} .

   for f in $BALLS; do
      if [ "$f" != "${f%.zst}" ]; then
         act su -s /bin/sh $UNPRIVU -c '"zstd -dc < "\"'"$f"'\"" | tar -xf -"'
      elif [ -d "$f" ]; then
         act su -s /bin/sh $UNPRIVU -c '"cat "\"'"$f"'\"/*" | tar -xf -"'
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

   set -- `find . -maxdepth 1 -type d -not -path . | sort`
   if [ $# -le 1 ]; then
      echo '== No snapshots to trim in snapshots/'$mydir
      exit 0
   fi

   echo '== Trimming snapshots in snapshots/'$mydir
   while [ $# -gt 1 ]; do
      echo '=== Deleting '$1
      act btrfs subvolume delete "$1"
      shift
   done
   ) || exit $?
}

setmount_one() {
   (
   mydir=$1
   cd snapshots/"$mydir" || exit 11

   set -- `find . -maxdepth 1 -type d -not -path . | sort`
   if [ $# -eq 0 ]; then
      echo '== No mount point to set from snapshots/'$mydir
      exit 0
   fi
   while [ $# -gt 1 ]; do
      shift
   done

   echo '== Setting "mount point" of '$mydir' to '$1
   # Since $HOSTNAME can be anything when we operate on sticks or whatever
   mountpoint=
   if [ "$HOSTNAME" = "`hostname`" ] &&
         < /etc/fstab grep -q 'subvol=/'"$mydir"; then
      mountpoint=`</etc/fstab awk '
            BEGIN{regex="/'"$mydir"'"; gsub("/","\\\/", regex)}
            $4 ~ regex{print $2}
            '`
      if [ "$mountpoint" = '/' ]; then
         echo '=== Not un-/remounting the root partition!'
         mountpoint=
      else
         act umount -f $mountpoint
      fi
   fi

   [ -d "$THEVOL/$mydir" ] && act btrfs subvolume delete "$THEVOL/$mydir"
   act btrfs subvolume snapshot "$1" "$THEVOL/$mydir"

   if [ -n "$mountpoint" ]; then
      act mount $mountpoint
   fi
   ) || exit $?
}

clone_to_cwd() {
   if [ "$1" = 1 ]; then
      for d in $DIRS; do
         i=
         [ -d "$CLONEDIR/$d" ] || i="$i \"$CLONEDIR/$d\""
         [ -d "$CLONEDIR/snapshots/$d" ] || i="$i \"$CLONEDIR/snapshots/$d\""
         [ -n "$i" ] && act mkdir -p $i
      done
   fi

   deldirs=
   for d in $DIRS; do
      target="$CLONEDIR"/snapshots/"$d"
      if [ -d "$CLONEDIR/$d" ] && [ -d "$target" ]; then :; else
         [ -d "$CLONEDIR/$d" ] && deldirs="$deldirs \"$CLONEDIR/$d\""
         echo '== Skipping non-existing snapshots/'$d
         continue
      fi
      (
      act cd "$target"

      set -- `find . -maxdepth 1 -type d -not -path . | sort`
      while [ $# -gt 1 ]; do
         shift
      done
      lastsync=$1

      act cd "$THEVOL"/snapshots/"$d"

      set -- `find . -maxdepth 1 -type d -not -path . | sort`
      if [ $# -eq 0 ]; then
         echo '== No snapshot to clone in snapshots/'$d
         exit 0
      fi
      parentmsg= parent=
      while [ $# -gt 1 ]; do
         if [ "$1" = "$lastsync" ]; then
            parentmsg=' with parent '"$1"
            parent='-p '"$1"
         fi
         shift
      done

      if [ -n "$lastsync" ]; then
         if [ "$1" = "$lastsync" ]; then
            echo '== Yet has up-to-date snapshot: snapshots/'$d
            exit 0
         fi
         if [ -z "$parent" ]; then
            echo '== Found parental mismatch: '"$parentmsg"
            echo '== Please remove snapshots which cannot be based upon!'
            echo '== Rejecting synchronization for snapshots/'$d
            exit 1
         fi
      fi

      echo '== Synchronizing to '"$1$parentmsg"' from snapshots/'$d
      ( set -o pipefail ) >/dev/null 2>&1 && set -o pipefail
      act btrfs send $parent $1 '|' \
         '('cd "$CLONEDIR"/snapshots/"$d" '&&' btrfs receive .')'
      ) || exit $?
   done

   if [ -n "$deldirs" ]; then
      echo '== The following snapshots have no upstream: '$deldirs
   fi
}

mytee() {
   while read l; do
      echo "$l"
      echo >&2 "$l"
   done
}

syno() {
   echo 'Synopsis: btrfs-snapshot.sh create|trim|setmounts'
   echo 'Synopsis: btrfs-snapshot.sh create-ball'
   echo 'Synopsis: btrfs-snapshot.sh receive-ball [:BALL:]'
   echo 'Synopsis: btrfs-snapshot.sh clone-to-cwd|sync-to-cwd'
   exit $1
}

cmd=$1
if [ "$cmd" = receive-ball ]; then
   shift
   BALLS="$@"
else
   [ $# -ne 1 ] && syno 1
   case $cmd in
   help) syno 0;;
   create) ;; trim) ;; setmounts) ;;
   create-ball) ;; #receive-ball) ;;
   clone-to-cwd) ;; sync-to-cwd) ;;
   *) syno 1;;
   esac
fi

( the_worker "$cmd" ) 2>&1 |
   mytee |
   mail -s 'BTRFS snapshot management: '"$cmd ${DEBUG:+ (DEBUG MODE)}" root

# s-sh-mode
