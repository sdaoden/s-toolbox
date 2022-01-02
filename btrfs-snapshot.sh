#!/bin/sh -
#@ Create BTRFS filesystem snapshots, send them to a ball, trim them down.
#@ The configuration is read from $BTRFS_SNAPSHOT, ./btrfs-snapshot, or
#@ otherwise /root/hosts/$HOSTNAME/btrfs-snapshot.  It must contain:
#@
#@   # Top BTRFS volume..
#@   THEVOL=/media/btrfs-master
#@
#@   # the mount points within; we cd(1) to $THEVOL, these need to be relative.
#@   DIRS='home x/doc x/m x/m-mp4 x/os x/p x/src var/cache/apk'
#@
#@   # ACCUDIR: where everything is stored, including the final target
#@   ACCUDIR=/media/btrfs-master
#@
#@   # If set, no real action is performed
#@   #DEBUG
#@
#@ TODO (Instead) We should offer command line arguments, to a config file
#@ TODO and/or to set the vars directly: THEVOL,DIRS,ACCUDIR.
#@
#@ Synopsis: btrfs-snapshot.sh create-dir-tree
#@ Synopsis: btrfs-snapshot.sh create|trim|setvols
#@ Synopsis: btrfs-snapshot.sh create-balls
#@ Synopsis: btrfs-snapshot.sh receive-balls [:BALL:]
#@ Synopsis: btrfs-snapshot.sh clone-to-cwd|sync-to-cwd
#@
#@ This script assumes a BTRFS master volume under which some subvolumes exist
#@ as mount points, and a snapshots/ at the first level under which all those
#@ subvolumes are mirrored.  Otherwise the_worker() must be adjusted.
#@
#@ - "create-dir-tree" creates all $DIRS and their snapshot mirrors,
#@   as necessary, in and under CWD.  It does not remove surplus directories.
#@   Any further synchronization can then be performed via
#@      cd WHEREVER && btrfs-snapshot.sh sync-to-cwd
#@
#@ - "create" creates snapshots/ of all $DIRS.
#@
#@ - "trim" deletes all but the last snaphost of each folder under snapshots/.
#@   It also removes anything (!) in .old/.
#@
#@ - "setvols" moves any existing $DIRS (subvolumes) to $THEVOL/.old/$now/
#@   (covered by "trim"), and recreates them from the latest corresponding
#@   entry within snapshots/.
#@
#@ - "create-balls" sends the (differences to the last, if any) snapshots into
#@   $ACCUDIR/.snap-ISODATE/ as zstd(1) compressed streams, split into files
#@   of 2 GB size at most.  You then move the entire $ACCUDIR/.snap-ISODATE
#@   directory tree somewhere else.  (Or you can create a tar archive of it,
#@   if the target filesystem can deal with very large files.)
#@
#@ - "receive-balls" receives one or multiple BALLS, which must have been
#@   created by "create-balls", and merges them in snapshots/.
#@   Ball must refer to a .snap-ISODATE super-directory, and the path must
#@   be absolute.  (If realpath(1) is available we use it though.)
#@   If the filename of a BALL is =, "trim" is executed.
#@
#@ - "clone-to-cwd" and "sync-to-cwd" need one existing snapshot (series),
#@   and will clone all the latest snapshots to the current-working-directory.
#@   clone-to-cwd creates the necessary hierarchy first, sync-to-cwd skips
#@   non-existing directories.
#@   Only the difference to the last snapshot which is present in both trees is
#@   synchronized: for the target this must be the last.
#@   Be aware that $DIRS etc. still corresponds to $HOSTNAME!
#@
#@ + the_worker() drives the logic, and may become adjusted, if simply
#@   setting other values for $THEVOL, $DIRS and $ACCUDIR does not suffice.
#
# 2019 - 2022 Steffen Nurpmeso <steffen@sdaoden.eu>.
# Public Domain

: ${HOSTNAME:=`uname -n`}

if [ -f "${BTRFS_SNAPSHOT}" ]; then
   . "${BTRFS_SNAPSHOT}"
