### Domain Creation Script for creating a "mirrored" AD Environment
### Created by Daniel Gilbert
### Version 1.0 - Initial Release on 2023-03-24 after a lot of testing

### Stuff to do:
### * Azure Tenant Setup stuff (this is a "Phase 2" item)
### * Maintain list of domains created and remove from allowed names (would need periodic checking to clear the list) (maybe...)

<#
    .SYNOPSIS
        Creates a new "mirrored" domain that is 99% of the source domain (excluding computer accounts)

    .DESCRIPTION
		Creates a new "mirrored" domain that is 99% of the source domain (excluding computer accounts)

    .COMPONENT
        Requires Module ActiveDirectory
		
    .Parameter NetBIOSChoice
        The NetBIOS name of the new domain. This is for command line usage. If run without it, a dialog box will be presented to get this variable.
		
	.Parameter DNSNameChoice
		The DNS name of the new domain. This is for command line usage. If run without it, a dialog box will be presented to get this variable.
	
    #>


###############################
# Variables to be changed for YOUR environment

# Exchange ISO for schema extension:
$ExchangeISO = 'https://download.microsoft.com/download/b/c/7/bc766694-8398-4258-8e1e-ce4ddb9b3f7d/ExchangeServer2019-x64-CU12.ISO'
# NOTE: This has only been tested with Exchange 2019 on Windows Server 2019. The commands for installation may need tweaking for other versions. 

# .NET Framework (needed for Exchange installation in most cases)
$DOTNETInstaller = 'https://go.microsoft.com/fwlink/?linkid=2088631'

# Set the follow NETBIOS and DNS domain names so that the appropriate name replacements are done as well as blocking any existing domains from being used. 
# NOTE: If someone in your environment sets up a new domain with the exact same name as an existing one, you will have a lot of problems. Don't let that happen.
#
# You can add more Banned NetBIOS/DNS names below if you want. Just add the appropriately numbered variable declaration and add another += to $NamesArray

$SOURCEDN = "DC=Company,DC=com"

$SOURCEDOMAINNBT = "PROD"
$BANNEDNETBIOS1 = "DEV"
$BANNEDNETBIOS2 = "TEST"

$SOURCEDOMAINDNS = "company.com"
$BANNEDDNS1 = "devcompany.com"
$BANNEDDNS2 = "testcompany.com"

$NamesArray = @()
$NamesArray += $SOURCEDOMAINNBT
$NamesArray += $SOURCEDOMAINDNS
$NamesArray += $BANNEDNETBIOS1
$NamesArray += $BANNEDDNS1
$NamesArray += $BANNEDNETBIOS2
$NamesArray += $BANNEDDNS2

###############################
# DO NOT EDIT BELOW THIS UNLESS YOU ABSOLUTELY KNOW WHAT YOU ARE DOING.

# Setting a parameter so the domain choice can be passed from command line or, more likely, from the scheduled task created to continue the setup
Param (
	[ValidateLength(3,15)][ValidatePattern('[a-zA-Z]')][string]$NetBIOSChoice,
	[ValidateLength(6, 253)][validatePattern('^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$')][ValidateNotNullOrEmpty()][string]$DNSNameChoice
)

