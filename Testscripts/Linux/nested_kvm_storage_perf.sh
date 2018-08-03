#!/bin/bash

#######################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
#######################################################################

#######################################################################
#
# nested_kvm_storage_perf.sh
#
# Description:
#   This script prepares nested kvm for fio test.
#
#######################################################################

. ./nested_kvm_utils.sh
. ./constants.sh
#HOW TO PARSE THE ARGUMENTS.. SOURCE - http://stackoverflow.com/questions/4882349/parsing-shell-script-arguments
while echo $1 | grep -q ^-; do
   declare $( echo $1 | sed 's/^-//' )=$2
   shift
   shift
done

if [ -z "$NestedImageUrl" ]; then
    echo "Please mention -NestedImageUrl next"
    exit 1
fi
if [ -z "$NestedUser" ]; then
    echo "Please mention -NestedUser next"
    exit 1
fi
if [ -z "$NestedUserPassword" ]; then
    echo "Please mention -NestedUserPassword next"
    exit 1
fi
if [ -z "$NestedCpuNum" ]; then
    echo "Please mention -NestedCpuNum next"
    exit 1
fi
if [ -z "$NestedMemMB" ]; then
    echo "Please mention -NestedMemMB next"
    exit 1
fi
if [ -z "$platform" ]; then
    echo "Please mention -platform next"
    exit 1
fi
if [ -z "$RaidOption" ]; then
    echo "Please mention -RaidOption next"
    exit 1
fi
if [ -z "$logFolder" ]; then
    logFolder="."
    echo "-logFolder is not mentioned. Using ."
else
    echo "Using Log Folder $logFolder"
fi
if [[ $RaidOption == 'RAID in L1' ]] || [[ $RaidOption == 'RAID in L2' ]] || [[ $RaidOption == 'No RAID' ]]; then
    echo "RaidOption is available"
else
    UpdateTestState $ICA_TESTABORTED
    echo "RaidOption $RaidOption is invalid"
    exit 0
fi

touch $logFolder/state.txt
touch $logFolder/`basename "$0"`.log

LogMsg()
{
    echo `date "+%b %d %Y %T"` : "$1" >> $logFolder/`basename "$0"`.log
}

RemoveRAID()
{
    LogMsg "INFO: Check and remove RAID first"
    mdvol=$(cat /proc/mdstat | grep md | awk -F: '{ print $1 }')
    if [ -n "$mdvol" ]; then
        echo "/dev/${mdvol} already exist...removing first"
        umount /dev/${mdvol}
        mdadm --stop /dev/${mdvol}
        mdadm --remove /dev/${mdvol}
        for disk in ${disks}
        do
            echo "formatting disk /dev/${disk}"
            mkfs -t ext4 -F /dev/${disk}
        done
    fi
}

CreateRAID0()
{
    LogMsg "INFO: Creating Partitions"
    count=0
    for disk in ${disks}
    do
        echo "formatting disk /dev/${disk}"
        (echo d; echo n; echo p; echo 1; echo; echo; echo t; echo fd; echo w;) | fdisk /dev/${disk}
        count=$(( $count + 1 ))
        sleep 1
    done
    LogMsg "INFO: Creating RAID of ${count} devices."
    yes | mdadm --create ${mdVolume} --level 0 --raid-devices ${count} /dev/${devices}[1-5]
    if [ $? -ne 0 ]; then
        UpdateTestState $ICA_TESTFAILED
        LogMsg "Error: Unable to create raid"
        exit 0
    else
        LogMsg "Create raid successfully."
    fi
}

RunFIO()
{
    LogMsg "Copy necessary scripts to nested VM"
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename ./azuremodules.sh -remote_path /root -cmd put
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename ./StartFioTest.sh -remote_path /root -cmd put
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename ./constants.sh -remote_path /root -cmd put
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename ./ParseFioTestLogs.sh -remote_path /root -cmd put
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename ./nested_kvm_perf_fio.sh -remote_path /root -cmd put

    LogMsg "Start to run StartFioTest.sh on nested VM"
    remote_exec -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort '/root/StartFioTest.sh'
}

CollectLogs()
{
    LogMsg "Finished running StartFioTest.sh, start to collect logs"
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename fioConsoleLogs.txt -remote_path "/root" -cmd get
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename runlog.txt -remote_path "/root" -cmd get
    remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename state.txt -remote_path "/root" -cmd get
    state=`cat state.txt`
    LogMsg "FIO Test state: $state"
    if [ $state == 'TestCompleted' ]; then
        remote_exec -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort '/root/ParseFioTestLogs.sh'
        remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename FIOTest-*.tar.gz -remote_path "/root" -cmd get
        remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename perf_fio.csv -remote_path "/root" -cmd get
        remote_copy -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort -filename nested_properties.csv -remote_path "/root" -cmd get
    else
        UpdateTestState $ICA_TESTFAILED
        exit 0
    fi
}

############################################################
#   Main body
############################################################
UpdateTestState $ICA_TESTRUNNING

if [[ $platform == 'HyperV' ]]; then
    devices='sd[b-z]'
else
    devices='sd[c-z]'
fi

disks=$(ls -l /dev | grep ${devices}$ | awk '{print $10}')
RemoveRAID

if [[ $RaidOption == 'RAID in L1' ]]; then
    mdVolume="/dev/md0"
    CreateRAID0
    disks='md0'
fi

InstallDependencies
ImageName="nested.qcow2"
GetImageFiles -destination_image_name $ImageName -source_image_url $NestedImageUrl

#Prepare command for start nested kvm
cmd="qemu-system-x86_64 -machine pc-i440fx-2.0,accel=kvm -smp $NestedCpuNum -m $NestedMemMB -hda $ImageName -display none -device e1000,netdev=user.0 -netdev user,id=user.0,hostfwd=tcp::$HostFwdPort-:22 -enable-kvm -daemonize"
for disk in ${disks}
do
    echo "add disk /dev/${disk} to nested VM"
    cmd="${cmd} -drive id=datadisk-${disk},file=/dev/${disk},cache=none,if=none,format=raw,aio=threads -device virtio-scsi-pci -device scsi-hd,drive=datadisk-${disk}"
done

#Prepare nested kvm
StartNestedVM -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort $cmd
EnableRoot -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort
RebootNestedVM -user root -passwd $NestedUserPassword -port $HostFwdPort

#Run fio test
RunFIO

#Collect test logs
CollectLogs
StopNestedVMs
collect_VM_properties
UpdateTestState $ICA_TESTCOMPLETED