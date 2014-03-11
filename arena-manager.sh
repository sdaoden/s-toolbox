#!/bin/sh -
#@ arena-manager.sh: some automatized operations on revision control repos.
#@ Works with Bourne/Korn/POSIX shells, requires awk(1) (a POSIX environment).
#@ Setup your repos once via `setup' mode ($ arena-manager.sh setup).
#
# Copyright (c) 2011 - 2014 Steffen (Daode) Nurpmeso <sdaoden@users.sf.net>.
# All rights reserved.
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# The version control executables
: ${GIT:=`command -v git`}
: ${HG:=`command -v hg`}
: ${SVN:=`command -v svn`}
: ${CVS:=`command -v cvs`}
:  ${CVS_FLAGS:=-fz9}
:  ${CVS_UPDATE_FLAGS:=-AP}
:  ${CVS_RSH:=ssh}

export CVS_RSH

# The necessary (POSIX) environment
: ${SHELL:=`command -v sh`}
: ${awk:=`command -v awk`}
: ${cat:=`command -v cat`}
: ${cp:=`command -v cp`}
: ${date:=`command -v date`}
: ${expr:=`command -v expr`}
: ${grep:=`command -v grep`}
: ${mkdir:=`command -v mkdir`}
: ${mv:=`command -v mv`}
: ${rm:=`command -v rm`}
: ${sed:=`command -v sed`}
: ${tee:=`command -v tee`}
: ${time:=`command -v time`}
: ${wc:=`command -v wc`}

# So what can this script do for you?
# It offers the following modes in an $ARENA of revision control repositories:
#    reduce|expand|gc|fullgc|update|automerge|autogc|checkup|autoup
# Please read all comments of this script before you use it, it was not written
# with public use in mind and thus is a bit complicated to setup.
# This script chooses what to do according to tags that it derives from the
# extension of the repositories top directory:
#
# .git         : git(1)
#           this script assumes local heads under 'refs/heads', and remote
#           heads under 'refs/remotes'...
# .svn_git     : git(1)-svn
#           requires a "pseudo local" reference (update-ref) with the same name
#           as the remote name that git-svn has produced, i.e., if that was
#           '[refs/]remotes/trunk' then do that once:
#           $ git update-ref refs/heads/trunk remotes/trunk
# .cvs_git     : git(1)-cvsimport
#           requires a very special setup!  Please read the update mode!!
# .cvs_bomb_git, .svn_bomb_git, .update_bomb_git:
#           plain git(1) repo inside plain checked out cvs(1)/svn(1) workdir
#           do this once after the initial checkout:
#           $ git init; git add --all; git ci -m created
#           Note that arena-manager will create origin/master and some
#           arena-manager branches as necessary!
#           Better do, for .cvs_bomb_git:
#           $ echo '.#*' >> .git/info/exclude
#           And, absolutely necessary, for .update_bomb_git:
#           $ echo 'svn export http://auau/trunk' > update.sh
#           Or whatever must be in update.sh to update the repo.
#           The repo should possibly be in a further subdirectory.
#           And, also rather for .update_bomb_git only, it is ok if update.sh
#           may itself initiates a commit.
# .sccs_bomb_git: SCCS(1) tree under .git control
# .tar_bomb_git: plain git(1) repo which is updated by exploding tarballs
# .hg          : hg(1) (Mercurial)
# .svn         : svn(1)
# .cvs         : cvs(1)
# .sccs        : sccs(1) (left alone)
#
# All those extensions can be extended with additional tags:
#
# -no_reduce: skip "reduce" and "expand" modes (git(1), hg(1) only)
#           if this is *not* part of the extension the git(1) managed
#           repositories need a branch 'arena-manager-null', which should
#           contain only a single file named 'NULL', which must only consist
#           of a single line with the name of the "master" branch to check out
#           when "expand" is called.  If this file is missing 'master' is used.
#           Mercurial does have a builtin "null" branch and thus simply needs
#           an "update" operation to switch back to the branch which was
#           checked out before "reduce" happened.
# -no_autoup: never perform "update" for this unless the name of the repo
#           was explicitely named on command line.
# -no_fullgc: even with "fullgc", never use --aggressive (git(1) only)
#           "fullgc", and "autogc" every six months, use the --aggressive
#           argument to git-gc.  Some repositories however require hours to
#           finish a fullgc (i.e. the Linux kernel).

