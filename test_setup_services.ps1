$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scripts = @('setup.sh', 'setup-precomf.sh')

foreach ($script in $scripts) {
    $path = Join-Path $repoRoot $script
    $content = Get-Content -Path $path -Raw -Encoding UTF8

    if ($content -notmatch 'WorkingDirectory=\$REPO_DIR') {
        throw "$script does not set WorkingDirectory to repo root for wmi-bridge.service"
    }

    if (
        $content -notmatch 'ExecStart=\$VENV_DIR/bin/python3 -m bridge\.serial_bridge' -and
        $content -notmatch 'ExecStart=\$VENV_DIR/bin/python3 -m \$BRIDGE_MODULE'
    ) {
        throw "$script does not run bridge.serial_bridge as a module"
    }

    if ($content -match 'BRIDGE_MODULE="bridge\.serial_bridge"' -or $script -eq 'setup-precomf.sh') {
        # expected
    }
    elseif ($content -match 'BRIDGE_MODULE=' -and $content -notmatch 'BRIDGE_MODULE="bridge\.serial_bridge"') {
        throw "$script does not point BRIDGE_MODULE at bridge.serial_bridge"
    }

    if ($content -match 'ExecStart=\$VENV_DIR/bin/python3 \$BRIDGE_SCRIPT') {
        throw "$script still launches bridge/serial_bridge.py directly"
    }

    if ($content -notmatch '\[ -L "\$target_root" \]') {
        throw "$script does not refuse symlinked dashboard deploy targets"
    }

    if ($content -notmatch '\[ -e "\$target_root" \] && \[ ! -d "\$target_root" \]') {
        throw "$script does not refuse non-directory dashboard deploy targets"
    }

    if ($content -notmatch 'validate_kiosk_launcher_target "\$KIOSK_LAUNCHER"') {
        throw "$script does not validate kiosk launcher target before overwrite"
    }

    if ($content -notmatch '\[ -L "\$target" \]') {
        throw "$script does not refuse symlinked kiosk launcher targets"
    }

    if ($content -notmatch '\[ -e "\$target" \] && \[ ! -f "\$target" \]') {
        throw "$script does not refuse non-file kiosk launcher targets"
    }

    if ($content -notmatch 'ExecStartPre=-/usr/bin/udevadm settle --timeout=10') {
        throw "$script does not wait for udev to settle before starting wmi-bridge.service"
    }

    if ($content -notmatch 'SupplementaryGroups=dialout') {
        throw "$script does not grant wmi-bridge.service explicit dialout access"
    }
}

$setupScript = Get-Content -Path (Join-Path $repoRoot 'setup.sh') -Raw -Encoding UTF8
$preconfiguredScript = Get-Content -Path (Join-Path $repoRoot 'setup-precomf.sh') -Raw -Encoding UTF8

if ($setupScript -notmatch 'write_managed_file "\$bash_profile"') {
    throw 'setup.sh does not preserve existing .bash_profile content'
}

if ($setupScript -notmatch 'write_managed_file "\$xinitrc"') {
    throw 'setup.sh does not preserve existing .xinitrc content'
}

if ($setupScript -notmatch 'unclutter -idle 0\.2 -root &') {
    throw 'setup.sh does not hide the mouse cursor in the tty1 startx kiosk path'
}

if ($setupScript -notmatch 'write_managed_file "\$openbox_autostart"') {
    throw 'setup.sh does not preserve existing openbox autostart content'
}

if ($setupScript -match 'cat > "\$RUN_HOME/\.bash_profile"') {
    throw 'setup.sh still overwrites .bash_profile directly'
}

if ($setupScript -match 'cat > "\$RUN_HOME/\.xinitrc"') {
    throw 'setup.sh still overwrites .xinitrc directly'
}

if ($setupScript -match 'cat > "\$RUN_HOME/\.config/openbox/autostart"') {
    throw 'setup.sh still overwrites openbox autostart directly'
}

if ($setupScript -notmatch 'http://localhost/\?profile=generic-ili9486-hat') {
    throw 'setup.sh does not scope the compact kiosk layout to the generic ILI9486 HAT profile'
}

if ($preconfiguredScript -notmatch 'WMI_DASHBOARD_URL') {
    throw 'setup-precomf.sh does not expose the dashboard URL override for preconfigured installs'
}

if ($setupScript -notmatch '\$REPO_DIR"/bridge/kiosk-launch\.sh') {
    throw 'setup.sh does not scope kiosk launcher writes to the repo bridge launcher'
}

if ($preconfiguredScript -notmatch '\$REPO_DIR"/bridge/kiosk-launch\.sh') {
    throw 'setup-precomf.sh does not scope kiosk launcher writes to the repo bridge launcher'
}

Write-Host 'setup service checks passed'
