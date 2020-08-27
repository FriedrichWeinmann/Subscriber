# Description

This module is designed to facilitate subscribing PowerShell actions to events in the Windows Eventlog.

## Installation

```powershell
Install-Module Subscriber
```

## Using the module

A simple eventsubscription could look like this:

```powershell
Install-EventSubscription -SubscriptionName 'Account Lockout' -ScriptPath '.\lockout.ps1' -LogName 'Security' -Source 'Microsoft-Windows-Security-Auditing' -EventID 4740
```

That would install the event subscription & task code on the local computer.
To install it on all domain controllers instead, this should do the trick:

```powershell
Install-EventSubscription -Computername (Get-ADComputer -LDAPFilter '(primaryGroupID=516)').DNSHostName -SubscriptionName 'Account Lockout' -ScriptPath '.\lockout.ps1' -LogName 'Security' -Source 'Microsoft-Windows-Security-Auditing' -EventID 4740
```
