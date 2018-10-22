##############################################################################################
# UpdateNestedTestParameters.ps1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
<#
.SYNOPSIS
    Check new vhds from specific vendor's storage containers

.PARAMETER
    <Parameters>

.INPUTS


.NOTES
    Creation Date:  22th Oct 2018

.EXAMPLE

#>
###############################################################################################

param(
    [string]$ContainerStr= "",
    [string]$CheckTimeInterval= ""
)

$Containers = $ContainerStr.Split(';')

$xmlFile = "blobsXml.xml"
$configFile = "config.xml"
$newVhdsFile = "NewVHDs.xml"
$vhdCount = 0
$lastCheckTime = [DateTime]::Now.AddHours(-$CheckTimeInterval)

if (Test-Path $newVhdsFile)
{
    Remove-Item $newVhdsFile
}

if (Test-Path $xmlFile)
{
    Remove-Item $xmlFile
}

if (Test-Path $configFile)
{
    Remove-Item $configFile
}

$VhdInfoXml = New-Object -TypeName xml
$root = $VhdInfoXml.CreateElement("VHDInfo")
$VhdInfoXml.AppendChild($root)


foreach ($container in $Containers)
{
    ($DistroCategory, $Url) = $container.Split(',')
    if (-not $DistroCategory -or -not $Url)
    {
        continue
    }
    $DistroCategory = $DistroCategory.Trim()
    $Url = $Url.Trim()

    $listBlobUrl = $Url + "&restype=container&comp=list"

    if (Test-Path $xmlFile)
    {
        Remove-Item $xmlFile
    }

    $configFileUrl = $Url.Insert($Url.IndexOf('?'), "/$configFile")
    $mailReceviers = ""

    <# Get the file config.xml, which contains the infomation of distro image test configuration, e.g.extra mail receivers
     # Accepted config.xml format:
     # 1. <MailReceivers>someone1@where.com,someone2@where.com</MailReceivers>
     # 2. One of the <MailReceivers> and <LogContainer> tags should be present
     #    <Config>
     #        <ImageMatch>namepattern</ImageMatch>
     #        <MailReceivers>someone1@where.com,someone2@where.com</MailReceivers>
     #        <LogContainer>
     #            <ContainerName>testing-logs</ContainerName>
     #            <SASL_URL>the SAS URL (with write permission) of the container for us to write result to </SASL_URL>
     #        </LogContainer>
     #    </Config>
     #>
    Invoke-RestMethod $configFileUrl -Method Get -ErrorVariable restError -OutFile $configFile

    if ($?)
    {
        $configXml = [xml](Get-Content $configFile)
        if ($configXml.MailReceivers)
        {
            $mailReceviers = $configXml.MailReceivers
        }
        if ($configXml.Config)
        {
            if ($configXml.Config.ImageMatch)
            {
                $imageMatchRegex = $configXml.Config.ImageMatch
            }
            if ($configXml.Config.MailReceivers)
            {
                $mailReceviers = $configXml.Config.MailReceivers
            }
            if ($configXml.Config.LogContainer -and $configXml.Config.LogContainer.SASL_URL)
            {
                $logContainerSAS = $configXml.Config.LogContainer.SASL_URL
            }
        }
    }
    else {
        Write-Host "Error: Get config failed($($restError[0].Message)) for distro category $DistroCategory."
        continue
    }

    # Get the blob metadata
    Invoke-RestMethod $listBlobUrl -Headers @{"Accept"="Application/xml"} -ErrorVariable restError -OutFile $xmlFile

    if ($?)
    {
        $blobsXml = [xml](Get-Content $xmlFile)
        $latestVhdTime = $lastCheckTime

        $vhdUrls = @()
        foreach ($blob in $blobsXml.EnumerationResults.Blobs.Blob)
        {
            $timeStamp = [DateTime]::Parse($blob.Properties.'Last-Modified')
            $etag = $blob.Properties.Etag

            if (($timeStamp -gt $lastCheckTime) -and (($blob.Properties.BlobType.ToLower() -eq "pageblob") -or $blob.Name.EndsWith(".vhd")) -and (-not $blob.Name.ToLower().Contains("alpha")))
            {
                $srcUrl = $Url.Insert($Url.IndexOf('?'), '/' + $blob.Name)

                # Try get metadata the second time to check whether the VHD is in the progress of uploading. Etag value changes if the vhd is being uploaded.
                Start-Sleep -s 5
                Invoke-RestMethod $listBlobUrl -Headers @{"Accept"="Application/xml"} -ErrorVariable restError -OutFile $xmlFile

                if ($?)
                {
                    $blobsXml2 = [xml](Get-Content $xmlFile)
                    $isUploading = $false
                    foreach ($b in $blobsXml2.EnumerationResults.Blobs.Blob)
                    {
                        if ($b.Name -eq $blob.Name)
                        {
                            if ($b.Properties.Etag -ne $etag)
                            {
                                $isUploading = $true
                                break
                            }
                        }
                    }
                    if ($isUploading)
                    {
                        continue
                    }
                }
                else
                {
                    Write-Host "Error: Get blob data of distro category $DistroCategory failed($($restError[0].Message))."
                    continue
                }

                # for distros that specifies images match conditions 
                if($imageMatchRegex)
                {
                    # image name match with regex defined
                    if($blob.Name -match $imageMatchRegex)
                    {
                        $vhdUrls += $srcUrl
                    }
                }
                else
                {
                    $vhdUrls += $srcUrl
                }
            }
        }
        if ($vhdUrls.Count -gt 0)
        {
            $vhdCount += $vhdUrls.Count
            Write-Host "$vhdCount new VHD found in distro category $DistroCategory. Urls: $vhdUrls"
            $VhdNode = $VhdInfoXml.CreateElement("VHD")
            $root.AppendChild($VhdNode)
            $DistroCategoryNode = $VhdInfoXml.CreateElement("DistroCategory")
            $DistroCategoryNode.set_InnerXml($DistroCategory)
            $VhdNode.AppendChild($DistroCategoryNode)
            $MailReceiversNode = $VhdInfoXml.CreateElement("MailReceivers")
            $MailReceiversNode.set_InnerXml($mailReceviers)
            $VhdNode.AppendChild($MailReceiversNode)

            $UrlsNode = $VhdInfoXml.CreateElement("Urls")
            $VhdNode.AppendChild($UrlsNode)
            foreach ($vhdurl in $vhdUrls)
            {
                $UrlNode = $VhdInfoXml.CreateElement("Url")
                $UrlNode.set_InnerXml($vhdUrl.Replace('&','&amp;'))
                $UrlsNode.AppendChild($UrlNode)
            }
            if($logContainerSAS)
            {
                $LogContainerSASUrlNode = $VhdInfoXml.CreateElement("LogContainerSASUrl")
                $LogContainerSASUrlNode.set_InnerXml($logContainerSAS.Replace('&','&amp;'))
                $VhdNode.AppendChild($LogContainerSASUrlNode)
            }
        }
        else
        {
            Write-Host "No new VHD found of distro category $DistroCategory."
        }
    }
    else
    {
        Write-Host "Error: Get blob data failed($($restError[0].Message)) for distro category $DistroCategory."
    }
}

if ($vhdCount -gt 0)
{
    $VhdInfoXml.Save($newVhdsFile)
}



