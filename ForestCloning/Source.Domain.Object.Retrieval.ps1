### Retrieval of all the Source domain objects needed for creating a "mirrored" AD Environment
### Created by Daniel Gilbert
### Version 1.0 - Initial Release on 2023-03-24 after a lot of testing

### Stuff to do:
### * Azure Tenant object retrieval (this is a "Phase 2" item)
### 

<#
    .SYNOPSIS
        Retrieves all the objects (Users, Groups, OUs, and GPOs) necesssary to create a new "mirrored" domain that is 99% of the source domain (excluding computer accounts)

    .DESCRIPTION
		Retrieves all the objects (Users, Groups, OUs, and GPOs) necesssary to create a new "mirrored" domain that is 99% of the source domain (excluding computer accounts)

    .COMPONENT
        Requires Module ActiveDirectory
	    
    #>
	

###############################
# NOTES on what this script does.
#
# This script will get all the objects from the existing domain.
# To get the objects and export files, you will need to run this using a Domain Admin account or the dedicated service account for retrieval on a server with the RSAT PowerShell extensions installed on it. 
# This server will need to be a member of the Source domain.
# By default, the script will create all the files in the working directory you are currently in. Be SURE you want to create things in that directory or switch directories.
# The .\GPO.Creation directory will be created if it does not exist and all the relevant GPO backup directories will be created there.
#
#
###############################
# DO NOT EDIT BELOW THIS UNLESS YOU ABSOLUTELY KNOW WHAT YOU ARE DOING.


# Warnings about what is going to happen
write-host -ForegroundColor Cyan -BackgroundColor Black "`n `nThis script will get all the objects from the existing domain. `nTo get the objects and export files, you will need to run this using a Domain Admin account or the dedicated service account for retrieval on a server with the RSAT PowerShell extensions installed on it. This server will need to be a member of the Source domain. `n `nBy default, the script will create all the files in the working directory you are currently in. The .\GPO.Creation directory will be created if it does not exist and all the relevant GPO backup directories will be created there."
write-host -ForegroundColor Red -BackgroundColor Black "`n `nMake ***SURE*** you are in a directory where your account has rights. If not, you will get errors. If you launch PowerShell as an Administrator this might mitigate this issue.`n `nAdditionally, do ***NOT*** open any of the files that are being exported until the script is finished or it will corrupt the files.`n"
Read-Host -Prompt "Press any key to continue..."

# Create temp directory for files
$path = $PSScriptRoot

# Create sub-directory for GPO backups
$GPOpath = "$path\GPO.Creation"
If (!(test-path $GPOpath)) {md $GPOpath}

# Get source domain
$SourceDN = Get-ADDomain | select -expand DistinguishedName


# Get all the OUs in to an ordered list for ordered creation in the new environment
write-host -ForegroundColor Magenta -BackgroundColor Black "Getting OUs"
Get-ADObject -Filter { ObjectClass -eq 'organizationalunit' } -prop * |? {($_.distinguishedName -notlike "OU=Domain Controllers,$SourceDN") -and ($_.distinguishedName -notlike "OU=Microsoft Exchange Security Groups,$SourceDN")} | sort CanonicalName | select name,@{n="path";e={$_.distinguishedName.Substring($_.distinguishedName.IndexOf(',')+1)}},DistinguishedName | export-csv -NoTypeInformation -Delimiter ';' "$path\New.OU.Creation.csv"

# Get all users, except default AD accounts, with only the relevant attributes
write-host -ForegroundColor Magenta -BackgroundColor Black "Getting User Objects"
$excludedUsers = @("Administrator","Guest","krbtgt","Exchange Online-ApplicationAccount")
Get-AdUser -Filter * -prop * |? { ($excludedUsers -notcontains $_.Name) -and ($_.SamAccountName -notlike "SM_*") } | select SamAccountName,City,Company,Country,Department,Description,DisplayName,@{n="BaseOU";e={$_.distinguishedName.Substring($_.distinguishedName.IndexOf(',')+1)}},EmailAddress,EmployeeID,Enabled,GivenName,mailNickname,Manager,MobilePhone,Name,Office,OfficePhone,PostalCode,State,StreetAddress,Surname,targetAddress,Title,UserPrincipalName,extensionAttribute1,extensionAttribute2,extensionAttribute3,extensionAttribute4,extensionAttribute5,extensionAttribute6,extensionAttribute7,extensionAttribute8,extensionAttribute9,extensionAttribute10,extensionAttribute11,extensionAttribute12,extensionAttribute13,extensionAttribute14,extensionAttribute15,SID | export-csv -NoTypeInformation "$path\All.Users.Export.csv" -Encoding UTF8

