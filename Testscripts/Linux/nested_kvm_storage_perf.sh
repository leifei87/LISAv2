#!/bin/bash

#######################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
#######################################################################

#######################################################################
#
# nested_kvm_storage_single_disk.sh
# Author : Fei Lei
#
# Description:
#   This script runs fio test on nested VMs with one data disk
#
#######################################################################

. ./azuremodules.sh
. ./constants.sh

#HOW TO PARSE THE ARGUMENTS.. SOURCE - http://stackoverflow.com/questions/4882349/parsing-shell-script-arguments
while echo $1 | grep -q ^-; do
   declare $( echo $1 | sed 's/^-//' )=$2
   shift
   shift
done
ImageName="nested.qcow2"
#
# Constants/Globals
#
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occurred during the test


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

touch $logFolder/state.txt
touch $logFolder/`basename "$0"`.log

LogMsg()
{
    echo `date "+%b %d %Y %T"` : "$1" >> $logFolder/`basename "$0"`.log
}

UpdateTestState()
{
    echo "$1" > $logFolder/state.txt
}

InstallDependencies()
{
    update_repos
    install_package aria2
    install_package qemu-kvm
    lsmod | grep kvm_intel
    exit_status=$?
    if [ $exit_status -ne 0 ]; then
        LogMsg "Failed to install KVM"
        UpdateTestState $ICA_TESTFAILED
        exit 0
    else
        LogMsg "Install KVM succeed"
    fi
    distro=$(detect_linux_ditribution)
    if [ $distro == "centos" ] || [ $distro == "rhel" ] || [ $distro == "oracle" ]; then
        LogMsg "Install epel repository"
        install_epel
        LogMsg "Install qemu-system-x86"
        install_package qemu-system-x86
    fi
    which qemu-system-x86_64
    if [ $? -ne 0 ]; then
        LogMsg "Cannot find qemu-system-x86_64"
        UpdateTestState $ICA_TESTFAILED
        exit 0
    fi
}

GetImageFiles()
{
    LogMsg "Downloading $NestedImageUrl..."
    aria2c -o $ImageName -x 10 $NestedImageUrl
    #curl -o $ImageName $NestedImageUrl
    exit_status=$?
    if [ $exit_status -ne 0 ]; then
        LogMsg "Download image fail: $NestedImageUrl"
        UpdateTestState $ICA_TESTFAILED
        exit 0
    else
        LogMsg "Download image succeed"
    fi
}

CreateRAID0()
{	
    LogMsg "INFO: Check and remove RAID first"
    mdvol=$(cat /proc/mdstat | grep "active raid" | awk {'print $1'})
    if [ -n "$mdvol" ]; then
        echo "/dev/${mdvol} already exist...removing first"
        umount /dev/${mdvol}
        mdadm --stop /dev/${mdvol}
        mdadm --remove /dev/${mdvol}
        mdadm --zero-superblock /dev/${devices}[1-5]
    fi
	
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
    mdadm --create ${mdVolume} --level 0 --raid-devices ${count} /dev/${devices}[1-5]
    if [ $? -ne 0 ]; then
        LogMsg "Error: Unable to create raid"            
        exit 1
    else
        LogMsg "Create raid successfully."
    fi
}

