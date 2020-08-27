function Install-EventSubscription
{
<#
	.SYNOPSIS
		Installs a powershell task that triggers off a windows eventlog event.
	
	.DESCRIPTION
		Installs a powershell task that triggers off a windows eventlog event.
		The code is deployed to the target machine and will run locally on that machine when triggered.
		
		The scriptblock or scriptfile receives one input object:
		The eventlog event object as returned by Get-WinEvent.
		If the scriptblock/-file does not have a parameter block yet, one will be created with the paraneter "$EventObject", which can be used in the code.
	
		This command does not implement dependency handling:
		Required modules must be installed separately on the target computer(s) if any are needed.
	
	.PARAMETER SubscriptionName
		Name of the subscription.
		Value is arbitrary, but must be unique and legal as a filename.
		This will be the name of the task, so no duplicates possible.
		Will overwrite an existing task of that name.
	
	.PARAMETER ScriptPath
		Path to the scriptfile to execute.
		Will be copied to the machine.
	
	.PARAMETER ScriptCode
		A scriptblock to execute.
		Will be written as file on the target system.
	
	.PARAMETER LogName
		The name of the log to monitor for events.
	
	.PARAMETER Source
		The name of the source off which to trigger tasks.
	
	.PARAMETER EventID
		The ID of the event that will trigger the task.
	
	.PARAMETER SubscriptionXML
		Rather than offering LogName, Source and EventID, you can offer a filter XML instead.
		This allows more granular filtering.
		To generate filter XML, the easiest way to set things up is to use the eventviewer MMC console:
		- Use the UI wizard to create a filter
		- When done, switch to the XML tab in the filter UI: That's the XML needed for this parameter.
	
	.PARAMETER Description
		Description to include in the scheduled task.
	
	.PARAMETER ComputerName
		The name of the computers to install the task on.
		Defaults to localhost.
	
	.PARAMETER Credential
		The credentials to use when connecting to the target system.
		NOT the account under which the event will trigger.
	
	.PARAMETER Elevated
		Whether the task should trigger with elevation.
	
	.PARAMETER Identity
		The user account under which the event should trigger.
		NOT the account used to create the scheduled task.
		Defaults to: SYSTEM
		Only specify a password if the account is a regular user account requiring one.
		Builtin accounts or gMSA do not require a password.
	
	.PARAMETER Executable
		Which executable should be used to execute the task.
		Defaults to powershell.exe
		Use "pwsh.exe" if you want the task to execute under PowerShell core (requires PowerShell Core to be installed on the target computer).
	
	.PARAMETER Author
		The Author listed in the Task Scheduler MMC console.
		Defaults to the current user.
	
	.PARAMETER EnableException
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.EXAMPLE
		PS C:\> Install-EventSubscription -SubscriptionName 'Account Lockout' -ScriptPath '.\lockout.ps1' -LogName 'Security' -Source 'Microsoft-Windows-Security-Auditing' -EventID 4740
	
		Registers the script lockout.ps1 to be executed every time an account gets locked out.
#>
	[CmdletBinding(DefaultParameterSetName = 'dataPath')]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$SubscriptionName,
		
		[Parameter(Mandatory = $true, ParameterSetName = 'dataPath')]
		[Parameter(Mandatory = $true, ParameterSetName = 'xmlPath')]
		[PsfValidateScript({ Test-Path $_ }, ErrorMessage = 'Path does not exist: {0}')]
		[string]
		$ScriptPath,
		
		[Parameter(Mandatory = $true, ParameterSetName = 'dataCode')]
		[Parameter(Mandatory = $true, ParameterSetName = 'xmlCode')]
		[scriptblock]
		$ScriptCode,
		
		[Parameter(Mandatory = $true, ParameterSetName = 'dataPath')]
		[Parameter(Mandatory = $true, ParameterSetName = 'dataCode')]
		[string]
		$LogName,
		
		[Parameter(Mandatory = $true, ParameterSetName = 'dataPath')]
		[Parameter(Mandatory = $true, ParameterSetName = 'dataCode')]
		[string]
		$Source,
		
		[Parameter(Mandatory = $true, ParameterSetName = 'dataPath')]
		[Parameter(Mandatory = $true, ParameterSetName = 'dataCode')]
		[int]
		$EventID,
		
		[Parameter(Mandatory = $true, ParameterSetName = 'xmlPath')]
		[Parameter(Mandatory = $true, ParameterSetName = 'xmlCode')]
		[string]
		$SubscriptionXML,
		
		[string]
		$Description,
		
		[Parameter(ValueFromPipeline = $true)]
		[PSFComputer[]]
		$ComputerName = $env:COMPUTERNAME,
		
		[PSCredential]
		$Credential,
		
		[switch]
		$Elevated,
		
		[PSCredential]
		$Identity,
		
		[string]
		$Executable = 'powershell.exe',
		
		[string]
		$Author = $env:USERNAME,
		
		[switch]
		$EnableException
	)
	
	begin
	{
		#region Resolve Task XML
		$registrationXML = @'
  <RegistrationInfo>
    <Author>{0}</Author>
    <Description>{1}</Description>
  </RegistrationInfo>
'@ -f $Author, $Description
		
		$filterXML = @"
<QueryList>
	<Query Id="0" Path="$LogName">
		<Select Path="$LogName">*[System[Provider[@Name='$Source'] and EventID=$EventID]]</Select>
	</Query>
</QueryList>
"@
		if ($SubscriptionXML) { $filterXML = $SubscriptionXML }
		$subscriptionText = ($filterXML -split "`n" -replace '>', '&gt;' -replace '<', '&lt;' | ForEach-Object { $_.Trim() }) -join ""
		
		$triggerXML = @'
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>{0}</Subscription>
      <ValueQueries>
        <Value name="Channel">Event/System/Channel</Value>
        <Value name="EventRecordID">Event/System/EventRecordID</Value>
      </ValueQueries>
    </EventTrigger>
  </Triggers>
'@ -f $subscriptionText
		
		$settingsXML = @'
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>false</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT8H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
'@
		$actionXML = @'
  <Actions Context="Author">
    <Exec>
      <Command>{0}</Command>
      <Arguments>-NoProfile -File "þfilepathþ" -Channel "$(Channel)" -EventRecordID "$(EventRecordID)" -Subscription {1}</Arguments>
    </Exec>
  </Actions>
'@ -f $Executable, $SubscriptionName
		
		$runLevel = 'LeastPrivilege'
		if ($Elevated) { $runLevel = 'HighestAvailable' }
		
		$userText = '      <UserId>S-1-5-18</UserId>'
		if ($Identity -and $Identity.UserName -ne 'SYSTEM')
		{
			if ($Identity.UserName -as [System.Security.Principal.SecurityIdentifier]) { $userSID = $Identity.UserName -as [System.Security.Principal.SecurityIdentifier] }
			else { $userSID = ([System.Security.Principal.NTAccount]$Identity.UserName).Translate([System.Security.Principal.SecurityIdentifier]) }
			$userText = "      <UserId>$($userSID)</UserId>"
		}
		if ($Identity)
		{
			if ($Identity.GetNetworkCredential().Password)
			{
				$userText += @'

      <LogonType>Password</LogonType>
'@
			}
		}
		
		$principalXML = @'
  <Principals>
    <Principal id="Author">
{0}
      <RunLevel>{1}</RunLevel>
    </Principal>
  </Principals>
'@ -f $userText, $runLevel
		
		$taskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
{0}
{1}
{2}
{3}
{4}
</Task>
'@ -f $registrationXML, $triggerXML, $principalXML, $settingsXML, $actionXML
		#endregion Resolve Task XML
		
		#region Resolve ScriptCode to $newScriptText
		if ($ScriptCode) { $scriptText = $ScriptCode.ToString() }
		else { $scriptText = Get-Content -Path $ScriptPath -Raw }
		
		$errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$null, [ref]$errors)
		if ($errors)
		{
			Stop-PSFFunction -String 'Install-EventSubscription.SyntaxError' -EnableException $EnableException
			return
		}
		
		if (-not $ast.ParamBlock)
		{
			$offset = 0
			if ($ast.EndBlock) { $offset = $ast.EndBlock.Extent.StartOffset }
			if ($ast.ProcessBlock) { $offset = $ast.ProcessBlock.Extent.StartOffset }
			if ($ast.BeginBlock) { $offset = $ast.BeginBlock.Extent.StartOffset }
			
			$newScriptText = ""
			if ($offset) { $newScriptText = $scriptText.SubString(0, $offset) }
			$newScriptText += @'
[CmdletBinding()]
param (
	$EventObject
)

'@
			$newScriptText += $scriptText.SubString($offset)
		}
		elseif (-not $ast.ParamBlock.Attributes.TypeName.FullName -eq 'CmdletBinding')
		{
			$offset = $ast.ParamBlock.Extent.StartOffset
			$newScriptText = ""
			if ($offset) { $newScriptText = $scriptText.SubString(0, $offset) }
			$newScriptText += @'
[CmdletBinding()]

'@
			$newScriptText += $scriptText.SubString($offset)
		}
		else { $newScriptText = $scriptText }
		#endregion Resolve ScriptCode to $newScriptText
		
		$subscriberCode = Get-Content -Path "$script:ModuleRoot\internal\scripts\Subscriber_EventLauncher.ps1" -Raw
	}
	process
	{
		if (Test-PSFFunctionInterrupt) { return }
		
		Invoke-PSFCommand -ComputerName $ComputerName -Credential $Credential -ArgumentList $taskXml, $newScriptText, $subscriberCode, $SubscriptionName, $Identity -ScriptBlock {
			param (
				[string]
				$TaskXml,
				
				[string]
				$NewScriptText,
				
				[string]
				$SubscriberCode,
				
				[string]
				$SubscriptionName,
				
				[AllowNull()]
				$Identity
			)
			
			#region Set up scriptfiles
			$encoding = New-Object System.Text.UTF8Encoding($true)
			
			$rootPath = "$env:ProgramFiles\WindowsPowerShell\EventSubscriptions"
			if (-not (Test-Path -Path $rootPath)) { $null = New-Item -Path $rootPath -ItemType Directory -Force }
			$subscriberPath = "$rootPath\Subscriber_EventLauncher.ps1"
			[System.IO.File]::WriteAllText($subscriberPath, $SubscriberCode, $encoding)
			
			$scriptFolder = "$rootPath\subscriptions"
			if (-not (Test-Path -Path $scriptFolder)) { $null = New-Item -Path $scriptFolder -ItemType Directory -Force }
			$scriptFilePath = "$scriptFolder\$SubscriptionName.ps1"
			[System.IO.File]::WriteAllText($scriptFilePath, $NewScriptText, $encoding)
			#endregion Set up scriptfiles
			
			#region Set up task
			$parameters = @{
				Force    = $true
				Xml	     = $TaskXml -replace 'þfilepathþ', $subscriberPath
				TaskPath = '\PowerShell_EventSubscriptions\'
				TaskName = $SubscriptionName
			}
			if ($Identity.UserName) { $parameters['User'] = $Identity.UserName }
			if ($Identity -and $Identity.GetNetworkCredential().Password) { $parameters['Password'] = $Identity.GetNetworkCredential().Password }
			$null = Register-ScheduledTask @parameters
			#endregion Set up task
		}
	}
}