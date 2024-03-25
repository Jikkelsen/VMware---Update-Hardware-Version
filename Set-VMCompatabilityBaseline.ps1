#Requires -Version 5.1
#Requires -Modules VMware.VimAutomation.Core
<#
   _____      _       __      ____  __  _____                            _        _     _ _ _ _         ____                 _ _
  / ____|    | |      \ \    / /  \/  |/ ____|                          | |      | |   (_) (_) |       |  _ \               | (_)
 | (___   ___| |_ _____\ \  / /| \  / | |     ___  _ __ ___  _ __   __ _| |_ __ _| |__  _| |_| |_ _   _| |_) | __ _ ___  ___| |_ _ __   ___
  \___ \ / _ \ __|______\ \/ / | |\/| | |    / _ \| '_ ` _ \| '_ \ / _` | __/ _` | '_ \| | | | __| | | |  _ < / _` / __|/ _ \ | | '_ \ / _ \
  ____) |  __/ |_        \  /  | |  | | |___| (_) | | | | | | |_) | (_| | || (_| | |_) | | | | |_| |_| | |_) | (_| \__ \  __/ | | | | |  __/
 |_____/ \___|\__|        \/   |_|  |_|\_____\___/|_| |_| |_| .__/ \__,_|\__\__,_|_.__/|_|_|_|\__|\__, |____/ \__,_|___/\___|_|_|_| |_|\___|
                                                            | |                                    __/ |
                                                            |_|                                   |___/

#>
#------------------------------------------------| HELP |------------------------------------------------#
<#
    .Synopsis
        This script is to list and update all VM's hardware comptibility.
    .PARAMETER vCenterCredential
        Creds to import for authorization on vCenters
    .PARAMETER MinimumVersion
        This specifies the vmx version to which all VMs *below* will be scheduled to upgrade *to* 
    .EXAMPLE
        # Upgrade all VMs below hardware version 10 to version 10
        $Params = @{
            vCenterCredential = Get-Credential
            vCenter           = "YourvCenter"
            MinimumVersion    = "vmx-10"
        }
        Set-VMCompatabilityBaseline.ps1 @Params
#>
#---------------------------------------------| PARAMETERS |---------------------------------------------#

param
(
    [Parameter(Mandatory)]
    [pscredential]
    $vCenterCredential,

    [Parameter(Mandatory)]
    [String]
    $vCenter,

    [Parameter(Mandatory)]
    [String]
    $MinimumVersion
)

#------------------------------------------------| SETUP |-----------------------------------------------#
# Variables for connection
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Establishing connection to all vCenter servers with "-alllinked" flag
[Void](Connect-VIServer -Server $vCenter -Credential $vCenterCredential -AllLinked -Force)

#-----------------------------------| Get VMs that should be upgraded |----------------------------------#

$AllVMs      = Get-VM | Where-Object {$_.name -notmatch "delete"}
$AllVersions = ($AllVMs.HardwareVersion | Sort-Object | get-unique)
Write-Host "Found $($AllVMs.Count) VMs, with a total of $($AllVersions.count) different hardware versions, seen below"
$AllVersions

# NoteJVM: String comparison virker simpelthen. Belejligt
$VMsScheduledForCompatabilityUpgrade = $allVMs | Where-Object HardwareVersion -lt $minimumversion
Write-host "Of those VMs, $($VMsScheduledForCompatabilityUpgrade.Count) has a hardware version lower than $MinimumVersion"

#----------------------------------| Schedule the upgrade on those VMs |---------------------------------#
if ($VMsScheduledForCompatabilityUpgrade.count -ne 0)
{
    Write-Host " ---- Scheduling hardware upgrade ---- "
    
    # Create a VirtualMachineConfigSpec object to define the scheduled hardware upgrade
    # This task will schedule VM compatability upgrade to $MimimumVersion 
    $UpgradeTask = New-Object -TypeName "VMware.Vim.VirtualMachineConfigSpec"
    $UpgradeTask.ScheduledHardwareUpgradeInfo               = New-Object -TypeName "VMware.Vim.ScheduledHardwareUpgradeInfo"
    $UpgradeTask.ScheduledHardwareUpgradeInfo.UpgradePolicy = [VMware.Vim.ScheduledHardwareUpgradeInfoHardwareUpgradePolicy]::onSoftPowerOff
    $UpgradeTask.ScheduledHardwareUpgradeInfo.VersionKey    = $MinimumVersion

    # Schedule each VM for upgrade to baseline, group by hardwareversion
    Foreach ($Group in ($VMsScheduledForCompatabilityUpgrade | Group-Object -Property "HardwareVersion"))
    {
        Write-Host " ---- $($Group.name) ---- "

        foreach ($VM in $Group.Group)
        {
            try
            {
                Write-Host "Scheduling upgrade on $($VM.name) ... "  -NoNewline
                
                #The scheduled hardware upgrade will take effect during the next soft power-off of each VM
                $Task = $vm.ExtensionData.ReconfigVM_Task($UpgradeTask)
                
                Write-Host "OK - created $($Task.Value)"
            }
            catch
            {
                Write-Host "FAIL!"
                throw
            }
        }
    }
}
else
{
    Write-host "All VMs are of minimum version $MinimumVersion at this time."
}
#---------------------------------------------| DISCONNECT |---------------------------------------------#
Write-Host "Cleanup: Disconnecting vCenter" 
Disconnect-VIserver * -Confirm:$false
Write-Host "The script has finished running: Closing"
#-------------------------------------------------| END |------------------------------------------------#
