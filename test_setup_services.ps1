$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scripts = @('setup.sh', 'setup-precomf.sh')

foreach ($script in $scripts) {
    $path = Join-Path $repoRoot $script
    $content = Get-Content -Path $path -Raw -Encoding UTF8

    if ($content -notmatch 'WorkingDirectory=\$REPO_DIR') {
        throw "$script does not set WorkingDirectory to repo root for wmi-bridge.service"
    }

    if ($content -notmatch 'ExecStart=\$VENV_DIR/bin/python3 -m bridge\.serial_bridge') {
        throw "$script does not run bridge.serial_bridge as a module"
    }

    if ($content -match 'ExecStart=\$VENV_DIR/bin/python3 \$BRIDGE_SCRIPT') {
        throw "$script still launches bridge/serial_bridge.py directly"
    }
}

Write-Host 'setup service checks passed'
