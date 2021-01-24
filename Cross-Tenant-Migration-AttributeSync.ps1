
<#
	Title: Cross-Tenant-Migration-AttributeSync.ps1
	Version: 0.1
	Date: 2021.01.22
	Authors: Denis Vilaca Signorelli (denis.signorelli@microsoft.com)

    .REQUIREMENTS: 
    
    1 - ExchangeOnlineManagement module (EXO v2) is required to run this script. 
        You can install manually using: Install-Module -Name ExchangeOnlineManagement. 
        If you don't install EXO v2 manually, the will install it automatically for you.

    2 - To make things easier, run this script from Exchange On-Premises machine powershell, 
        the script will automatically import the Exchange On-Prem module. If you don't want 
        to run the script from an Exchange machine, use the switch -LocalMachineIsNotExchange 
        and enter the FQDN of an Exchange Server. You will be prompted to sign-in, use the same 
        credential that you are already logged in your domain machine

	.PARAMETES: 

    -AdminUPN 
        Mandatory parameter used to connec to to Exchange Online. Only the UPN is 
        stored to avoid token expiration during the session, no password is stored.

    -CustomAttributeNumber 
        Mandatory parameter used to inform the code which custom attributes will 
        be used to scope the search

    -CustomAttributeValue 
        Mandatory parameter used to inform the code which value will be used to 
        scope the search

    -SourceDomain 
        Mandatory parameter used to replace the source SMTP domain to the target SMTP 
        domain in the CSV. These values are not replaced on the object itself, only in the CSV. 

    -TargetDomain 
        Mandatory parameter used to replace the source SMTP domain to the target SMTP domain 
        in the CSV. These values are not replaced in the object itself, only in the CSV.  

    -Path
        Optional parameter used to inform which path will be used to save the CSV. 
        If no path is chosen, the script will save on desktop path. 

    -LocalMachineIsNotExchange
        Optional parameter used to inform that you are running the script from 
        a non-Exchange Server machine. This parameter will require the -ExchangeHostname. 

    -ExchangeHostname
        Mandatory parameter if the switch -LocalMachineIsNotExchange was used. 
        Used to inform the Exchange Server FQDN that the script will connect.


	.DESCRIPTION: 

    This script will dump all necessary attributes that cross-tenant RMS migration requires. 
    No changes will be performed this code.

    ##############################################################################################
    #This sample script is not supported under any Microsoft standard support program or service.
    #This sample script is provided AS IS without warranty of any kind.
    #Microsoft further disclaims all implied warranties including, without limitation, any implied
    #warranties of merchantability or of fitness for a particular purpose. The entire risk arising
    #out of the use or performance of the sample script and documentation remains with you. In no
    #event shall Microsoft, its authors, or anyone else involved in the creation, production, or
    #delivery of the scripts be liable for any damages whatsoever (including, without limitation,
    #damages for loss of business profits, business interruption, loss of business information,
    #or other pecuniary loss) arising out of the use of or inability to use the sample script or
    #documentation, even if Microsoft has been advised of the possibility of such damages.
    ##############################################################################################

#>


