#!/bin/sh -
#@ Create BTRFS filesystem snapshots, trim them down, etc.
#@ This script assumes a BTRFS master volume under which some subvolumes exist
#@ as mount points, and a snapshots/ at the first level under which all those
#@ subvolumes are mirrored.  Otherwise the_worker() must be adjusted.
#@ The configuration is read from $BTRFS_SNAPSHOT, ./btrfs-snapshot, or
#@ otherwise /root/hosts/$HOSTNAME/btrfs-snapshot.  It must contain:
#@
#@   # Top BTRFS volume..
#@   THEVOL=/media/btrfs-master
#@
#@   # the mount points within; we cd(1) to $THEVOL, these need to be relative.
#@   # Note I: whitespace and other shell quoting issues are not handled!
#@   # Note II: directories may not begin with equal-sign =.
#@   DIRS='home x/doc x/m x/m-mp4 x/os x/p x/src var/cache/apk'
#@
#@   # If set, no real action is performed
#@   #DEBUG
#@
#@ TODO (Instead) We should offer command line arguments, to a config file
#@ TODO and/or to set the vars directly: THEVOL,DIRS,ACCUDIR.
#@
#@ Synopsis: btrfs-snapshot.sh create-dir-tree
#@ Synopsis: btrfs-snapshot.sh create|trim|setvols
#@ Synopsis: btrfs-snapshot.sh clone-to-cwd|sync-to-cwd
#@
#@ - "create-dir-tree" creates all $DIRS and their snapshot mirrors,
#@   as necessary, in and under CWD.  It does not remove surplus directories.
#@   All further synchronizations can then be performed via
#@     cd WHEREVER && btrfs-snapshot.sh sync-to-cwd
#@
#@ - "create" creates a new snapshots/ of all $DIRS.
#@
#@ - "trim" deletes all but the last snapshot of each folder under snapshots/.
#@   It also removes anything (!) in .old/.
#@
#@ - "setvols" moves any existing $DIRS (subvolumes) to $THEVOL/.old/$now/
#@   (covered by "trim"), and recreates them from the latest corresponding
#@   entry within snapshots/.
#@
#@ - "clone-to-cwd" and "sync-to-cwd" need one existing snapshot (series),
#@   and will clone all the latest snapshots to the current-working-directory.
#@   clone-to-cwd creates the necessary hierarchy first, sync-to-cwd skips
#@   non-existing directories.
#@   Only the difference to the last snapshot which is present in both trees is
#@   synchronized: for the target this must be the last.
#@   Note $DIRS etc. still corresponds to what came in via configuration!
#@
#@ + the_worker() drives the logic, and may become adjusted, if simply
#@   setting other values for $THEVOL, $DIRS and $ACCUDIR does not suffice.
#
# 2019 - 2022 Steffen Nurpmeso <steffen@sdaoden.eu>.
# Public Domain

: ${HOSTNAME:=$(uname -n)}

if [ -f "$BTRFS_SNAPSHOT" ]; then
	. "$BTRFS_SNAPSHOT"
elif [ -f ./btrfs-snapshot ]; then
	. ./btrfs-snapshot
elif [ -f /root/hosts/$HOSTNAME/btrfs-snapshot ]; then
	. /root/hosts/$HOSTNAME/btrfs-snapshot
else
	logger -s -t /root/bin/btrfs-snapshot.sh "no config ./btrfs-snapshot, nor /root/hosts/$HOSTNAME/btrfs-snapshot"
	exit 1
fi
: ${ZSTD_LEVEL=-5}

# Non-empty and we will not act().
: ${DEBUG=}

## >8 -- 8<

TEMPLATE=

the_worker() ( # (output redirected)
	if [ $1 = clone-to-cwd ] || [ $1 = sync-to-cwd ]; then
		CLONEDIR=$(pwd)
	fi

	if mountpoint -q "$THEVOL"; then
		echo '= '$THEVOL' is already mounted'
		UMOUNT=:
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
	elif [ $1 = trim ]; then
		echo '= Trimming snapshots for '$DIRS
		for d in $DIRS; do
			trim_one "$d"
		done
		for d in $DIRS; do
			(
				cd snapshots/"$d" || exit 11
				echo '== Syncing on removal(s) of '$d
				act btrfs subvolume sync .
			) || exit $?
		done
		trim_old_vols
	elif [ $1 = setvols ]; then
		create_setup
		echo '= Checking .old mirrors for '$DIRS
		for d in $DIRS; do
			dx=$(dirname "$d")
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
)

## >8 -- -- 8<

