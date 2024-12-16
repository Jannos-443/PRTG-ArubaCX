<#
.SYNOPSIS
Monitors Aruba CX Switches using the Switch Rest API

.DESCRIPTION
Powershell Script to monitor Aruba CX Switch Health including CPU, FAN, PSU...

.PARAMETER Hostname
Device Hostname or IP

.PARAMETER Username
Monitoring User Login

.PARAMETER Password
Monitoring User Password

.PARAMETER ChannelPSU
Use -ChannelPSU to Include PSUs in the PRTG output
-> if no -ChannelXXX Parameter is used, every Channel will be in the Output

.PARAMETER ChannelFAN
Use -ChannelFAN to Include FANs in the PRTG output
-> if no -ChannelXXX Parameter is used, every Channel will be in the Output

.PARAMETER ChannelTEMP
Use -ChannelTEMP to Include TEMPs in the PRTG output
-> if no -ChannelXXX Parameter is used, every Channel will be in the Output

.PARAMETER ChannelNAE
Use -ChannelNAE to Include NAEs in the PRTG output
-> if no -ChannelXXX Parameter is used, every Channel will be in the Output

.PARAMETER ChannelSystem
Use -ChannelSystem to Include System in the PRTG output
-> if no -ChannelXXX Parameter is used, every Channel will be in the Output

.PARAMETER ChannelInterfaces
Use -ChannelInterfaces to Include Interfaces in the PRTG output
-> if no -ChannelXXX Parameter is used, every Channel will be in the Output

.PARAMETER IncludeDescription
Use Regual Expression to filter for Interfaces by Description
-IncludeDescription "^(.*uplink.*)$" = all interfaces with description having "uplink" in the description

.PARAMETER IncludeInterface
Use Regual Expression to filter for Interfaces by InterfaceName

.PARAMETER ExcludeDescription
Use Regual Expression to filter for Interfaces by Description

.PARAMETER ExcludeInterface
Use Regual Expression to filter for Interfaces by InterfaceName

.PARAMETER IncludeAdminDown
by default all "AdminDown" Interfaces are excluded for interface monitoring
Use -IncludeAdminDown to also monitor AdminDown Interfaces

.PARAMETER DesiredState
by default the DesiredState for Interfaces is "up", if you want to be alerted on a interfaces that goes UP you could change it to -DesiredState "down"

Regular Expression: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_regular_expressions?view=powershell-7.1

.EXAMPLE
1. Download/Install the Powershell Module "PowerArubaCX" on your PRTG Probe
    - Install-Module PowerArubaCX
    - https://github.com/PowerAruba/PowerArubaCX
    - Verify that the Module is available under "C:\Program Files (x86)\WindowsPowerShell\Modules\PowerArubaCX" # PRTG use x86 Powershell
2. Put LinuxUser and LinuxPassword Credentials for Rest API Access in PRTG
3. Put PRTG-ArubaCX.ps1 under "C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML"
3. Sample call from PRTG EXE/Script Advanced
    - PRTG-ArubaCX.ps1 -Hostname "%host" -Username "%linuxuser" -Password "%linuxpassword"

.NOTES
Version:        1.00
Author:         Jannos-443
URL:            https://github.com/Jannos-443/
Creation Date:  13.12.2024

This script is based on https://github.com/fabi-d/arubaoscx-prtg from fabi-d

#>
param(
    [string]$Hostname = "",
    [string]$Username = "",
    [string]$Password = '',
    [switch]$ChannelPSU,
    [switch]$ChannelFAN,
    [switch]$ChannelTEMP,
    [switch]$ChannelNAE,
    [switch]$ChannelSystem,
    [switch]$ChannelInterfaces,
    [string]$IncludeInterface = "",
    [string]$IncludeDescription = "^(.*uplink.*)$",
    [string]$ExcludeInterface = "",
    [string]$ExcludeDescription = "",
    [switch]$IncludeAdminDown,
    [String]$DesiredState = "up"
)

trap {
    if ($connection) {
        try {
            Write-Host "disconnecting session because an error ocured"
            Disconnect-ArubaCX -connection $connection -Confirm:$false | out-null
        }
        catch {
            Write-Host "disconnecting session failed"
        }
    }
    $Output = "line:$($_.InvocationInfo.ScriptLineNumber.ToString()) char:$($_.InvocationInfo.OffsetInLine.ToString()) --- message: $($_.Exception.Message.ToString()) --- line: $($_.InvocationInfo.Line.ToString()) "
    $Output = $Output.Replace("<", "")
    $Output = $Output.Replace(">", "")
    $Output = $Output.Replace("#", "")
    Write-Output "<prtg>"
    Write-Output "<error>1</error>"
    Write-Output "<text>$($Output)</text>"
    Write-Output "</prtg>"
    Exit
}