# Define Parameters
[CmdletBinding(DefaultParameterSetName="Default")]
Param(
    [Parameter(Mandatory=$true,
    HelpMessage="Enter an EXO administrator UPN")]
    [string]$AdminUPN,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the custom attribute number. Valid range: 1-15")]
    [ValidateRange(1,15)]
    [Int]$CustomAttributeNumber,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the custom attribute value that will be used")]
    [string]$CustomAttributeValue,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the SOURCE domain. E.g. contoso.com")]
    [string]$SourceDomain,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the TARGET domain. E.g. fabrikam.com")]
    [string]$TargetDomain,
    
    [Parameter(Mandatory=$false,
    HelpMessage="The script will check if you have Auto-Expanding archive enable on organization
    level, if yes each mailbox will be check if there is an Auto-Expanding archive mailbox
    This check might increase the script duration. You can opt-out using this switch")]
    [switch]$BypassAutoExpandingArchiveCheck,

    [Parameter(Mandatory=$false,
    HelpMessage="Enter a custom output path for the csv. if no value is defined it will save on Desktop")]
    [string]$Path,
    
    [Parameter(ParameterSetName="RemoteExchange",Mandatory=$false)]
    [switch]$LocalMachineIsNotExchange,
    
    [Parameter(ParameterSetName="RemoteExchange",Mandatory=$true,
    HelpMessage="Enter the remote exchange hostname")]
    [string]$ExchangeHostname
    )


if ( $Path -ne '' ) 
{ 

$outFile = "$path\UserListToImport.csv"
$AUXFile = "$path\AUXEnable-Mailboxes.txt"

} else {

$outFile = "$home\desktop\UserListToImport.csv"
$AUXFile = "$home\desktop\AUXEnable-Mailboxes.txt"

}

$outArray = @() 
$CustomAttribute = "CustomAttribute$CustomAttributeNumber"
$SourceDomain = "@$SourceDomain"
$TargetDomain = "@$TargetDomain"

# Check if EXO v2 is installed, if not check if the powershell is RunAs admin
if (Get-Module -ListAvailable -Name ExchangeOnlineManagement) {
    
    Write-Host "$(Get-Date) - Exchange Online Module v2 already exists" -ForegroundColor Green

} else {

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $RunAs = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($RunAs -like 'False') {

        Write-Host "$(Get-Date) - Administrator rights are required to install modules. RunAs Administrator and then run the script" -ForegroundColor Green
        Exit

    } else {

        #User consent to install EXO v2 Module, if not stop the script
        $title    = Write-Host "$(Get-Date) - Exchange Online Module v2 Installation" -ForegroundColor Green
        $question = Write-Host "Do you want to proceed with the module installation?" -ForegroundColor Green
        $choices  = '&Yes', '&No'
        $decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)

        if ($decision -eq 0) {
        
            Write-Host "$(Get-Date) - Installing..." -ForegroundColor Green
            Install-Module ExchangeOnlineManagement -AllowClobber -Confirm:$False -Force

        } else {
        
            Write-Host "$(Get-Date) - We cannot proceed without EXO v2 module" -ForegroundColor Green
            Exit

        }

    }

}

if ( $LocalMachineIsNotExchange.IsPresent ) {

    # Connect to Exchange
    Write-Host "$(Get-Date) - Loading AD Module and Exchange Server Module" -ForegroundColor Green
    $Credentials = Get-Credential -Message "Enter your Exchange admin credentials. It should be the same that you are logged in the current machine"
    $ExOPSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$ExchangeHostname/PowerShell/ -Authentication Kerberos -Credential $Credentials
    Import-PSSession $ExOPSession -AllowClobber -DisableNameChecking | Out-Null

    # Connect to AD
    $sessionAD = New-PSSession -ComputerName $env:LogOnServer.Replace("\\","")
    Invoke-Command { Import-Module ActiveDirectory } -Session $sessionAD
    Export-PSSession -Session $sessionAD -CommandName *-AD* -OutputModule RemoteAD -AllowClobber -Force | Out-Null
    Remove-PSSession -Session $sessionAD
            
    try {
        
        # Create copy of the module on the local computer
        Import-Module RemoteAD -Prefix Remote -DisableNameChecking -ErrorAction Stop 
        
    } catch { 
        
        # Sometimes the following path is not registered as system variable for PS modules path, thus we catch explicitly the .psm1
        Import-Module "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\RemoteAD\RemoteAD.psm1" -Prefix Remote -DisableNameChecking
              
    } finally {

        If (Get-Module -Name RemoteAD) {

            Write-Host "$(Get-Date) - AD Module was succesfully installed." -ForegroundColor Green
                
        } else {
                
            Write-Host "$(Get-Date) - AD module failed to load. Please run the script from an Exchange Server." -ForegroundColor Green 
            Exit

        }

    }

} else {

    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn; 

}


# Save all properties from MEU object to variable
$RemoteMailboxes = Get-RemoteMailbox -resultsize unlimited | Where-Object {$_.$CustomAttribute -like $CustomAttributeValue}
Write-Host "$(Get-Date) - $($RemoteMailboxes.Count) mailboxes with $($CustomAttribute) as $($CustomAttributeValue) were returned" -ForegroundColor Green


# Remove Exchange On-Prem PSSession in order to connect later to EXO PSSession
Get-PSSession | Remove-PSSession

# Connect specifying username, if you already have authenticated 
# to another moduel, you actually do not have to authenticate
Connect-ExchangeOnline -UserPrincipalName $AdminUPN -ShowProgress:$True -ShowBanner:$False

# This will make sure when you need to reauthenticate after 1 hour 
# that it uses existing token and you don't have to write password
$global:UserPrincipalName=$AdminUPN

# Saving AUX org status if bypass switch is not present
if ( $BypassAutoExpandingArchiveCheck.IsPresent ) {

    Write-Host "$(Get-Date) - Bypassing Auto-Expand archive check" -ForegroundColor Green

} else {

    $OrgAUXStatus = Get-OrganizationConfig | Select-Object AutoExpandingArchiveEnabled

    if ( $OrgAUXStatus.AutoExpandingArchiveEnabled -eq '$True' ) {

        Write-Host "$(Get-Date) - Auto-Expand archive is enabled at organization level" -ForegroundColor Green

    } else {

        Write-Host "$(Get-Date) - Auto-Expand archive is not enabled at organization level, but we will check each mailbox" -ForegroundColor Green

    }
    
}

Foreach ($i in $RemoteMailboxes)  
{ 
 	$user = get-Recipient $i.alias 
 	$object = New-Object System.Object 
 	$object | Add-Member -type NoteProperty -name primarysmtpaddress -value $i.PrimarySMTPAddress 
 	$object | Add-Member -type NoteProperty -name alias -value $i.alias 
 	$object | Add-Member -type NoteProperty -name FirstName -value $User.FirstName 
 	$object | Add-Member -type NoteProperty -name LastName -value $User.LastName 
 	$object | Add-Member -type NoteProperty -name DisplayName -value $User.DisplayName 
 	$object | Add-Member -type NoteProperty -name Name -value $i.Name 
 	$object | Add-Member -type NoteProperty -name SamAccountName -value $i.SamAccountName 
 	$object | Add-Member -type NoteProperty -name legacyExchangeDN -value $i.legacyExchangeDN 
 	$object | Add-Member -type NoteProperty -name CustomAttribute -value $CustomAttribute    
 	$object | Add-Member -type NoteProperty -name CustomAttributeValue -value $CustomAttributeValue
    
    if ( $BypassAutoExpandingArchiveCheck.IsPresent ) {
    
        # Save necessary properties from EXO object to variable avoiding AUX check
        Write-Host "$(Get-Date) - Getting EXO mailboxes necessary attributes. This may take some time..." -ForegroundColor Green
        $EXOMailbox = Get-EXOMailbox -Identity $i.Alias -PropertySets Retention,Hold,Archive,StatisticsSeed 
    
    } else {

        if ($OrgAUXStatus.AutoExpandingArchiveEnabled -eq '$True') {

            # If AUX is enable at org side, doesn't metter if the mailbox has it explicitly enabled
            $EXOMailbox = Get-EXOMailbox -Identity $i.Alias -PropertySets All | Select-Object ExchangeGuid,MailboxLocations,LitigationHoldEnabled,SingleItemRecoveryEnabled,ArchiveDatabase,ArchiveGuid

        } else {

            # If AUX isn't enable at org side, we check if the mailbox has it explicitly enabled
            $EXOMailbox = Get-EXOMailbox -Identity $i.Alias -PropertySets All | Select-Object ExchangeGuid,MailboxLocations,LitigationHoldEnabled,SingleItemRecoveryEnabled,ArchiveDatabase,ArchiveGuid,AutoExpandingArchiveEnabled
        
        }

    }

    if ( $BypassAutoExpandingArchiveCheck.IsPresent ) {
    
        # Save necessary properties from EXO object to variable avoiding AUX check
        Write-Host "$(Get-Date) - Bypassing MailboxLocation check for Auto-Expand archive" -ForegroundColor Green

    } else {

        # AUX enabled doesn't mean that the mailbox indeed have AUX
        # archive. We need to check the MailboxLocation to be sure
        if ( ($OrgAUXStatus.AutoExpandingArchiveEnabled -eq '$True' -and $EXOMailbox.MailboxLocations -like '*;AuxArchive;*') -or 
        ($OrgAUXStatus.AutoExpandingArchiveEnabled -eq '$False' -and $EXOMailbox.AutoExpandingArchiveEnabled -eq '$True' -and 
        $EXOMailbox.MailboxLocations -like '*;AuxArchive;*') ) 
        {

            Write-Output "$(Get-Date) - User $($i.Alias) has an auxiliar Auto-Expanding archive mailbox. Be aware that any auxiliar archive mailbox will not be migrated" | Out-File -FilePath $AUXFile -Append
            
        } 
    } 

    # Get mailbox guid from EXO because if the mailbox was created from scratch 
    # on EXO, the ExchangeGuid would not write-back to On-Premises this value
    $object | Add-Member -type NoteProperty -name ExchangeGuid -value $EXOMailbox.ExchangeGuid
    
    # Get mailbox ECL value
    $ELCValue = 0 
    if ($EXOMailbox.LitigationHoldEnabled) {$ELCValue = $ELCValue + 8} 
    if ($EXOMailbox.SingleItemRecoveryEnabled) {$ELCValue = $ELCValue + 16} 
    if ($ELCValue -gt 0) { $object | Add-Member -type NoteProperty -name ELCValue -value $ELCValue}
    
    # Get the ArchiveGuid from EXO if it exist. The reason that we don't rely on
    # "-ArchiveStatus" parameter is that may not be trustable in certain scenarios 
    # https://docs.microsoft.com/en-us/office365/troubleshoot/archive-mailboxes/archivestatus-set-none
    if ( $EXOMailbox.ArchiveDatabase -ne '' -and 
         $EXOMailbox.ArchiveGuid -ne "00000000-0000-0000-0000-000000000000" )    
    {
        
        $object | Add-Member -type NoteProperty -name ArchiveGuid -value $EXOMailbox.ArchiveGuid
    
    }

    # Get any SMTP alias avoiding *.onmicrosoft
    $ProxyArray = @()
    $TargetArray = @()
    $Proxy = $i.EmailAddresses
	foreach ($email in $Proxy)
    {
        if ($email -notlike '*.onmicrosoft.com')
        {

            $ProxyArray = $ProxyArray += $email

        }

        if ($email -like '*.onmicrosoft.com')
        {

            $TargetArray = $TargetArray += $email

        }

    }
         
    # Join it using ";" and replace the old domain (source) to the new one (target)
    $ProxyToString = [system.String]::Join(";",$ProxyArray)
    $object | Add-Member -type NoteProperty -name EmailAddresses -value $ProxyToString.Replace($SourceDomain,$TargetDomain) 
    #TO DO: Provide input for more source and target domains and probably mapping them bases on CSV.

    # Get ProxyAddress only for *.mail.onmicrosoft to define in the target AD the targetAddress value
    $TargetToString = [system.String]::Join(";",$TargetArray)
    $object | Add-Member -type NoteProperty -name ExternalEmailAddress -value $TargetToString.Replace("smtp:","")


    if ( $LocalMachineIsNotExchange.IsPresent )
    {

        # Connect to AD exported module only if this machine isn't an Exchange   
        $Junk = Get-RemoteADUser -Identity $i.SamAccountName -Properties *
    
    } else {

        $Junk = Get-ADUser -Identity $i.SamAccountName -Properties *

    }

        # Get Junk hashes, these are SHA-265 write-backed from EXO. Check if the user 
        # has any hash, if yes we convert the HEX to String removing the "-"
    if ( $null -ne $junk.msExchSafeSendersHash -and
         $junk.msExchSafeSendersHash -ne '' )
    {
        $SafeSender = [System.BitConverter]::ToString($junk.msExchSafeSendersHash)
        $Safesender = $SafeSender.Replace("-","")
        $object | Add-Member -type NoteProperty -name SafeSender -value $SafeSender
    }
    
    if ( $null -ne $junk.msExchSafeRecipientsHash -and
         $junk.msExchSafeRecipientsHash -ne '' )
    {
        $SafeRecipient = [System.BitConverter]::ToString($junk.msExchSafeRecipientsHash)
        $SafeRecipient = $SafeRecipient.Replace("-","")
        $object | Add-Member -type NoteProperty -name SafeRecipient -value $SafeRecipient 

    }

    if ( $null -ne $junk.msExchBlockedSendersHash -and
         $junk.msExchBlockedSendersHash -ne '' )
    {
        $BlockedSender = [System.BitConverter]::ToString($junk.msExchBlockedSendersHash)
        $BlockedSender = $BlockedSender.Replace("-","")
        $object | Add-Member -type NoteProperty -name BlockedSender -value $BlockedSender
    }


 	$outArray += $object 
} 

# Export to a CSV and clear up variables and sessions
if ( $BypassAutoExpandingArchiveCheck.IsPresent ) {
    
    Write-Host "$(Get-Date) - Saving CSV on $($outfile)" -ForegroundColor Green

    } else {

        Write-Host "$(Get-Date) - Saving CSV on $($outfile)" -ForegroundColor Green
        Write-Host "$(Get-Date) - Saving TXT on $($AUXFile)" -ForegroundColor Green

    }

$outArray | Export-CSV $outfile -notypeinformation
Remove-Variable * -ErrorAction SilentlyContinue
Get-PSSession | Remove-PSSession

