#!/bin/sh -
#@ ZTE Modem per script
#@
#@ 2018 Steffen (Daode) Nurpmeso <steffen@sdaoden.eu>.
#@ Public Domain.

# Will be asked on TTY if empty
PASSWORD=

set_cmd() {
   cmd='-d goformId='$1' -d isTest=false'
   shift
   while [ $# -gt 0 ]; do
      cmd="$cmd -d $1"
      shift
   done

   result=`curl --header 'Referer: http://192.168.0.1/index.html' \
      $cmd \
      --connect-timeout 5 \
      http://192.168.0.1/goform/goform_set_cmd_process \
      2>/dev/null`
   es=$?
}

get_cmd() {
   result=`curl --header 'Referer: http://192.168.0.1/index.html' \
      --connect-timeout 5 \
      'http://192.168.0.1/goform/goform_get_cmd_process?'"$1" \
      2>/dev/null`
   es=$?
}

case "$@" in
login)
   while [ -z "$PASSWORD" ]; do
      ttyreset=
      if command -v stty >/dev/null 2>&1; then
         ttyreset="stty `stty -g`"
         stty -echo
      fi
      printf 'Enter passphrase: '
      read PASSWORD
      $ttyreset
   done
   i=`printf '%s' "$PASSWORD" | openssl base64`
   set_cmd LOGIN "password=$i"
   ;;
conn*)
   set_cmd CONNECT_NETWORK
   ;;
disco*)
   set_cmd DISCONNECT_NETWORK
   ;;
info)
   s='cmd=signalbar,wan_csq,network_type,network_provider,ppp_status,'
   s="$s"'modem_main_state,rmcc,rmnc,domain_stat,cell_id,lac_code,rssi,'
   s="$s"'rscp,lte_rssi,lte_rsrq,lte_rsrp,lte_snr,ecio,sms_received_flag,'
   s="$s"'sts_received_flag,simcard_roam,cbm_r&multi_data=1'
   s="$s"'&sms_received_flag_flag=0&sts_received_flag_flag=0'
   s="$s"'&cbm_received_flag_flag=0'
   get_cmd "$s"
   ;;
*)
   echo 2>&1 'Synopsis: login|conn|disco|info'
   exit 1
   ;;
esac

echo estat=$es result=$result
exit $es

   SET_BEARER_PREFERENCE&BearerPreference=
      following options available after "=" sign (case-sensitive)
      NETWORK_auto
      WCDMA_preferred
      GSM_preferred
      Only_GSM
      Only_WCDMA
      Only_LTE
      WCDMA_AND_GSM
      WCDMA_AND_LTE
      GSM_AND_LTE

github.com/ab77/beastcraft-telemetry (partial)
==============================================
# en/disable roaming
set_cmd SET_CONNECTION_MODE roam_setting_option=on|off
# enable auto-dial
set_cmd SET_CONNECTION_MODE ConnectionMode=auto_dial|manual_dial
# upgrade_result
get_cmd cmd=upgrade_result
# current_upgrade_state
get_cmd cmd=current_upgrade_state
# sms_data_total
get_cmd cmd=sms_data_total&page=0&data_per_page=500&mem_store=1&tags=10&order_by=order+by+id+desc
# sms_capacity_info
get_cmd cmd=sms_capacity_info
# sms_parameter_info
get_cmd cmd=sms_parameter_info
# pbm_init_flag
get_cmd cmd=pbm_init_flag
# pbm_capacity_info&pbm_location=pbm_sim
get_cmd cmd=pbm_capacity_info&pbm_location=pbm_sim
# sim_imsi
get_cmd cmd=sim_imsi%2Csim_imsi_lists&multi_data=1

# s-sh-mode