if (($DesiredState -ne "up") -and ($DesiredState -ne "down")) {
    Write-Output "<prtg>"
    Write-Output "<error>1</error>"
    Write-Output "<text>-DesiredState needs to be `"up`" or `"down`"</text>"
    Write-Output "</prtg>"
    Exit
}

# Check Channels
if ((-not $ChannelPSU) -and (-not $ChannelFAN) -and (-not $ChannelTEMP) -and (-not $ChannelNAE) -and (-not $ChannelSystem) -and (-not $ChannelInterfaces)) {
    $ChannelPSU = $true
    $ChannelFAN = $true
    $ChannelTEMP = $true
    $ChannelNAE = $true
    $ChannelSystem = $true
    $ChannelInterfaces = $true
}

# Error if there's anything going on
$ErrorActionPreference = "Stop"

#Add-Type -AssemblyName System.Web

# import modules and overwrite existing ones
try {
    Import-Module PowerArubaCX
}
catch {
    $Output = "PS Module `"PowerArubaCX`" Import failed, verify `"C:\Program Files (x86)\WindowsPowerShell\Modules\PowerArubaCX`" exists || line:$($_.InvocationInfo.ScriptLineNumber.ToString()) char:$($_.InvocationInfo.OffsetInLine.ToString()) --- message: $($_.Exception.Message.ToString()) --- line: $($_.InvocationInfo.Line.ToString()) "
    # trim string to 2000 letter
    if ($Output.length -gt 1970) {
        $Output = $Output.Substring(0, 1970)
        $Output = $Output.Insert($Output.length, " || OUTPUT TO LONG... || ")
    }
    $Output = $Output.Replace("<", "")
    $Output = $Output.Replace(">", "")
    $Output = $Output.Replace("#", "")
    Write-Output "<prtg>"
    Write-Output "<error>1</error>"
    Write-Output "<text>$($Output)</text>"
    Write-Output "</prtg>"
    Exit
}


# Ignore Certificates
if ($IgnoreCert) {
    add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
    ServicePoint srvPoint, X509Certificate certificate,
    WebRequest request, int certificateProblem) {
    return true;
        }
    }
"@
    try {
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }
    catch {}
}

