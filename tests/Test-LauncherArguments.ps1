$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$launcher = Join-Path $repoRoot 'Start-ClaudeDesktopProxy.ps1'

if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
  throw "Missing launcher script: $launcher"
}

function Assert-Contains {
  param(
    [object[]]$Collection,
    [object]$Expected,
    [string]$Message
  )

  if ($Collection -notcontains $Expected) {
    throw "$Message Missing '$Expected'."
  }
}

function Assert-NotContains {
  param(
    [object[]]$Collection,
    [object]$Unexpected,
    [string]$Message
  )

  if ($Collection -contains $Unexpected) {
    throw "$Message Unexpected '$Unexpected'."
  }
}

$tempExeDir = Join-Path $env:TEMP ("claude-launcher-test-{0}" -f ([guid]::NewGuid().ToString('N')))
$tempExe = Join-Path $tempExeDir 'Claude.exe'
New-Item -ItemType Directory -Path $tempExeDir -Force | Out-Null
New-Item -ItemType File -Path $tempExe -Force | Out-Null

try {
  $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher `
    -DryRun `
    -ClaudeExe $tempExe `
    -ProxyServer '127.0.0.1:10808'

  $result = $json | ConvertFrom-Json

  if (-not $result.dryRun) {
    throw 'Expected dryRun to be true.'
  }

  if ($result.proxyServer -ne 'http://127.0.0.1:10808') {
    throw "Expected normalized proxy, got $($result.proxyServer)."
  }

  Assert-Contains $result.arguments '--proxy-server=http://127.0.0.1:10808' 'Proxy flag should use the resolved proxy.'
  Assert-Contains $result.arguments '--proxy-bypass-list=<-loopback>' 'Loopback bypass should be explicit.'
  Assert-Contains $result.arguments '--disable-quic' 'QUIC should be disabled for proxy compatibility.'
  Assert-Contains $result.arguments '--disable-gpu' 'GPU should be disabled for affected Electron starts.'
  Assert-Contains $result.arguments '--disable-gpu-compositing' 'GPU compositing should be disabled.'
  Assert-Contains $result.arguments '--disable-gpu-sandbox' 'GPU sandbox should be disabled for affected Electron GPU subprocesses.'
  Assert-Contains $result.arguments '--disable-accelerated-2d-canvas' 'Accelerated canvas should be disabled.'
  Assert-Contains $result.arguments '--disable-accelerated-video-decode' 'Accelerated video decode should be disabled.'
  Assert-Contains $result.arguments '--disable-features=Vulkan,UseSkiaRenderer,CanvasOopRasterization,WebGPU,DawnGraphite' 'Known crashing Chromium GPU features should be disabled.'
  Assert-NotContains $result.arguments '--disable-software-rasterizer' 'Software rasterizer must remain available for visible window creation.'
}
finally {
  Remove-Item -LiteralPath $tempExeDir -Recurse -Force -ErrorAction SilentlyContinue
}

'Launcher argument dry-run test: OK'
