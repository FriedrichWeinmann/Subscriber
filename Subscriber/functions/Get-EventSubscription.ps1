function Get-EventSubscription
{
<#
	.SYNOPSIS
		Returns information on installed event subscriptions.
	
	.DESCRIPTION
		Returns information on installed event subscriptions.
	
	.PARAMETER SubscriptionName
		Name of the subscription to filter by.
		Defaults to '*'.
	
	.PARAMETER ComputerName
		Name of the computers against which to operate.
		Defaults to localhost.
	
	.PARAMETER Credential
		Credentials to use when connecting to computers.
	
	.EXAMPLE
		PS C:\> Get-EventSubscription
	
		List all event subscriptions installed on the local computer.
#>
	[CmdletBinding()]
	param (
		[string]
		$SubscriptionName = '*',
		
		[Parameter(ValueFromPipeline = $true)]
		[PSFComputer[]]
		$ComputerName = $env:COMPUTERNAME,
		
		[PSCredential]
		$Credential
	)
	
	process
	{
		Invoke-PSFCommand -ComputerName $ComputerName -Credential $Credential -ArgumentList $SubscriptionName -ScriptBlock {
			param (
				$SubscriptionName
			)
			
			try { $tasks = Get-ScheduledTask -TaskPath '\PowerShell_EventSubscriptions\' -ErrorAction Stop }
			catch { return }
			
			$scriptFolder = "$env:ProgramFiles\WindowsPowerShell\EventSubscriptions\subscriptions"
			
			foreach ($task in $tasks)
			{
				if ($task.TaskName -notlike $SubscriptionName) { continue }
				
				$taskInfo = $task | Get-ScheduledTaskInfo
				
				$code = $null
				if (Test-Path -Path "$scriptFolder\$($task.TaskName).ps1") { $code = Get-Content -Path "$scriptFolder\$($task.TaskName).ps1" -Raw }
				
				try { $queryObjects = ([xml]$task.Triggers.Subscription).QueryList.Query.Select }
				catch { }
				
				$queries = foreach ($query in $queryObjects)
				{
					$source, $eventID = $query.'#text' -replace "^.+@Name='([^']+)'] and EventID=(\d+).+$", '$1þ$2' -split 'þ'
					$object = [pscustomobject]@{
						Path = $query.Path
						Filter = $query.'#text'
						Source = $source
						EventID = $eventID -as [int]
					}
					Add-Member -InputObject $object -MemberType ScriptMethod -Name ToString -Value {
						if ($this.EventID) { '{0}: {1} > {2}' -f $this.Path, $this.Source, $this.EventID }
						else { '{0}: {1}' -f $this.Path, $this.Filter }
					} -Force -PassThru
				}
				
				[pscustomobject]@{
					PSTypeName   = 'Subscriber.Task'
					ComputerName = $env:COMPUTERNAME
					Subscription = $task.TaskName
					LastRun	     = $taskInfo.LastRunTime
					LastResult   = $taskInfo.LastTaskResult
					Filter	     = $queries
					TaskObject   = $task
					Code		 = $code
				}
			}
		}
	}
}