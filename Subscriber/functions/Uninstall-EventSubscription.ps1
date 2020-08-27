function Uninstall-EventSubscription
{
<#
	.SYNOPSIS
		Removes an eventsubscription created with Install-EventSubscription.
	
	.DESCRIPTION
		Removes an eventsubscription created with Install-EventSubscription.
	
	.PARAMETER SubscriptionName
		Name of the subscription to uninstall.
	
	.PARAMETER ComputerName
		Name of the computers against which to operate.
		Defaults to localhost.
	
	.PARAMETER Credential
		Credentials to use when connecting to computers.
	
	.PARAMETER Confirm
		If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
	
	.PARAMETER WhatIf
		If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
	
	.EXAMPLE
		PS C:\> Uninstall-EventSubscription -SubscriptionName 'MyTask'
	
		Uninstalls the subscription "MyTask" from the local computer.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$SubscriptionName,
		
		[Parameter(ValueFromPipeline = $true)]
		[PSFComputer[]]
		$ComputerName = $env:COMPUTERNAME,
		
		[PSCredential]
		$Credential
	)
	
	begin
	{
		$shouldProcess = $PSBoundParameters | ConvertTo-PSFHashtable -Include WhatIf, Confirm
	}
	process
	{
		Invoke-PSFCommand -ComputerName $ComputerName -Credential $Credential -ArgumentList $SubscriptionName, $shouldProcess -ScriptBlock {
			param (
				$SubscriptionName,
				
				$ShouldProcess
			)
			
			try { $tasks = Get-ScheduledTask -TaskPath '\PowerShell_EventSubscriptions\' -ErrorAction Stop }
			catch { return }
			
			$scriptFolder = "$env:ProgramFiles\WindowsPowerShell\EventSubscriptions\subscriptions"
			
			foreach ($task in $tasks)
			{
				if ($task.TaskName -ne $SubscriptionName) { continue }
				
				Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop @ShouldProcess
				if (Test-Path -Path "$scriptFolder\$($task.TaskName).ps1") { Remove-Item -Path "$scriptFolder\$($task.TaskName).ps1" -Force -ErrorAction Stop @ShouldProcess }
			}
		}
	}
}