##  --  >8  --  8<  --  ##

# Existence of $ARENA is checked first in execution (below all the funs)
exit

# Calm down anything which cares
LC_ALL=C
CVSROOT=/nonexistent
export LC_ALL CVSROOT

# These *must* reside in $ARENA!
LOGFILE=.ARENA-LOG
AUTOGCFILE=.ARENA-AUTOGC

#
ESTAT=0
GITDID=0
AUTOUP=0

MODE="${1}"
shift
PARAMS=${@+"${@}"}
CURRD=

log() {
   echo "${*}"
   echo "${*}" >> "${LOGFILE}"
}
logerr() {
   echo >&2 "ERROR: ${*}"
   echo "ERROR: ${*}" >> "${LOGFILE}"
   ESTAT=1
}

SEP='================================================================'
intro() {
   log ''
   log ${SEP}
   log "${1}"
}
final() {
   if [ ${1} -eq 0 ]; then
      log "... ok: ${2}"
   else
      ESTAT=${1}
      logerr "${2}"
   fi
   log ${SEP}
}

# basename(1) plus cleanup
bname() {
   CURRD=`echo "${CURRD}" | ${sed} -e 's/\/\/*$//' -e 's/\(^.*\/\/*\)//'`
}

_pipefail() {
   if [ -z "${__pipefail}" ]; then
      if ( set -o pipefail ) >/dev/null 2>&1; then
         __pipefail=0
      else
         __pipefail=1
      fi
   fi
   return ${__pipefail}
}
pipefail_on() {
   _pipefail || return 0
   set -o pipefail
}
pipefail_off() {
   _pipefail || return 0
   set +o pipefail
}

# Does $1 contain any substring that matches $2[-$X]?
matches() {
   var=${1} i=
   shift

   # Take care for older shells which don't support ${//}
   if [ -z "${__matchsubst}" ]; then
      i=zauberberg
      if ( eval "test \${i/ber/} = zauberg" ) >/dev/null 2>&1; then
         __matchsubst=1
      else
         __matchsubst=0
      fi
   fi
   if [ ${__matchsubst} -ne 0 ]; then
      for i
      do
         [ "${var}" != "${var/${i}/}" ] && return 0
      done
   else
      for i
      do
         echo ${var} | ${grep} "${i}" >/dev/null 2>&1 && return 0
      done
   fi
   return 1
}
# Same as "! matches" except that old shells gobble it
nmatches() {
   matches ${@+"${@}"}
   [ ${?} -eq 0 ] && return 1 || return 0
}

## git(1) stuff: all called from within subshell with -o pipefail

git_check_status() {
   if [ 0 != `${GIT} status --short | ${wc} -l | \
         ${sed} -Ee 's/^[[:space:]]+(.*)$/\1/'` ]; then
      echo >&2 'Modified or untracked files present, bailing out!'
      exit 10
   fi
}

git_checkout() {
   br=${1}
   if ${GIT} checkout -q -f "${br}" --; then
      :
   else
      echo >&2 "Can't checkout branch ${br}, bailing out!"
      exit 11
   fi
}

git_ref_check_gc_update() {
   # Return 41 if no new data, 42 if new data, otherwise error
   repodir=${1} autogcfile=${2}
   ${GIT} show-ref |
   perl -e "\$rd = \"$repodir\"; \$agcf = \"$autogcfile\";" -e '
        my (%remotes, %heads);
        while (<STDIN>) {
            chomp;
            my ($sha, $ref) = split;
            #print STDERR "sha<$sha> ref<$ref>\n";
            $ref =~ s/^refs\/(.+)/$1/;
            if ($ref =~ s/^remotes\///) {
                $remotes{$ref} = $sha;
            } elsif ($ref =~ s/^heads\///) {
                $heads{$ref} = $sha;
            } elsif ($ref !~ /^tags/) {
                print STDERR "Skipping unrecognized ref $ref\n";
            }
        }

        my $es = 41;
        die "Cannot open append-write $agcf: $!" unless open AGCF, ">>", $agcf;
        foreach (keys %remotes) {
            (my $lr = $_) =~ s/^origin\///;
            next unless exists $heads{$lr};
            next if $heads{$lr} eq $remotes{$_};
            $es = 42;
            print "... {at least \"$lr\" and \"remotes/$_\" differ, ",
                  "marking for autogc}\n";
            die "Cannot write $agcf: $!" unless print AGCF $rd, "\n";
            last;
        } 
        die "Cannot close $agcf: $!" unless close AGCF;
        exit $es;
   '
   return ${?}
}

