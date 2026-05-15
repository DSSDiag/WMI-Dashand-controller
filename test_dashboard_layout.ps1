$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appPath = Join-Path $repoRoot 'dashboard\src\App.jsx'
$cssPath = Join-Path $repoRoot 'dashboard\src\index.css'
$testPath = Join-Path $repoRoot 'dashboard\src\App.test.jsx'

$app = Get-Content -Path $appPath -Raw -Encoding UTF8
$css = Get-Content -Path $cssPath -Raw -Encoding UTF8
$tests = Get-Content -Path $testPath -Raw -Encoding UTF8

if ($app -notmatch "window\.addEventListener\('orientationchange', updateViewportScale\)") {
    throw 'App.jsx does not refresh compact layout on orientation changes'
}

if ($app -notmatch "window\.visualViewport") {
    throw 'App.jsx does not listen to visualViewport changes for touch devices'
}

if ($app -notmatch 'data-testid="dashboard-shell"' -or $app -notmatch "data-compact=\{isCompactDisplay \? 'true' : 'false'\}") {
    throw 'App.jsx does not expose explicit compact layout state for tests'
}

if ($css -notmatch 'overscroll-behavior:\s*none;') {
    throw 'index.css does not disable root overscroll bounce'
}

if ($css -notmatch '\.settings-page\s*\{\s*overscroll-behavior:\s*contain;') {
    throw 'index.css does not contain settings-page overscroll behavior'
}

if ($css -notmatch '\.settings-page input\[type=range\]\s*\{\s*touch-action:\s*pan-x;') {
    throw 'index.css does not preserve horizontal range dragging on touch screens'
}

if ($tests -notmatch "getByTestId\('dashboard-shell'\)\)\.toHaveAttribute\('data-compact', 'true'\)") {
    throw 'App.test.jsx does not assert the explicit compact state'
}

Write-Host 'dashboard layout checks passed'
