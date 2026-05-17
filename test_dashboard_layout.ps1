$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appPath = Join-Path $repoRoot 'dashboard\src\App.jsx'
$cssPath = Join-Path $repoRoot 'dashboard\src\index.css'
$mainPath = Join-Path $repoRoot 'dashboard\src\main.jsx'
$testPath = Join-Path $repoRoot 'dashboard\src\App.test.jsx'

$app = Get-Content -Path $appPath -Raw -Encoding UTF8
$css = Get-Content -Path $cssPath -Raw -Encoding UTF8
$main = Get-Content -Path $mainPath -Raw -Encoding UTF8
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

if ($main -notmatch "params\.get\('profile'\) === 'generic-ili9486-hat'") {
    throw 'main.jsx does not parse the generic ILI9486 HAT profile from the kiosk URL'
}

if ($css -notmatch 'overscroll-behavior:\s*none;') {
    throw 'index.css does not disable root overscroll bounce'
}

if ($css -notmatch '\.settings-page\s*\{\s*overscroll-behavior:\s*contain;') {
    throw 'index.css does not contain settings-page overscroll behavior'
}

if ($css -notmatch '\.settings-page \.custom-scrollbar\s*\{\s*touch-action:\s*pan-y;\s*-webkit-overflow-scrolling:\s*touch;') {
    throw 'index.css does not preserve vertical touch scrolling on compact settings grids'
}

if ($css -notmatch '\.settings-page\.compact-settings\.sensor-page input\[type="number"\]\s*\{') {
    throw 'index.css does not apply compact sensor-page number input sizing to the actual sensor page element'
}

if (
    $css -notmatch '\.settings-page\.compact-settings input\[type="number"\]\s*\{\s*font-size:\s*1rem\s*!important;\s*line-height:\s*1\.1rem\s*!important;'
) {
    throw 'index.css does not keep compact number inputs large enough to avoid touch-browser zoom'
}

if ($css -notmatch '\.settings-page input\[type=range\]\s*\{\s*touch-action:\s*pan-x;') {
    throw 'index.css does not preserve horizontal range dragging on touch screens'
}

if ($tests -notmatch 'displayProfile="generic-ili9486-hat"') {
    throw 'App.test.jsx does not cover the generic HAT compact layout path'
}

if ($tests -notmatch 'loads preset calibration values and re-enables editing in custom mode') {
    throw 'App.test.jsx does not guard sensor preset calibration and custom editability'
}

if (
    $app -notmatch "HW REV:" -or
    $app -notmatch "flex flex-wrap items-center gap-x-1 gap-y-0.5 text-\[9px\] leading-tight" -or
    $app -notmatch "Select a preset or map a custom 0-5V sensor / ECU output" -or
    $app -notmatch "whitespace-normal"
) {
    throw 'App.jsx does not let compact setup headers wrap cleanly on the 480x320 profile'
}

if (
    $app -notmatch 'aria-label="Return to dashboard"[\s\S]*min-h-\[2\.35rem\] min-w-\[2\.35rem\] flex items-center justify-center' -or
    $app -notmatch 'aria-label="Open sensor setup"[\s\S]*min-h-\[2\.35rem\] min-w-\[2\.35rem\] flex items-center justify-center' -or
    $app -notmatch 'aria-label="Return to settings"[\s\S]*min-h-\[2\.35rem\] min-w-\[2\.35rem\] flex items-center justify-center'
) {
    throw 'App.jsx does not keep compact header navigation buttons at an explicit touch-friendly minimum size'
}

if (
    $app -notmatch 'aria-label="Save settings and return to dashboard"[\s\S]*min-h-\[2\.35rem\][\s\S]*whitespace-nowrap' -or
    $app -notmatch 'aria-label="Save sensor setup and return to dashboard"[\s\S]*min-h-\[2\.35rem\][\s\S]*whitespace-nowrap'
) {
    throw 'App.jsx does not keep compact save-and-exit buttons at an explicit touch-friendly minimum size'
}

if ($app -notmatch 'data-testid="sensor-page-grid"' -or $app -notmatch "isCompactDisplay \? 'grid-cols-1 gap-1 pr-0' : 'grid-cols-2 gap-2 pr-1'") {
    throw 'App.jsx does not stack the sensor setup page into a single column on the compact HAT profile'
}

if ($app -notmatch 'data-testid="sensor-setup-grid"' -or $app -notmatch "data-testid=`"sensor-setup-grid`"[\s\S]*isCompactDisplay \? 'grid-cols-1 gap-1 pr-0' : 'grid-cols-2 gap-2 pr-1'") {
    throw 'App.jsx does not stack the dedicated sensor setup grid into a single column on the compact HAT profile'
}

if ($app -notmatch 'data-testid="sensor-preset-grid"' -or $app -notmatch "isCompactDisplay \? 'grid-cols-1' : 'grid-cols-2'") {
    throw 'App.jsx does not stack the sensor preset buttons on the compact HAT profile'
}

if (
    $app -notmatch "Manual signal mapping" -or
    $app -notmatch "flex min-h-\[3\.25rem\] min-w-0 touch-manipulation flex-col justify-between" -or
    $tests -notmatch "className\)\.toContain\('flex-col'\)"
) {
    throw 'Compact sensor preset cards are not guarded as stacked flex layouts'
}

if (
    $tests -notmatch "name: /2 bar map/i" -or
    $tests -notmatch "name: /custom \\\/ ecu/i" -or
    $tests -notmatch "className\)\.toContain\('touch-manipulation'\)"
) {
    throw 'App.test.jsx does not guard touch-manipulation on compact sensor preset cards'
}

if ($app -notmatch 'data-testid="sensor-profile-summary-grid"' -or $app -notmatch "data-testid=`"sensor-profile-summary-grid`"[\s\S]*isCompactDisplay \? 'grid-cols-1' : 'grid-cols-2'") {
    throw 'App.jsx does not stack the selected-profile summary cards on the compact HAT profile'
}

if (
    $app -notmatch 'data-testid="sensor-profile-name"' -or
    $app -notmatch "data-testid=`"sensor-profile-name`"[\s\S]*isCompactDisplay \? 'mt-1 text-\[11px\] leading-tight whitespace-normal break-words' : 'mt-1 text-sm'" -or
    $app -notmatch 'data-testid="sensor-profile-description"' -or
    $app -notmatch "data-testid=`"sensor-profile-description`"[\s\S]*isCompactDisplay \? 'mt-1 text-\[8px\] leading-tight whitespace-normal' : 'mt-1 text-\[9px\] leading-4'"
) {
    throw 'App.jsx does not keep the selected-profile summary text compact and wrapped on the HAT layout'
}

if ($app -notmatch 'data-testid="sensor-boost-window-card"' -or $app -notmatch "data-testid=`"sensor-boost-window-card`"[\s\S]*isCompactDisplay \? 'col-span-1' : 'col-span-2'") {
    throw 'App.jsx does not keep the compact boost-window summary card inside the single-column sensor summary grid'
}

if (
    $app -notmatch 'inputMode="decimal"' -or
    $app -notmatch 'enterKeyHint="done"' -or
    $app -notmatch 'aria-label="Minimum gauge limit"' -or
    $app -notmatch 'aria-label="Maximum gauge limit"'
) {
    throw 'App.jsx does not expose touch-friendly gauge limit inputs with a done action hint'
}

Write-Host 'dashboard layout checks passed'
