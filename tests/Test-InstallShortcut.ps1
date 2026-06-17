$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$installer = Join-Path $repoRoot 'Install-Shortcut.ps1'
$launcher = Join-Path $repoRoot 'Start-ClaudeDesktopProxy.cmd'

if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
  throw "Missing installer script: $installer"
}

if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
  throw "Missing launcher wrapper: $launcher"
}

$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
  -DryRun `
  -Scope Both `
  -ShortcutName 'Claude Desktop Proxy Launcher Test' `
  -ProxyServer 'http://127.0.0.1:10808'

$result = $json | ConvertFrom-Json

if (-not $result.dryRun) {
  throw 'Expected dryRun to be true.'
}

if ($result.shortcutCount -ne 2) {
  throw "Expected two shortcut plans, got $($result.shortcutCount)."
}

foreach ($shortcut in $result.shortcuts) {
  if ($shortcut.targetPath -ne $launcher) {
    throw "Unexpected shortcut target: $($shortcut.targetPath)"
  }

  if ($shortcut.arguments -notmatch '-ProxyServer "http://127\.0\.0\.1:10808"') {
    throw "Proxy argument missing from shortcut arguments: $($shortcut.arguments)"
  }

  if ($shortcut.arguments -notmatch '-RestartExisting') {
    throw "RestartExisting argument missing from shortcut arguments: $($shortcut.arguments)"
  }
}

'Install-Shortcut dry-run test: OK'
