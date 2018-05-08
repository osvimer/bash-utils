#=========================================================
# Author         : Junjie Huang
# Email          : junjie.huang@seraphic-corp.com
# Last modified  : 2018-05-07 19:08
# Filename       : prelink_status.sh
# Description    : to check prelink status for elf file
#=========================================================

#!/bin/bash

RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`

for elf in $@
do
  if [[ $(readelf -S ${elf} | grep -i prelink) ]] ; then
    echo "${GREEN} ${elf} prelinked ${RESET}"
  else
    echo "${RED} ${elf} unprelinked ${RESET}"
  fi
done