# Get all groups except for the default AD/Exchange groups
write-host -ForegroundColor Magenta -BackgroundColor Black "Getting Security Groups"
$excludedGroups = @("Administrators","Users","Guests","Print Operators","Backup Operators","Replicator","Remote Desktop Users","Network Configuration Operators","Performance Monitor Users","Performance Log Users","Distributed COM Users","IIS_IUSRS","Cryptographic Operators","Event Log Readers","Certificate Service DCOM Access","RDS Remote Access Servers","RDS Endpoint Servers","RDS Management Servers","Hyper-V Administrators","Access Control Assistance Operators","Remote Management Users","Storage Replica Administrators","Domain Computers","Domain Controllers","Schema Admins","Enterprise Admins","Cert Publishers","Domain Admins","Domain Users","Domain Guests","Group Policy Creator Owners","RAS and IAS Servers","Server Operators","Account Operators","Pre-Windows 2000 Compatible Access","Incoming Forest Trust Builders","Windows Authorization Access Group","Terminal Server License Servers","Allowed RODC Password Replication Group","Denied RODC Password Replication Group","Read-only Domain Controllers","Enterprise Read-only Domain Controllers","Cloneable Domain Controllers","Protected Users","Key Admins","Enterprise Key Admins","DnsAdmins","DnsUpdateProxy","Organization Management","Recipient Management","View-Only Organization Management","Public Folder Management","UM Management","Help Desk","Records Management","Discovery Management","Server Management","Delegated Setup","Hygiene Management","Compliance Management","Security Reader","Security Administrator","Exchange Servers","Exchange Trusted Subsystem","Managed Availability Servers","Exchange Windows Permissions","ExchangeLegacyInterop","Exchange Install Domain Servers")
$groups = get-adgroup -filter * -prop * |? { $excludedGroups -notcontains $_.Name }
$groups | select SamAccountName,mail,displayname,description,GroupScope,GroupCategory,SID,@{n="owneraccount";e={(get-aduser $_.managedby | select -ExpandProperty samaccountname)}},@{n="BaseOU";e={$_.distinguishedName.Substring($_.distinguishedName.IndexOf(',')+1)}} | export-csv -NoTypeInformation "$path\All.Groups.Export.csv" -Encoding UTF8

# Get Group Memberships for ALL groups (including default groups excluded in the previous step)
write-host -ForegroundColor Magenta -BackgroundColor Black "Getting Security Group Memberships"
$groups |% { $g = $_.samaccountname;get-adgroup $_ -Properties Member | select -ExpandProperty Member | get-adobject -Properties * |? {$_.ObjectClass -notlike "computer"} | select @{n="GroupName";e={$g}},SamAccountName,ObjectClass} | export-csv -notype "$path\All.Groups.Expanded.csv" -Encoding utf8

# Backup all GPOs and their settings to the sub-directory. Each GPO backup will create its own directory
write-host -ForegroundColor Magenta -BackgroundColor Black "Backup up GPOs"
Backup-GPO -All -Path $GPOpath | Out-Null

# Get a list of the GPOs to create in the new environment
write-host -ForegroundColor Magenta -BackgroundColor Black "Getting GPO List"
$ListGPO = Get-GPO -all | Select-Object DisplayName 
$ListGPO | Export-Csv -Path "$path\ListGPO.csv" -NoTypeInformation -Encoding UTF8

# Get the GPO links to which OUs each GPO is linked to
write-host -ForegroundColor Magenta -BackgroundColor Black "Getting GPO Links"
(Get-ADOrganizationalUnit -filter * | Get-GPInheritance).GpoLinks | select Target,DisplayName,Enabled,Enforced,Order | Export-Csv -notype "$path\GPO.OU.Links.csv" -Encoding UTF8

# Get all the Security Filtering for each GPO
write-host -ForegroundColor Magenta -BackgroundColor Black "Getting GPO Security Filtering"
$GPOs = Get-GPO -All
$GPPerms = foreach ($GPO in $GPOs) {Get-GPPermissions -Guid $GPO.Id -All | Select-Object @{n='GPOName';e={$GPO.DisplayName}},@{n='AccountName';e={$_.Trustee.Name}},@{n='AccountType';e={$_.Trustee.SidType.ToString()}},@{n='Permissions';e={$_.Permission}}}
$GPPerms |? {($_.AccountType -notlike "Unknown") -and ($_.AccountType -notlike "Computer")} | Export-Csv -Path "$path\GPO.Permissions.csv" -NoTypeInformation -Encoding UTF8

# Get SIDs for all user and group objects in the source domain for mapping to the new domain
$sourceusers = get-aduser -filter {SamAccountName -notlike "SM_*"} | select samaccountname,@{n='SourceSID';e={$_.SID}},ObjectClass
$sourcegroups = get-adgroup -filter * | select samaccountname,@{n='SourceSID';e={$_.SID}},ObjectClass
$sourcedom = $sourceusers + $sourcegroups
$sourcedom | Export-Csv -Path "$path\SID.Mapping.csv" -NoTypeInformation -Encoding UTF8


# Output to console the information on what was exported
$output = "New.OU.Creation.csv`n"
$output += "All.Users.Export.csv`n"
$output += "All.Security.Groups.Export.csv`n"
$output += "All.Security.Groups.Expanded.csv`n"
$output += "ListGPO.csv`n"
$output += "GPO.OU.Links.csv`n"
$output += "GPO.Permissions.csv`n"
$output += "SID.Mapping.csv`n"

if ($output -notlike $null) {write-host -ForegroundColor Magenta -BackgroundColor Black  "`n`nThis process created the 8 files listed below that you will need to create a new domain. It also created a sub-directory named `"GPO.Creation`". You need to copy these 7 files and the sub-directory to the new server on which you are going to create a domain and follow the directions for the domain creation process. Good luck!`n`nCreated files:`n"$output}


write-host -ForegroundColor Magenta -BackgroundColor Black "`n `nVerify everything above was retrieved correctly and then press a key to exit the script"
Read-Host -Prompt "Press any key to continue..."