StartNestedVM()
{
    LogMsg "Start the nested VM: $ImageName"
    cmd="qemu-system-x86_64 -machine pc-i440fx-2.0,accel=kvm -smp $NestedCpuNum -m $NestedMemMB -hda $ImageName -display none -device e1000,netdev=user.0 -netdev user,id=user.0,hostfwd=tcp::$HostFwdPort-:22 -enable-kvm -daemonize"
    for disk in ${disks}
    do
        LogMsg "add disk /dev/${disk} to nested VM"
        cmd="${cmd} -drive id=datadisk-${disk},file=/dev/${disk},cache=none,if=none,format=raw,aio=threads -device virtio-scsi-pci -device scsi-hd,drive=datadisk-${disk}"
    done
    LogMsg "Run command: $cmd"
    $cmd
    LogMsg "Wait for the nested VM to boot up ..."
    sleep 10
    retry_times=20
    exit_status=1
    while [ $exit_status -ne 0 ] && [ $retry_times -gt 0 ];
    do
        retry_times=$(expr $retry_times - 1)
        if [ $retry_times -eq 0 ]; then
            LogMsg "Timeout to connect to the nested VM"
            UpdateTestState $ICA_TESTFAILED
            exit 0
        else
            sleep 10
            LogMsg "Try to connect to the nested VM, left retry times: $retry_times"
            remote_copy -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort -filename ./enableRoot.sh -remote_path /home/$NestedUser -cmd put
            exit_status=$?
        fi
    done
    if [ $exit_status -ne 0 ]; then
        UpdateTestState $ICA_TESTFAILED
        exit 0
    fi
    remote_copy -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort -filename ./enablePasswordLessRoot.sh -remote_path /home/$NestedUser -cmd put
    remote_copy -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort -filename ./azuremodules.sh -remote_path /home/$NestedUser -cmd put
    remote_copy -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort -filename ./StartFioTest.sh -remote_path /home/$NestedUser -cmd put
    remote_copy -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort -filename ./constants.sh -remote_path /home/$NestedUser -cmd put
    remote_copy -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort -filename ./ParseFioTestLogs.sh -remote_path /home/$NestedUser -cmd put
    remote_copy -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort -filename ./nested_kvm_perf_fio.sh -remote_path /home/$NestedUser -cmd put

    remote_exec -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort "chmod a+x /home/$NestedUser/*.sh"
    remote_exec -host localhost -user $NestedUser -passwd $NestedUserPassword -port $HostFwdPort "echo $NestedUserPassword | sudo -S /home/$NestedUser/enableRoot.sh -password $NestedUserPassword"
    if [ $? -eq 0 ]; then
        LogMsg "Root enabled for VM: $image_name"
    else
        LogMsg "Failed to enable root for VM: $image_name"
        UpdateTestState $ICA_TESTFAILED
        exit 0
    fi
    remote_exec -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort "cp /home/$NestedUser/*.sh /root"	
}

RebootNestedVM()
{
    LogMsg "Reboot the nested VM"
    remote_exec -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort "reboot"
    LogMsg "Wait for the nested VM to boot up ..."
    sleep 30
    retry_times=20
    exit_status=1
    while [ $exit_status -ne 0 ] && [ $retry_times -gt 0 ];
    do
        retry_times=$(expr $retry_times - 1)
        if [ $retry_times -eq 0 ]; then
            LogMsg "Timeout to connect to the nested VM"
            UpdateTestState $ICA_TESTFAILED
            exit 0
        else
            sleep 10
            LogMsg "Try to connect to the nested VM, left retry times: $retry_times"
            remote_exec -host localhost -user root -passwd $NestedUserPassword -port $HostFwdPort "hostname"
            exit_status=$?
        fi
    done
    if [ $exit_status -ne 0 ]; then
        UpdateTestState $ICA_TESTFAILED
        exit 0
    fi
}

RunFIO()
{
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

StopNestedVMs()
{
    LogMsg "Stop the nested VMs"
    pid=$(pidof qemu-system-x86_64)
    if [ $? -eq 0 ]; then
        kill -9 $pid
    fi
}


if [[ $platform == 'HyperV' ]]; then
    devices='sd[b-z]'
else
    devices='sd[c-z]'
fi

disks=$(ls -l /dev | grep ${devices}$ | awk '{print $10}')

if [[ $RaidOption == 'RAID in L1' ]]; then
	mdVolume="/dev/md0"
	CreateRAID0
	disks='md0'
fi

UpdateTestState $ICA_TESTRUNNING
InstallDependencies
GetImageFiles
StartNestedVM
RebootNestedVM
RunFIO
CollectLogs
StopNestedVMs
collect_VM_properties
UpdateTestState $ICA_TESTCOMPLETED