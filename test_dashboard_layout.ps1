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

if (
    $main -notmatch "normalizeDisplayProfile\(params\.get\('profile'\)\)" -or
    $main -notmatch "import \{ normalizeDisplayProfile \} from './utils'"
) {
    throw 'main.jsx does not normalize the setup.sh display profile from the kiosk URL'
}

if (
    $app -notmatch "isCompactDisplayProfile\(displayProfile\)" -or
    $app -notmatch "import \{[\s\S]*isCompactDisplayProfile[\s\S]*\} from './utils';"
) {
    throw 'App.jsx does not derive compact layouts from the shared supported 3.5-inch display profile helper'
}

if (
    $tests -notmatch "52pi-k0403" -or
    $tests -notmatch "waveshare-35g" -or
    $tests -notmatch "generic-ili9486-hat"
) {
    throw 'App.test.jsx does not cover every compact 3.5-inch display profile'
}

if (
    $main -notmatch "preview === 'compact-480x320'" -or
    $main -notmatch "displayProfile: 'generic-ili9486-hat'"
) {
    throw 'main.jsx does not preserve the explicit compact preview profile'
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

if ($tests -notmatch 'treats every supported 3.5-inch setup profile as a compact layout') {
    throw 'App.test.jsx does not guard the shared compact layout behavior across setup.sh 3.5-inch profiles'
}

if ($tests -notmatch 'loads preset calibration values and re-enables editing in custom mode') {
    throw 'App.test.jsx does not guard sensor preset calibration and custom editability'
}

if (
    $tests -notmatch 'class MockVisualViewport' -or
    $tests -notmatch 'rescales the compact layout on orientation and visual viewport changes' -or
    $tests -notmatch "window\.dispatchEvent\(new Event\('orientationchange'\)\)" -or
    $tests -notmatch "window\.visualViewport\.emit\('resize'\)" -or
    $tests -notmatch 'removes visual viewport listeners when the dashboard unmounts'
) {
    throw 'App.test.jsx does not guard viewport/orientation scaling and visualViewport cleanup'
}

if (
    $app -notmatch "HW REV:" -or
    $app -notmatch "flex flex-wrap items-center gap-x-1 gap-y-0.5 text-\[9px\] leading-tight" -or
    $app -notmatch "Four verified presets plus a custom ECU / Haltech 0-5V analog map" -or
    $app -notmatch "whitespace-normal"
) {
    throw 'App.jsx does not let compact setup headers wrap cleanly on the 480x320 profile'
}

if (
    $app -notmatch 'aria-label="Return to dashboard"[\s\S]*min-h-\[2\.35rem\][\s\S]*touch-manipulation[\s\S]*flex items-center justify-center' -or
    $app -notmatch 'aria-label="Open MAP sensor mapping"[\s\S]*min-h-\[2\.35rem\][\s\S]*touch-manipulation[\s\S]*flex items-center justify-center' -or
    $app -notmatch 'aria-label="Return to settings"[\s\S]*min-h-\[2\.35rem\][\s\S]*touch-manipulation[\s\S]*flex items-center justify-center'
) {
    throw 'App.jsx does not keep compact header navigation buttons at an explicit touch-friendly size with direct touch handling'
}

if (
    $app -notmatch 'aria-label="Save settings and return to dashboard"[\s\S]*min-h-\[2\.35rem\][\s\S]*touch-manipulation[\s\S]*whitespace-nowrap' -or
    $app -notmatch 'aria-label="Save MAP sensor mapping and return to dashboard"[\s\S]*min-h-\[2\.35rem\][\s\S]*touch-manipulation[\s\S]*whitespace-nowrap'
) {
    throw 'App.jsx does not keep compact save-and-exit buttons at an explicit touch-friendly size with direct touch handling'
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
    $app -notmatch "Manual 0-5V mapping" -or
    $app -notmatch "flex min-h-\[3\.25rem\] min-w-0 touch-manipulation flex-col justify-between" -or
    $tests -notmatch "className\)\.toContain\('flex-col'\)"
) {
    throw 'Compact sensor preset cards are not guarded as stacked flex layouts'
}

if (
    $tests -notmatch "name: /gm \\\/ delphi 3 bar/i" -or
    $tests -notmatch "name: /custom ecu \\\/ haltech/i" -or
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

if (
    $app -notmatch 'aria-label="Signal minimum voltage"[\s\S]*min-h-\[2\.35rem\] px-2\.5 py-1\.5 text-\[15px\]' -or
    $app -notmatch 'aria-label="Signal maximum voltage"[\s\S]*min-h-\[2\.35rem\] px-2\.5 py-1\.5 text-\[15px\]' -or
    $app -notmatch 'aria-label="Pressure minimum absolute"[\s\S]*min-h-\[2\.35rem\] px-2\.5 py-1\.5 text-\[15px\]' -or
    $app -notmatch 'aria-label="Pressure maximum absolute"[\s\S]*min-h-\[2\.35rem\] px-2\.5 py-1\.5 text-\[15px\]'
) {
    throw 'App.jsx does not keep compact sensor calibration inputs at an explicit touch-friendly size'
}

if (
    $tests -notmatch "name: /signal minimum voltage/i[\s\S]*className\)\.toContain\('min-h-\[2\.35rem\]'\)" -or
    $tests -notmatch "name: /signal maximum voltage/i[\s\S]*className\)\.toContain\('min-h-\[2\.35rem\]'\)" -or
    $tests -notmatch "name: /pressure minimum absolute/i[\s\S]*className\)\.toContain\('min-h-\[2\.35rem\]'\)" -or
    $tests -notmatch "name: /pressure maximum absolute/i[\s\S]*className\)\.toContain\('min-h-\[2\.35rem\]'\)"
) {
    throw 'App.test.jsx does not guard compact sensor calibration touch target sizing'
}

if (
    $tests -notmatch "return to dashboard" -or
    $tests -notmatch "open map sensor mapping" -or
    $tests -notmatch "save settings and return to dashboard" -or
    $tests -notmatch "return to settings" -or
    $tests -notmatch "save map sensor mapping and return to dashboard" -or
    $tests -notmatch "touch-manipulation"
) {
    throw 'App.test.jsx does not guard touch-manipulation on compact navigation and save actions'
}

Write-Host 'dashboard layout checks passed'
