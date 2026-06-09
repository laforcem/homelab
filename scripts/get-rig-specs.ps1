#Requires -RunAsAdministrator
<#
    get-rig-specs.ps1
    Dumps comprehensive hardware specs to console and to a timestamped file
    in the same directory as this script. Run on the target machine as admin.
#>

$ErrorActionPreference = 'SilentlyContinue'

$outFile = Join-Path $PSScriptRoot ("rig-specs-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
$lines   = [System.Collections.Generic.List[string]]::new()

function Section($title) {
    $bar = '=' * 60
    $lines.Add("")
    $lines.Add($bar)
    $lines.Add("  $title")
    $lines.Add($bar)
}

function Row($label, $value) {
    $lines.Add("  {0,-30} {1}" -f "$label`:", $value)
}

function Blank { $lines.Add("") }


# ── Header ────────────────────────────────────────────────────────────────────

$lines.Add("RIG SPEC DUMP — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Hostname: $env:COMPUTERNAME")


# ── OS / System ───────────────────────────────────────────────────────────────

Section "OPERATING SYSTEM"
$os = Get-CimInstance Win32_OperatingSystem
Row "OS"           $os.Caption
Row "Version"      "$($os.Version) (Build $($os.BuildNumber))"
Row "Architecture" $os.OSArchitecture
Row "Install date" $os.InstallDate
Row "Last boot"    $os.LastBootUpTime
$uptime = (Get-Date) - $os.LastBootUpTime
Row "Uptime"       ("{0}d {1}h {2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes)
Row "Page file"    ("{0} MB total / {1} MB in use" -f $os.TotalVirtualMemorySize, ($os.TotalVirtualMemorySize - $os.FreeVirtualMemory))


# ── Motherboard / BIOS ────────────────────────────────────────────────────────

Section "MOTHERBOARD & BIOS"
$mb   = Get-CimInstance Win32_BaseBoard
$bios = Get-CimInstance Win32_BIOS
$sys  = Get-CimInstance Win32_ComputerSystem
Row "Manufacturer"    $mb.Manufacturer
Row "Model"           $mb.Product
Row "Version"         $mb.Version
Row "Serial"          $mb.SerialNumber
Blank
Row "BIOS vendor"     $bios.Manufacturer
Row "BIOS version"    $bios.SMBIOSBIOSVersion
Row "BIOS date"       $bios.ReleaseDate
Blank
Row "System model"    $sys.Model
Row "Chassis type"    (Get-CimInstance Win32_SystemEnclosure).ChassisTypes -join ', '


# ── CPU ───────────────────────────────────────────────────────────────────────

Section "CPU"
$cpus = Get-CimInstance Win32_Processor
foreach ($cpu in $cpus) {
    Row "Name"              $cpu.Name.Trim()
    Row "Socket"            $cpu.SocketDesignation
    Row "Cores (physical)"  $cpu.NumberOfCores
    Row "Threads (logical)" $cpu.NumberOfLogicalProcessors
    Row "Base clock"        "$($cpu.MaxClockSpeed) MHz"
    Row "L2 cache"          "$($cpu.L2CacheSize) KB"
    Row "L3 cache"          "$($cpu.L3CacheSize) KB"
    Row "Status"            $cpu.Status
    Blank
}


# ── RAM ───────────────────────────────────────────────────────────────────────

Section "MEMORY (slot by slot)"
$dimms = Get-CimInstance Win32_PhysicalMemory
$totalMB = ($dimms | Measure-Object -Property Capacity -Sum).Sum / 1MB
Row "Total installed" ("{0} GB across {1} slot(s)" -f [math]::Round($totalMB/1024, 1), $dimms.Count)
Blank
foreach ($d in $dimms) {
    $gb   = [math]::Round($d.Capacity / 1GB, 0)
    $mhz  = $d.ConfiguredClockSpeed
    $type = switch ($d.MemoryType) {
        26 { "DDR4" } 34 { "DDR5" } 24 { "DDR3" } default { "type $($d.MemoryType)" }
    }
    Row "Slot $($d.DeviceLocator)" "$gb GB $type @ ${mhz} MHz | $($d.Manufacturer.Trim()) | P/N: $($d.PartNumber.Trim()) | S/N: $($d.SerialNumber.Trim())"
    Row "  Form factor"            (switch ($d.FormFactor) { 8 {'DIMM'} 12 {'SO-DIMM'} default {"code $($d.FormFactor)"} })
    Row "  Bank"                   $d.BankLabel
    Blank
}

$memSlots = (Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1)
Row "Total slots on board" $memSlots.MemoryDevices
Row "Max board capacity"   ("{0} GB" -f ($memSlots.MaxCapacity / 1MB))


# ── GPU ───────────────────────────────────────────────────────────────────────

Section "GPU(s)"
$gpus = Get-CimInstance Win32_VideoController
foreach ($g in $gpus) {
    Row "Name"          $g.Name
    Row "VRAM"          ("{0} MB" -f [math]::Round($g.AdapterRAM / 1MB))
    Row "Driver ver"    $g.DriverVersion
    Row "Driver date"   $g.DriverDate
    Row "Resolution"    "$($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz"
    Row "Video mode"    $g.VideoModeDescription
    Blank
}


# ── Storage ───────────────────────────────────────────────────────────────────

Section "STORAGE DRIVES"
$disks = Get-PhysicalDisk | Sort-Object MediaType, DeviceId
foreach ($d in $disks) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    Row "Drive $($d.DeviceId)"     "$($d.FriendlyName) — $sizeGB GB"
    Row "  Media type"             $d.MediaType
    Row "  Bus"                    $d.BusType
    Row "  Serial"                 $d.SerialNumber.Trim()
    Row "  Firmware"               $d.FirmwareVersion
    Row "  Health"                 $d.HealthStatus
    Row "  Usage"                  $d.Usage
    Blank
}

# Logical volumes
$lines.Add("  --- Logical volumes ---")
Blank
Get-Volume | Where-Object { $_.DriveLetter } | Sort-Object DriveLetter | ForEach-Object {
    $usedGB  = [math]::Round(($_.Size - $_.SizeRemaining) / 1GB, 1)
    $totalGB = [math]::Round($_.Size / 1GB, 1)
    $pct     = if ($_.Size -gt 0) { [math]::Round(($usedGB / $totalGB) * 100) } else { 0 }
    Row "$($_.DriveLetter):\" "$usedGB GB / $totalGB GB used ($pct%) — $($_.FileSystem) — $($_.FileSystemLabel)"
}


# ── Network ───────────────────────────────────────────────────────────────────

Section "NETWORK ADAPTERS"
Get-NetAdapter | Where-Object { $_.Status -ne 'Not Present' } | Sort-Object Status | ForEach-Object {
    Row $_.Name ("$($_.InterfaceDescription) | Speed: $([math]::Round($_.LinkSpeed/1e6))Mbps | MAC: $($_.MacAddress) | Status: $($_.Status)")
}
Blank
$lines.Add("  --- IP addresses ---")
Get-NetIPAddress | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -notmatch '^169\.' } | ForEach-Object {
    Row "  $($_.InterfaceAlias)" "$($_.IPAddress)/$($_.PrefixLength)"
}