act() {
	if [ -n "$DEBUG" ]; then
		echo eval "$@"
	else
		eval "$@"
		if [ $? -ne 0 ]; then
			echo 'PANIC: '$*
			exit 1
		fi
	fi
}

check_mirror() {
	if [ -d "$1" ] && [ -d "$2"/"$1" ]; then :; else
		if [ -n "$3" ]; then
			act mkdir -p "$1" "$2"/"$1"
		else
			echo 'PANIC: cannot handle DIR ('$2'/) '$1
			exit 1
		fi
	fi
}

create_setup() {
	now=$(date +%Y%m%dT%H%M%S)
}

create_one() {
	echo '== Creating snapshot: '$1' -> snapshots/'$1'/'$now
	act btrfs subvolume snapshot -r "$1" snapshots/"$1"/"$now"
}

trim_one() {
	(
	mydir=$1
	dosync=$2
	cd snapshots/"$mydir" || exit 11

	set -- $(find . -maxdepth 1 -type d -not -path . | sort)
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
	if [ -n "$dosync" ]; then
		echo '=== Syncing on removal(s)'
		act btrfs subvolume sync .
	fi
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
	echo '== Syncing on removal(s)'
	act btrfs subvolume sync .
	) || exit $?
}

setvol_one() {
	(
	mydir=$1
	cd snapshots/"$mydir" || exit 11

	set -- $(find . -maxdepth 1 -type d -not -path . | sort)
	if [ $# -eq 0 ]; then
		echo '== No volume to set from snapshots/'$mydir
		exit 0
	fi

	# Shift all but one
	i=$((-(1 - $#)))
	[ $i -gt 0 ] && shift $i

	echo '== Setting '$mydir' to '$1
	if [ -d "$THEVOL/$mydir" ]; then
		if btrfs subvolume show "$THEVOL/$mydir" >/dev/null 2>&1; then
			# We do not remove old volumes, but move them to .old.
			# This keeps mount points intact etc.  Of course it means later cleaning is necessary
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

		set -- $(find . -maxdepth 1 -type d -not -path . | sort)
		# Shift all but one
		i=$((-(1 - $#)))
		[ $i -gt 0 ] && shift $i
		lastsync=$1

		act cd "$THEVOL"/snapshots/"$d"

		set -- $(find . -maxdepth 1 -type d -not -path . | sort)
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
				echo '== Found no matching base snapshot!'
				echo '== Last of template '"$THEVOL"' is '"$1"
				echo '== Last of target '"$CLONEDIR"' is '"$lastsync"
				echo '== Rejecting synchronization for snapshots/'$d
				exit 1
			fi
		fi

		echo '== Synchronizing to '"$1$parentmsg"' from snapshots/'$d
		# On #btrfs@Libera.Chat multicore: and darkling: suggested looking for
		# "btrfs sub list -R", and if received_uuid is empty then it was not
		# successful, but (a) hard to make that fit into this code path, and
		# (b) "-" seems to cause from uid_is_null(subv->ruuid) and that also
		# seems to succeed for regular local volumes not received.
		mysnap=$1
		_remit() {
			trap '' EXIT
			echo '!! Cleaning up after error'
			act cd "$CLONEDIR"/snapshots/"$d" '&&' btrfs subvolume delete $mysnap '&&' btrfs subvolume sync .
			echo '!! Cleanup finished'
		}
		( set -o pipefail ) >/dev/null 2>&1 && set -o pipefail
		trap _remit EXIT
		act btrfs send $parent $1 '|' 
			'('cd "$CLONEDIR"/snapshots/"$d" '&&' btrfs receive . '&&' btrfs filesystem sync .')'
		trap '' EXIT
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
	if [ -n "$DEBUG" ] || ! command -v mail >/dev/null 2>&1; then
		cat
	else
		mail -s 'BTRFS snapshot management: '"$cmd" root
	fi
}

syno() {
	echo 'Synopsis: btrfs-snapshot.sh create-dir-tree'
	echo 'Synopsis: btrfs-snapshot.sh create|trim|setvols'
	echo 'Synopsis: btrfs-snapshot.sh clone-to-cwd|sync-to-cwd'
	echo
	echo 'See script head for documentation: '$0
	exit $1
}

cmd=$1
tmpl=$2
[ $# -ne 1 ] && syno 1
case $cmd in
help) syno 0;;
create-dir-tree) ;;
create) ;; trim) ;; setvols) ;;
clone-to-cwd) ;; sync-to-cwd) ;;
*) syno 1;;
esac

#(set -o pipefail) >/dev/null 2>&1 && set -o pipefail
es=$(exec 3>&1 1>&2; { the_worker "$cmd"; echo $? >&3; } | mytee | mymail)

exit $es
# s-sht-mode
