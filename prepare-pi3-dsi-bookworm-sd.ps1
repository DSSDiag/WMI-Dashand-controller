[CmdletBinding()]
param(
    [int]$DiskNumber = -1,
    [string]$Hostname = 'wmidash',
    [string]$UserName = 'wmi',
    [string]$Password = 'wmidash',
    [string]$SshPublicKeyPath = "$HOME\.ssh\id_ed25519.pub",
    [switch]$StageOnly,
    [switch]$RedownloadImage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-IsAdministrator {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevation {
    if ($StageOnly -or (Test-IsAdministrator)) {
        return
    }

    Write-Step 'Requesting Administrator access for SD card flashing...'
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Hostname', $Hostname,
        '-UserName', $UserName,
        '-Password', $Password
    )
    if ($DiskNumber -ge 0) {
        $argList += @('-DiskNumber', $DiskNumber.ToString())
    }
    if ($RedownloadImage) {
        $argList += '-RedownloadImage'
    }

    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    exit 0
}

function Get-RepoRoot {
    return Split-Path -Parent $PSCommandPath
}

function Get-WorkDirectory {
    $path = Join-Path $env:TEMP 'wmi-pi3-sd-prep'
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
    return $path
}

function Get-OfficialImageInfo {
    $fallback = [pscustomobject]@{
        Name = 'Raspberry Pi OS (Legacy, 64-bit) Lite'
        ReleaseDate = '2026-04-13'
        Url = 'https://downloads.raspberrypi.com/raspios_oldstable_lite_arm64/images/raspios_oldstable_lite_arm64-2026-04-14/2026-04-13-raspios-bookworm-arm64-lite.img.xz'
        Sha256 = '58da0a63e68ed922aacb54adebec1d23d557ad8b7009a865bdbf16541185dd6e'
    }

    try {
        $catalog = Invoke-RestMethod 'https://downloads.raspberrypi.com/os_list_imagingutility_v4.json'
        $bucket = $catalog.os_list | Where-Object { $_.name -eq 'Raspberry Pi OS (other)' } | Select-Object -First 1
        $item = $bucket.subitems | Where-Object { $_.name -eq 'Raspberry Pi OS (Legacy, 64-bit) Lite' } | Select-Object -First 1
        if ($null -eq $item) {
            throw 'Official Bookworm Lite item was not found in Raspberry Pi catalog.'
        }

        return [pscustomobject]@{
            Name = $item.name
            ReleaseDate = $item.release_date
            Url = $item.url
            Sha256 = $item.extract_sha256
        }
    }
    catch {
        Write-Warning "Falling back to pinned official image metadata because the live catalog lookup failed: $($_.Exception.Message)"
        return $fallback
    }
}

function Get-RpiImagerPath {
    $candidates = @(
        'C:\Program Files\Raspberry Pi Ltd\Imager\rpi-imager.exe',
        'C:\Program Files (x86)\Raspberry Pi Ltd\Imager\rpi-imager.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $cmd = Get-Command rpi-imager.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw 'Raspberry Pi Imager was not found. Install it first, then rerun this script.'
}

function Get-DefaultDiskNumber {
    $usbDisks = @(Get-CimInstance Win32_DiskDrive | Where-Object {
        $_.InterfaceType -eq 'USB' -and
        [int64]$_.Size -ge 8GB
    })

    if ($usbDisks.Count -eq 1) {
        return [int]$usbDisks[0].Index
    }

    $summary = $usbDisks | Select-Object Index, Model, InterfaceType, Size | Format-Table -AutoSize | Out-String
    throw "Could not safely auto-select a target SD card. Found $($usbDisks.Count) USB disk candidates.`n$summary"
}

function Resolve-DiskNumber {
    if ($DiskNumber -ge 0) {
        return $DiskNumber
    }
    return Get-DefaultDiskNumber
}

function Get-TargetDiskSummary {
    param([int]$Number)

    $disk = Get-CimInstance Win32_DiskDrive | Where-Object { [int]$_.Index -eq $Number } | Select-Object -First 1
    if ($null -eq $disk) {
        throw "Disk $Number was not found."
    }

    return [pscustomobject]@{
        Number = [int]$disk.Index
        Model = $disk.Model
        InterfaceType = $disk.InterfaceType
        SizeGB = [math]::Round(([double]$disk.Size / 1GB), 2)
    }
}

function Ensure-ImageDownloaded {
    param(
        [Parameter(Mandatory)]$ImageInfo,
        [Parameter(Mandatory)][string]$WorkDir
    )

    $fileName = [IO.Path]::GetFileName(([Uri]$ImageInfo.Url).AbsolutePath)
    $target = Join-Path $WorkDir $fileName

    if ($RedownloadImage -and (Test-Path $target)) {
        Remove-Item $target -Force
    }

    if (-not (Test-Path $target)) {
        Write-Step "Downloading official Raspberry Pi image: $($ImageInfo.Name) ($($ImageInfo.ReleaseDate))"
        Invoke-WebRequest -Uri $ImageInfo.Url -OutFile $target
    }
    else {
        Write-Step "Using cached Raspberry Pi image: $target"
    }

    return $target
}

function Test-ImageSha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedSha256 = ''
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        Write-Warning "No SHA256 was provided for $Path. Skipping checksum verification."
        return
    }

    Write-Step "Verifying image checksum for $(Split-Path -Leaf $Path) ..."
    $actualSha256 = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected = $ExpectedSha256.Trim().ToLowerInvariant()

    if ($actualSha256 -ne $expected) {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
        throw "Downloaded image checksum mismatch for $Path. Expected $expected but found $actualSha256. The cached file was removed; rerun the script to download a fresh copy."
    }
}

