#!/bin/bash

#######################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
#######################################################################

#######################################################################
#
# nested_kvm_perf_io.sh
#
# Description:
#   This script runs fio test on nested VMs with one or multiple data disk
#
#######################################################################

HOMEDIR="/root"
log_msg()
{
	echo "[$(date +"%x %r %Z")] ${1}"
	echo "[$(date +"%x %r %Z")] ${1}" >> "${HOMEDIR}/runlog.txt"
}
log_msg "Sleeping 10 seconds.."
sleep 10

#export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/oem/bin:/usr/share/oem/python/bin:/opt/bin
CONSTANTS_FILE="$HOMEDIR/constants.sh"
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occurred during the test
touch ./fioTest.log

if [ -e ${CONSTANTS_FILE} ]; then
	. ${CONSTANTS_FILE}
else
	errMsg="Error: missing ${CONSTANTS_FILE} file"
	log_msg "${errMsg}"
	update_test_state $ICA_TESTABORTED
	exit 10
fi


update_test_state()
{
	echo "${1}" > $HOMEDIR/state.txt
}

install_fio() {
	DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux\|clear-linux-os" /etc/{issue,*release,*version} /usr/lib/os-release`

	if [[ $DISTRO =~ "Ubuntu" ]] || [[ $DISTRO =~ "Debian" ]];
	then
		log_msg "Detected UBUNTU/Debian. Installing required packages"
		until dpkg --force-all --configure -a; sleep 10; do echo 'Trying again...'; done
		apt-get update
		apt-get install -y pciutils gawk mdadm
		apt-get install -y wget sysstat blktrace bc fio
		if [ $? -ne 0 ]; then
			log_msg "Error: Unable to install fio"
			update_test_state $ICA_TESTABORTED
			exit 1
		fi
		mount -t debugfs none /sys/kernel/debug
						
	elif [[ $DISTRO =~ "Red Hat Enterprise Linux Server release 6" ]];
	then
		log_msg "Detected RHEL 6.x; Installing required packages"
		rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
		yum -y --nogpgcheck install wget sysstat mdadm blktrace libaio fio
		mount -t debugfs none /sys/kernel/debug

	elif [[ $DISTRO =~ "Red Hat Enterprise Linux Server release 7" ]];
	then
		log_msg "Detected RHEL 7.x; Installing required packages"
		rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
		yum -y --nogpgcheck install wget sysstat mdadm blktrace libaio fio
		mount -t debugfs none /sys/kernel/debug
			
	elif [[ $DISTRO =~ "CentOS Linux release 6" ]] || [[ $DISTRO =~ "CentOS release 6" ]];
	then
		log_msg "Detected CentOS 6.x; Installing required packages"
		rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
		yum -y --nogpgcheck install wget sysstat mdadm blktrace libaio fio
		mount -t debugfs none /sys/kernel/debug
			
	elif [[ $DISTRO =~ "CentOS Linux release 7" ]];
	then
		log_msg "Detected CentOS 7.x; Installing required packages"
		rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
		yum -y --nogpgcheck install wget sysstat mdadm blktrace libaio fio
		mount -t debugfs none /sys/kernel/debug

	elif [[ $DISTRO =~ "SUSE Linux Enterprise Server 12" ]];
	then
		log_msg "Detected SLES12. Installing required packages"
		zypper addrepo http://download.opensuse.org/repositories/benchmark/SLE_12_SP3_Backports/benchmark.repo
		zypper --no-gpg-checks --non-interactive --gpg-auto-import-keys refresh
		zypper --no-gpg-checks --non-interactive --gpg-auto-import-keys remove gettext-runtime-mini-0.19.2-1.103.x86_64
		zypper --no-gpg-checks --non-interactive --gpg-auto-import-keys install sysstat
		zypper --no-gpg-checks --non-interactive --gpg-auto-import-keys install grub2
		zypper --no-gpg-checks --non-interactive --gpg-auto-import-keys install wget mdadm blktrace libaio1 fio
	elif [[ $DISTRO =~ "clear-linux-os" ]];
	then
		log_msg "Detected Clear Linux OS. Installing required packages"
		swupd bundle-add dev-utils-dev sysadmin-basic performance-tools os-testsuite-phoronix network-basic openssh-server dev-utils os-core os-core-dev

	else
			log_msg "Unknown Distro"
			update_test_state $ICA_TESTABORTED
			UpdateSummary "Unknown Distro, test aborted"
			return 1
	fi
}

