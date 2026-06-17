[CmdletBinding()]
param(
  [ValidateSet('Desktop', 'StartMenu', 'Both')]
  [string]$Scope = 'Desktop',
  [string]$ShortcutName = 'Claude Desktop Proxy Launcher',
  [string]$ProxyServer = '',
  [string]$LauncherPath = '',
  [switch]$NoRestartExisting,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-LauncherPath {
  if (-not [string]::IsNullOrWhiteSpace($LauncherPath)) {
    if (Test-Path -LiteralPath $LauncherPath -PathType Leaf) {
      return (Resolve-Path -LiteralPath $LauncherPath).Path
    }

    throw "The path passed via -LauncherPath does not exist: $LauncherPath"
  }

  $scriptDirectory = $PSScriptRoot
  $defaultLauncher = Join-Path $scriptDirectory 'Start-ClaudeDesktopProxy.cmd'
  if (Test-Path -LiteralPath $defaultLauncher -PathType Leaf) {
    return (Resolve-Path -LiteralPath $defaultLauncher).Path
  }

  throw "Start-ClaudeDesktopProxy.cmd was not found next to Install-Shortcut.ps1."
}

function Get-SafeShortcutFileName {
  param([string]$Name)

  $safeName = $Name
  foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
    $safeName = $safeName.Replace([string]$invalidChar, ' ')
  }

  $safeName = $safeName.Trim()
  if ([string]::IsNullOrWhiteSpace($safeName)) {
    throw 'ShortcutName cannot be empty.'
  }

  if (-not $safeName.EndsWith('.lnk', [System.StringComparison]::OrdinalIgnoreCase)) {
    $safeName = "$safeName.lnk"
  }

  return $safeName
}

function Get-ShortcutDirectories {
  $directories = @()

  if (($Scope -eq 'Desktop') -or ($Scope -eq 'Both')) {
    $directories += [Environment]::GetFolderPath('Desktop')
  }

  if (($Scope -eq 'StartMenu') -or ($Scope -eq 'Both')) {
    $directories += Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  }

  return @($directories | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Quote-LauncherArgument {
  param([string]$Value)

  if ($Value -match '"') {
    throw 'Arguments with double quotes are not supported.'
  }

  return '"' + $Value + '"'
}

function Get-LauncherArguments {
  $arguments = @()

  if (-not $NoRestartExisting) {
    $arguments += '-RestartExisting'
  }

  if (-not [string]::IsNullOrWhiteSpace($ProxyServer)) {
    $arguments += '-ProxyServer'
    $arguments += (Quote-LauncherArgument $ProxyServer)
  }

  return ($arguments -join ' ')
}

function New-ShortcutPlan {
  param(
    [string]$Directory,
    [string]$FileName,
    [string]$Launcher,
    [string]$Arguments
  )

  $shortcutPath = Join-Path $Directory $FileName

  return [pscustomobject]@{
    path = $shortcutPath
    targetPath = $Launcher
    arguments = $Arguments
    workingDirectory = Split-Path -Parent $Launcher
    description = 'Launch Claude Desktop with explicit proxy flags on Windows.'
    exists = [bool](Test-Path -LiteralPath $shortcutPath)
  }
}

function Save-Shortcut {
  param([pscustomobject]$Plan)

  $directory = Split-Path -Parent $Plan.path
  New-Item -ItemType Directory -Force -Path $directory | Out-Null

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($Plan.path)
  $shortcut.TargetPath = $Plan.targetPath
  $shortcut.Arguments = $Plan.arguments
  $shortcut.WorkingDirectory = $Plan.workingDirectory
  $shortcut.Description = $Plan.description
  $shortcut.WindowStyle = 7
  $shortcut.Save()
}

$launcher = Resolve-LauncherPath
$shortcutFileName = Get-SafeShortcutFileName -Name $ShortcutName
$launcherArguments = Get-LauncherArguments

$plans = @(Get-ShortcutDirectories | ForEach-Object {
  New-ShortcutPlan -Directory $_ -FileName $shortcutFileName -Launcher $launcher -Arguments $launcherArguments
})

$result = [pscustomobject]@{
  dryRun = [bool]$DryRun
  shortcutCount = $plans.Count
  shortcutName = $shortcutFileName
  launcherPath = $launcher
  shortcuts = $plans
}

if ($DryRun) {
  $result | ConvertTo-Json -Depth 5
  exit 0
}

foreach ($plan in $plans) {
  Save-Shortcut -Plan $plan
}

$result | ConvertTo-Json -Depth 5
