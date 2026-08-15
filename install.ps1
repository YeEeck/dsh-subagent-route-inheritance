<#
.SYNOPSIS
Install the dsh-subagent-route-inheritance plugin into one or more dsh profiles.

.DESCRIPTION
Copies plugin\subagent-route-inheritance.mjs into <profile>\plugins and inserts
its own `- insert:` block into the profile's cordis.patch.yml. The loader picks
the row up after the next `dsh` start. Installing twice is a no-op.

.PARAMETER Profiles
One or more dsh profile names to install into. Defaults to 'web'.

.PARAMETER All
Install into every known profile (web, headless).

.EXAMPLE
.\install.ps1
.\install.ps1 -Profiles web,headless
.\install.ps1 -All

The dsh home resolves as $env:DSH_HOME, else $HOME\.dsh.
#>
[CmdletBinding()]
param(
  [string[]]$Profiles = @('web'),
  [switch]$All
)

$ErrorActionPreference = 'Stop'

if ($All) { $Profiles = @('web', 'headless') }

$pluginFile = 'subagent-route-inheritance.mjs'
$pluginId = 'subagent-route-inheritance'
$pluginSource = Join-Path $PSScriptRoot "plugin\$pluginFile"
$blockComment = "# dsh-subagent-route-inheritance: subagent children inherit the parent's live model/effort route"
$block = @(
  $blockComment,
  '- insert:',
  '    - id: subagent-route-inheritance',
  '      name: ./plugins/subagent-route-inheritance.mjs'
) -join "`n"

if (-not (Test-Path $pluginSource)) {
  throw "install.ps1: plugin source not found: $pluginSource"
}

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
$profilesDir = Join-Path $dshHome 'profiles'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($p in $Profiles) {
  $profileDir = Join-Path $profilesDir $p
  $pluginsDir = Join-Path $profileDir 'plugins'
  $patchFile = Join-Path $profileDir 'cordis.patch.yml'
  $pluginTarget = Join-Path $pluginsDir $pluginFile
  Write-Host "== profile: $p ($profileDir)"

  New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null
  Copy-Item $pluginSource $pluginTarget -Force
  Write-Host "  plugin copied to $pluginTarget"

  $content = if (Test-Path $patchFile) { [System.IO.File]::ReadAllText($patchFile) } else { '' }
  # Idempotency is keyed on the exact row line, not any mention of the plugin
  # id: a comment can legitimately name the plugin without installing it.
  if ($content -match [regex]::Escape('    - id: subagent-route-inheritance')) {
    Write-Host "  cordis.patch.yml already contains '$pluginId'; nothing to do"
    continue
  }

  if ($content -match '(?m)^[ \t]*\[\][ \t]*\r?$') {
    # Replace a bare `[]`, keeping any header comments.
    $content = [regex]::Replace($content, '(?m)^[ \t]*\[\][ \t]*\r?$', "`n$block", 1)
  } else {
    if ($content -ne '' -and -not $content.EndsWith("`n")) { $content += "`n" }
    $content += $block + "`n"
  }
  [System.IO.File]::WriteAllText($patchFile, $content, $utf8NoBom)
  Write-Host "  insert block added to $patchFile"
}

Write-Host ''
Write-Host 'Done. Restart dsh (or reload the web profile) for the plugin to take effect.'