# ── USB Controllers ───────────────────────────────────────────────────────────

Section "USB CONTROLLERS"
Get-PnpDevice -Class USB | Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -match 'controller|host' } |
    Sort-Object FriendlyName | ForEach-Object {
        $lines.Add("  $($_.FriendlyName)")
    }


# ── PCIe / PnP devices of interest ───────────────────────────────────────────

Section "PCI DEVICES (non-generic)"
Get-PnpDevice | Where-Object {
    $_.Status -eq 'OK' -and
    $_.Class -in @('Display','Media','SCSIAdapter','HDC','Net','AudioEndpoint','Bluetooth') -and
    $_.FriendlyName -notmatch 'Microsoft|Generic|Composite|HID|Root'
} | Sort-Object Class, FriendlyName | ForEach-Object {
    $lines.Add("  [$($_.Class.PadRight(14))] $($_.FriendlyName)")
}


# ── Sound ─────────────────────────────────────────────────────────────────────

Section "AUDIO DEVICES"
Get-CimInstance Win32_SoundDevice | ForEach-Object {
    Row $_.Name $_.Status
}


# ── Thermals (requires HWiNFO or WMI OHW; best-effort) ──────────────────────

Section "TEMPERATURES (best-effort via WMI MSAcpi)"
$thermals = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
if ($thermals) {
    foreach ($t in $thermals) {
        $c = [math]::Round(($t.CurrentTemperature - 2732) / 10, 1)
        Row $t.InstanceName "$c °C"
    }
} else {
    $lines.Add("  (MSAcpi_ThermalZoneTemperature not available — install HWiNFO64 for full thermal data)")
}


# ── Power plan ────────────────────────────────────────────────────────────────

Section "POWER"
$active = powercfg /getactivescheme 2>$null
$lines.Add("  Active scheme: $active")
Blank
$lines.Add("  Wake capabilities:")
powercfg /devicequery wake_armed 2>$null | ForEach-Object { $lines.Add("    $_") }


# ── Installed relevant software ───────────────────────────────────────────────

Section "INSTALLED SOFTWARE (relevant)"
$keywords = 'nvidia|cuda|driver|chipset|intel|amd|virtualbox|vmware|hyper-v|wsl|git|visual|python|node|docker'
Get-ItemProperty `
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object { $_.DisplayName -match $keywords -and $_.DisplayName } |
    Sort-Object DisplayName |
    Select-Object -Unique DisplayName, DisplayVersion |
    ForEach-Object {
        Row $_.DisplayName $_.DisplayVersion
    }


# ── Windows features ──────────────────────────────────────────────────────────

Section "WINDOWS OPTIONAL FEATURES (enabled)"
$features = @('Microsoft-Hyper-V','VirtualMachinePlatform','HypervisorPlatform',
               'Microsoft-Windows-Subsystem-Linux','Containers','NetFx3')
foreach ($f in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue).State
    if ($state) { Row $f $state }
}


# ── Output ────────────────────────────────────────────────────────────────────

$output = $lines -join "`n"
$output | Set-Content -Path $outFile -Encoding UTF8
$output | Write-Host

Write-Host "`n`nOutput saved to: $outFile" -ForegroundColor Cyan

# ── Upload to gofile ──────────────────────────────────────────────────────────

try {
    Write-Host "Uploading to gofile..." -ForegroundColor Yellow
    $server   = (Invoke-RestMethod 'https://api.gofile.io/servers').data.servers[0].name
    $response = Invoke-RestMethod -Uri "https://$server.gofile.io/contents/uploadfile" `
                    -Method Post `
                    -Form @{ file = Get-Item $outFile }
    $link = $response.data.downloadPage
    Write-Host "Share this link: $link" -ForegroundColor Green
} catch {
    Write-Host "Gofile upload failed — just send the file directly: $outFile" -ForegroundColor Red
}
