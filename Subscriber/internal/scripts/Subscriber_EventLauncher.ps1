<#
	.SYNOPSIS
		Launcher script of the Subscriber module.
	
	.DESCRIPTION
		Launcher script of the Subscriber module.
		Is triggered by scheduled tasks set to trigger off eventlog events, as deployed by the Subscriber module's Install-EventSubscription command.
		It will resolve the original event object, then trigger the associated scribt, passing that event object.

		Associated sripts need to:
		- Implement CmdletBinding
		- Accept one Parameter: The event object triggering the event

		The event object is of the object type returned by Get-WinEvent
	
	.PARAMETER Channel
		The Eventlog Channel (LogName) the message was written in.
	
	.PARAMETER EventRecordID
		The specific record ID if that particular event message.
	
	.PARAMETER Subscription
		Name of the subscription.
		Used to resolve the script to launch.

	.EXAMPLE
		PS C:\> .\Subscriber_EventLauncher.ps1 -Channel Application -EventRecordID 11111111 -Subscription appCrash

		Starts the subscriber script "appCrash" for the event with RecordID 11111111 from the Application log.
#>
[CmdletBinding()]
param (
	[Parameter(Mandatory = $true)]
	[string]
	$Channel,
	
	[Parameter(Mandatory = $true)]
	[string]
	$EventRecordID,
	
	[Parameter(Mandatory = $true)]
	[string]
	$Subscription
)

$filterXml = @"
<QueryList>
  <Query Id="0" Path="$Channel">
    <Select Path="$Channel">*[System[(EventRecordID=$EventRecordID)]]</Select>
  </Query>
</QueryList>
"@

try { $eventObject = Get-WinEvent -FilterXml $filterXml -ErrorAction Stop }
catch { throw }

try { $scriptFile = Get-Item -Path "$PSScriptRoot\subscriptions\$Subscription.ps1" -ErrorAction Stop }
catch { throw }

try { & $scriptFile.FullName $eventObject -ErrorAction Stop }
catch { throw }