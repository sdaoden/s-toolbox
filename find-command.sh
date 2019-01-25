#!/bin/sh -
#@ Find an executable command within a POSIX shell.
#@ which(1) is not standardized, and command(1) -v may return non-executable,
#@ so here is how it is possible to really find a usable executable file.
#@ Use like this:
#@    thecmd_testandset chown chown ||
#@       PATH="/sbin:${PATH}" thecmd_set chown chown ||
#@       PATH="/usr/sbin:${PATH}" thecmd_set_fail chown chown
#@ or
#@    thecmd_testandset_fail MAKE make
#@ or
#@    MAKE=/usr/bin/make thecmd_testandset_fail MAKE make
#
# 2017 - 2019 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
# Thanks to Robert Elz (kre).
# Public Domain

## First of all, the actual functions need some environment:

VERBOSE=1

( set -o noglob ) >/dev/null 2>&1 && noglob_shell=1 || unset noglob_shell

msg() {
   fmt=${1}
   shift
   printf >&2 -- "${fmt}\n" "${@}"
}

## These are the actual functions

acmd_test() { fc__acmd "${1}" 1 0 0; }
acmd_test_fail() { fc__acmd "${1}" 1 1 0; }
acmd_set() { fc__acmd "${2}" 0 0 0 "${1}"; }
acmd_set_fail() { fc__acmd "${2}" 0 1 0 "${1}"; }
acmd_testandset() { fc__acmd "${2}" 1 0 0 "${1}"; }
acmd_testandset_fail() { fc__acmd "${2}" 1 1 0 "${1}"; }
thecmd_set() { fc__acmd "${2}" 0 0 1 "${1}"; }
thecmd_set_fail() { fc__acmd "${2}" 0 1 1 "${1}"; }
thecmd_testandset() { fc__acmd "${2}" 1 0 1 "${1}"; }
thecmd_testandset_fail() { fc__acmd "${2}" 1 1 1 "${1}"; }
fc__acmd() {
   pname=${1} dotest=${2} dofail=${3} verbok=${4} varname=${5}

   if [ "${dotest}" -ne 0 ]; then
      eval dotest=\$${varname}
      if [ -n "${dotest}" ]; then
         if [ -x "${dotest}" ]; then
            [ -n "${VERBOSE}" ] && [ ${verbok} -ne 0 ] &&
               msg ' . ${%s} ... %s' "${pname}" "${dotest}"
            return 0
         fi
         msg 'ERROR: ignoring non-executable ${%s}=%s' "${pname}" "${dotest}"
      fi
   fi

   # It may be an absolute path, check that first
   if [ "${pname}" != "${pname#/}" ] &&
         [ -f "${pname}" ] && [ -x "${pname}" ]; then
      [ -n "${VERBOSE}" ] && [ ${verbok} -ne 0 ] &&
            msg ' . ${%s} ... %s' "${pname}" "${pname}"
      [ -n "${varname}" ] && eval ${varname}="${pname}"
      return 0
   fi

   # Manual search over $PATH
   oifs=${IFS} IFS=:
   [ -n "${noglob_shell}" ] && set -o noglob
   set -- ${PATH}
   [ -n "${noglob_shell}" ] && set +o noglob
   IFS=${oifs}
   for path
   do
      if [ -z "${path}" ] || [ "${path}" = . ]; then
         if [ -d "${PWD}" ]; then
            path=${PWD}
         else
            path=.
         fi
      fi
      if [ -f "${path}/${pname}" ] && [ -x "${path}/${pname}" ]; then
         [ -n "${VERBOSE}" ] && [ ${verbok} -ne 0 ] &&
            msg ' . ${%s} ... %s' "${pname}" "${path}/${pname}"
         [ -n "${varname}" ] && eval ${varname}="${path}/${pname}"
         return 0
      fi
   done

   [ -n "${varname}" ] && eval ${varname}=
   [ ${dofail} -eq 0 ] && return 1
   msg 'ERROR: no trace of utility '"${pname}"
   exit 1
}

# s-sh-mode