## misc

xy_bomb_git_update() {
   comm=${1} commname=${2} modlns=0 es=

   # (We need to compare local master and remote to detect wether there were
   # updates)
   if ${GIT} checkout -q -f -B arena-manager-download master --; then
      :
   else
      echo >&2 'Cannot reset branch arena-manager-download, bailing out!'
      exit 20
   fi
   if ${GIT} update-ref refs/remotes/origin/master arena-manager-download; then
      :
   else
      echo >&2 'Cannot reset branch origin/master, bailing out!'
      exit 21
   fi

   ${comm}
   es=${?}

   # Commit was performed by update.sh script?
   if [ "`${GIT} show-ref --hash refs/heads/master`" != \
         "`${GIT} show-ref --hash refs/heads/arena-manager-download`" ]; then
      modlns=1
      ${GIT} update-ref refs/remotes/origin/master arena-manager-download ||\
         exit 24
      echo "${CURRD}" >> "${ARENA}/${AUTOGCFILE}" || exit 25
   else
      # Ignore all updates which occur in .svn/CVS directories, at least for
      # checking wether any repo content has been updated.
      # To avoid problems with DOS/Unix newline changes in working
      # directories, don't use status but this hint (note this new approach
      # would allow for changing some sed(1) REs, but .. just wait a bit xxx)
      modlns=`${GIT} add --all --dry-run 2>/dev/null |
            ${sed} -Ee '/(\.svn|CVS|SCCS)\/.*$/d' -e '/\.git/d' \
               -e '/\/?\.#/d' | ${wc} -l |\
            ${sed} -Ee 's/^[[:space:]]+(.*)$/\1/'`
      if [ 0 != "${modlns}" ]; then
         echo "... ${commname} updated some, initiating git(1) commit"
         ${GIT} add --all || exit 22
         ${GIT} commit -m \
            "arena-manager: ${commname} update, `${date} +'%FT%T%z'`" || exit 23
         ${GIT} update-ref refs/remotes/origin/master arena-manager-download ||\
            exit 24
         echo "${CURRD}" >> "${ARENA}/${AUTOGCFILE}" || exit 25
        fi
    fi

    if [ 0 = "${modlns}" ]; then
      ${GIT} reset -q --hard HEAD || exit 26
      echo "... ${commname} did not seem to have new data"
    fi

    git_checkout master
    return ${es}
}

## modes

reduce_expand() {
   if [ "${MODE}" = reduce ]; then
      git_branch=arena-manager-null
      hg_branch=null
   else
      git_branch=
      hg_branch=
   fi

   for CURRD in ${PARAMS}
   do
      bname
      if matches "${CURRD}" no_reduce || nmatches "${CURRD}" git hg; then
         log ''
         log "[${CURRD}: ${MODE} does not apply]"
         continue
      fi

      intro "${CURRD}: performing ${MODE}"
      pipefail_on
      (  cd "${CURRD}" || exit 10
         if matches "${CURRD}" git; then
            # File NULL on branch arena-manager-null contains a single line
            # stating the master branch's name
            if [ -z "${git_branch}" ]; then
               if [ -f NULL ]; then
                  git_branch=`cat NULL`
               else
                  echo >&2 "No file NULL (stating branch name) in ${CURRD}"
                  git_branch=master
               fi
            fi
            git_checkout "${git_branch}"
         #elif matches "${CURRD}" hg; then
         else
            ${HG} up ${hg_branch}
         fi
         exit ${?}
      ) 2>&1 | ${tee} -a "${LOGFILE}"
      final ${?} "${CURRD}"
      pipefail_off
   done
}

xgc() {
   GCT= gcmode= gcarg=
   [ "${MODE}" = fullgc ] && GCT=--aggressive
   for CURRD in ${PARAMS}
   do
      bname
      if nmatches "${CURRD}" git; then
         log ''
         log "[${CURRD}: ${MODE} does not apply]"
         continue
      fi
      gcmode=${MODE}
      gcarg=${GCT}
      if matches "${CURRD}" no_fullgc; then
         gcmode='gc (fullgc forcefully downgraded)'
         gcarg=
      fi
      intro "${CURRD}: performing ${gcmode}"
      pipefail_on
      (  cd "${CURRD}" || exit 1
         ${time} ${GIT} gc ${gcarg}
      ) 2>&1 | ${tee} -a "${LOGFILE}"
      final ${?} "${CURRD}"
      pipefail_off
   done
}

