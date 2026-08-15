<#
.SYNOPSIS
Uninstall the dsh-subagent-route-inheritance plugin from one or more dsh profiles.

.DESCRIPTION
Removes plugin\subagent-route-inheritance.mjs and the insert block (or its row
lines, if the block was hand-edited) from each profile's cordis.patch.yml.
Other patch content is left untouched.

.PARAMETER Profiles
One or more dsh profile names to uninstall from. Defaults to 'web'.

.PARAMETER All
Uninstall from every known profile (web, headless).

.EXAMPLE
.\uninstall.ps1
.\uninstall.ps1 -Profiles web,headless
.\uninstall.ps1 -All

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
$blockComment = "# dsh-subagent-route-inheritance: subagent children inherit the parent's live model/effort route"
$rowId = '    - id: subagent-route-inheritance'
$rowName = '      name: ./plugins/subagent-route-inheritance.mjs'

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
$profilesDir = Join-Path $dshHome 'profiles'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($p in $Profiles) {
  $profileDir = Join-Path $profilesDir $p
  $pluginsDir = Join-Path $profileDir 'plugins'
  $patchFile = Join-Path $profileDir 'cordis.patch.yml'
  Write-Host "== profile: $p ($profileDir)"

  $pluginTarget = Join-Path $pluginsDir $pluginFile
  if (Test-Path $pluginTarget) { Remove-Item $pluginTarget -Force }
  Write-Host '  plugin file removed'

  if (-not (Test-Path $patchFile)) {
    Write-Host '  no cordis.patch.yml; nothing else to do'
    continue
  }

  $content = [System.IO.File]::ReadAllText($patchFile)
  $nl = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = $content -split "`r?`n"
  $kept = New-Object System.Collections.Generic.List[string]
  $skip = 0
  foreach ($line in $lines) {
    $s = $line.TrimEnd("`r")
    if ($skip -gt 0) { $skip--; continue }
    # The canonical block is the comment line plus its three body lines.
    if ($s -eq $blockComment) { $skip = 3; continue }
    # Stray exact rows (hand-edited block) are dropped individually.
    if ($s -eq $rowId -or $s -eq $rowName) { continue }
    $kept.Add($line)
  }

  # Drop insert headers whose block ended up with no rows.
  $result = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $kept.Count; $i++) {
    $s = $kept[$i].TrimEnd("`r")
    if ($s -match '^[ \t]*- insert:[ \t]*$') {
      $j = $i + 1
      while ($j -lt $kept.Count -and $kept[$j].Trim() -eq '') { $j++ }
      if ($j -ge $kept.Count -or $kept[$j] -notmatch '^[ \t]') { continue }
    }
    $result.Add($kept[$i])
  }

  # The loader requires the patch file to stay a top-level YAML array: a file
  # left with only comments and blank lines would fail boot, so restore `[]`.
  $hasEntry = $false
  foreach ($line in $result) {
    if ($line.Trim() -ne '' -and -not $line.TrimStart().StartsWith('#')) { $hasEntry = $true; break }
  }
  if (-not $hasEntry) { $result.Add('[]') }

  [System.IO.File]::WriteAllText($patchFile, (($result -join $nl) + $nl), $utf8NoBom)
  Write-Host "  plugin rows removed from $patchFile"
}

Write-Host ''
Write-Host 'Done. Restart dsh for the change to take effect.'
