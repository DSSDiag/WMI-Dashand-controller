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

    if ($content -notmatch 'resolved_target="\$\(resolve_path_or_empty "\$target_root"\)"') {
        throw "$script does not resolve the dashboard deploy target before replacement"
    }

    if ($content -notmatch '\[ -n "\$resolved_target" \] && \[ "\$resolved_target" != "/var/www/wmi-dashboard" \]') {
        throw "$script does not refuse redirected dashboard deploy targets"
    }

    if ($content -notmatch 'validate_kiosk_launcher_target "\$KIOSK_LAUNCHER"') {
        throw "$script does not validate kiosk launcher target before overwrite"
    }

    if ($content -notmatch 'WorkingDirectory=\$REPO_DIR\s+Environment=HOME=\$RUN_HOME\s+Environment=XAUTHORITY=\$RUN_HOME/\.Xauthority\s+ExecStartPre=/usr/bin/test -x \$KIOSK_LAUNCHER\s+ExecStart=\$KIOSK_LAUNCHER') {
        throw "$script does not harden wmi-kiosk.service with repo-scoped execution context and launcher verification"
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

    if ($content -notmatch 'resolve_chromium_bin\(\)') {
        throw "$script does not define a Chromium resolver helper"
    }

    if ($content -notmatch 'build_dashboard_url\(\)') {
        throw "$script does not define a dashboard URL builder helper"
    }

    if ($content -notmatch 'install_dashboard_dependencies\(\)') {
        throw "$script does not define a dashboard dependency installer helper"
    }

    if (
        $content -notmatch '\[ ! -d "\$dashboard_dir" \]' -or
        $content -notmatch 'Dashboard directory is missing: \$dashboard_dir'
    ) {
        throw "$script does not fail fast when the dashboard directory is missing"
    }

    if (
        $content -notmatch 'command -v npm >/dev/null 2>&1' -or
        $content -notmatch 'npm is required to install dashboard dependencies\. Please install Node\.js first\.'
    ) {
        throw "$script does not fail fast with a clear message when npm is unavailable"
    }

    if (
        $content -notmatch '\[ -f "\$dashboard_dir/package-lock\.json" \]' -or
        $content -notmatch 'cd "\$dashboard_dir"' -or
        $content -notmatch 'npm ci --silent' -or
        $content -notmatch 'npm install --silent' -or
        $content -notmatch 'npm ci failed for \$dashboard_dir\. Falling back to npm install'
    ) {
        throw "$script does not implement a real npm ci fallback npm install path from the dashboard directory"
    }

    if ($content -notmatch 'CHROMIUM_BIN="\$\(resolve_chromium_bin\)"') {
        throw "$script does not fail fast when Chromium is missing"
    }

    if (
        $content -notmatch '\[ ! -x "\$chromium_bin" \]' -and
        $content -notmatch '\[ ! -x "\$CHROMIUM_BIN" \]'
    ) {
        throw "$script does not verify the Chromium executable inside the kiosk launcher"
    }

    if ($content -notmatch 'curl -fsS "\$dashboard_ready_url"') {
        throw "$script does not wait on the configured dashboard URL before launching Chromium"
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

if (
    $setupScript -notmatch 'KIOSK_DISPLAY_PROFILE="\$\{WMI_DISPLAY_PROFILE:-\$DISPLAY_PROFILE\}"' -or
    $setupScript -notmatch 'DASHBOARD_URL="\$\(build_dashboard_url "\$\{WMI_DASHBOARD_URL:-http://localhost\}" "\$KIOSK_DISPLAY_PROFILE"\)"'
) {
    throw 'setup.sh does not build the kiosk dashboard URL from the selected or overridden display profile'
}

if (
    $setupScript -notmatch '\[\[ "\$base_url" == \*\[\\\?\\&\]profile=\* \]\]' -or
    $setupScript -notmatch 'printf ''%s%sprofile=%s\\n'' "\$base_url" "\$separator" "\$display_profile"'
) {
    throw 'setup.sh does not append the display profile to the kiosk URL safely'
}

if (
    $preconfiguredScript -notmatch 'DASHBOARD_URL="\$\(build_dashboard_url "\$\{WMI_DASHBOARD_URL:-http://localhost\}" "\$\{WMI_DISPLAY_PROFILE:-\}"\)"' -or
    $preconfiguredScript -notmatch 'WMI_DASHBOARD_URL' -or
    $preconfiguredScript -notmatch 'WMI_DISPLAY_PROFILE'
) {
    throw 'setup-precomf.sh does not expose profile-aware dashboard URL overrides for preconfigured installs'
}

if ($setupScript -notmatch '\$REPO_DIR"/bridge/kiosk-launch\.sh') {
    throw 'setup.sh does not scope kiosk launcher writes to the repo bridge launcher'
}

if ($preconfiguredScript -notmatch '\$REPO_DIR"/bridge/kiosk-launch\.sh') {
    throw 'setup-precomf.sh does not scope kiosk launcher writes to the repo bridge launcher'
}

if ($setupScript -notmatch 'LCD_SHOW_DIR="\$REPO_DIR/LCD-show"') {
    throw 'setup.sh does not scope LCD-show operations to the repo checkout path'
}

if ($setupScript -notmatch 'validate_lcd_show_dir\(\)') {
    throw 'setup.sh does not define an LCD-show path validator'
}

if ($setupScript -notmatch 'validate_lcd_show_dir "\$LCD_SHOW_DIR"') {
    throw 'setup.sh does not validate the LCD-show path before clone or reuse'
}

if ($setupScript -notmatch '\[ -L "\$target" \]') {
    throw 'setup.sh does not refuse symlinked LCD-show paths'
}

if ($setupScript -notmatch '\[ -e "\$target" \] && \[ ! -d "\$target" \]') {
    throw 'setup.sh does not refuse non-directory LCD-show paths'
}

if (
    $setupScript -notmatch '\[ -d "\$LCD_SHOW_DIR/\.git" \]' -or
    $setupScript -notmatch '\[ -d "\$LCD_SHOW_DIR" \]' -or
    $setupScript -notmatch 'Refusing to reuse existing non-git LCD-show directory' -or
    $setupScript -notmatch 'git clone https://github\.com/goodtft/LCD-show\.git "\$LCD_SHOW_DIR"'
) {
    throw 'setup.sh does not harden LCD-show checkout reuse and clone behavior'
}

Write-Host 'setup service checks passed'