# set culture to en-US to avoid problems with decimal point in XML
function setCulture() {
    # set decimal point for serialization in XML
    $culture = [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    $culture.NumberFormat.NumberDecimalSeparator = "."
    $culture.NumberFormat.NumberGroupSeparator = ","
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
}


# add channel for the used PoE power in percent of a single chassis (switch) 
function addPoePercentageChannel([string] $ModuleDisplayName, [Object] $PoePower) {
    $PoeAvailable = $PoePower.available_power
    $PoeConsumed = $PoePower.drawn_power
  
    # calculate percentage
    $PoePercentage = [math]::Round(($PoeConsumed / $PoeAvailable) * 100, 0)
  
    # add channel
    $xmlOutput += "<result>
    <channel>$($ModuleDisplayName) PoE drawn</channel>
    <value>$($PoePercentage)</value>
    <unit>Percent</unit>
    </result>"
}

function Subsystems($data) {
    $xmlOutput_temp = ""
    #region Subsystem:
    $All_TEMPs = New-Object -TypeName "System.Collections.ArrayList"
    $All_PSUs = New-Object -TypeName "System.Collections.ArrayList"
    $All_FANs = New-Object -TypeName "System.Collections.ArrayList"
    $global:All_MGMTModules = New-Object -TypeName "System.Collections.ArrayList"
    $All_Modules = New-Object -TypeName "System.Collections.ArrayList"

    foreach ($Module in $data.PSObject.Properties) {
        $null = $All_Modules.Add($Module)
        foreach ($FAN in $module.value.fans.psobject.Properties) {
            $null = $All_FANs.Add($FAN)
        }
        foreach ($PSU in $module.value.power_supplies.psobject.Properties) {
            $null = $All_PSUs.Add($PSU)
        }
        foreach ($TEMP in $module.value.temp_sensors.psobject.Properties) {
            $null = $All_TEMPs.Add($TEMP)
        }
        if ($Module.Value.type -eq "management_module") {
            $null = $All_MGMTModules.Add($Module)
        }
    }

    # FAN
    if ($ChannelFAN) {
        if ($All_FANs.count -gt 0) {
            $status_ok = $All_FANs | Where-Object { $_.value.status -eq "ok" }
            $status_not_ok = $All_FANs | Where-Object { $_.value.status -ne "ok" }
            # calculate failed percentage
            $percentage = [math]::Round((($All_FANs.count - $status_not_ok.count) / $All_FANs.count) * 100, 0)
  
            foreach ($notok in $status_not_ok) {
                $xmlOutputText_temp += "FAN `"$($notok.value.name)`" state: `"$($notok.value.status)`" || "
            }

            # add channel
            $xmlOutput_temp += "<result>
        <channel>FAN Health</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMinError>100</LimitMinError>
        </result>"
        }
    }
    # PSU
    if ($ChannelPSU) {
        if ($All_PSUs.count -gt 0) {
            $status_ok = $All_PSUs | Where-Object { $_.value.status -eq "ok" }
            $status_not_ok = $All_PSUs | Where-Object { $_.value.status -ne "ok" }
            # calculate failed percentage
            $percentage = [math]::Round((($All_PSUs.count - $status_not_ok.count) / $All_PSUs.count) * 100, 0)
      
            foreach ($notok in $status_not_ok) {
                $xmlOutputText_temp += "PSU `"$($notok.value.name)`" state: `"$($notok.value.status)`" || "
            }

            # add channel
            $xmlOutput_temp += "<result>
        <channel>PSU Health</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMinError>100</LimitMinError>
        </result>"
        }
    }
    # TEMP
    if ($ChannelTEMP) {
        if ($All_TEMPs.count -gt 0) {
            $status_ok = $All_TEMPs | Where-Object { $_.value.status -eq "normal" }
            $status_not_ok = $All_TEMPs | Where-Object { $_.value.status -ne "normal" }
            # calculate failed percentage
            $percentage = [math]::Round((($All_TEMPs.count - $status_not_ok.count) / $All_TEMPs.count) * 100, 0)
      
            foreach ($notok in $status_not_ok) {
                $xmlOutputText_temp += "TEMP `"$($notok.value.name)`" state: `"$($notok.value.status)`" || "
            }

            # add channel
            $xmlOutput_temp += "<result>
        <channel>TEMP Health</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMinError>100</LimitMinError>
        </result>"

            $InletTempSensors = $All_TEMPs | Where-Object { $_.Value.name -match "Inlet-Air$" }
            if (($InletTempSensors | Measure-Object).count -gt 0) {
                $MaxInletTemp = 0
                foreach ($InletTempSensor in $InletTempSensors) {
                    if ($InletTempSensor.Value.temperature -gt $MaxInletTemp) {
                        $MaxInletTemp = $InletTempSensor.Value.temperature
                    }
                }
                $MaxInletTemp = [math]::Round($MaxInletTemp / 1000, 1)
                if ($MaxInletTemp -ne 0) {
                    $xmlOutput_temp += "<result>
            <channel>TEMP Inlet</channel>
            <value>$($MaxInletTemp)</value>
            <unit>Temperature</unit>
            <float>1</float>
            </result>"
                }
            }
        }
        $CPUTempSensors = $All_TEMPs | Where-Object { $_.Value.name -like "*CPU*" }
        if (($CPUTempSensors | Measure-Object).count -gt 0) {
            $MaxCpuTemp = 0
            foreach ($CPUTempSensor in $CPUTempSensors) {
                if ($CPUTempSensor.Value.temperature -gt $MaxCpuTemp) {
                    $MaxCpuTemp = $CPUTempSensor.Value.temperature
                }
            }
            $MaxCpuTemp = [math]::Round($MaxCpuTemp / 1000, 1)
            if ($MaxCpuTemp -ne 0) {
                $xmlOutput_temp += "<result>
            <channel>TEMP CPU</channel>
            <value>$($MaxCpuTemp)</value>
            <unit>Temperature</unit>
            <float>1</float>
            </result>"
            }
        }
        
    }
    #CPU AND RAM
    if ($ChannelSystem) {
        if ($All_MGMTModules.count -gt 0) {
            $max_cpu_avg1 = 0
            $max_cpu_avg5 = 0
            $max_memory = 0
            foreach ($MGMTModule in $All_MGMTModules) {
                if ($MGMTModule.Value.resource_utilization.cpu_avg_1_min -gt $max_cpu_avg1) {
                    $max_cpu_avg1 = $MGMTModule.Value.resource_utilization.cpu_avg_1_min
                }
                if ($MGMTModule.Value.resource_utilization.cpu_avg_5_min -gt $max_cpu_avg5) {
                    $max_cpu_avg5 = $MGMTModule.Value.resource_utilization.cpu_avg_5_min
                }
                if ($MGMTModule.Value.resource_utilization.memory -gt $max_memory) {
                    $max_memory = $MGMTModule.Value.resource_utilization.memory
                }
            }
            # CPU 1min AVG
            $percentage = [math]::Round($max_cpu_avg1, 0)
            $xmlOutput_temp += "<result>
        <channel>CPU 1min</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        </result>"
            # CPU 5min AVG
            $percentage = [math]::Round($max_cpu_avg5, 0)
            $xmlOutput_temp += "<result>
        <channel>CPU 5min</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMaxError>90</LimitMaxError>
        </result>"
            # RAM
            $percentage = [math]::Round($max_memory, 0)
            $xmlOutput_temp += "<result>
        <channel>Memory</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMaxError>90</LimitMaxError>
        </result>"
        }
    }
    # Modules
    if ($ChannelSystem) {
        if ($All_Modules.count -gt 1) {
            $status_ok = $data.psobject.Properties | Where-Object { $_.value.name -ne 1 } | Where-Object { ($_.value.state -eq "empty") -or ($_.value.state -eq "ready") }
            $status_not_ok = $data.psobject.Properties | Where-Object { $_.value.name -ne 1 } | Where-Object { ($_.value.state -ne "empty") -and ($_.value.state -ne "ready") }
            $All_Modules_withoutChassis = $All_Modules | Where-Object { $_.value.name -ne 1 }
            # calculate failed percentage
            $percentage = [math]::Round((($All_Modules_withoutChassis.count - $status_not_ok.count) / $All_Modules_withoutChassis.count) * 100, 0)

            foreach ($notok in $status_not_ok) {
                $xmlOutputText_temp += "Module `"$($notok.value.name)`" state: `"$($notok.value.state)`" || "
            }

            # add channel
            $xmlOutput_temp += "<result>
        <channel>Module Health</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMinError>100</LimitMinError>
        </result>"
        }
    }


    #endregion
    $global:xmlOutput += $xmlOutput_temp
    $global:OutputText += $xmlOutputText_temp
}
  
function createTransceiverChannel([Object] $data) {
    
    #region: Transeiver
    if ($ChannelInterfaces) {
        if (-not $IncludeAdminDown) {
            #remove ports with AdminDown
            $data = $data | Where-Object {(-not ($_.value.admin_state -eq "down"))}

            #LAG admin_state is always $null
            #LAG admin is $null if AdminDown and "up" if AdminUp
            $data = $data | Where-Object {(-not (($null -eq $_.value.admin_state) -and ($null -eq $_.value.admin)))}
        }    

        $transceivers = 0
        $total_errors = 0

        foreach ($Transceiver in $data) {
            $pmInfo = $Transceiver.Value.pm_info
            $l1_state = $Transceiver.Value.l1_state

            # skip interfaces without transceiver
            if ($null -eq $pmInfo.connector -or $pmInfo.connector -eq "Absent") {
                continue
            }

            # skip interfaces without connection
            if ($l1_state.l1_state_down_reason -eq "waiting_for_link" -and $settings.Transceiver.IgnoreWaitingForLinkPorts -eq "true") {
                continue
            }

            # skip interfaces that are administratively down
            if ($l1_state.l1_state_down_reason -eq "admin_down" -and $settings.Transceiver.IgnoreAdminDownPorts -eq "true") {
                continue
            }

            $transceivers++

            #rx_power_high_alarm
            #rx_power_low_alarm
            #tx_power_high_alarm
            #tx_power_low_alarm
            if ($pmInfo.rx_power_high_alarm -eq "On" `
                    -or $pmInfo.rx_power_low_alarm -eq "On" `
                    -or $pmInfo.tx_power_high_alarm -eq "On" `
                    -or $pmInfo.tx_power_low_alarm -eq "On") {
                $total_errors++
                $xmlOutputText_temp += "$($Transceiver.value.name) RXTXAlerts, "
            }

            #temperature_high_alarm
            #temperature_low_alarm

            if ($pmInfo.temperature_high_alarm -eq "On" `
                    -or $pmInfo.temperature_low_alarm -eq "On") {
                $total_errors++
                $xmlOutputText_temp += "$($Transceiver.value.name) TempErrors, "
            }

            #tx_bias_high_alarm
            #tx_bias_low_alarm

            if ($pmInfo.tx_bias_high_alarm -eq "On" `
                    -or $pmInfo.tx_bias_low_alarm -eq "On") {
                $total_errors++
                $xmlOutputText_temp += "$($Transceiver.value.name) LaserBiasErrors, "
            }

            #vcc_high_alarm
            #vcc_low_alarm

            if ($pmInfo.vcc_high_alarm -eq "On" `
                    -or $pmInfo.vcc_low_alarm -eq "On") {
                $total_errors++
                $xmlOutputText_temp += "$($Transceiver.value.name) VoltageErrors, "
            }
        }

        if ($transceivers -eq 0) {
            return
        }

        if($total_errors -gt 0){
            $xmlOutputText_temp += " || "
        }
        else{
            $xmlOutputText_temp = ""
        }

        $xmlOutput_temp += "<result>
    <channel>Transceiver alerts</channel>
    <value>$($total_errors)</value>
    <unit>Count</unit>
    <LimitMode>1</LimitMode>
    <LimitMaxError>0</LimitMaxError>
    </result>"

        #endregion:
        $global:xmlOutput += $xmlOutput_temp
        $global:OutputText += $xmlOutputText_temp
    }
}

function GetInterfaces([Object] $data) {
    #region: Interfaces
    if ($ChannelInterfaces) {
        $interface_state_wrong = 0
        if (-not $IncludeAdminDown) {
            #remove ports with AdminDown
            $data = $data | Where-Object {(-not ($_.value.admin_state -eq "down"))}

            #LAG admin_state is always $null
            #LAG admin is $null if AdminDown and "up" if AdminUp
            $data = $data | Where-Object {(-not (($null -eq $_.value.admin_state) -and ($null -eq $_.value.admin)))}
        }
        $Interfaces_Count = ($data | Measure-Object).count
        foreach ($interface in $data) {
            $tempstate = "unknown?"
            # for normal interfaces link_state shows the state
            if($null -ne $interface.value.link_state){
                $tempstate = $interface.value.link_state
            }
            # for lag interfaces bond_status.state shows the state
            else{
                $tempstate = $interface.value.bond_status.state
            }
            if ($tempstate -ne "up") {
                $xmlOutputText_temp += "Int `"$($interface.value.name)`" Desc `"$($interface.value.description)`" status `"$($tempstate)`" || "
                $interface_state_wrong ++
            }
        }
        $xmlOutput_temp += "<result>
        <channel>Interface monitored</channel>
        <value>$($Interfaces_Count)</value>
        <unit>Count</unit>
        </result>"
        $xmlOutput_temp += "<result>
        <channel>Interface state wrong</channel>
        <value>$($interface_state_wrong)</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0</LimitMaxError>
        </result>"
    }
    #endregion:
    $global:xmlOutput += $xmlOutput_temp
    $global:OutputText += $xmlOutputText_temp
}

function NAE() {
    #region NAE:
    if ($ChannelNAE) {
        $xmlOutput_temp = ""
        $xmlOutputText_temp = ""

        $prtg_nae_state = -1

        # THIS WILL FAIL IF THE SWITCH DOES NOT SUPPORT NAE
        try {
            $data = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system\nae_scripts"
            $prtg_nae_state = 1
        }
        catch {
            $prtg_nae_state = -1
        }

        #NAE NOT SUPPORTED
        if ($prtg_nae_state -eq -1) {
            $xmlOutputText_temp += "NAE not supported || "

            $xmlOutput_temp += "<result>
        <channel>NAE Health</channel>
        <value>100</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMinError>100</LimitMinError>
        </result>"

        }

        #NAE SUPPORTED
        else {
            $All_NAE_Scripts = New-Object -TypeName "System.Collections.ArrayList"
            $All_NAE_Agents = New-Object -TypeName "System.Collections.ArrayList"
    
            #GET ALL NAE SCRIPTS AND AGENTS
            foreach ($nae_script in $data.PSObject.Properties) {
                $null = $All_NAE_Scripts.Add($nae_script.value)
    
                $nae_agents = $null
                $nae_agents = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system\nae_scripts\$($nae_script.name)\nae_agents" -depth 2
                foreach ($nae_agent in $nae_agents.PSObject.Properties) {
                    $null = $All_NAE_Agents.Add($nae_agent.Value)
                }
            
    
            }
    
            $status_ok = ($All_NAE_Agents | Measure-Object).count
            $status_error = ($All_NAE_Agents | Where-Object { $_.status.error_at -ne 0 } | Measure-Object).count
    
            # calculate failed percentage
            $percentage = [math]::Round((($status_ok - $status_error) / $status_ok) * 100, 0)
    
            # add channel
            $xmlOutput_temp += "<result>
        <channel>NAE Health</channel>
        <value>$($percentage)</value>
        <unit>Percent</unit>
        <LimitMode>1</LimitMode>
        <LimitMinError>100</LimitMinError>
        </result>"
        }
    }
    


    #endregion
    $global:xmlOutput += $xmlOutput_temp
    $global:OutputText += $xmlOutputText_temp
}
  

function SYSTEM($data) {
    if ($ChannelSystem) {
        $xmlOutput_temp = ""
        $xmlOutputText_temp = ""

        $xmlOutputText_temp += "hostname: `"$($data.hostname)`" platform: `"$($data.platform_name)`" version: `"$($data.software_version)`" || "

        #region: Boot Time
        $unixTimeStamp = $data.boot_time
        $date1 = (Get-Date 01.01.1970) + ([System.TimeSpan]::fromseconds($unixTimeStamp))  
        $date_today = Get-Date
        $Uptime = (New-TimeSpan -Start $date1 -End $date_today).TotalSeconds
        $Uptime = [math]::Round($Uptime)

        $xmlOutput_temp += "
    <result>
    <channel>Uptime</channel>
    <value>$($Uptime)</value>
    <unit>TimeSeconds</unit>
    </result>"
        #endregion:

        #region: NTP
        $prtg_ntp_state = -1
        if ($null -eq $data.ntp_config) {
            $prtg_ntp_state = -1
        }
        elseif ($data.ntp_config.enable -ne $true) {
            $prtg_ntp_state = 0
        }
        else {
            $prtg_ntp_state = 1
            $ntp_last_polled_max = 0

            $ntp_ass_response = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system\vrfs\default\ntp_associations" -depth 2

            if ((($ntp_ass_response.psobject.Properties | Measure-Object).count) -eq 0) {
                Write-Error "NTP enabled but no server found???"
            }
            foreach ($ntp in $ntp_ass_response.psobject.Properties) {
                $ntp_last_polled_temp = 0
                if ($null -eq $ntp.value.association_status) {
                    $ntp_last_polled_temp = 115516800
                    $xmlOutputText_temp += "NTP $($ntp.value.address) was never polled || "
                }
                #NTP response "--" = never polled
                elseif ($ntp.value.association_status.last_polled -eq "--") {
                    $ntp_last_polled_temp = 115516800
                    $xmlOutputText_temp += "NTP $($ntp.value.address) was never polled || "
                }
                #NTP response "-" = 0 sec ago 
                elseif ($ntp.value.association_status.last_polled -eq "-") {
                    $ntp_last_polled_temp = 0
                }
                else {
                    $ntp_last_polled_temp = $ntp.value.association_status.last_polled
                }

                if ($ntp_last_polled_temp -gt $ntp_last_polled_max) {
                    $ntp_last_polled_max = $ntp_last_polled_temp
                }
            }# End for Each NTP

            $xmlOutput_temp += "
        <result>
        <channel>NTP Last Polled</channel>
        <value>$($ntp_last_polled_max)</value>
        <unit>TimeSeconds</unit>
        <LimitMode>1</LimitMode>
        <LimitMaxError>2592000</LimitMaxError>
        </result>"
        }
        
    


        #prtg_ntp_state = -1 = unkown
        #prtg_ntp_state = 0 = disabled
        #prtg_ntp_state = 1 = enabled
        $xmlOutput_temp += "<result>
    <channel>NTP State</channel>
    <value>$($prtg_ntp_state)</value>
    <unit>Custom</unit>
    <CustomUnit>Status</CustomUnit>
    <valuelookup>arubacx.ntp.state</valuelookup>
    </result>"
        #endregion:

        #region: VSX
        $prtg_vsx_state = -1
        $prtg_vsx_string = ""
        try {
            $vsx_response = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system\vsx" -depth 2
            $prtg_vsx_state = 1
        }
        catch {
            $prtg_vsx_state = -1
        }

        #VSX SUPPORTED/ENABLED
        if ($prtg_vsx_state -eq 1) {

            $VSX_device_role = $vsx_response.device_role
            $VSX_oper_status = $vsx_response.oper_status

            #Config Sync

            if ($vsx_response.config_sync_disable -eq $true) {
                $VSX_oper_status_config_sync_state = "disabled"
            }
            
            else {
                $VSX_oper_status_config_sync_state = $VSX_oper_status.config_sync_state
                if ($VSX_oper_status_config_sync_state -ne "in-sync") {
                    $prtg_vsx_state = 2
                }
            }
            #islp_Link_state
            $VSX_oper_status_islp_link_state = $VSX_oper_status.islp_link_state
            if ( $VSX_oper_status_islp_link_state -ne "in_sync") {
                $prtg_vsx_state = 2
            }
            #islp_device_state
            $VSX_oper_status_islp_device_state = $VSX_oper_status.islp_device_state
            if ($VSX_oper_status_islp_device_state -ne "peer_established") {
                $prtg_vsx_state = 2
            }

            #isl_mgmt_state
            $VSX_oper_status_isl_mgmt_state = $VSX_oper_status.isl_mgmt_state
            if ($VSX_oper_status_isl_mgmt_state -ne "operational") {
                $prtg_vsx_state = 2
            }

            $prtg_vsx_string = "VSX - Role: `"$($VSX_device_role)`" ISL State: `"$($VSX_oper_status_islp_link_state)`" ISL Peer: `"$($VSX_oper_status_islp_device_state)`" ISL MGMT: `"$($VSX_oper_status_isl_mgmt_state)`" ConfigSync: `"$($VSX_oper_status_config_sync_state) || "
        
            $prtg_vsx_ka_state = -1
            if ($vsx_response.keepalive_status) {
                if ($vsx_response.keepalive_status.state -eq "init") {
                    $prtg_vsx_ka_state = 2
                }
                elseif ($vsx_response.keepalive_status.state -eq "in_sync_established") {
                    $prtg_vsx_ka_state = 3
                }
                elseif ($vsx_response.keepalive_status.state -eq "configured") {
                    $prtg_vsx_ka_state = 4
                }
                elseif ($vsx_response.keepalive_status.state -eq "failed") {
                    $prtg_vsx_ka_state = 5
                }
                else {
                    $prtg_vsx_ka_state = -2
                }
            }
            else {
                $prtg_vsx_ka_state = 0
            }
            #KA_Status
            # -1 = Error
            # 0 = not supported
            # 1 = not configured
            # 2 = init
            # 3 = established
            # 4 = configured
            # 5 = failed
            $xmlOutput_temp += "<result>
        <channel>VSX KeepAlive State</channel>
        <value>$($prtg_vsx_ka_state)</value>
        <unit>Custom</unit>
        <CustomUnit>Status</CustomUnit>
        <valuelookup>arubacx.keepalive.state</valuelookup>
        </result>"

        }

        $xmlOutputText_temp += $prtg_vsx_string

        # -2 = unknown
        # -1 = not configured
        # 0 = disabled
        # 1 = ok
        # 2 = failed
        $xmlOutput_temp += "<result>
    <channel>VSX State</channel>
    <value>$($prtg_vsx_state)</value>
    <unit>Custom</unit>
    <CustomUnit>Status</CustomUnit>
    <valuelookup>arubacx.vsx.state</valuelookup>
    </result>"

        #endregion: VSX

        #region: VSF
        $prtg_vsf_state = -1
        $prtg_vsf_string = ""
        try {
            $vsf_response = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system" -attributes "vsf_status" -depth 2
            $prtg_vsf_state = 1

            #EMPTY Response = NotSupported
            if (($null -eq $vsf_response.vsf_status) -or ([string]::IsNullOrEmpty($vsf_response.vsf_status))) {
                $prtg_vsf_state = -1
            }
        }
        catch {
            $prtg_vsf_state = -1
        }

        #VSF SUPPORTED/ENABLED
        if ($prtg_vsf_state -eq 1) {

            if ($vsf_response.vsf_status.topology_type -eq "standalone") {
                $prtg_vsf_state = 0
            }
            else {
                $prtg_vsf_string = "VSF type: `"$($vsf_response.vsf_status.topology_type)`" state: `"$($vsf_response.vsf_status.stack_split_state)`" || "
                if ($vsf_response.vsf_status.stack_split_state -ne "no_split") {
                    $prtg_vsf_state = 3
                }
                else {
                    if ($vsf_response.vsf_status.topology_type -eq "chain") {
                        $prtg_vsf_state = 1
                    }
                    elseif ($vsf_response.vsf_status.topology_type -eq "ring") {
                        $prtg_vsf_state = 2
                    }
                    else {
                        $prtg_vsf_state = -2
                    }
                }
            }
        }

        $xmlOutputText_temp += $prtg_vsf_string

        # -2 = unknown
        # -1 = not configured
        # 0 = disabled
        # 1 = chain
        # 2 = ring
        # 3 = split
        $xmlOutput_temp += "<result>
    <channel>VSF State</channel>
    <value>$($prtg_vsf_state)</value>
    <unit>Custom</unit>
    <CustomUnit>Status</CustomUnit>
    <valuelookup>arubacx.vsf.state</valuelookup>
    </result>"
        #endregion: VSF

        #region: Redudant MGMT
        $response = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system\redundant_managements" -attributes "name,state,mgmt_role,mgmt_module" -depth 2
        foreach ($mgmt_module in $response.psobject.Properties) {
            $mgmt_name = $mgmt_module.Value.mgmt_module.psobject.Properties.name.Replace("management_module,", "")
            $mgmt_state = -1
            if (($All_MGMTModules.value | Where-Object { $_.name -eq $mgmt_name }).state -eq "empty") {
                $mgmt_state = 0
                $xmlOutputText_temp += "MGMT `"$($mgmt_name)`" state `"empty`" || "
            }
            else {
                if ($mgmt_module.Value.state -ne "ready") {
                    $mgmt_state = 1
                    $xmlOutputText_temp += "MGMT $($mgmt_name) state `"$($mgmt_module.Value.state)`" || "
                }
                elseif ($mgmt_module.Value.mgmt_role -eq "Active") {
                    $mgmt_state = 2
                }
                elseif ($mgmt_module.Value.mgmt_role -eq "Standby") {
                    $mgmt_state = 3
                }
            }
            #Lookup:
            # 0 = Empty
            # 1 = Error
            # 2 = Active
            # 3 = Standby
            $xmlOutput_temp += "<result>
        <channel>MGMT $($mgmt_name) State</channel>
        <value>$($mgmt_state)</value>
        <unit>Custom</unit>
        <CustomUnit>Status</CustomUnit>
        <valuelookup>arubacx.mgmt.state</valuelookup>
        </result>"
        
        }

        #endregion: Redundant MGMT


        $global:xmlOutput += $xmlOutput_temp
        $global:OutputText += $xmlOutputText_temp
    }
}

function main() {
    setCulture

    $global:xmlOutput = '<prtg>'
    $global:OutputText = ""

    # get environment variables from PRTG
    #$Username = [System.Environment]::GetEnvironmentVariable('prtg_windowsuser')
    #$Password = [System.Environment]::GetEnvironmentVariable('prtg_windowspassword')
    #$IPAddress = [System.Environment]::GetEnvironmentVariable('prtg_host')
  
    # create new API object
    $SecPasswd = ConvertTo-SecureString $Password -AsPlainText -Force
    $Credentials = New-Object System.Management.Automation.PSCredential ($UserName, $secpasswd)
    $connection = Connect-ArubaCX -Server $Hostname -SkipCertificateCheck -Credential $Credentials
    #$connection.headers = @{ "depth" = 6 }

    $data = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system\subsystems" -attributes "type,state,resource_utilization,name,fans,temp_sensors,power_supplies" -depth 4

    Subsystems($data)

    $data = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system" -attributes "stp_config,boot_time,hostname,platform_name,software_version,ntp_config_vrf,ntp_config,redundant_managements,last_configuration_time" -depth 2

    System($data)

    NAE

    $data = Invoke-ArubaCXRestMethod -connection $connection -method "get" -uri "system\interfaces" -attributes "name,admin,admin_state,description,link_state,rate_statistics,bond_status,l1_state,pm_info" -depth 2

    # Filter Interfaces
    $data = $data.psobject.Properties
    if (($ExcludeInterface -ne "") -and ($null -ne $ExcludeInterface)) {
        $data = $data | Where-Object { $_.value.name -notmatch $ExcludeInterface }
    }
    if (($ExcludeDescription -ne "") -and ($null -ne $ExcludeDescription)) {
        $data = $data | Where-Object { $_.value.description -notmatch $ExcludeDescription }
    }
    if (($IncludeInterface -ne "") -and ($null -ne $IncludeInterface)) {
        $data = $data | Where-Object { $_.value.name -match $IncludeInterface }
    }
    if (($IncludeDescription -ne "") -and ($null -ne $IncludeDescription)) {
        $data = $data | Where-Object { $_.value.description -match $IncludeDescription }
    }

    createTransceiverChannel($data)

    GetInterfaces($data)

    if ($global:xmlOutput -ne "") {
        $global:OutputText = $global:OutputText.Replace("<", "")
        $global:OutputText = $global:OutputText.Replace(">", "")
        $global:OutputText = $global:OutputText.Replace("#", "")
        # remove ending || 
        if ($global:OutputText.EndsWith(" || ")) {
            $global:OutputText = $global:outputtext.substring(0, $global:OutputText.LastIndexOf(" || "))
        }

        # trim string to 2000 letter
        if ($global:OutputText.length -gt 1970) {
            $global:OutputText = $global:OutputText.Substring(0, 1970)
            $global:OutputText = $global:OutputText.Insert($global:OutputText.length, " || OUTPUT TO LONG... || ")
        }
        $global:xmlOutput += "<text>$($OutputText)</text>"
    }
    
    $global:xmlOutput += "</prtg>"
    Write-Host $xmlOutput
    Disconnect-ArubaCX -connection $connection -Confirm:$false
}

main