Function ADInstall {
	# Start downloading Exchange ISO and continue on while it downloads
	write-host -ForegroundColor Magenta -BackgroundColor Black "Download the Exchange ISO for extending the AD Schema"
	Start-Job -ScriptBlock {Start-BitsTransfer -Source $ExchangeISO  -Destination "$using:path\Exchange.iso"}

	# Install .NET Framework 4.8 (needed for Exchange)
	write-host -ForegroundColor Magenta -BackgroundColor Black "Downloading and installing .NET 4.8 for Exchange"
	Start-BitsTransfer -Source $DOTNETInstaller -Destination "$path\DotNETInstall.exe"; & "$path\DotNETInstall.exe" /q /norestart

	# Installing the base packages necessary for AD
	write-host -ForegroundColor Magenta -BackgroundColor Black "Installing necessary features for AD installation"
	Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
	sleep 10

	# Create the new AD Domain
	write-host -ForegroundColor Magenta -BackgroundColor Black "Creating AD Forest & Domain"
	$Password = ConvertTo-SecureString "Elvis is the King of Rock 'n Roll!" -AsPlainText -Force
	Install-ADDSForest -CreateDnsDelegation:$false -DatabasePath C:\Windows\NTDS -DomainMode WinThreshold -DomainName $DNSName -DomainNetbiosName $NetBIOS -ForestMode WinThreshold -InstallDns:$true -LogPath C:\Windows\NTDS -NoRebootOnCompletion:$true -SafeModeAdministratorPassword $Password -SysvolPath C:\Windows\SYSVOL -Force:$true
	Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools

	# While Exchange ISO not exist, wait 10 seconds and check again
	while (!(Test-Path "$path\Exchange.iso")) { Start-Sleep 10 }

	# Restart to continue
	write-host -ForegroundColor Magenta -BackgroundColor Black "Verify everything above installed correctly and then press a key to reboot"
	Read-Host -Prompt "Press any key to continue..."

	# Creating a Scheduled Task that will continue the script upon reboot
	Add-Content -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\Domain.Creation.Continue.bat" "Powershell.exe -Command `"$path\Domain.Creation.Script.ps1`" -NetBIOSChoice $NetBIOSChoice -DNSNameChoice $DNSNameChoice"

	# Rebooting the computer now that all tasks are done
	sleep 10
	restart-computer
}


