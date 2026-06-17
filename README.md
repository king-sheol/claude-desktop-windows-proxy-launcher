# Claude Desktop Windows Proxy Launcher

Unofficial workaround for Claude Desktop on Windows when the app breaks after an
update and cannot reach `claude.ai` through the same proxy/VPN path that works in
your browser.

Not affiliated with Anthropic. This project does not modify, patch, decompile,
redistribute, or replace Anthropic software.

## Emergency Quick Start

Use this if Claude Desktop is crashing, stuck in a Windows Repair/Restore loop,
showing a blank window, or saying "Could not connect to Claude".

1. Download this repository as a ZIP:
   <https://github.com/king-sheol/claude-desktop-windows-proxy-launcher/archive/refs/heads/main.zip>
2. Extract the ZIP into a normal folder, for example:
   `%USERPROFILE%\Documents\ClaudeDesktopProxyLauncher`
3. Open that folder.
4. Double-click:
   `Start-ClaudeDesktopProxy.cmd`

If you prefer PowerShell first, run a dry-run preview before launching:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ClaudeDesktopProxy.ps1 -DryRun
```

Then launch Claude through the wrapper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ClaudeDesktopProxy.ps1 -RestartExisting
```

## Does This Match Your Problem?

This may help if:

- Claude Desktop fails to launch after an update, crashes immediately, or hangs
  in Task Manager without showing a usable window.
- Windows repeatedly suggests repairing/restoring the Claude app, but repair or
  reinstalling over the existing app does not fix the startup loop.
- Claude opens but shows "Could not connect to Claude".
- Claude opens to a blank/white screen.
- Logs mention Electron/Chromium startup or GPU-process failures near launch.
- Logs show network failures such as `ERR_TIMED_OUT` or HTTP 403 while loading
  `https://claude.ai`.
- Your browser can open Claude through the same proxy/VPN, but Claude Desktop
  cannot.
- You use a local or corporate HTTP(S) proxy.

This probably will not help if:

- Cowork VM reaches "API UNREACHABLE" because the VM itself has no usable egress
  path through a corporate proxy.
- Hyper-V, HNS, Virtual Machine Platform, App Installer, disk space, or MSIX
  servicing is broken.
- Your proxy is PAC-only or NTLM/Kerberos-only and cannot be represented as a
  simple proxy URL without a local relay.

## Setup Options

### Option A: Let an AI Assistant Help

If you want ChatGPT, Copilot, Codex, Claude, or another local-capable assistant
to do the setup with you, copy/paste:

[`AI-ASSISTANT-PROMPT.md`](AI-ASSISTANT-PROMPT.md)

That prompt tells the assistant to run dry-run checks first, avoid deleting
Claude data, avoid changing system proxy settings, and ask before creating a
shortcut.

### Option B: Download ZIP

1. Download:
   <https://github.com/king-sheol/claude-desktop-windows-proxy-launcher/archive/refs/heads/main.zip>
2. Extract the ZIP.
3. Open the extracted folder.
4. Run `Start-ClaudeDesktopProxy.cmd`, or use the PowerShell commands in
   "Emergency Quick Start".

### Option C: Git Clone

```powershell
git clone https://github.com/king-sheol/claude-desktop-windows-proxy-launcher.git "$env:USERPROFILE\Documents\ClaudeDesktopProxyLauncher"
cd "$env:USERPROFILE\Documents\ClaudeDesktopProxyLauncher"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ClaudeDesktopProxy.ps1 -DryRun
```

## Install a Persistent Shortcut

The launcher can create a new shortcut named `Claude Desktop Proxy Launcher`.
It does not replace or modify the official Claude shortcut.

Create a Desktop shortcut:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1
```

Create both Desktop and Start Menu shortcuts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1 -Scope Both
```

Preview what would be created without writing anything:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1 -DryRun -Scope Both
```

If your proxy can change over time, do not pass `-ProxyServer`. The shortcut will
launch the wrapper without a fixed proxy, and the launcher will resolve the
current Windows/env proxy each time.

Only bake in a proxy if you really want a fixed value:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1 -Scope Both -ProxyServer "http://127.0.0.1:10808"
```

## What Success Looks Like

- Claude Desktop opens through `Start-ClaudeDesktopProxy.cmd` or the new
  `Claude Desktop Proxy Launcher` shortcut.
