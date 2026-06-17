[CmdletBinding()]
param(
  [string]$ProxyServer = '',
  [string]$ClaudeExe = '',
  [switch]$RestartExisting,
  [switch]$NoGpuWorkaround,
  [switch]$NoQuicWorkaround,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Select-ProxyFromMap {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value) -or ($Value -notlike '*=*')) {
    return $null
  }

  $parts = @($Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  foreach ($name in @('https', 'http', 'socks5', 'socks4', 'socks')) {
    $escapedName = [regex]::Escape($name)
    $match = @($parts | Where-Object { $_ -match "^\s*$escapedName\s*=\s*(.+)\s*$" } | Select-Object -First 1)
    if ($match.Count -eq 0) {
      continue
    }

    $target = ([regex]::Replace($match[0], "^\s*$escapedName\s*=\s*", '')).Trim()
    if ([string]::IsNullOrWhiteSpace($target)) {
      continue
    }

    if (($name -like 'socks*') -and ($target -notmatch '^[a-zA-Z][a-zA-Z0-9+\-.]*://')) {
      return "socks5://$target"
    }

    return Normalize-ProxyServer $target
  }

  return $null
}

function Normalize-ProxyServer {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  $clean = $Value.Trim().Trim('"').Trim("'")
  if ([string]::IsNullOrWhiteSpace($clean) -or ($clean -match '^(direct|none)$')) {
    return $null
  }

  $mapped = Select-ProxyFromMap $clean
  if ($mapped) {
    return $mapped
  }

  if ($clean -match '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
    return $clean
  }

  return "http://$clean"
}

function Add-ProxyCandidate {
  param(
    [System.Collections.ArrayList]$Candidates,
    [string]$Source,
    [string]$Value
  )

  $normalized = Normalize-ProxyServer $Value
  if ($normalized) {
    [void]$Candidates.Add([pscustomobject]@{
      Source = $Source
      ProxyServer = $normalized
    })
  }
}

function Get-ProxyCandidates {
  $candidates = [System.Collections.ArrayList]::new()

  Add-ProxyCandidate -Candidates $candidates -Source 'argument' -Value $ProxyServer

  $settingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  $settings = Get-ItemProperty -Path $settingsPath -ErrorAction SilentlyContinue
  if ($settings -and ($settings.ProxyEnable -eq 1) -and $settings.ProxyServer) {
    Add-ProxyCandidate -Candidates $candidates -Source 'windows-current-user' -Value ([string]$settings.ProxyServer)
  }

  foreach ($scope in @('Process', 'User', 'Machine')) {
    foreach ($name in @('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY')) {
      Add-ProxyCandidate -Candidates $candidates -Source "env-$scope-$name" -Value ([Environment]::GetEnvironmentVariable($name, $scope))
    }
  }

  $seen = @{}
  foreach ($candidate in $candidates) {
    $key = $candidate.ProxyServer.ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
      continue
    }
    $seen[$key] = $true
    $candidate
  }
}

function Resolve-ClaudeProxy {
  $candidates = @(Get-ProxyCandidates)
  if ($candidates.Count -eq 0) {
    return [pscustomobject]@{
      ProxyServer = $null
      Source = 'none'
      Candidates = @()
    }
  }

  return [pscustomobject]@{
    ProxyServer = $candidates[0].ProxyServer
    Source = $candidates[0].Source
    Candidates = $candidates
  }
}

function Find-ClaudeExecutable {
  if (-not [string]::IsNullOrWhiteSpace($ClaudeExe)) {
    if (Test-Path -LiteralPath $ClaudeExe) {
      return (Resolve-Path -LiteralPath $ClaudeExe).Path
    }
    throw "The path passed via -ClaudeExe does not exist: $ClaudeExe"
  }

  $pkg = @(Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1)[0]
  if ($pkg -and $pkg.InstallLocation) {
    $msixExe = Join-Path $pkg.InstallLocation 'app\Claude.exe'
    if (Test-Path -LiteralPath $msixExe) {
      return $msixExe
    }
  }

  $patterns = @(
    (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\app-*\Claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\app-*\claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\claude-desktop\Claude.exe')
  )

  foreach ($pattern in $patterns) {
    $match = @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
      Sort-Object -Property LastWriteTime -Descending |
      Select-Object -First 1)
    if ($match.Count -gt 0) {
      return $match[0].FullName
    }
  }

  throw 'Claude.exe was not found. Pass the full path with -ClaudeExe.'
}

function Stop-ExistingClaudeProcesses {
  param([string]$ExePath)

  if (-not $RestartExisting) {
    return
  }

  $target = $ExePath.ToLowerInvariant()
  $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.ExecutablePath -and ($_.ExecutablePath.ToLowerInvariant() -eq $target)
    })

  foreach ($proc in $processes) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
  }
}

function Set-ProxyEnvironment {
  param([string]$ResolvedProxy)

  if ([string]::IsNullOrWhiteSpace($ResolvedProxy)) {
    return
  }

  $env:HTTP_PROXY = $ResolvedProxy
  $env:HTTPS_PROXY = $ResolvedProxy
  $env:ALL_PROXY = $ResolvedProxy
  if ([string]::IsNullOrWhiteSpace($env:NO_PROXY)) {
    $env:NO_PROXY = 'localhost,127.0.0.1,::1,.local'
  }
}

function Get-ClaudeArguments {
  param([string]$ResolvedProxy)

  $arguments = @()
  if (-not [string]::IsNullOrWhiteSpace($ResolvedProxy)) {
    $arguments += "--proxy-server=$ResolvedProxy"
    $arguments += '--proxy-bypass-list=<-loopback>'
  }

  if (-not $NoQuicWorkaround) {
    $arguments += '--disable-quic'
  }

  if (-not $NoGpuWorkaround) {
    $arguments += '--disable-gpu'
    $arguments += '--disable-gpu-compositing'
  }

  return $arguments
}

$proxy = Resolve-ClaudeProxy
$exe = Find-ClaudeExecutable
$arguments = @(Get-ClaudeArguments -ResolvedProxy $proxy.ProxyServer)
$workingDirectory = Split-Path -Parent $exe

$result = [pscustomobject]@{
  dryRun = [bool]$DryRun
  claudeExe = $exe
  workingDirectory = $workingDirectory
  proxyServer = $proxy.ProxyServer
  proxySource = $proxy.Source
  restartExisting = [bool]$RestartExisting
  arguments = $arguments
}

if ($DryRun) {
  $result | ConvertTo-Json -Depth 5
  exit 0
}

Stop-ExistingClaudeProcesses -ExePath $exe
Set-ProxyEnvironment -ResolvedProxy $proxy.ProxyServer

Write-Host "Launching Claude:"
Write-Host "  $exe"
if ($proxy.ProxyServer) {
  Write-Host "Proxy:"
  Write-Host "  $($proxy.ProxyServer) ($($proxy.Source))"
}
else {
  Write-Warning 'No proxy was resolved. Claude will be launched without --proxy-server.'
}

Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $workingDirectory | Out-Null