elif [ -f ./btrfs-snapshot ]; then
   . ./btrfs-snapshot
elif [ -f /root/hosts/${HOSTNAME}/btrfs-snapshot ]; then
   . /root/hosts/${HOSTNAME}/btrfs-snapshot
else
   logger -s -t /root/bin/btrfs-snapshot.sh \
      "no config ./btrfs-snapshot, nor /root/hosts/${HOSTNAME}/btrfs-snapshot"
   exit 1
fi
: ${ZSTD_LEVEL:=-5}

# Non-empty and we will not act().
: ${DEBUG:=}

## >8 -- 8<

# Will be set by "receive-balls"
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
   i=
   [ $1 = create-dir-tree ] && i=y
   for d in $DIRS; do
      check_mirror "$d" "snapshots" "$i"
   done

   if [ $1 = create-dir-tree ]; then
      exit 0
   elif [ $1 = create ]; then
      echo '= Creating snapshots for '$DIRS
      create_setup
      for d in $DIRS; do
         create_one "$d"
      done
   elif [ $1 = create-balls ]; then
      create_setup
      echo '= Creating balls in '$ACCUDIR/.snap-$now

      act mkdir "$ACCUDIR"/.snap-$now
      trap "cd; rm -rf \"$ACCUDIR\"/.snap-$now; $UMOUNT" EXIT

      for d in $DIRS; do
         create_ball "$d"
      done

      trap "$UMOUNT" EXIT
   elif [ $1 = receive-balls ]; then
      echo '= Working balls'
      for b in $BALLS; do
         echo '== Receiving ball '$b
         for d in $DIRS; do
            if [ "$b" = = ]; then
               trim_one "$d"
            else
               receive_one "$d" "$b"
            fi
         done
      done
   elif [ $1 = trim ]; then
      echo '= Trimming snapshots for '$DIRS
      for d in $DIRS; do
         trim_one "$d"
      done
      trim_old_vols
   elif [ $1 = setvols ]; then
      create_setup
      echo '= Checking .old mirrors for '$DIRS
      for d in $DIRS; do
         dx=`dirname "$d"`
         check_mirror "$dx" ".old/$now" y
      done
      echo '= Setting '$DIRS' to newest snapshots'
      for d in $DIRS; do
         setvol_one "$d"
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

## >8 -- -- 8<

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
   if [ -d "$1" ] && [ -d "$2"/"$1" ]; then :; else
      if [ -n "$3" ]; then
         act mkdir -p "$1" "$2"/"$1"
      else
         echo 'PANIC: cannot handle '$1
         exit 1
      fi
   fi
}

create_setup() {
   now=`date +%Y%m%dT%H%M%S`
}

create_one() {
   echo '== Creating snapshot: '$1' -> snapshots/'$1'/'$now
   act btrfs subvolume snapshot -r "$1" snapshots/"$1"/"$now"
}

create_ball() {
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

   # The send stream
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
   target="$ACCUDIR"/.snap-$now/"$mydir" #/"$this"

   echo '== '$mydir': '$i' to '$target

   act mkdir -p "$target"
   act btrfs send $parent "$this" "|" \
      zstd -zc -T0 ${ZSTD_LEVEL} "|" \
      '(cd '"$target"' &&
        echo '"$this"' > .stamp &&
        split -a 4 -b 2000000000 -d -)'
   ) || exit $?
}

