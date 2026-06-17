[CmdletBinding()]
param(
  [string]$ProxyServer = '',
  [string]$ClaudeExe = '',
  [switch]$RestartExisting,
  [switch]$NoGpuWorkaround,
  [switch]$NoQuicWorkaround,
  [switch]$NoLaunchHealthCheck,
  [int]$PostLaunchCheckSeconds = 12,
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

function Join-OptionalPath {
  param(
    [string]$Base,
    [string]$Child
  )

  if ([string]::IsNullOrWhiteSpace($Base)) {
    return $null
  }

  return (Join-Path $Base $Child)
}

function Add-ClaudeCandidate {
  param(
    [System.Collections.Generic.List[string]]$Candidates,
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  try {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
      return
    }

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if ($resolved -notmatch '(?i)\\claude\.exe$') {
      return
    }

    foreach ($candidate in $Candidates) {
      if ([string]::Equals($candidate, $resolved, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
      }
    }

    [void]$Candidates.Add($resolved)
  } catch {
    return
  }
}

function Add-ClaudeCandidatePattern {
  param(
    [System.Collections.Generic.List[string]]$Candidates,
    [string]$Pattern
  )

  if ([string]::IsNullOrWhiteSpace($Pattern)) {
    return
  }

  Get-ChildItem -Path $Pattern -ErrorAction SilentlyContinue |
    Sort-Object -Property LastWriteTime -Descending |
    ForEach-Object { Add-ClaudeCandidate -Candidates $Candidates -Path $_.FullName }
}

function Add-ClaudeCandidateFromDirectory {
  param(
    [System.Collections.Generic.List[string]]$Candidates,
    [string]$Directory
  )

  if ([string]::IsNullOrWhiteSpace($Directory)) {
    return
  }

  foreach ($relativePath in @('app\Claude.exe', 'Claude.exe', 'app\claude.exe', 'claude.exe')) {
    Add-ClaudeCandidate -Candidates $Candidates -Path (Join-Path $Directory $relativePath)
  }
}

function Get-ShortcutTargetPath {
  param([string]$ShortcutPath)

  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    return $shortcut.TargetPath
  } catch {
    return $null
  }
}

function Find-ClaudeExecutable {
  if (-not [string]::IsNullOrWhiteSpace($ClaudeExe)) {
    if (Test-Path -LiteralPath $ClaudeExe) {
      return (Resolve-Path -LiteralPath $ClaudeExe).Path
    }
    throw "The path passed via -ClaudeExe does not exist: $ClaudeExe"
  }

  $candidates = New-Object 'System.Collections.Generic.List[string]'
  $seenPackages = @{}

  foreach ($pkg in @(Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue)) {
    if ($pkg -and $pkg.PackageFullName -and -not $seenPackages.ContainsKey($pkg.PackageFullName)) {
      $seenPackages[$pkg.PackageFullName] = $pkg
    }
  }

  foreach ($pkg in @(Get-AppxPackage -Name '*Claude*' -ErrorAction SilentlyContinue)) {
    if ($pkg -and $pkg.PackageFullName -and -not $seenPackages.ContainsKey($pkg.PackageFullName)) {
      $seenPackages[$pkg.PackageFullName] = $pkg
    }
  }

  foreach ($pkg in @($seenPackages.Values | Sort-Object -Property Version -Descending)) {
    if ($pkg.InstallLocation) {
      Add-ClaudeCandidateFromDirectory -Candidates $candidates -Directory $pkg.InstallLocation
    }
  }

  $patterns = @(
    (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\app-*\Claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\app-*\claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Claude Desktop\Claude.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\claude-desktop\Claude.exe'),
    (Join-OptionalPath $env:ProgramFiles 'Anthropic\Claude\Claude.exe'),
    (Join-OptionalPath $env:ProgramFiles 'Claude\Claude.exe'),
    (Join-OptionalPath $env:ProgramFiles 'Claude Desktop\Claude.exe'),
    (Join-OptionalPath ${env:ProgramFiles(x86)} 'Anthropic\Claude\Claude.exe'),
    (Join-OptionalPath ${env:ProgramFiles(x86)} 'Claude\Claude.exe'),
    (Join-OptionalPath ${env:ProgramFiles(x86)} 'Claude Desktop\Claude.exe')
  )

  foreach ($pattern in $patterns) {
    Add-ClaudeCandidatePattern -Candidates $candidates -Pattern $pattern
  }

  $shortcutPatterns = @(
    (Join-OptionalPath $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Claude*.lnk'),
    (Join-OptionalPath $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Claude*.lnk'),
    (Join-OptionalPath ([Environment]::GetFolderPath('Desktop')) 'Claude*.lnk'),
    (Join-OptionalPath ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Claude*.lnk')
  )

  foreach ($shortcutPattern in $shortcutPatterns) {
    if ([string]::IsNullOrWhiteSpace($shortcutPattern)) {
      continue
    }

    Get-ChildItem -Path $shortcutPattern -ErrorAction SilentlyContinue |
      Sort-Object -Property LastWriteTime -Descending |
      ForEach-Object {
        Add-ClaudeCandidate -Candidates $candidates -Path (Get-ShortcutTargetPath -ShortcutPath $_.FullName)
      }
  }

  $uninstallRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )

  foreach ($root in $uninstallRoots) {
    Get-ChildItem -Path $root -ErrorAction SilentlyContinue |
      ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } |
      Where-Object { $_.DisplayName -match '(?i)\bClaude\b|Anthropic' } |
      ForEach-Object {
        if ($_.InstallLocation) {
          Add-ClaudeCandidateFromDirectory -Candidates $candidates -Directory $_.InstallLocation
        }

        if ($_.DisplayIcon) {
          $iconPath = ($_.DisplayIcon -replace ',\d+$', '').Trim('"')
          Add-ClaudeCandidate -Candidates $candidates -Path $iconPath
        }
      }
  }

  if ($candidates.Count -gt 0) {
    return $candidates[0]
  }

  throw @'
Claude.exe was not found automatically.

Pass the full path with -ClaudeExe, for example:
  .\Start-ClaudeDesktopProxy.ps1 -ClaudeExe "C:\Path\To\Claude.exe"
'@
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

function Get-ClaudeProcessesForLaunch {
  param(
    [string]$ExePath,
    [string]$ResolvedProxy
  )

  $target = $ExePath.ToLowerInvariant()
  @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      if (-not $_.ExecutablePath -or ($_.ExecutablePath.ToLowerInvariant() -ne $target)) {
        $false
      }
      elseif ([string]::IsNullOrWhiteSpace($ResolvedProxy)) {
        $true
      }
      else {
        $commandLine = [string]$_.CommandLine
        $commandLine.IndexOf("--proxy-server=$ResolvedProxy", [System.StringComparison]::OrdinalIgnoreCase) -ge 0
      }
    })
}

function Get-VisibleClaudeProcessesForLaunch {
  param(
    [string]$ExePath,
    [string]$ResolvedProxy
  )

  foreach ($proc in @(Get-ClaudeProcessesForLaunch -ExePath $ExePath -ResolvedProxy $ResolvedProxy)) {
    $process = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
    if ($process -and ($process.MainWindowHandle -ne 0) -and $process.Responding) {
      $proc
    }
  }
}

function Wait-ForVisibleClaudeWindow {
  param(
    [string]$ExePath,
    [string]$ResolvedProxy,
    [int]$TimeoutSeconds
  )

  $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
  do {
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  @(Get-VisibleClaudeProcessesForLaunch -ExePath $ExePath -ResolvedProxy $ResolvedProxy)
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
    $arguments += '--disable-gpu-sandbox'
    $arguments += '--disable-accelerated-2d-canvas'
    $arguments += '--disable-accelerated-video-decode'
    $arguments += '--disable-features=Vulkan,UseSkiaRenderer,CanvasOopRasterization,WebGPU,DawnGraphite'
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
  launchHealthCheck = -not [bool]$NoLaunchHealthCheck
  postLaunchCheckSeconds = [int]$PostLaunchCheckSeconds
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

if (-not $NoLaunchHealthCheck) {
  $visibleProcesses = @(Wait-ForVisibleClaudeWindow -ExePath $exe -ResolvedProxy $proxy.ProxyServer -TimeoutSeconds $PostLaunchCheckSeconds)
  if ($visibleProcesses.Count -eq 0) {
    Write-Warning "Claude was launched, but no visible main window was detected after $PostLaunchCheckSeconds second(s)."
    Write-Warning 'If the process is stuck in the background, close Claude from Task Manager and re-run this launcher with -RestartExisting.'
    exit 1
  }

  Write-Host "Claude visible window detected ($($visibleProcesses.Count) process match)."
}
