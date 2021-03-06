<#
<copyright file="Begin-ImportScript-Lync.ps1" company="Microsoft">
	Copyright (c) Microsoft. All Rights Reserved.
	Licensed under the MIT license. See LICENSE.txt file in the project root for full license information.
</copyright>
<summary>
	The Begin-Import script for the Skype 2015 / Lync 2010 / 2013 Connector.
	Opens the RPS session and imports a set of Lync cmdlets into it.
</summary>
#>

[CmdletBinding()]
param(
	[parameter(Mandatory = $true)]
	[System.Collections.ObjectModel.KeyedCollection[string,Microsoft.MetadirectoryServices.ConfigParameter]]
	$ConfigParameters,
	[parameter(Mandatory = $true)]
	[Microsoft.MetadirectoryServices.Schema]
	$Schema,
	[parameter(Mandatory = $true)]
	[Microsoft.MetadirectoryServices.OpenImportConnectionRunStep]
	$OpenImportConnectionRunStep,
	[parameter(Mandatory = $true)]
	[Alias('PSCredential')] # To fix mess-up of the parameter name in the RTM version of the PowerShell connector.
	[System.Management.Automation.PSCredential]
	$Credential,
	[parameter(Mandatory = $false)]
	[ValidateScript({ Test-Path $_ -PathType "Container" })]
	[string]
	$ScriptDir = [Microsoft.MetadirectoryServices.MAUtils]::MAFolder # Optional parameter for manipulation by the TestHarness script.
)

Set-StrictMode -Version "2.0"

$commonModule = (Join-Path -Path $ScriptDir -ChildPath $ConfigParameters["Common Module Script Name (with extension)"].Value)

if (!(Get-Module -Name (Get-Item $commonModule).BaseName)) { Import-Module -Name $commonModule }

Enter-Script -ScriptType "Begin-Import" -ErrorObject $Error

function Get-OpenImportConnectionResults
{
	<#
	.Synopsis
		Gets the OpenImportConnectionResults object.
	.Description
		Gets the OpenImportConnectionResults object.
		The OpenImportConnectionResults object contains the watermark xml ot be used in the import script.
	#>
	
	[CmdletBinding()]
	[OutputType([System.Collections.Generic.List[Microsoft.MetadirectoryServices.OpenImportConnectionResults]])]
	param(
	)
	
	$watermark = Get-WaterMark

	$results = New-Object Microsoft.MetadirectoryServices.OpenImportConnectionResults($watermark.InnerXml)

	return $results
}

function Get-WaterMark
{
	<#
	.Synopsis
		Gets the WaterMark XML.
	.Description
		Gets the WaterMark XML.
	#>
	
	[CmdletBinding()]
    [OutputType([xml])]
	param(
	)
	
	$waterMarkXml = $null

	if (!$deltaImport -or [string]::IsNullOrEmpty($OpenImportConnectionRunStep.CustomData))
	{
		$waterMarkXml = "<WaterMark>"
		$waterMarkXml += "<CurrentPageIndex>0</CurrentPageIndex>"

		foreach ($type in $Schema.Types)
		{
			$waterMarkXml += "<{0}><MoreToImport>1</MoreToImport></{0}>" -f $type.Name
		}

		$waterMarkXml += "<PreferredDomainController>{0}</PreferredDomainController>" -f $preferredDomainController
		$waterMarkXml += "<LastRunDateTime></LastRunDateTime>"
		$waterMarkXml += "</WaterMark>"

		$waterMark = [xml]$waterMarkXml
	}
	else
	{
		$waterMark = [xml]$OpenImportConnectionRunStep.CustomData

		if ($waterMark -eq $null -or $waterMark.WaterMark -eq $null)
		{
			throw ("Invalid Watermark. Please run Full Import first.")
		}

		$waterMark.WaterMark.CurrentPageIndex = "0"
		
		foreach ($type in $Schema.Types)
		{
			$waterMark.WaterMark.($type.Name).MoreToImport = "1"
		}
	}

	Write-Debug ("Watermark initialized to: {0}" -f $waterMark.InnerXml)

	return $waterMark
}

$fullObjectImport  = $OpenImportConnectionRunStep.ImportType -eq "FullObject"
if ($fullObjectImport)
{
	throw ("Operation Type {0} Import is not supported" -f $OpenImportConnectionRunStep.ImportType)
}

$fullImport = $OpenImportConnectionRunStep.ImportType -eq "Full"
$deltaImport = $OpenImportConnectionRunStep.ImportType -eq "Delta"

$server = Get-ConfigParameter -ConfigParameters $ConfigParameters -ParameterName "Server"
$preferredDomainController = Get-ConfigParameter -ConfigParameters $ConfigParameters -ParameterName "PreferredDomainControllerFQDN"

if (![string]::IsNullOrEmpty($preferredDomainController))
{
	$preferredDomainController = Select-PreferredDomainController -DomainControllerList $preferredDomainController
}

$session = Get-PSSession -Name $Global:RemoteSessionName -ErrorAction "SilentlyContinue"
$Error.Clear() # Could use -ErrorAction "Igonre" in PSH v3.0

if (!$session)
{
	Write-Debug "Opening a new RPS Session."

	$skipCertificate = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
	$session = New-PSSession -ConnectionUri $server -Credential $Credential -SessionOption $skipCertificate -Name $Global:RemoteSessionName
	$Global:Session = $session
	$lyncCommands = "Get-CsUser", "Get-CsAdUser"
	Import-PSSession $Global:Session -CommandName $lyncCommands | Out-Null

	Write-Debug "Opened a new RPS Session."
}

Get-OpenImportConnectionResults

$exceptionRaisedOnErrorCheck = [Microsoft.MetadirectoryServices.ServerDownException]
Exit-Script -ScriptType "Begin-Import" -ExceptionRaisedOnErrorCheck $exceptionRaisedOnErrorCheck -ErrorObject $Error