update() {
   if ${rm} -rf "${AUTOGCFILE}"; then
      :
   else
      echo >&2 "Failed to remove stale ${AUTOGCFILE}"
      exit 1
   fi

   for CURRD in ${PARAMS}
   do
      bname
      if [ ${AUTOUP} -ne 0 ] && matches "${CURRD}" no_autoup; then
         log ''
         log "[${CURRD}: ${MODE} does not apply]"
         continue
      fi
      if matches "${CURRD}" .tar_bomb_git .sccs_bomb_git; then
         log ''
         log "[${CURRD}: (automatic) ${MODE} does not apply]"
         continue
      fi

      intro "${CURRD}: performing ${MODE}"
      pipefail_on
      (  cd "${CURRD}" || exit 9
         if nmatches "${CURRD}" git; then
            case "${CURRD}" in
            *.hg*)
               # TODO use incoming, and produce an AUTOGC entry if there
               # TODO are any revisions; then pull that and rm it!!
               ${HG} pull -u
               es=${?}
               ;;
            *.svn*)
               ${SVN} update
               es=${?}
               ;;
            *.cvs*)
               ${CVS} ${CVS_FLAGS} update ${CVS_UPDATE_FLAGS}
               es=${?}
               ;;
            *.sccs*)
               echo "SCCS(1) managed tree, skip: ${CURRD}"
               es=0
               ;;
            *)
               echo >&2 "Unknown revision-control-system: ${CURRD}"
               es=1
               ;;
            esac
            exit ${es}
         fi

         # git(1) and related
         git_check_status

         case "${CURRD}" in
         *.git*)
            #${GIT} pull -v --ff-only --stat --prune
            ${GIT} fetch --verbose --prune
            es=${?}
            [ ${es} -eq 0 ] &&
               git_ref_check_gc_update "${CURRD}" "${ARENA}/${AUTOGCFILE}"
            ;;
         *.update_bomb_git*)
            xy_bomb_git_update "${SHELL} -c ./update.sh" 'update.sh'
            es=${?}
            ;;
         *.svn_bomb_git*)
            omode=${MODE}
            MODE=expand
            reduce_expand
            MODE=${omode}
            xy_bomb_git_update "${SVN} update" 'svn(1)'
            es=${?}
            ;;
         *.svn_git*)
            # This auto-merges into "master", so that there can be found no
            # indication of wether there were updates or not; thus the local
            # "pseudo" branch we use for that (better solution is clear, maybe
            # in arena-manager.pl which is single instance and can store all
            # refs before in memory and compare against refs after)
            omode=${MODE}
            MODE=expand
            reduce_expand
            MODE=${omode}
            ${GIT} svn rebase
            es=${?}
            [ ${es} -eq 0 ] &&
               git_ref_check_gc_update "${CURRD}" "${ARENA}/${AUTOGCFILE}"
            ;;
         *.cvs_bomb_git*)
            xy_bomb_git_update \
               "${CVS} ${CVS_FLAGS} update ${CVS_UPDATE_FLAGS}" 'cvs(1)'
            es=${?}
            ;;
         *.cvs_git*)
            # This is more complicated; you need to setup a branch
            # arena-manager-config; check that out
            git_checkout arena-manager-config

            # It contains several files which are used to store the config
            master=`${cat} git_master`       # The name of the master branch
            cvs_root=`${cat} cvs_root`       # CVSROOT repo URL (CVS/Root)
            cvs_module=`${cat} cvs_module`   # CVS module (CVS/Repository)
            # The name of the cvsps(1) cache file is stored in here;
            # that file itself is always stored as 'cvsps_cache' instead
            cvsps_file=`${cat} cvsps_file`
            # Up to you wether you want -R or not
            [ -f cvs-revisions ] && Rflag=-R || Rflag= # git cvsimport dat

            # Prepare cvsps(1) (and git(1) cvsimport) cache
            cvsps_dir="${HOME}/.cvsps"
            if [ -d "${cvsps_dir}" ] || ${mkdir} "${cvsps_dir}"; then
               :
            else
               echo >&2 "${CURRD}: failed to create ${cvsps_dir} directory"
               exit 20
            fi
            [ -n "${Rflag}" ] && ${cp} -f cvs-revisions .git/
            ${cp} -f cvsps_cache "${cvsps_dir}/${cvsps_file}"

            # NOTE: we *require* these -r -d etc... TODO maybe it would be
            # TODO better to offer a "cvsimport-setup"?  arena-manager.pl..
            ${GIT} cvsimport -ai ${Rflag} -p '-u,--cvs-direct' -r origin \
               -d "${cvs_root}" "${cvs_module}"
            es=${?}
            if [ ${es} -ne 0 ]; then
               echo >&2 "${CURRD} git(1) cvsimport failed, bailing out"
               git_checkout "${master}"
               exit ${es}
            fi

            # Again, don't create commits unless any repository content has
            # been updated; cvsps(1) always recreates it's cache file...
            git_ref_check_gc_update "${CURRD}" "${ARENA}/${AUTOGCFILE}"
            if [ ${?} -eq 42 ]; then
               echo '... committing updated configuration'
               [ -n "${Rflag}" ] && ${mv} -f .git/cvs-revisions .
               ${mv} -f "${cvsps_dir}/${cvsps_file}" cvsps_cache
               ${GIT} add --all || exit 21
               ${GIT} commit -m 'arena-manager .cvs_git update' || exit 22
            else
               echo '... cvsimport had nothing, not updating config'
               [ -n "${Rflag}" ] && ${rm} -f .git/cvs-revisions
               ${rm} -f "${cvsps_dir}/${cvsps_file}"
            fi

            git_checkout "${master}"
            ;;
         *)
            echo >&2 "Unknown revision-control-system: ${CURRD}"
            es=1
            ;;
         esac
         exit ${es}
      ) 2>&1 | ${tee} -a "${LOGFILE}"
      es=${?}
      pipefail_off
      final ${es} "${CURRD}"
   done

   [ -s "${AUTOGCFILE}" ] && GITDID=1
}