receive_one() {
   (
   mydir=$1
   ball=$2

   if [ -d "$ball"/"$mydir" ]; then :; else
      echo '=== '$mydir': no snapshot for me in here: '"$ball"/"$mydir"
      exit 0
   fi

   snaps=0
   for snap in "$ball"/"$mydir"/*; do
      snaps=$((snaps + 1))
      [ -f "$snap" ] && continue
      echo '=== '$mydir': invalid content, skipping this: '$snap
      exit 1
   done
   if [ -f "$ball"/"$mydir"/.stamp ]; then
      snap=`cat "$ball"/"$mydir"/.stamp`
   else
      echo '=== '$mydir': invalid content, missing .stamp file'
      exit 1
   fi

   cd snapshots/"$mydir" || exit 11

   if [ -d "$snap" ]; then
      echo '=== '$mydir': snapshot '$snap' already exists'
      exit 0
   fi

   echo '=== '$mydir': receiving snapshot of '$snaps' files'
   act cat "$ball"/"$mydir"/* '|' zstd -dc '|' btrfs receive .
   act btrfs filesystem sync .
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
   echo '=== Syncing on removal(s)'
   act btrfs subvolume sync .
   ) || exit $?
}

trim_old_vols() {
   (
   echo '= Trimming old volumes in .old'
   btrfs subvol list . |
      awk '/ .old\//{print $9}' |
      while read p; do
         act btrfs subvolume delete "$p"
      done
   rm -rf .old
   echo '= Syncing on removal(s)'
   act btrfs subvolume sync .
   ) || exit $?
}

setvol_one() {
   (
   mydir=$1
   cd snapshots/"$mydir" || exit 11

   set -- `find . -maxdepth 1 -type d -not -path . | sort`
   if [ $# -eq 0 ]; then
      echo '== No volume to set from snapshots/'$mydir
      exit 0
   fi
   while [ $# -gt 1 ]; do
      shift
   done

   echo '== Setting '$mydir' to '$1
   if [ -d "$THEVOL/$mydir" ]; then
      if btrfs subvolume show "$THEVOL/$mydir" >/dev/null 2>&1; then
         # We do not remove old volumes, but move them to .old.
         # This keeps mount points intact etc.  Of course it means later
         # cleaning is necessary
         act mv "$THEVOL/$mydir" "$THEVOL/.old/$now/$mydir"
      else
         act rm -rf "$THEVOL/$mydir"
      fi
   fi
   act btrfs subvolume snapshot "$1" "$THEVOL/$mydir"
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
         '('cd "$CLONEDIR"/snapshots/"$d" '&&' btrfs receive . '&&' \
            btrfs filesystem sync .')'
      ) || exit $?
   done

   if [ -n "$deldirs" ]; then
      echo '== The following snapshots have no upstream: '$deldirs
   fi
}

mytee() {
   while read l; do
      [ -z "$DEBUG" ] && echo "$l"
      echo >&2 "$l"
   done
}

mymail() {
   if [ -n "$DEBUG" ]; then
      cat
   else
      mail -s 'BTRFS snapshot management: '"$cmd ${DEBUG:+ (DEBUG MODE)}" root
   fi
}

syno() {
   echo 'Synopsis: btrfs-snapshot.sh create-dir-tree'
   echo 'Synopsis: btrfs-snapshot.sh create|trim|setvols'
   echo 'Synopsis: btrfs-snapshot.sh create-balls'
   echo 'Synopsis: btrfs-snapshot.sh receive-balls [:BALL:]'
   echo 'Synopsis: btrfs-snapshot.sh clone-to-cwd|sync-to-cwd'
   exit $1
}

cmd=$1
if [ "$cmd" = receive-balls ]; then
   shift
   echo '= Checking balls'
   rp=
   command -v realpath >/dev/null 2>&1 && rp=realpath
   for b in "$@"; do
      if  [ "$b" = = ]; then
         BALLS="$BALLS $b"
      elif [ -d "$b" ]; then
         [ -n "$rp" ] && b=`$rp "$b"`
         BALLS="$BALLS $b" # XXX quoting
      else
         echo 'No such ball to receive: '$b
         exit 1
      fi
   done
else
   [ $# -ne 1 ] && syno 1
   case $cmd in
   help) syno 0;;
   create-dir-tree) ;;
   create) ;; trim) ;; setvols) ;;
   create-balls) ;; #receive-balls) ;;
   clone-to-cwd) ;; sync-to-cwd) ;;
   *) syno 1;;
   esac
fi

( the_worker "$cmd" ) 2>&1 | mytee | mymail

# s-sh-mode