function New-PayloadArchive {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$WorkDir
    )

    $archivePath = Join-Path $WorkDir 'wmi-payload.tgz'
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force
    }

    Write-Step 'Building WMI payload archive from the current working tree...'
    Push-Location $RepoRoot
    try {
        & tar.exe `
            --exclude=.git `
            --exclude=.pytest_cache `
            --exclude=files-from-working-device `
            --exclude=dashboard/node_modules `
            --exclude=dashboard/dist `
            --exclude=bridge/.venv `
            --exclude=simulation/.venv `
            --exclude=LCD-show `
            -czf $archivePath .
    }
    finally {
        Pop-Location
    }

    return $archivePath
}

function ConvertTo-ShellLiteral {
    param([string]$Value)
    if ($Value -match "'") {
        throw "Single quotes are not supported in bootstrap values: $Value"
    }
    return "'$Value'"
}

function New-FirstRunScript {
    param(
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$HostNameValue,
        [Parameter(Mandatory)][string]$UserNameValue,
        [Parameter(Mandatory)][string]$PasswordValue,
        [string]$SshPublicKeyValue = ''
    )

    $scriptPath = Join-Path $WorkDir 'firstrun.sh'
    $userLiteral = ConvertTo-ShellLiteral $UserNameValue
    $passLiteral = ConvertTo-ShellLiteral $PasswordValue
    $hostLiteral = ConvertTo-ShellLiteral $HostNameValue
    $sshKeyLiteral = ConvertTo-ShellLiteral $SshPublicKeyValue

    $content = @'
#!/bin/sh
set -eu

BOOT_DIR="/boot"
if [ -d /boot/firmware ]; then
    BOOT_DIR="/boot/firmware"
fi

LOG_FILE="/var/log/wmi-firstboot.log"
mkdir -p /var/log
exec >>"$LOG_FILE" 2>&1
trap 'cp "$LOG_FILE" "$BOOT_DIR/wmi-firstboot.log" 2>/dev/null || true' EXIT

echo "=== $(date -Is) starting WMI bootstrap ==="

WMI_USER=__WMI_USER_LITERAL__
WMI_PASS=__WMI_PASS_LITERAL__
WMI_HOSTNAME=__WMI_HOST_LITERAL__
WMI_SSH_KEY=__WMI_SSH_KEY_LITERAL__
PAYLOAD="$BOOT_DIR/wmi-payload.tgz"
TARGET_HOME="/home/$WMI_USER"
TARGET_DIR="$TARGET_HOME/WMI-Dashand-controller"

if ! id "$WMI_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$WMI_USER"
fi

echo "$WMI_USER:$WMI_PASS" | chpasswd
usermod -aG sudo,dialout,video,audio,input,plugdev "$WMI_USER" || true
systemctl enable ssh || true

install -o "$WMI_USER" -g "$WMI_USER" -m 700 -d "$TARGET_HOME/.ssh"
if [ -n "$WMI_SSH_KEY" ]; then
    printf '%s\n' "$WMI_SSH_KEY" > "$TARGET_HOME/.ssh/authorized_keys"
    chown "$WMI_USER:$WMI_USER" "$TARGET_HOME/.ssh/authorized_keys"
    chmod 600 "$TARGET_HOME/.ssh/authorized_keys"
fi

hostnamectl set-hostname "$WMI_HOSTNAME" || true
if [ -f /etc/hostname ]; then
    printf '%s\n' "$WMI_HOSTNAME" > /etc/hostname
fi
if [ -f /etc/hosts ]; then
    sed -i '/127\.0\.1\.1/d' /etc/hosts || true
    printf '127.0.1.1\t%s\n' "$WMI_HOSTNAME" >> /etc/hosts
fi

if [ ! -f "$PAYLOAD" ]; then
    echo "Missing WMI payload archive at $PAYLOAD"
    exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
tar -xzf "$PAYLOAD" -C "$TARGET_DIR" --strip-components=1
chown -R "$WMI_USER:$WMI_USER" "$TARGET_HOME"

echo "Waiting for network access so apt/npm installs can complete..."
i=0
network_ready=0
while [ $i -lt 96 ]; do
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 downloads.raspberrypi.com >/dev/null 2>&1 || ping -c 1 -W 2 github.com >/dev/null 2>&1; then
        network_ready=1
        break
    fi
    i=$((i + 1))
    sleep 5
done

if [ "$network_ready" -ne 1 ]; then
    echo "Network did not become ready in time. The automatic WMI install requires Internet access on first boot."
    exit 1
fi

cd "$TARGET_DIR"
chmod +x setup.sh

echo "Running WMI setup.sh for: Pi 3 / Lite / 5-inch DSI"
printf '2\n1\n1\n' | env SUDO_USER="$WMI_USER" ./setup.sh

touch "$TARGET_HOME/.wmi-firstboot-complete"
chown "$WMI_USER:$WMI_USER" "$TARGET_HOME/.wmi-firstboot-complete"
sync

rm -f /boot/firstrun.sh /boot/firmware/firstrun.sh || true
sed -i 's| systemd.run=.*||g' /boot/cmdline.txt /boot/firmware/cmdline.txt 2>/dev/null || true

echo "WMI bootstrap finished successfully."
'@

    $content = $content.
        Replace('__WMI_USER_LITERAL__', $userLiteral).
        Replace('__WMI_PASS_LITERAL__', $passLiteral).
        Replace('__WMI_HOST_LITERAL__', $hostLiteral).
        Replace('__WMI_SSH_KEY_LITERAL__', $sshKeyLiteral)

    Set-Content -Path $scriptPath -Value $content -NoNewline
    return $scriptPath
}

function Invoke-ImagerWrite {
    param(
        [Parameter(Mandatory)][string]$ImagerPath,
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][string]$FirstRunPath,
        [Parameter(Mandatory)][int]$TargetDisk
    )

    $destination = "\\.\PHYSICALDRIVE$TargetDisk"
    Write-Step "Writing image to $destination with Raspberry Pi Imager..."
    $process = Start-Process -FilePath $ImagerPath -ArgumentList @(
        '--cli',
        '--disable-eject',
        '--first-run-script', $FirstRunPath,
        $ImagePath,
        $destination
    ) -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Raspberry Pi Imager exited with code $($process.ExitCode)."
    }
}

function Wait-ForBootVolume {
    param(
        [Parameter(Mandatory)][int]$TargetDisk,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $partitions = @(Get-Partition -DiskNumber $TargetDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
        foreach ($partition in $partitions) {
            $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
            if ($null -eq $volume) {
                continue
            }
            if ($volume.FileSystem -eq 'FAT32' -or $partition.Size -lt 1GB) {
                return "$($partition.DriveLetter):"
            }
        }
        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for the Raspberry Pi boot volume to mount on disk $TargetDisk."
}

function Copy-BootstrapFiles {
    param(
        [Parameter(Mandatory)][string]$BootDrive,
        [Parameter(Mandatory)][string]$PayloadArchive
    )

    Write-Step "Copying WMI payload archive to $BootDrive ..."
    Copy-Item -Path $PayloadArchive -Destination (Join-Path $BootDrive 'wmi-payload.tgz') -Force

    $readmePath = Join-Path $BootDrive 'WMI-BOOTSTRAP.txt'
    @"
This SD card was prepared for:
- Raspberry Pi 3
- Raspberry Pi OS Bookworm Lite (64-bit)
- 5-inch capacitive DSI display

First-boot assumptions:
- The Pi has Internet access on first boot, usually by Ethernet.
- A local user named '$UserName' is created with password '$Password'.
- First-boot progress is logged to /var/log/wmi-firstboot.log and copied here as wmi-firstboot.log.
"@ | Set-Content -Path $readmePath
}

Invoke-SelfElevation

$repoRoot = Get-RepoRoot
$workDir = Get-WorkDirectory
$imageInfo = Get-OfficialImageInfo
$sshPublicKeyValue = ''
if ($SshPublicKeyPath -and (Test-Path $SshPublicKeyPath)) {
    $sshPublicKeyValue = (Get-Content $SshPublicKeyPath -Raw).Trim()
}

Write-Step "Image: $($imageInfo.Name) - release $($imageInfo.ReleaseDate)"

$imagePath = Ensure-ImageDownloaded -ImageInfo $imageInfo -WorkDir $workDir
Test-ImageSha256 -Path $imagePath -ExpectedSha256 $imageInfo.Sha256
$payloadArchive = New-PayloadArchive -RepoRoot $repoRoot -WorkDir $workDir
$firstRunPath = New-FirstRunScript -WorkDir $workDir -HostNameValue $Hostname -UserNameValue $UserName -PasswordValue $Password -SshPublicKeyValue $sshPublicKeyValue

if ($StageOnly) {
    Write-Step 'Stage-only mode complete.'
    Write-Host "Work directory : $workDir"
    Write-Host "Image cache    : $imagePath"
    Write-Host "Payload archive: $payloadArchive"
    Write-Host "First-run file : $firstRunPath"
    exit 0
}

$targetDisk = Resolve-DiskNumber
$targetSummary = Get-TargetDiskSummary -Number $targetDisk
$imagerPath = Get-RpiImagerPath

Write-Step "Target disk: Disk $($targetSummary.Number) - $($targetSummary.Model) - $($targetSummary.SizeGB) GB ($($targetSummary.InterfaceType))"

Invoke-ImagerWrite -ImagerPath $imagerPath -ImagePath $imagePath -FirstRunPath $firstRunPath -TargetDisk $targetDisk
$bootDrive = Wait-ForBootVolume -TargetDisk $targetDisk
Copy-BootstrapFiles -BootDrive $bootDrive -PayloadArchive $payloadArchive

Write-Step 'SD card preparation complete.'
Write-Host ''
Write-Host "Boot volume : $bootDrive"
Write-Host "Pi hostname : $Hostname"
Write-Host "Pi username : $UserName"
Write-Host "Pi password : $Password"
Write-Host ''
Write-Host 'Important: the automatic WMI install expects Internet access on the Pi at first boot.'