automerge() {
   if [ ! -s "${AUTOGCFILE}" ]; then
      logerr 'Necessary information for automerge is missing'
      exit 1
   fi
   for CURRD in `cat "${AUTOGCFILE}"`
   do
      if nmatches "${CURRD}" git; then
         log ''
         log "[${CURRD}: ${MODE} does not apply]"
         continue
      fi

      intro "${CURRD}: performing ${MODE}"
      pipefail_on
      (  cd "${CURRD}" || exit 9
         git_check_status
         # This works with our hackish approach, but is rather unnecessary;
         # if we would have configuration files, it would be so clear!
         # arena-manager.pl could do a much better job!
         master=`${GIT} rev-parse --symbolic-full-name HEAD | \
               ${sed} -e 's/^refs\/heads\///'`
         matches "${CURRD}" .svn_git && issvn=1 || issvn=0
         perl -e "\$git = \"$GIT\"; \$is_svn = $issvn;" -e '
                my (%remotes, %heads, @reflines);
                die "Cannot read refs: $^E"
                    unless open RLPIPE, "$git show-ref |";
                @reflines = <RLPIPE>;
                close RLPIPE;
                while (@reflines) {
                    my $l = pop @reflines;
                    chomp $l;
                    my ($sha, $ref) = split /\s+/, $l;
                    $ref =~ s/^refs\/(.+)/$1/;
                    if ($ref =~ s/^remotes\///) {
                        $remotes{$ref} = $sha;
                    } elsif ($ref =~ s/^heads\///) {
                        $heads{$ref} = $sha;
                    } elsif ($ref !~ /^tags/) {
                        print STDERR "Skipping unrecognized ref $ref\n";
                    }
                }

                my $es = 0;
                foreach (keys %remotes) {
                    (my $lr = $_) =~ s/^origin\///;
                    next unless exists $heads{$lr};
                    next if $heads{$lr} eq $remotes{$_};
                    if ($is_svn) {
                        print "\n... git-svn performs automerge, ",
                              "so update-ref $lr\n";
                        system("$git update-ref " .
                               "refs/heads/$lr refs/remotes/$_");
                        $es |= $?;
                    } else {
                        print "\n... Performing automerge from $_ to $lr\n";
                        system("$git checkout -q -f $lr; " .
                               "$git merge --ff-only $_");
                        $es |= $?;
                    }
                } 
                exit $es;
         '
         es=${?}
         git_checkout "${master}"
      ) 2>&1 | ${tee} -a "${LOGFILE}"
      es=${?}
      pipefail_off
      final ${es} "${CURRD}"
   done
}