Function SchemaObjectSetup {
		# Continuing after reboot with Exchange Schema extension to AD. Please note that this has only been tested with Exchange 2019. The commands may need tweaking for other versions. 

	if (Test-Path "$path\Exchange.iso") {write-host -ForegroundColor Magenta -BackgroundColor Black  "Starting Exchange Schema extension"} else {write-host -ForegroundColor Magenta -BackgroundColor Black  "Something is wrong. Try first part again.";exit}
	$mountResult = Mount-DiskImage "$path\Exchange.iso" -PassThru
	$mountResult | Get-Volume
	$cmd = ($mountResult | Get-Volume).DriveLetter + ":\setup.exe"
	&$cmd /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /PrepareAD /OrganizationName:"$NetBIOS"
	&$cmd /IAcceptExchangeServerLicenseTerms_DiagnosticDataON /PrepareSchema

	write-host -ForegroundColor Magenta -BackgroundColor Black "Verify that Exchange extended the AD schema correctly and then press a key to continue with AD Object setup"
	Read-Host -Prompt "Press any key to continue..."

	Dismount-DiskImage -ImagePath "$path\Exchange.iso"

	Remove-Item -Path "$path\Net4.8.exe"
	Remove-Item -Path "$path\Exchange.iso"


	# Testing to see if the necessary import files exist in the $path folder on this server. We cannot continue without them. 
	if (!(Test-Path "$path\New.OU.Creation.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the New.OU.Creation.csv file necessary to create the OU structure.";$output += "New.OU.Creation.csv`n"}
	if (!(Test-Path "$path\All.Users.Export.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the All.Users.Export.csv file necessary to create the Users.";$output += "All.Users.Export.csv`n"}
	if (!(Test-Path "$path\All.Groups.Export.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the All.Groups.Export.csv file necessary to create the Security Grous.";$output += "All.Groups.Export.csv`n"}
	if (!(Test-Path "$path\All.Groups.Expanded.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the All.Groups.Expanded.csv file necessary to create the Group Memberships.";$output += "All.Groups.Expanded.csv`n"}
	if (!(Test-Path "$path\ListGPO.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the ListGPO.csv file necessary to create the GPOs.";$output += "ListGPO.csv`n"}
	if (!(Test-Path "$path\GPO.OU.Links.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the GPO.OU.Links.csv file necessary to create the Group Memberships.";$output += "GPO.OU.Links.csv`n"}
	if (!(Test-Path "$path\GPO.Permissions.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the GPO.Permissions.csv file necessary to create the Group Memberships.";$output += "GPO.Permissions.csv`n"}
	if (!(Test-Path "$path\SID.Mapping.csv")) {write-host -ForegroundColor Magenta -BackgroundColor Black  "Missing the SID.Mapping.csv file necessary to replace to old domain SIDs with the new domain SIDs.";$output += "SID.Mapping.csv`n"}

	if ($output -notlike $null) {write-host -ForegroundColor Magenta -BackgroundColor Black  "You are missing the following necessary import files and the script cannot continue until they exist in the $path folder on this server. `nThe script is now exiting. Please add the files and restart the task from Scheduled Tasks or reboot for the script to continue.`n `nMissing files:`n"$output;Read-Host -Prompt "Press any key to continue...";exit}


	# Replacing variables in the files to make the imports work correctly
	Get-ChildItem $path\*.csv -Recurse | ForEach-Object {
		(Get-Content $_) -Replace "@$SOURCEDOMAINDNS",$FQDN | Set-Content $_
		(Get-Content $_) -Replace $SOURCEDN,$BaseOUChange | Set-Content $_
		(Get-Content $_) -Replace 'Rm. 116,OU=','OU=' | Set-Content $_
		(Get-Content $_) -Replace 'Jr,OU=','OU=' | Set-Content $_
		(Get-Content $_) -Replace 'M.S,OU=','OU=' | Set-Content $_
		(Get-Content $_) -Replace 'Default Domain Policy ','Default Domain Policy' | Set-Content $_
	}

	Get-ChildItem "$path\*.xml" -Recurse | ForEach-Object {
		(Get-Content $_) -Replace $SOURCEDOMAINDNS,$FQDN | Set-Content $_
		(Get-Content $_) -Replace [regex]::Escape("$SOURCEDOMAINNBT\"),$DomainSlash | Set-Content $_
		(Get-Content $_) -Replace 'Default Domain Policy ','Default Domain Policy' | Set-Content $_
	}

	Get-ChildItem "$path\GPO.OU.Links.csv" -Recurse | ForEach-Object {
	# Read the file and use replace()
		(Get-Content $_) -Replace 'True','YES' | Set-Content $_
		(Get-Content $_) -Replace 'False','NO' | Set-Content $_
	}



	# Create the OU Structure
	write-host -ForegroundColor Magenta -BackgroundColor Black "Creating the OU structure"
	Import-CSV $path\New.OU.Creation.csv -Delimiter ";" | New-ADOrganizationalUnit

	# Import the user list
	$users = import-csv $path\All.Users.Export.csv

	# Create the user accounts
	write-host -ForegroundColor Magenta -BackgroundColor Black "Creating the User Accounts"
	write-host -ForegroundColor Yellow -BackgroundColor Black "NOTE: You can safely ignore any error messages about password requirements not being met"
	$NewUserPassword = ConvertTo-SecureString "NewSuperSecureTest@cc0unt4Us" -AsPlainText -force
	$users |% {
		$username = $_.SamAccountName
		Try{
			$hash = @{SamAccountName=$_.SamAccountName;Name=$_.name;DisplayName=$_.DisplayName;GivenName=$_.GivenName;SurName=$_.SurName;Department=$_.Department;Path=$($_.BaseOU);Company=$_.Company;Description=$_.Description;AccountPassword=$NewUserPassword;Enabled=([System.Convert]::ToBoolean($_.Enabled));Office=$_.Office;OfficePhone=$_.OfficePhone;PostalCode=$_.PostalCode;City=$_.City;State=$_.State;Country=$_.Country;EmployeeID=$_.EmployeeID;StreetAddress=$_.StreetAddress;Title=$_.Title;EmailAddress=$_.EmailAddress;MobilePhone=$_.MobilePhone}
			$keysToRemove = $hash.keys |? {!$hash[$_]}
			$keysToRemove |% {$hash.remove($_)}
			if (!($hash.Count -eq 0)) {New-ADUser @hash}	
		}
		Catch{write-host "Error adding:" $username "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}


	# Add in additional attributes for the users
	write-host -ForegroundColor Magenta -BackgroundColor Black "Adding additional attributes to the User Accounts"
	$users |? {$_.samaccountname -notlike "SM_*"} |% {
		
		$username = $_.SamAccountName
		Try{
			$hash = @{extensionAttribute1=$_.extensionAttribute1;extensionAttribute2=$_.extensionAttribute2;extensionAttribute3=$_.extensionAttribute3;extensionAttribute4=$_.extensionAttribute4;extensionAttribute5=$_.extensionAttribute5;extensionAttribute6=$_.extensionAttribute6;extensionAttribute7=$_.extensionAttribute7;extensionAttribute8=$_.extensionAttribute8;extensionAttribute9=$_.extensionAttribute9;extensionAttribute10=$_.extensionAttribute10;extensionAttribute11=$_.extensionAttribute11;;extensionAttribute12=$_.extensionAttribute12;extensionAttribute13=$_.extensionAttribute13;extensionAttribute14=$_.extensionAttribute14;extensionAttribute15=$_.extensionAttribute15;Manager=$_.Manager;UserPrincipalName=$_.UserPrincipalName}
			$keysToRemove = $hash.keys |? {!$hash[$_]}
			$keysToRemove |% {$hash.remove($_)}
			if (!($hash.Count -eq 0)) {Set-ADUser -Identity $_.SamAccountName -Replace $hash}
		}
		Catch{write-host "Error updating:" $username "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}


	# Create Groups from File
	write-host -ForegroundColor Magenta -BackgroundColor Black "Creating the Security Groups"
	$groups = import-csv $path\All.Groups.Export.csv
	$groups |% {
		$group = $_.SamAccountName
		Try{
		$hash = @{ManagedBy=$_.owneraccount}
		$keysToRemove = $hash.keys |? {!$hash[$_]}
		$keysToRemove |% {$hash.remove($_)}
		if (!($hash.Count -eq 0)) {New-ADGroup -Path $_.BaseOU -Name $_.SamAccountName -GroupScope $_.GroupScope -GroupCategory $_.GroupCategory -DisplayName $_.DisplayName -Description $_.Description -ManagedBy $hash.ManagedBy} else {New-ADGroup -Path $_.BaseOU -Name $_.SamAccountName -GroupScope $_.GroupScope -GroupCategory Security -DisplayName $_.DisplayName -Description $_.Description}
		}
		Catch{write-host "Error creating:" $group "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}
	

	# Add Group Memberships from Group Member Export and not User MemberOf as it doesn't have Group Nesting
	write-host -ForegroundColor Magenta -BackgroundColor Black "Adding members to the Security Groups"
	$groupmemberships = import-csv $path\All.Groups.Expanded.csv
	$groupmemberships |% {
		$group = $_.GroupName
		$member = $_.SamAccountName
		Try{
		Add-ADGroupMember -Identity $_.GroupName -Members $_.SamAccountName
		}
		Catch{write-host "Error adding" $member "to" $group "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}

	#NOTE: There will very likely be some errors in this adding of members to groups. As long as it isn't all errors it should be fine. It will likely be 10 - 50 errors total or more depending on the size of the Source Domain. 


	# SID Mapping from Source Domain to New Domain for GPOs
	write-host -ForegroundColor Magenta -BackgroundColor Black "Mapping SIDs from Source Domain to the New Domain for GPOs"
	$sourcedom = import-csv $path\SID.Mapping.csv
	$newdom = $sourcedom |% {$g = $null;$g = $_;$newsid = $null;if ($g.objectclass -like "user") {$newsid = get-aduser $g.samaccountname | select -expand SID} else {$newsid = get-adgroup $g.samaccountname | select -expand SID};new-object psobject -prop ([ordered]@{SamAccountName=$g.SamAccountName;SourceSID=$g.SourceSID;ObjectClass=$g.ObjectClass;NewSID=$newsid})}

	Get-ChildItem "$path\GPO.Creation\*.xml" -Recurse |% {
		$file = $null
		$file = Get-Content $_
		foreach ($e in $newdom) {
			$file = $file -replace $e.SourceSID, $e.NewSID
		}
		set-content $_ $file
	}

	Get-ChildItem "$path\GPO.Creation\*.inf" -Recurse |% {
		$file = $null
		$file = Get-Content $_
		foreach ($e in $newdom) {
			$file = $file -replace $e.SourceSID, $e.NewSID
		}
		set-content $_ $file
	}
		

	# Create GPOs in new Domain
	write-host -ForegroundColor Magenta -BackgroundColor Black "Creating the GPOs"
	$CreateGPOs = Import-Csv -Path $path\ListGPO.csv -encoding UTF8
	$ErrorActionPreference = "Stop"
	$CreateGPOs.DisplayName |? {($_ -notlike "Default Domain Policy") -and ($_ -notlike "Default Domain Controllers Policy")} |% {
		$GPO = $_
		Try{
		New-GPO $_ | Out-Null
		}
		Catch{write-host "Error creating" $GPO "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}
	$ErrorActionPreference = "Continue"


	# Import GPOs in new Domain
	write-host -ForegroundColor Magenta -BackgroundColor Black "Importing the GPO Settings"
	$SettingsPath= "$path\GPO.Creation"
	$ErrorActionPreference = "Stop"
	$CreateGPOs.DisplayName |% {
		$GPO = $_
		Try{
		Import-GPO -BackupGpoName $_ -TargetName $_ -Path "$SettingsPath"  | Out-Null
		}
		Catch{write-host "Error restoring settings for" $GPO "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}
	$ErrorActionPreference = "Continue"	


	# Link the GPOs to OUs
	write-host -ForegroundColor Magenta -BackgroundColor Black "Linking the GPOs to OUs"
	$GPLinks = Import-Csv -Path $path\GPO.OU.Links.csv -encoding UTF8
	$ErrorActionPreference = "Stop"
	$GPLinks |% {
		$GPO = $_.DisplayName
		$OU = $_.Target
		Try{
		New-GPLink -Name $_.DisplayName -Target $_.Target -LinkEnabled:$_.Enabled -Enforced:$_.Enforced -Order $_.Order | Out-Null
		}
		Catch{write-host "Error linking" $GPO "to" $OU "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}
	$ErrorActionPreference = "Continue"


	# Set security principals on GPOs
	write-host -ForegroundColor Magenta -BackgroundColor Black "Setting Security Permissions and Filtering on the GPOs"
	$GPPerms = Import-Csv -Path $path\GPO.Permissions.csv -encoding UTF8
	$ErrorActionPreference = "Stop"
	$GPPerms |% {
		$GPO = $_.GPOName
		$Principal = $_.AccountName
		Try{ 
		if (!($_.AccountType -like "User")) {Set-GPPermission -Name $_.GPOName -TargetName $_.AccountName -TargetType Group -PermissionLevel $_.Permissions | Out-Null} 
		else {Set-GPPermission -Name $_.GPOName -TargetName $_.AccountName -TargetType User -PermissionLevel $_.Permissions | Out-Null} 
		}
		Catch{write-host "Error adding" $Principal "to" $GPO "-- " -NoNewline;write-host $PSItem.Exception.Message -ForegroundColor RED}
	}	
	$ErrorActionPreference = "Continue"
	

	# Restart to continue
	write-host -ForegroundColor Magenta -BackgroundColor Black "Verify everything above installed correctly and then press a key to reboot"
	Read-Host -Prompt "Press any key to continue..."
	Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\Domain.Creation.Continue.bat" -force
	Remove-Item -Path "$path\New.OU.Creation.csv" -force
	Remove-Item -Path "$path\All.Users.Export.csv" -force
	Remove-Item -Path "$path\All.Groups.Export.csv" -force
	Remove-Item -Path "$path\All.Groups.Expanded.csv" -force
	Remove-Item -Path "$path\ListGPO.csv" -force
	Remove-Item -Path "$path\GPO.OU.Links.csv" -force
	Remove-Item -Path "$path\GPO.Permissions.csv" -force
	Remove-Item -Path "$path\GPO.Creation" -recurse -force
	Remove-Item -Path "$path\SID.Mapping.csv" -recurse -force
	sleep 15
	restart-computer
}

Function AzureTenantSetup {
### This is a placeholder for now. May never been completed.
#
#
#
}

# Get path where the script is running from. All files should be in this directory along with the script
$path = $PSScriptRoot

# Choose Domain to Create
function DomainChooser {
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
	[void] [System.Windows.Forms.Application]::EnableVisualStyles() 
	
	$Form                 = New-Object system.Windows.Forms.Form
	$Form.Size            = New-Object System.Drawing.Size(700,300)
	$Form.MaximizeBox     = $false
	$Form.StartPosition   = "CenterScreen"
	$Form.FormBorderStyle = 'Fixed3D'
	$Form.Text            = "Domain Name for New Environment"
	$Font                 = New-Object System.Drawing.Font("Arial",11,[System.Drawing.FontStyle]::Bold)
	$Form.Font            = $Font
	
	# NetBIOS Name Parameters
	$LabelPrevious          = New-Object System.Windows.Forms.Label
	$LabelPrevious.Text     = "Enter the NetBIOS Name of the new Domain. Between 3 - 15 letters."
	$LabelPrevious.AutoSize = $true
	$LabelPrevious.Location = New-Object System.Drawing.Size(20,10)
	$Form.Controls.Add($LabelPrevious) 
	
	# Input NetBIOS Name
	$textBoxFile1          = New-Object System.Windows.Forms.TextBox
	$textBoxFile1.Location = New-Object System.Drawing.Point(20,30)
	$textBoxFile1.Size     = New-Object System.Drawing.Size(200,40)
	$Form.Controls.Add($textBoxFile1)
	
	# DNS Name Parameters
	$LabelCurrent          = New-Object System.Windows.Forms.Label
	$LabelCurrent.Text     = "Enter the DNS Name of the new Domain. Accepts letters, numbers, periods, and dashes."
	$LabelCurrent.AutoSize = $true
	$LabelCurrent.Location = New-Object System.Drawing.Size(20,100)
	$Form.Controls.Add($LabelCurrent) 
	
	# Input DNS Name
	$textBoxFile2          = New-Object System.Windows.Forms.TextBox
	$textBoxFile2.Location = New-Object System.Drawing.Point(20,120)
	$textBoxFile2.Size     = New-Object System.Drawing.Size(450,40)
	$Form.Controls.Add($textBoxFile2)
	
	# Submit entries
	$Okbutton          = New-Object System.Windows.Forms.Button
	$Okbutton.Location = New-Object System.Drawing.Size(170,200)
	$Okbutton.Size     = New-Object System.Drawing.Size(200,30)
	$Okbutton.Text     = "Submit"
	
	#  Set variables
	$Okbutton.Add_Click({
	[ValidateLength(3,15)][ValidatePattern('[a-zA-Z]')][string]$script:NetBIOSChoice = $($textBoxFile1.Text)
	[ValidateLength(6, 253)][validatePattern('^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$')][ValidateNotNullOrEmpty()][string]$script:DNSNameChoice = $($textBoxFile2.Text)
	$form.Close()
	}) 
	$Form.Controls.Add($Okbutton) 
	
	$form.ShowDialog()
}

# If the choice variables are passed from command line or the scheduled task it will skip the Domain Chooser
if (!(($NetBIOSChoice) -and ($DNSNameChoice))) {DomainChooser}

write-host -ForegroundColor Magenta -BackgroundColor Black "You entered " $NetBIOSChoice " for the NetBIOS name and " $DNSNameChoice " for the DNS name for the new domain. Is this correct?"
Read-Host -Prompt "Press any key to continue..."

# Validate the choice variables to make sure they are not existing AD domains
if (($NamesArray.Where{$NetBIOSChoice -like $_}) -or ($NamesArray.Where{$DNSNameChoice -like $_})) {write-host -ForegroundColor Magenta -BackgroundColor Black "You used a NetBIOS or DNS Name for a domain that is already in use. You will need to choose something else. Please try again.";Read-Host -Prompt "Press any key to continue...";exit}

# Set Domain Variables
$FQDN="@$DNSNameChoice";$BaseOUChange=$('DC=' + $DNSNameChoice.Replace('.',',DC='));$NetBIOS=$NetBIOSChoice;$DNSName=$DNSNameChoice;$DomainSlash="$NetBIOSChoice\"

if (!(Test-Path "$path\Exchange.iso")) {ADInstall}
if (Test-Path "$path\Exchange.iso") {SchemaObjectSetup}