- The app no longer stops at "Could not connect to Claude".
- The dry-run output finds a `Claude.exe` path.
- If a proxy is resolved, the launch arguments include `--proxy-server=...`.
- The launcher reports that a visible Claude window was detected after launch.

## How to Undo

This workaround is intentionally easy to remove:

1. Close Claude Desktop.
2. Delete the `Claude Desktop Proxy Launcher` shortcut from Desktop and/or Start
   Menu if you created it.
3. Delete the folder where you extracted or cloned this repository.

Your Claude chats, projects, workspace folders, settings, plugins, and skills
are not stored in this launcher folder.

## What This Changes

This launcher:

1. Finds Claude Desktop in MSIX/AppX install locations first.
2. Falls back to common Win32/Squirrel install paths, Start Menu/Desktop
   shortcuts, and Windows uninstall registry entries.
3. Resolves a proxy from explicit argument, Windows user proxy, or env vars.
4. Sets child-process env vars:
   - `HTTP_PROXY`
   - `HTTPS_PROXY`
   - `ALL_PROXY`
   - `NO_PROXY`
5. Starts Claude with flags similar to:

```text
--proxy-server=http://127.0.0.1:10808
--proxy-bypass-list=<-loopback>
--disable-quic
--disable-gpu
--disable-gpu-compositing
--disable-gpu-sandbox
--disable-accelerated-2d-canvas
--disable-accelerated-video-decode
--disable-features=Vulkan,UseSkiaRenderer,CanvasOopRasterization,WebGPU,DawnGraphite
```

The launcher intentionally does not pass `--disable-software-rasterizer`. On at
least one affected Windows 11 setup, that flag allowed the process to survive
but prevented Claude from creating a usable visible window.

If Claude is installed in a custom location that cannot be discovered
automatically, pass it explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ClaudeDesktopProxy.ps1 -ClaudeExe "C:\Path\To\Claude.exe"
```

## What This Does Not Change

- It does not remove `%APPDATA%\Claude`, `%LOCALAPPDATA%\Packages`, workspace
  folders, plugins, sessions, or settings.
- It does not patch `app.asar` or any signed Anthropic package.
- It does not set machine-wide proxy settings.
- It does not modify WinHTTP, firewall, DNS, Hyper-V, or Windows services.
- It does not replace the official Claude shortcut.
- It does not bypass authentication, subscriptions, rate limits, regional
  availability, or any Anthropic policy.

## Why No EXE?

This project intentionally ships as a readable PowerShell script plus a tiny CMD
wrapper instead of an unsigned EXE. An unsigned executable from a small GitHub
repository is harder for users to audit and is more likely to trigger Windows
SmartScreen or antivirus warnings.

The CMD file is only a convenience wrapper for double-click launching. The real
logic stays in `Start-ClaudeDesktopProxy.ps1`, where users can inspect exactly
what will run before they run it.

## Observed Version and Scope

This workaround was created after a June 2026 Claude Desktop for Windows update
wave. The symptoms were not limited to one installer type: they may appear with
MSIX/AppX builds as well as traditional EXE/Squirrel/Win32 installs.

It was locally verified against the MSIX/AppX package version `1.13576.0.0`
(`Claude_1.13576.0.0_x64__pzs8sxrjxfjjc`), and the launcher intentionally
searches for both MSIX/AppX and Win32 install locations.

It may also help nearby Windows builds with the same symptoms, but this project
does not claim an official regression window. The practical symptom is that the
main Electron/Chromium UI appears unable to use the same proxy path that works in
the browser or in some child processes. Passing Chromium's `--proxy-server`
explicitly at launch can restore connectivity for that UI layer.

## Files in This Repository

- `Start-ClaudeDesktopProxy.cmd`: double-click wrapper for normal use.
- `Start-ClaudeDesktopProxy.ps1`: main launcher logic.
- `Install-Shortcut.ps1`: optional shortcut installer.
- `AI-ASSISTANT-PROMPT.md`: prompt for a local-capable AI assistant.
- `tests/`: developer verification scripts. Normal users do not need this
  folder to launch Claude.

## Upstream Fix Suggestion

Claude Desktop should provide a supported proxy configuration path for Windows
Desktop, including the main Electron webview and the Claude Code / MCP child
processes. For MSIX builds, it would also help to support an official way to pass
safe Chromium/Electron startup flags or expose equivalent settings in the app UI.