autogc() {
   if [ ! -s "${AUTOGCFILE}" ]; then
      logerr 'Necessary information for autogc is missing'
      exit 1
   fi
   set -- `${cat} "${AUTOGCFILE}"`
   PARAMS=${@+"${@}"}
   # Do a full --aggressive gc every xy months
   m=`${date} +%m`
   m=`${expr} ${m} : '0*\(.*\)' % 6`
   if [ 0 = "${m}" ]; then
      MODE=fullgc
      log 'Turned over to mode fullgc (full because MONTH % 6 == 0)'
   else
      MODE=gc
      log 'Turned over to mode gc'
   fi
   xgc
}

checkup() {
   es=0
   log 'Checking how likely it is an update would succeed'
   for CURRD in ${PARAMS}
   do
      bname
      if [ ${AUTOUP} -ne 0 ] && matches "${CURRD}" no_autoup; then
         log "  [${CURRD}: -no_autoup tag, skip]"
         continue
      fi
      if matches "${CURRD}" .tar_bomb_git .sccs_bomb_git; then
         log "  [${CURRD}: ${MODE} does not apply]"
         continue
      fi
      if matches "${CURRD}" git; then
         action="${GIT} status --short"
      elif matches "${CURRD}" .hg; then
         action="${HG} status"
      else
         log "  [${CURRD}: ${MODE} does not apply]"
         continue
      fi
      if [ 0 != `cd "${CURRD}" && ${action} | ${wc} -l | \
            ${sed} -Ee 's/^[[:space:]]+(.*)$/\1/'` ]; then
         log "! ${CURRD}: modified or untracked files present!"
         es=1
      else
         log "  ${CURRD}: looks good"
      fi
   done
   if [ ${es} -ne 0 ]; then
      echo >&2 'Some repositories need a hand first'
      exit ${es}
   fi
}

## exec

# Top dir where everything happens
if [ -z "${ARENA}" ]; then
   echo >&2 '(Environment) variable ARENA is not set'
   exit 1
fi
if cd "${ARENA}"; then
   :
else
   echo >&2 "Failed to chdir to ARENA=${ARENA}"
   exit 1
fi

if [ -f "${LOGFILE}" ]; then
   if ${mv} -f "${LOGFILE}" "${LOGFILE-LAST}"; then
      :
   else
      echo >&2 "Failed to move old ${LOGFILE} to ${LOGFILE}-LAST"
      exit 1
   fi
fi

[ -z "${MODE}" ] && MODE=autoup
log "${0}: script startup, mode ${MODE}"
[ ${#} -eq 0 ] && PARAMS=`echo *.*`

case "${MODE}" in
reduce|expand)  reduce_expand;;
fullgc|gc)      xgc;;
update)         update;;
automerge)      automerge;;
autogc)         autogc;;
checkup)        checkup;;
autoup)
   AUTOUP=1
   MODE='autoup: checkup'
   checkup
   if [ -x ./autoup-prehook ]; then
      MODE='autoup: running autoup-prehook'
      ${SHELL} ./autoup-prehook || exit 100
   fi
   MODE='autoup: update'
   update
   if [ -s "${AUTOGCFILE}" ]; then
      MODE='autoup: automerge'
      automerge
      if [ -x ./autoup-posthook ]; then
         MODE='autoup: running autoup-posthook'
         ${SHELL} ./autoup-posthook || exit 101
      fi
      MODE='autoup: autogc'
      autogc
      GITDID=0
   else
      log ''
      log 'It seems there is no new data at all, skipping merge+gc'
   fi
   ;;
*)
   echo 'USAGE: arena-manager MODE [LIST-OF-DIRS]'
   echo 'MODEs: reduce|expand|gc|fullgc|update|automerge|autogc|checkup|autoup'
   exit 1
   ;;
esac

log ''
log '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
if [ ${GITDID} -ne 0 ]; then
   log 'Some git(1) repos seem to have new packs, run arena-manager autogc'
fi
if [ ${ESTAT} -ne 0 ]; then
   log 'Errors occurred!  Ooooh, my gooooooood!  :)'
else
   log 'All seems fine around here, ciao'
fi
exit ${ESTAT}
# vim:set fenc=utf-8:s-it-mode
