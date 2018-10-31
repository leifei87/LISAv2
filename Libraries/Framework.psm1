##############################################################################################
# Framework.psm1
# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
# Description : Pipeline framework modules.
# Operations :
#              
## Author : lisasupport@microsoft.com
###############################################################################################
function GetTestSummary($testCycle, [DateTime] $StartTime, [string] $xmlFilename, [string] $distro, $testSuiteResultDetails)
{
    <#
	.Synopsis
    	Append the summary text from each VM into a single string.
        
    .Description
        Append the summary text from each VM one long string. The
        string includes line breaks so it can be display on a 
        console or included in an e-mail message.
        
	.Parameter xmlConfig
    	The parsed xml from the $xmlFilename file.
        Type : [System.Xml]

    .Parameter startTime
        The date/time the ICA test run was started
        Type : [DateTime]

    .Parameter xmlFilename
        The name of the xml file for the current test run.
        Type : [String]
        
    .ReturnValue
        A string containing all the summary message from all
        VMs in the current test run.
        
    .Example
        GetTestSummary $testCycle $myStartTime $myXmlTestFile
	
#>
    
	$endTime = [Datetime]::Now.ToUniversalTime()
	$testSuiteRunDuration= $endTime - $StartTime    
	$testSuiteRunDuration=$testSuiteRunDuration.Days.ToString() + ":" +  $testSuiteRunDuration.hours.ToString() + ":" + $testSuiteRunDuration.minutes.ToString()
    $str = "<br />Test Results Summary<br />"
    $str += "ICA test run on " + $startTime
    if ( $BaseOsImage )
    {
        $str += "<br />Image under test " + $BaseOsImage
    }
    if ( $BaseOSVHD )
    {
        $str += "<br />VHD under test " + $BaseOSVHD
    }
    if ( $ARMImage.Publisher )
    {
        $str += "<br />ARM Image under test " + "$($ARMImage.Publisher) : $($ARMImage.Offer) : $($ARMImage.Sku) : $($ARMImage.Version)"
    }
	$str += "<br />Total Executed TestCases " + $testSuiteResultDetails.totalTc + " (" + $testSuiteResultDetails.totalPassTc + " Pass" + ", " + $testSuiteResultDetails.totalFailTc + " Fail" + ", " + $testSuiteResultDetails.totalAbortedTc + " Abort)"
	$str += "<br />Total Execution Time(dd:hh:mm) " + $testSuiteRunDuration.ToString()
    $str += "<br />XML file: $xmlFilename<br /><br />"
	        
    # Add information about the host running ICA to the e-mail summary
    $str += "<pre>"
    $str += $testCycle.emailSummary + "<br />"
    $hostName = hostname
    $str += "<br />Logs can be found at $LogDir" + "<br /><br />"
    $str += "</pre>"
    $plainTextSummary = $str
    $strHtml =  '
<STYLE>
BODY, TABLE, TD, TH, P {
  font-family:Verdana,Helvetica,sans serif;
  font-size:11px;
  color:black;
}
TD.bg1 { color:white; background-color:#0000C0; font-size:180% }
TD.bg2 { color:black; font-size:130% }
TD.bg3 { color:black; font-size:110% }
.TFtable{width:1024px; border-collapse:collapse; }
.TFtable td{ padding:7px; border:#4e95f4 1px solid;}
.TFtable tr{ background: #b8d1f3;}
.TFtable tr:nth-child(odd){ background: #dbe1e9;}
.TFtable tr:nth-child(even){background: #ffffff;}
</STYLE>
<table>
<TR><TD class="bg1" colspan="2"><B>Test Results Summary</B></TD></TR>
</table>
<BR/>
'

    if ( $BaseOsImage )
    {
        $strHtml += "
<table>
<TR><TD class=`"bg2`" colspan=`"2`"><B>ICA test run on - $startTime</B></TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">Build URL: <A href=`"${BUILD_URL}`">${BUILD_URL}</A></TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">Image under test - $BaseOsImage</TD></TR>
</table>
<BR/>
"
    }
    if ( $BaseOSVHD )
    {
        $strHtml += "
<table>
<TR><TD class=`"bg2`" colspan=`"2`"><B>ICA test run on - $startTime</B></TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">Build URL: <A href=`"${BUILD_URL}`">${BUILD_URL}</A></TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">VHD under test - $BaseOsVHD</TD></TR>
</table>
<BR/>
"
    }
    if ( $ARMImage.Publisher )
    {
        $strHtml += "
<table>
<TR><TD class=`"bg2`" colspan=`"2`"><B>ICA test run on - $startTime</B></TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">Build URL: <A href=`"${BUILD_URL}`">${BUILD_URL}</A></TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">ARM Image under test - $($ARMImage.Publisher) : $($ARMImage.Offer) : $($ARMImage.Sku) : $($ARMImage.Version)</TD></TR>
</table>
<BR/>
"
    }
	$strHtml += "
<table>
<TR><TD class=`"bg3`" colspan=`"2`">Total Executed TestCases - $($testSuiteResultDetails.totalTc)</TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">[&nbsp;<span><span style=`"color:#008000;`"><strong>$($testSuiteResultDetails.totalPassTc)</strong></span></span> - PASS, <span ><span style=`"color:#ff0000;`"><strong>$($testSuiteResultDetails.totalFailTc)</strong></span></span> - FAIL, <span><span style=`"color:#ff0000;`"><strong><span style=`"background-color:#ffff00;`">$($testSuiteResultDetails.totalAbortedTc)</span></strong></span></span> - ABORTED ]</TD></TR>
<TR><TD class=`"bg3`" colspan=`"2`">Total Execution Time(dd:hh:mm) $($testSuiteRunDuration.ToString())</TD></TR>
</table>
<BR/>
"

    # Add information about the host running ICA to the e-mail summary
    $strHtml += "
<table border='0' class='TFtable'>
$($testCycle.htmlSummary)
</table>
"

    if (-not (Test-Path(".\temp\CI"))) {
        mkdir ".\temp\CI" | Out-Null 
    }

	Set-Content ".\temp\CI\index.html" $strHtml
	return $plainTextSummary, $strHtml
}

function SendEmail([XML] $xmlConfig, $body)
{
    <#
	.Synopsis
    	Send an e-mail message with test summary information.
        
    .Description
        Collect the test summary information from each testcycle.  Send an
        eMail message with this summary information to emailList defined
        in the xml config file.
        
	.Parameter xmlConfig
    	The parsed XML from the test xml file
        Type : [System.Xml]
        
    .ReturnValue
        none
        
    .Example
        SendEmail $myConfig
	#>

    $to = $xmlConfig.config.global.emailList.split(",")
    $from = $xmlConfig.config.global.emailSender
    $subject = $xmlConfig.config.global.emailSubject + " " + $testStartTime
    $smtpServer = $xmlConfig.config.global.smtpServer
    $fname = [System.IO.Path]::GetFilenameWithoutExtension($xmlConfigFile)
    # Highlight the failed tests 
    $body = $body.Replace("Aborted", '<em style="background:Yellow; color:Red">Aborted</em>')
    $body = $body.Replace("FAIL", '<em style="background:Yellow; color:Red">Failed</em>')
    
	Send-mailMessage -to $to -from $from -subject $subject -body $body -smtpserver $smtpServer -BodyAsHtml
}

function Usage()
{
    write-host
    write-host "  Start automation: AzureAutomationManager.ps1 -xmlConfigFile <xmlConfigFile> -runTests -email -Distro <DistroName> -cycleName <TestCycle>"
    write-host
    write-host "         xmlConfigFile : Specifies the configuration for the test environment."
    write-host "         DistroName    : Run tests on the distribution OS image defined in Azure->Deployment->Data->Distro"
    write-host "         -help         : Displays this help message."
    write-host
}
Function GetCurrentCycleData($xmlConfig, $cycleName)
{
    foreach ($Cycle in $xmlConfig.config.testCycles.Cycle )
    {
        if($cycle.cycleName -eq $cycleName)
        {
        return $cycle
        break
        }
    }
    
}
Function ThrowException($Exception)
{
    $line = $Exception.InvocationInfo.ScriptLineNumber
    $script_name = ($Exception.InvocationInfo.ScriptName).Replace($PWD,".")
    $ErrorMessage =  $Exception.Exception.Message
    Write-Host "EXCEPTION : $ErrorMessage"
    Write-Host "SOURCE : Line $line in script $script_name."
    Throw "Calling function - $($MyInvocation.MyCommand)"
}

<#
JUnit XML Report Schema:
	http://windyroad.com.au/dl/Open%20Source/JUnit.xsd
Example:
	Import-Module .\UtilLibs.psm1 -Force

	StartLogReport("$pwd/report.xml")

	$testsuite = StartLogTestSuite "CloudTesting"

	$testcase = StartLogTestCase $testsuite "BVT" "CloudTesting.BVT"
	FinishLogTestCase $testcase

	$testcase = StartLogTestCase $testsuite "NETWORK" "CloudTesting.NETWORK"
	FinishLogTestCase $testcase "FAIL" "NETWORK fail" "Stack trace: XXX"

	$testcase = StartLogTestCase $testsuite "VNET" "CloudTesting.VNET"
	FinishLogTestCase $testcase "ERROR" "VNET error" "Stack trace: XXX"

	FinishLogTestSuite($testsuite)

	$testsuite = StartLogTestSuite "FCTesting"

	$testcase = StartLogTestCase $testsuite "BVT" "FCTesting.BVT"
	FinishLogTestCase $testcase

	$testcase = StartLogTestCase $testsuite "NEGATIVE" "FCTesting.NEGATIVE"
	FinishLogTestCase $testcase "FAIL" "NEGATIVE fail" "Stack trace: XXX"

	FinishLogTestSuite($testsuite)

	FinishLogReport

report.xml:
	<testsuites>
	  <testsuite name="CloudTesting" timestamp="2014-07-11T06:37:24" tests="3" failures="1" errors="1" time="0.04">
		<testcase name="BVT" classname="CloudTesting.BVT" time="0" />
		<testcase name="NETWORK" classname="CloudTesting.NETWORK" time="0">
		  <failure message="NETWORK fail">Stack trace: XXX</failure>
		</testcase>
		<testcase name="VNET" classname="CloudTesting.VNET" time="0">
		  <error message="VNET error">Stack trace: XXX</error>
		</testcase>
	  </testsuite>
	  <testsuite name="FCTesting" timestamp="2014-07-11T06:37:24" tests="2" failures="1" errors="0" time="0.03">
		<testcase name="BVT" classname="FCTesting.BVT" time="0" />
		<testcase name="NEGATIVE" classname="FCTesting.NEGATIVE" time="0">
		  <failure message="NEGATIVE fail">Stack trace: XXX</failure>
		</testcase>
	  </testsuite>
	</testsuites>
#>

[xml]$junitReport = $null
[object]$reportRootNode = $null
[string]$junitReportPath = ""
[bool]$isGenerateJunitReport=$False

Function StartLogReport([string]$reportPath)
{
	if(!$junitReport)
	{
		$global:junitReport = new-object System.Xml.XmlDocument
		$newElement = $global:junitReport.CreateElement("testsuites")
		$global:reportRootNode = $global:junitReport.AppendChild($newElement)
		
		$global:junitReportPath = $reportPath
		
		$global:isGenerateJunitReport = $True
	}
	else
	{
		throw "CI report has been created."
	}
	
	return $junitReport
}

Function FinishLogReport([bool]$isFinal=$True)
{
	if(!$global:isGenerateJunitReport)
	{
		return
	}
	
	$global:junitReport.Save($global:junitReportPath)
	if($isFinal)
	{
		$global:junitReport = $null
		$global:reportRootNode = $null
		$global:junitReportPath = ""
		$global:isGenerateJunitReport=$False
	}
}

Function StartLogTestSuite([string]$testsuiteName)
{
	if(!$global:isGenerateJunitReport)
	{
		return
	}
	
	$newElement = $global:junitReport.CreateElement("testsuite")
	$newElement.SetAttribute("name", $testsuiteName)
	$newElement.SetAttribute("timestamp", [Datetime]::Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss"))
	$newElement.SetAttribute("tests", 0)
	$newElement.SetAttribute("failures", 0)
	$newElement.SetAttribute("errors", 0)
	$newElement.SetAttribute("time", 0)
	$testsuiteNode = $global:reportRootNode.AppendChild($newElement)
	
	$timer = CIStartTimer
	$testsuite = New-Object -TypeName PSObject
	Add-Member -InputObject $testsuite -MemberType NoteProperty -Name testsuiteNode -Value $testsuiteNode -Force
	Add-Member -InputObject $testsuite -MemberType NoteProperty -Name timer -Value $timer -Force
	
	return $testsuite
}

Function FinishLogTestSuite([object]$testsuite)
{
	if(!$global:isGenerateJunitReport)
	{
		return
	}
	
	$testsuite.testsuiteNode.Attributes["time"].Value = CIStopTimer $testsuite.timer
	FinishLogReport $False
}

Function StartLogTestCase([object]$testsuite, [string]$caseName, [string]$className)
{
	if(!$global:isGenerateJunitReport)
	{
		return
	}
	
	$newElement = $global:junitReport.CreateElement("testcase")
	$newElement.SetAttribute("name", $caseName)
	$newElement.SetAttribute("classname", $classname)
	$newElement.SetAttribute("time", 0)
	
	$testcaseNode = $testsuite.testsuiteNode.AppendChild($newElement)
	
	$timer = CIStartTimer
	$testcase = New-Object -TypeName PSObject
	Add-Member -InputObject $testcase -MemberType NoteProperty -Name testsuite -Value $testsuite -Force
	Add-Member -InputObject $testcase -MemberType NoteProperty -Name testcaseNode -Value $testcaseNode -Force
	Add-Member -InputObject $testcase -MemberType NoteProperty -Name timer -Value $timer -Force
	return $testcase
}

Function FinishLogTestCase([object]$testcase, [string]$result="PASS", [string]$message="", [string]$detail="")
{
	if(!$global:isGenerateJunitReport)
	{
		return
	}
	
	$testcase.testcaseNode.Attributes["time"].Value = CIStopTimer $testcase.timer
	
	[int]$testcase.testsuite.testsuiteNode.Attributes["tests"].Value += 1
	if ($result -eq "FAIL")
	{
		$newChildElement = $global:junitReport.CreateElement("failure")
		$newChildElement.InnerText = $detail
		$newChildElement.SetAttribute("message", $message)
		$testcase.testcaseNode.AppendChild($newChildElement)
		
		[int]$testcase.testsuite.testsuiteNode.Attributes["failures"].Value += 1
	}
	
	if ($result -eq "ERROR")
	{
		$newChildElement = $global:junitReport.CreateElement("error")
		$newChildElement.InnerText = $detail
		$newChildElement.SetAttribute("message", $message)
		$testcase.testcaseNode.AppendChild($newChildElement)
		
		[int]$testcase.testsuite.testsuiteNode.Attributes["errors"].Value += 1
	}
	FinishLogReport $False
}

Function CIStartTimer()
{
	$timer = [system.diagnostics.stopwatch]::startNew()
	return $timer
}

Function CIStopTimer([System.Diagnostics.Stopwatch]$timer)
{
	$timer.Stop()
	return [System.Math]::Round($timer.Elapsed.TotalSeconds, 2)

}

Function AddReproVMDetailsToHtmlReport()
{
	$reproVMHtmlText += "<br><font size=`"2`"><em>Repro VMs: </em></font>"
	if ( $UserAzureResourceManager )
	{
		foreach ( $vm in $allVMData )
		{
			$reproVMHtmlText += "<br><font size=`"2`">ResourceGroup : $($vm.ResourceGroup), IP : $($vm.PublicIP), SSH : $($vm.SSHPort)</font>"
		}
	}
	else
	{
		foreach ( $vm in $allVMData )
		{
			$reproVMHtmlText += "<br><font size=`"2`">ServiceName : $($vm.ServiceName), IP : $($vm.PublicIP), SSH : $($vm.SSHPort)</font>"
		}
	}
	return $reproVMHtmlText
}

Function GetCurrentCycleData($xmlConfig, $cycleName)
{
	foreach ($Cycle in $xmlConfig.config.testCycles.Cycle )
	{
		if($cycle.cycleName -eq $cycleName)
		{
		return $cycle
		break
		}
	}

}

Function GetCurrentTestData($xmlConfig, $testName)
{
	foreach ($test in $xmlConfig.config.testsDefinition.test)
	{
		if ($test.testName -eq $testName)
		{
		LogMsg "Loading the test data for $($test.testName)"
		Set-Variable -Name CurrentTestData -Value $test -Scope Global -Force
		return $test
		break
		}
	}
}

Function RefineTestResult2 ($testResult)
{
	$i=0
	$tempResult = @()
	foreach ($cmp in $testResult)
	{
		if(($cmp -eq "PASS") -or ($cmp -eq "FAIL") -or ($cmp -eq "ABORTED"))
		{
			$tempResult += $testResult[$i]
			$tempResult += $testResult[$i+1]
			$testResult = $tempResult
			break
		}
		$i++;
	}
	return $testResult
}

Function RefineTestResult1 ($tempResult)
{
	foreach ($new in $tempResult)
	{
		$lastObject = $new
	}
	$tempResultSplitted = $lastObject.Split(" ")
	if($tempResultSplitted.Length > 1 )
	{
		Write-Host "Test Result =  $lastObject" -ForegroundColor Gray
	}
	$lastWord = ($tempResultSplitted.Length - 1)

	return $tempResultSplitted[$lastWord]
}

Function ValidateVHD($vhdPath)
{
    try
    {
        $tempVHDName = Split-Path $vhdPath -leaf
        LogMsg "Inspecting '$tempVHDName'. Please wait..."
        $VHDInfo = Get-VHD -Path $vhdPath -ErrorAction Stop
        LogMsg "  VhdFormat            :$($VHDInfo.VhdFormat)"
        LogMsg "  VhdType              :$($VHDInfo.VhdType)"
        LogMsg "  FileSize             :$($VHDInfo.FileSize)"
        LogMsg "  Size                 :$($VHDInfo.Size)"
        LogMsg "  LogicalSectorSize    :$($VHDInfo.LogicalSectorSize)"
        LogMsg "  PhysicalSectorSize   :$($VHDInfo.PhysicalSectorSize)"
        LogMsg "  BlockSize            :$($VHDInfo.BlockSize)"
        LogMsg "Validation successful."
    }
    catch
    {
        LogMsg "Failed: Get-VHD -Path $vhdPath"
        Throw "INVALID_VHD_EXCEPTION"
    }
}

Function ValidateMD5($filePath, $expectedMD5hash)
{
    LogMsg "Expected MD5 hash for $filePath : $($expectedMD5hash.ToUpper())"
    $hash = Get-FileHash -Path $filePath -Algorithm MD5
    LogMsg "Calculated MD5 hash for $filePath : $($hash.Hash.ToUpper())"
    if ($hash.Hash.ToUpper() -eq  $expectedMD5hash.ToUpper())
    {
        LogMsg "MD5 checksum verified successfully."
    }
    else
    {
        Throw "MD5 checksum verification failed."
    }
}

Function Test-FileLock 
{
	param 
	(
	  [parameter(Mandatory=$true)][string]$Path
	)
	$File = New-Object System.IO.FileInfo $Path
	if ((Test-Path -Path $Path) -eq $false) 
	{
		return $false
	}
	try 
	{
		$oStream = $File.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
		if ($oStream) 
		{
			$oStream.Close()
		}
		return $false
	} 
	catch 
	{
		# file is locked by a process.
		return $true
	}
}