run_fio()
{
	update_test_state $ICA_TESTRUNNING

	####################################
	#All run config set here
	#

	#Log Config
	
	mkdir $HOMEDIR/FIOLog/jsonLog
	mkdir $HOMEDIR/FIOLog/iostatLog
	mkdir $HOMEDIR/FIOLog/blktraceLog

	JSONFILELOG="${LOGDIR}/jsonLog"
	IOSTATLOGDIR="${LOGDIR}/iostatLog"
	BLKTRACELOGDIR="${LOGDIR}/blktraceLog"
	LOGFILE="${LOGDIR}/fio-test.log.txt"	

	#redirect blktrace files directory
	Resource_mount=$(mount -l | grep /sdb1 | awk '{print$3}')
	blk_base="${Resource_mount}/blk-$(date +"%m%d%Y-%H%M%S")"
	mkdir $blk_base
	#Test config
	iteration=0
	io_increment=128

	####################################
	echo "Test log created at: ${LOGFILE}"
	echo "===================================== Starting Run $(date +"%x %r %Z") ================================"
	echo "===================================== Starting Run $(date +"%x %r %Z") script generated 2/9/2015 4:24:44 PM ================================" >> $LOGFILE

	chmod 666 $LOGFILE
	echo "Preparing Files: $FILEIO"
	echo "Preparing Files: $FILEIO" >> $LOGFILE
	log_msg "Preparing Files: $FILEIO"
	# Remove any old files from prior runs (to be safe), then prepare a set of new files.
	rm fiodata
	echo "--- Kernel Version Information ---" >> $LOGFILE
	uname -a >> $LOGFILE
	cat /proc/version >> $LOGFILE
	cat /etc/*-release >> $LOGFILE
	echo "--- PCI Bus Information ---" >> $LOGFILE
	lspci >> $LOGFILE
	echo "--- Drive Mounting Information ---" >> $LOGFILE
	mount >> $LOGFILE
	echo "--- Disk Usage Before Generating New Files ---" >> $LOGFILE
	df -h >> $LOGFILE
	fio --cpuclock-test >> $LOGFILE
	fio $FILEIO --readwrite=read --bs=1M --runtime=1 --iodepth=128 --numjobs=8 --name=prepare
	echo "--- Disk Usage After Generating New Files ---" >> $LOGFILE
	df -h >> $LOGFILE
	echo "=== End Preparation  $(date +"%x %r %Z") ===" >> $LOGFILE
	log_msg "Preparing Files: $FILEIO: Finished."
	####################################
	#Trigger run from here
	for testmode in $modes; do
		io=$startIO
		while [ $io -le $maxIO ]
		do
			Thread=$startThread			
			while [ $Thread -le $maxThread ]
			do
				if [ $Thread -ge 8 ]
				then
					numjobs=8
				else
					numjobs=$Thread
				fi
				iostatfilename="${IOSTATLOGDIR}/iostat-fio-${testmode}-${io}K-${Thread}td.txt"
				nohup iostat -x 5 -t -y > $iostatfilename &
				echo "-- iteration ${iteration} ----------------------------- ${testmode} test, ${io}K bs, ${Thread} threads, ${numjobs} jobs, 5 minutes ------------------ $(date +"%x %r %Z") ---" >> $LOGFILE
				log_msg "Running ${testmode} test, ${io}K bs, ${Thread} threads ..."
				jsonfilename="${JSONFILELOG}/fio-result-${testmode}-${io}K-${Thread}td.json"
				fio $FILEIO --readwrite=$testmode --bs=${io}K --runtime=$ioruntime --iodepth=$Thread --numjobs=$numjobs --output-format=json --output=$jsonfilename --name="iteration"${iteration} >> $LOGFILE
				#fio $FILEIO --readwrite=$testmode --bs=${io}K --runtime=$ioruntime --iodepth=$Thread --numjobs=$numjobs --name="iteration"${iteration} --group_reporting >> $LOGFILE
				iostatPID=`ps -ef | awk '/iostat/ && !/awk/ { print $2 }'`
				kill -9 $iostatPID
				Thread=$(( Thread*2 ))		
				iteration=$(( iteration+1 ))
			done
		io=$(( io * io_increment ))
		done
	done
	####################################
	echo "===================================== Completed Run $(date +"%x %r %Z") script generated 2/9/2015 4:24:44 PM ================================" >> $LOGFILE
	rm fiodata

	compressedFileName="${HOMEDIR}/FIOTest-$(date +"%m%d%Y-%H%M%S").tar.gz"
	log_msg "INFO: Please wait...Compressing all results to ${compressedFileName}..."
	tar -cvzf $compressedFileName $LOGDIR/

	echo "Test logs are located at ${LOGDIR}"
	update_test_state $ICA_TESTCOMPLETED
}

remove_raid()
{
	disks=$(ls -l /dev | grep sd[b-z]$ | awk '{print $10}')

	log_msg "INFO: Check and remove RAID first"
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

create_raid0()
{
	disks=$(ls -l /dev | grep sd[b-z]$ | awk '{print $10}')	
	log_msg "INFO: Creating Partitions"
	count=0
	for disk in ${disks}
	do		
		echo "formatting disk /dev/${disk}"
		(echo d; echo n; echo p; echo 1; echo; echo; echo t; echo fd; echo w;) | fdisk /dev/${disk}
		count=$(( $count + 1 ))
		sleep 1
	done
	log_msg "INFO: Creating RAID of ${count} devices."
	sleep 1
	yes | mdadm --create ${mdVolume} --level 0 --raid-devices ${count} /dev/sd[b-z][1-5]
	sleep 1
	time mkfs -t $1 -F ${mdVolume}
	mkdir ${mountDir}
	sleep 1
	mount -o nobarrier ${mdVolume} ${mountDir}
	if [ $? -ne 0 ]; then
		update_test_state "$ICA_TESTFAILED"
		log_msg "Error: unable to mount ${mdVolume} to ${mountDir}"
		exit 1
	else
		log_msg "${mdVolume} mounted to ${mountDir} successfully."
	fi
}

mount_disk()
{
	time mkfs -t $1 -F /dev/${disk}
	mkdir ${mountDir}
	sleep 1
	mount -o nobarrier /dev/${disk} ${mountDir}
	if [ $? -ne 0 ]; then
		update_test_state "$ICA_TESTFAILED"
		log_msg "Error: Unable to mount ${disk} to ${mountDir}"
		exit 1
	else
		log_msg "${disk} mounted to ${mountDir} successfully."
	fi
}
############################################################
#	Main body
############################################################

HOMEDIR=$HOME
mv $HOMEDIR/FIOLog/ $HOMEDIR/FIOLog-$(date +"%m%d%Y-%H%M%S")/
mkdir $HOMEDIR/FIOLog
LOGDIR="${HOMEDIR}/FIOLog"
DISTRO=`grep -ihs "buntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux" /etc/{issue,*release,*version}`
if [[ $DISTRO =~ "SUSE Linux Enterprise Server 12" ]];
then
	mdVolume="/dev/md/mdauto0"
else
	mdVolume="/dev/md0"
fi

mountDir="/data"
cd ${HOMEDIR}

install_fio
remove_raid

disks=($(ls -l /dev | grep sd[b-z]$ | awk '{print $10}'))

#Skip to create RAID0 for single disk
if [ ${#disks[@]} -eq 1 ]; then
	disk=${disks[0]}
	mount_disk ext4
else
	if [[ $RaidOption == 'RAID in L2' ]]; then
		create_raid0 ext4
	fi
fi

#Run test from here
log_msg "*********INFO: Starting test execution*********"
if [[ $RaidOption == 'No RAID' && ${#disks[@]} -gt 1 ]]; then
	filename=''
	for disk in ${disks[@]}
	do
		if [[ $filename == '' ]]; then
			filename="/dev/${disk}"
		else
			filename="${filename}:/dev/${disk}"
		fi
	done
	FILEIO="--size=${fileSize} --direct=1 --ioengine=libaio --filename=${filename} --overwrite=1  "
else
	FILEIO="--size=${fileSize} --direct=1 --ioengine=libaio --filename=fiodata --overwrite=1  "
	cd ${mountDir}
fi
run_fio
log_msg "*********INFO: Script execution reach END. Completed !!!*********"