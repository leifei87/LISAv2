$result = ""
$CurrentTestResult = CreateTestResultObject
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{
		$testVMData = $allVMData
		ProvisionVMsForLisa -allVMData $allVMData -installPackagesOnRoleNames "none"
		LogMsg "Generating constansts.sh ..."
		$constantsFile = "$LogDir\constants.sh"
		Set-Content -Value "#Generated by Azure Automation." -Path $constantsFile
		foreach ( $param in $currentTestData.TestParameters.param)
		{
			Add-Content -Value "$param" -Path $constantsFile
			LogMsg "$param added to constants.sh"
			if ( $param -imatch "startThread" )
			{
				$startThread = [int]($param.Replace("startThread=",""))
			}
			if ( $param -imatch "maxThread" )
			{
				$maxThread = [int]($param.Replace("maxThread=",""))
			}
			if ( $param -imatch "NestedUser=" )
			{
				$NestedUser = $param.Replace("NestedUser=","")
			}
			if ( $param -imatch "NestedUserPassword" )
			{
				$NestedUserPassword = $param.Replace("NestedUserPassword=","")
			}
			if ( $param -imatch "HostFwdPort" )
			{
				$nestedKVMSSHPort = [int]($param.Replace("HostFwdPort=",""))
			}
		}
		Add-Content -Value "platform=$TestPlatform" -Path $constantsFile

		LogMsg "constanst.sh created successfully..."
		#endregion
		
		#region EXECUTE TEST
		$myString = @"
chmod +x nested_kvm_perf_fio.sh
./nested_kvm_perf_fio.sh &> fioConsoleLogs.txt
. azuremodules.sh
collect_VM_properties nested_properties.csv
"@

		$myString2 = @"
wget https://ciwestusv2.blob.core.windows.net/scriptfiles/JSON.awk
wget https://ciwestusv2.blob.core.windows.net/scriptfiles/gawk
wget https://ciwestusv2.blob.core.windows.net/scriptfiles/fio_jason_parser.sh
chmod +x *.sh
cp fio_jason_parser.sh gawk JSON.awk /root/FIOLog/jsonLog/
cd /root/FIOLog/jsonLog/
./fio_jason_parser.sh
cp perf_fio.csv /root
chmod 666 /root/perf_fio.csv
"@
		Set-Content "$LogDir\StartFioTest.sh" $myString
		Set-Content "$LogDir\ParseFioTestLogs.sh" $myString2		
		#endregion
		RemoteCopy -uploadTo $testVMData.PublicIP -port $testVMData.SSHPort -files $currentTestData.files -username $user -password $password -upload
		RemoteCopy -uploadTo $testVMData.PublicIP -port $testVMData.SSHPort -files "$constantsFile,.\$LogDir\StartFioTest.sh,.\$LogDir\ParseFioTestLogs.sh" -username $user -password $password -upload
		$out = RunLinuxCmd -ip $testVMData.PublicIP -port $testVMData.SSHPort -username $user -password $password -command "chmod +x *.sh" -runAsSudo
		LogMsg "Executing : $($currentTestData.testScript)"
        $testJob = RunLinuxCmd -ip $testVMData.PublicIP -port $testVMData.SSHPort -username $user -password $password -command "./$($currentTestData.testScript) > TestExecutionConsole.log" -runAsSudo -RunInBackground
		#region MONITOR TEST
		while ( (Get-Job -Id $testJob).State -eq "Running" )
		{
			$currentStatus = RunLinuxCmd -ip $testVMData.PublicIP -port $testVMData.SSHPort -username $user -password $password -command "cat state.txt"
			LogMsg "Current Test Staus : $currentStatus"
			WaitFor -seconds 20
		}
		#endregion
		RemoteCopy -downloadFrom $testVMData.PublicIP -port $testVMData.SSHPort -username $user -password $password -download -downloadTo $LogDir -files "/home/$user/state.txt, /home/$user/$($currentTestData.testScript).log, /home/$user/TestExecutionConsole.log"
		$finalStatus = Get-Content $LogDir\state.txt
		if ( $finalStatus -imatch "TestFailed")
		{
			LogErr "Test failed. Last known status : $currentStatus."
			$testResult = "FAIL"
		}
		elseif ( $finalStatus -imatch "TestAborted")
		{
			LogErr "Test Aborted. Last known status : $currentStatus."
			$testResult = "ABORTED"
		}
		elseif ( $finalStatus -imatch "TestCompleted")
		{
			$testResult = "PASS"
		}
		elseif ( $finalStatus -imatch "TestRunning")
		{
			LogMsg "Powershell backgroud job for test is completed but VM is reporting that test is still running. Please check $LogDir\TestExecutionConsole.txt"
			$testResult = "ABORTED"
		}		
		RemoteCopy -downloadFrom $testVMData.PublicIP -port $testVMData.SSHPort -username $user -password $password -download -downloadTo $LogDir -files "fioConsoleLogs.txt"
		$CurrentTestResult.TestSummary += CreateResultSummary -testResult $testResult -metaData "" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName		
        if ($testResult -imatch "PASS")
        {
			$remoteFiles = "FIOTest-*.tar.gz,perf_fio.csv,nested_properties.csv,VM_properties.csv,runlog.txt"
			RemoteCopy -downloadFrom $testVMData.PublicIP -port $testVMData.SSHPort -username $user -password $password -download -downloadTo $LogDir -files "$remoteFiles"
			try
				{
					foreach($line in (Get-Content "$LogDir\perf_fio.csv"))
					{
						if ( $line -imatch "Max IOPS of each mode" )
						{
							$maxIOPSforMode = $true
							$maxIOPSforBlockSize = $false
							$fioData = $false
						}
						if ( $line -imatch "Max IOPS of each BlockSize" )
						{
							$maxIOPSforMode = $false
							$maxIOPSforBlockSize = $true
							$fioData = $false
						}
						if ( $line -imatch "Iteration,TestType,BlockSize" )
						{
							$maxIOPSforMode = $false
							$maxIOPSforBlockSize = $false
							$fioData = $true
						}
						if ( $maxIOPSforMode )
						{
							Add-Content -Value $line -Path $LogDir\maxIOPSforMode.csv
						}
						if ( $maxIOPSforBlockSize )
						{
							Add-Content -Value $line -Path $LogDir\maxIOPSforBlockSize.csv
						}
						if ( $fioData )
						{
							Add-Content -Value $line -Path $LogDir\fioData.csv
						}
					}
					$maxIOPSforModeCsv = Import-Csv -Path $LogDir\maxIOPSforMode.csv
					$maxIOPSforBlockSizeCsv = Import-Csv -Path $LogDir\maxIOPSforBlockSize.csv
					$fioDataCsv = Import-Csv -Path $LogDir\fioData.csv


					LogMsg "Uploading the test results.."
					$dataSource = $xmlConfig.config.$TestPlatform.database.server
					$DBuser = $xmlConfig.config.$TestPlatform.database.user
					$DBpassword = $xmlConfig.config.$TestPlatform.database.password
					$database = $xmlConfig.config.$TestPlatform.database.dbname
					$dataTableName = $xmlConfig.config.$TestPlatform.database.dbtable
					$TestCaseName = $xmlConfig.config.$TestPlatform.database.testTag
					if ($dataSource -And $DBuser -And $DBpassword -And $database -And $dataTableName) 
					{
						$GuestDistro	= cat "$LogDir\VM_properties.csv" | Select-String "OS type"| %{$_ -replace ",OS type,",""}
						$HostType = $TestPlatform
						if ($TestPlatform -eq "hyperV")
						{
							$HostBy = $xmlConfig.config.Hyperv.Host.ServerName
							$HyperVMappedSizes = [xml](Get-Content .\XML\AzureVMSizeToHyperVMapping.xml)
							$L1GuestCpuNum = $HyperVMappedSizes.HyperV.$HyperVInstanceSize.NumberOfCores
							$L1GuestMemMB = [int]($HyperVMappedSizes.HyperV.$HyperVInstanceSize.MemoryInMB)
							$L1GuestSize = "$($L1GuestCpuNum)Cores $($L1GuestMemMB/1024)G"
						}
						else
						{
							$HostBy	= ($xmlConfig.config.$TestPlatform.General.Location).Replace('"','')						
							$L1GuestSize = $AllVMData.InstanceSize
						}
						$setupType = $currentTestData.setupType
						$count = 0
						foreach ($disk in $xmlConfig.config.$TestPlatform.Deployment.$setupType.ResourceGroup.VirtualMachine.DataDisk)
						{
							$disk_size = $disk.DiskSizeInGB
							$count ++
						}
						$DiskSetup = "$count SSD: $($disk_size)G"
						$HostOS	= cat "$LogDir\VM_properties.csv" | Select-String "Host Version"| %{$_ -replace ",Host Version,",""}
						# Get L1 guest info
						$L1GuestDistro	= cat "$LogDir\VM_properties.csv" | Select-String "OS type"| %{$_ -replace ",OS type,",""}
						$L1GuestOSType	= "Linux"
						$L1GuestKernelVersion	= cat "$LogDir\VM_properties.csv" | Select-String "Kernel version"| %{$_ -replace ",Kernel version,",""}

						# Get L2 guest info
						$L2GuestDistro	= cat "$LogDir\nested_properties.csv" | Select-String "OS type"| %{$_ -replace ",OS type,",""}
						$L2GuestKernelVersion	= cat "$LogDir\nested_properties.csv" | Select-String "Kernel version"| %{$_ -replace ",Kernel version,",""}
						foreach ( $param in $currentTestData.TestParameters.param)
						{
							if ($param -match "NestedCpuNum")
							{
								$L2GuestCpuNum = [int]($param.split("=")[1])
							}
							if ($param -match "NestedMemMB")
							{
								$L2GuestMemMB = [int]($param.split("=")[1])
							}
						}
						$connectionString = "Server=$dataSource;uid=$DBuser; pwd=$DBpassword;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
						
						$SQLQuery = "INSERT INTO $dataTableName (TestCaseName,TestDate,HostType,HostBy,HostOS,L1GuestOSType,L1GuestDistro,L1GuestSize,L1GuestKernelVersion,L2GuestDistro,L2GuestKernelVersion,L2GuestCpuNum,L2GuestMemMB,DiskSetup,BlockSize_KB,QDepth,seq_read_iops,seq_read_lat_usec,rand_read_iops,rand_read_lat_usec,seq_write_iops,seq_write_lat_usec,rand_write_iops,rand_write_lat_usec) VALUES "

						for ( $QDepth = $startThread; $QDepth -le $maxThread; $QDepth *= 2 ) 
						{
							$seq_read_iops = [Float](($fioDataCsv |  where { $_.TestType -eq "read" -and  $_.Threads -eq "$QDepth"} | Select ReadIOPS).ReadIOPS)
							$seq_read_lat_usec = [Float](($fioDataCsv |  where { $_.TestType -eq "read" -and  $_.Threads -eq "$QDepth"} | Select MaxOfReadMeanLatency).MaxOfReadMeanLatency)

							$rand_read_iops = [Float](($fioDataCsv |  where { $_.TestType -eq "randread" -and  $_.Threads -eq "$QDepth"} | Select ReadIOPS).ReadIOPS)
							$rand_read_lat_usec = [Float](($fioDataCsv |  where { $_.TestType -eq "randread" -and  $_.Threads -eq "$QDepth"} | Select MaxOfReadMeanLatency).MaxOfReadMeanLatency)
							
							$seq_write_iops = [Float](($fioDataCsv |  where { $_.TestType -eq "write" -and  $_.Threads -eq "$QDepth"} | Select WriteIOPS).WriteIOPS)
							$seq_write_lat_usec = [Float](($fioDataCsv |  where { $_.TestType -eq "write" -and  $_.Threads -eq "$QDepth"} | Select MaxOfWriteMeanLatency).MaxOfWriteMeanLatency)
							
							$rand_write_iops = [Float](($fioDataCsv |  where { $_.TestType -eq "randwrite" -and  $_.Threads -eq "$QDepth"} | Select WriteIOPS).WriteIOPS)
							$rand_write_lat_usec= [Float](($fioDataCsv |  where { $_.TestType -eq "randwrite" -and  $_.Threads -eq "$QDepth"} | Select MaxOfWriteMeanLatency).MaxOfWriteMeanLatency)

							$BlockSize_KB= [Int]((($fioDataCsv |  where { $_.Threads -eq "$QDepth"} | Select BlockSize)[0].BlockSize).Replace("K",""))
							
							$SQLQuery += "('$TestCaseName','$(Get-Date -Format yyyy-MM-dd)','$HostType','$HostBy','$HostOS','$L1GuestOSType','$L1GuestDistro','$L1GuestSize','$L1GuestKernelVersion','$L2GuestDistro','$L2GuestKernelVersion','$L2GuestCpuNum','$L2GuestMemMB','$DiskSetup','$BlockSize_KB','$QDepth','$seq_read_iops','$seq_read_lat_usec','$rand_read_iops','$rand_read_lat_usec','$seq_write_iops','$seq_write_lat_usec','$rand_write_iops','$rand_write_lat_usec'),"	
							LogMsg "Collected performace data for $QDepth QDepth."
						}

						$SQLQuery = $SQLQuery.TrimEnd(',')
						Write-Host $SQLQuery
						$connection = New-Object System.Data.SqlClient.SqlConnection
						$connection.ConnectionString = $connectionString
						$connection.Open()

						$command = $connection.CreateCommand()
						$command.CommandText = $SQLQuery
						
						$result = $command.executenonquery()
						$connection.Close()
						LogMsg "Uploading the test results done!!"
					}
					else
					{
						LogMsg "Invalid database details. Failed to upload result to database!"
					}
				
				}
				catch 
				{
					$ErrorMessage =  $_.Exception.Message
					LogErr "EXCEPTION : $ErrorMessage"
				}
		}
	}
	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = ""
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
        LogMsg "Test result : $testResult"
	}   
}

else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$CurrentTestResult.TestResult = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -CurrentTestResult $CurrentTestResult -testName $currentTestData.testName -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $CurrentTestResult