# "Cloned" AD Environment Setup Scripts and Documentation

This repo is for the scripts and documentation necessary to create and maintain the new Active Directory (AD) environments that have been created in order to "clone" an AD environment for testing/development purposes. 

The new AD environment will be created as “mirrors” of the Source AD environment. They can be kept in sync with Source environment as well except when necessary. 

There will be NO Forest-to-Forest Trusts created between the Source domains and the new domains. The Source and Target domains will each be a distinct security boundary and synchronization of users and groups will occur from Source to Target only. There will be no mechanism nor allowance to sync any users or groups back to Source. Each new domain will have the Active Directory Schema extended for Exchange in order to provide the same attributes on objects as exists in Source. However, Exchange will not be installed in the Target environment. Only the schema extension from the Exchange installation is necessary. 

*Future functionality: A corresponding Azure Tenant with Azure Active Directory will be created for each new domain and Azure AD Sync (AADSync) will be implemented to keep each new domain in sync with it’s Azure AD instance.*
NOTE: Currently this is still a manual process


## Installation Instructions

The overall order in which you need to proceed is this:
* Gather all required export files
* Copy all required files to the target server
* Run the script
* Check for errors on 1st part and then reboot
* Run 2nd part manually (if it doesn't continue automatically)
* Check 2nd part for errors and reboot
* Launch ADUC and GPMC tools to verify OUs, users, groups, and GPOs were created and correct


### Gather all required export files
You will need to either run the Domain.Migration.Object.Retrieval.ps1 script or by copying/pasting the commands. You will need to do this using a Domain Admin account or a dedicated service account for retrieval on a server with the RSAT PowerShell extensions installed on it. This server will need to be a member of the ***SOURCE*** domain. By default, this will create files/run in the directory in which you are in. All the relevant CSV files and GPO backup directories will be created there. 


### Copy all required files to the target server
Once you have exported all the necessary files, you will need to copy them to the Target server you are going to turn in to a "cloned" Domain Controller. You should have 8 CSVs in a directory on your Source server and a sub-directory named GPO.Creation (C:\Temp\GPO.Creation for instance if using C:\Temp on the Source server) with a sub-directory for each GPO that was backed up. You need to copy all 8 CSV files and the GPO.Creation directory. You will also need the Domain.Creation.Script.ps1 from GitHub. Put all of the files in your desired folder on the Target server. 


### Run the script
Once you have all the files in on the Target server, you are ready to run the script. To run the script, you will need to open a PowerShell window with Run as Administrator privileges. You cannot run the script just by clicking on it. The script will need elevated privileges that you will only get by starting an Administrator: PowerShell window.

In your PowerShell window, enter `cd ***drive:\directory***` (i.e. c:\temp) to get to the correct directory to run the script and then enter `Domain.Creation.Script.ps1` and hit Tab then enter in order to run the script. 

You should see a pop-up window that forces you to choose which domain to create:
![Domain Chooser](/assets/images/Domain.Chooser.jpg)


### Check for errors on 1st part and then reboot
Once you choose the domain, the script will automatically run the 1st part. This part downloads .NET and Exchange for installation later, adds the appropriate management tools, and creates the new Forest and Domain. Once everything is downloaded and installed, the script will pause for you to review the screen output. Once you have done that and pressed a key to continue, the server will reboot to continue.


### Run 2nd part manually (if it doesn't continue automatically)
Part 2 should start upon logging in as the Administrator account after the reboot. It is possible that it does not and that will be covered below. Part 2 will the extend the AD Schema for Exchange (but not install any Exchange components) and then create the OUs, Users, Groups, Group Memberships, GPOs, GPO Links, and GPO Security Filtering based on the exported files you copied to the Target server. If any of the files are not found, the script will exit.  

If, for some reason, the script does not start automatically for Part 2 or it does something weird like trying to re-run Part 1, you can manually get it to start in Part 2. You will need to open a PowerShell window with Run as Administrator privileges again. Go to the directory where you copied the files (i.e. `cd c:\temp`) and again enter `Domain.Creation.Script.ps1` and hit Tab. However, do ***NOT*** hit enter just yet. Instead, you need to put in the name of the domain you chose/created in Part 1. So, either `.\Domain.Creation.Script.ps1 DEV` or `.\Domain.Creation.Script.ps1 TEST`. Then hit Enter and it should proceed to Part 2 and begin doing the Exchange Schema extension. 


### Check 2nd part for errors and reboot
Once Part 2 is finished, it will again pause for you to review the screen output. Once you have done that and pressed a key to continue, the server will reboot one more time. Once it comes back from the reboot, the installation process is finished.


### Launch ADUC and GPMC tools to verify OUs, users, groups, and GPOs were created and correct
After the final reboot, log in to the server and check to make sure objects were created by spot checking. Use *Active Directory Users & Computers* to check OUs, Users, Groups, and Group Memberships were created. Spot check a few objects at random. For GPOs, use *Group Policy Management Console* to check that GPOs are indeed linked to OUs and that some GPOs have additional objects added to Security Filtering. 
