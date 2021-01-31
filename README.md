# Exchange Online: Cross-tenant migration scripts

*Any sample script in this repository is provided AS IS and not supported under any Microsoft standard support program, service and without warranty of any kind.*

## Overview:

This repository contains two scripts to sync all necessary attributes between the source and target tenant before the MRS move mailbox. Before starting using the resources provided in this repository, please review the [Microsoft official document about the cross-tenant EXO migration](https://docs.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-mailbox-migration). It’s very important that you understand how the migration works in order to use these scripts.

## How it works:

1 - Fill some Exchange custom attributes (1-15) with any value. This will become the filter for the script to get only mailboxes with the attribute that you choose.

2 - Fill the CSV file which will be used to mapping the source <-> target domain. You can find more description on this current page or in the script itself.

3 - Understand all parameters that you may use to run the script. You can find all parameter's description on this current page or in the script itself.

4 - Run the script *Cross-Tenant-Migration-Attribute-Export.ps1* to dump the source mailboxes and validate yourself that the CSV generated by the script contains only mailboxes that you filter by the custom attribute.

5 - Run the *Cross-Tenant-Migration-Attribute-Import.ps1* to create Mail User objects (aka MEU) in the target on-prem AD. The script will stop Azure AD Connect sync cycle or ask you to do yourself before the execution. The reason is because you might validate that all MEU objects are properly created before sync it.

6 - Re-enable the Azure AD Connect sync cycle manually – the script will not do this for you, but will provide you the cmdlet to do when you will be ready. 


## Requirement:

**Common requirements for both scripts:**

- Depending on the current powershell execution policy state, it could require to be set as Unrestricted.

- You need Active Directory and Exchange Server On-Premises. In other words, the script was not developed to work in Azure AD cloud-only scenarios or with AD On-Premises in hybrid but with no Exchange On-Premises. 


**Cross-Tenant-Migration-Attribute-Export.ps1:**

- You must fill a custom attribute field with some value by your preference in order to be used by the script as a filter to get only mailboxes that have the custom attribute and value filled by you. This will provide more security once the script will not get anything else than you want to. 

- You must fill a CSV that maps which souce domain will become which target domain. Start the first line as *source,target* and then map each source domain for each target domain, e.g:

    ```DomainMapping.csv
    source,target
    contoso.com,fabrikam.com
    source1.com,target1.com
    sub.source.com,sub.target.com

- You can run the script from an Exchange Server machine or from any other domain-joined machine as long as you use the switch -LocalMachineIsNotExchange and the string -ExchangeHostname to inform which Exchange the script will open the PSSession. 

- The script will connect to the Exchange Online using v2 module. If you don't have it installed, the script can install for you as long as the PC may reach the powershell gallery.  

- If you run the script from an Exchange Server machine the script will leverage the local AD module present on Exchange. Otherwise the script will export a PSSession from the Domain Controller which authenticated your PC.   


## Parameters:

**Cross-Tenant-Migration-Attribute-Export.ps1**

| Parameter | Value | Required or Optional
|-----------------------------------------|-------------------------|---------------|
| AdminUPN                                | Exchange Online administrator UPN. | Required |
| CustomAttributeNumber                   | Exchange Custom Attribute number (1-15) where the script will use to filter. | Required |
| CustomAttributeValue                    | Exchange Custom Attribute value where the script will use to filter. | Required |
| DomainMappingCSV                        | CSV file that maps source <-> target domain. If the CSV file is in the same paht as the script, just enter the CSV file name. | Required |
| BypassAutoExpandingArchiveCheck         | Switch to check if there are Auto-Expanding archive mailboxes.¹ | Optional |
| Path                                    | Custom output path for the csv. if no value is defined it will be saved on Desktop. | Optional |
| LocalMachineIsNotExchange               | Switch to be used when the script is executed from a non-Exchange Server machine. | Optional |
| ExchangeHostname                        | Exchange server hostname that the script will connect to. | Required² |
||||
    
¹ The Auto-Expanding archive is verified because move-mailbox of auxiliar Auto-Expanding archive mailbox is not supported, you can see the [official article for more details](https://docs.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-mailbox-migration?view=o365-worldwide#known-issues). Thus, the script will dump all mailboxes that have auxiliar Auto-Expanding archive mailbox to a TXT file. Be aware that this check might increase the script duration.

² Required only if -LocalMachineIsNotExchange is used.

**Cross-Tenant-Migration-Attribute-Import.ps1**

| Parameter | Value | Required or Optional
|-----------------------------------------|-------------------------|---------------|
| UPNSuffix                               | UPN domain for the new MEU objects e.g: contoso.com  | Required |
| Password                                | Choose a password for all new MEU objects. If no password is chosen, the script will define '?r4mdon-_p@ss0rd!' as password. | Optional |
| ResetPassword                           | Require password change on first user access. | Optional |
| OrganizationalInit                      | Source domain used in your organization such as contoso.com. | Optional |
| Path                                    | Custom output path for import the csv. if no value is defined the script will try to get it from the Desktop. | Optional |
| LocalMachineIsNotExchange               | Switch to be used when the script is executed from a non-Exchange Server machine. | Optional |
| ExchangeHostname                        | Exchange server hostname that the script will connect to. | Required¹ |
||||

¹ Required only if -LocalMachineIsNotExchange is used.

## AD Attributes

The *Cross-Tenant-Migration-Attribute-Export.ps1* will dump to a CSV the following attributes:

- ExchangeGuid
- EmailAddresses
- ExternalEmailAddress
- legacyExchangeDN
- PrimarySMTPAddress
- Alias
- FirstName
- LastName
- DisplayName
- Name
- SamAccountName
- ArchiveGuid
- msExchSafeSendersHash
- msExchSafeRecipientsHash
- msExchBlockedSendersHash
- CustomAttribute ¹
- CustomAttribute Value ¹
- MailboxLocations ²
- LitigationHoldEnabled ³
- SingleItemRecoveryEnabled ³

¹ The custom attributes number and value that will be dumped is chosen according to the user’s input before running the script

² The script doesn’t really dump MailboxLocations to a CSV but it dumps the UserDisplayName from any users that might have an Auto-Expanding archive mailbox to a TXT. This is not a requirement for the migration itself, but as Microsoft doesn’t support the Auto-Expanding archive mailbox migration the script dumps it to make you aware of. 

³ These properties are converted to a number which represents the ELC mailbox flag.

