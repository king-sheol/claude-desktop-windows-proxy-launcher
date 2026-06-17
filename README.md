# Claude Desktop Windows Proxy Launcher

Unofficial workaround. Not affiliated with Anthropic. This project does not
modify, patch, decompile, redistribute, or replace Anthropic software.

Small workaround launcher for a specific Claude Desktop on Windows failure mode:
the app is installed and starts, but the main Electron/Chromium UI cannot reach
`claude.ai` through the user's Windows proxy, while Claude Code or other child
processes may still respect `HTTP_PROXY` / `HTTPS_PROXY`.

This launcher does not delete Claude data, does not modify the MSIX package, and
does not change system proxy settings. It only starts `Claude.exe` with explicit
Chromium proxy flags and proxy environment variables for child processes.

## Observed version and scope

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

## When this may help

- Claude Desktop fails to launch after an update, crashes immediately, or hangs
  in Task Manager without showing a usable window.
- Windows repeatedly suggests repairing/restoring the Claude app, but repair or
  reinstalling over the existing app does not fix the startup loop.
- Logs mention Electron/Chromium startup or GPU-process failures near launch.
- Claude Desktop on Windows shows "Could not connect to Claude".
- The app opens to a blank/white screen and logs show network failures such as
  `ERR_TIMED_OUT` or HTTP 403 while loading `https://claude.ai`.
- Your browser can open Claude through the same proxy/VPN, but Claude Desktop
  cannot.
- You use a local or corporate HTTP(S) proxy.

## When this probably will not help

- Cowork VM reaches "API UNREACHABLE" because the VM itself has no usable egress
  path through a corporate proxy.
- Hyper-V, HNS, Virtual Machine Platform, App Installer, disk space, or MSIX
  servicing is broken.
- Your proxy is a PAC-only or NTLM/Kerberos-only setup that requires an
  authenticated local relay and cannot be represented as a simple proxy URL.

## Usage

Download both files into the same folder:

- `Start-ClaudeDesktopProxy.ps1`
- `Start-ClaudeDesktopProxy.cmd`

Run:

```powershell
.\Start-ClaudeDesktopProxy.ps1
```

By default the script reads the current Windows user proxy from:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
```

It also checks `HTTPS_PROXY`, `HTTP_PROXY`, and `ALL_PROXY`.

To pass a proxy explicitly:

```powershell
.\Start-ClaudeDesktopProxy.ps1 -ProxyServer "http://127.0.0.1:10808"
```

If Claude is already running without the correct flags, restart it through the
launcher:

```powershell
.\Start-ClaudeDesktopProxy.ps1 -RestartExisting
```

To inspect what would be launched without starting Claude:

```powershell
.\Start-ClaudeDesktopProxy.ps1 -DryRun
```

If GPU flags make things worse on your system:

```powershell
.\Start-ClaudeDesktopProxy.ps1 -NoGpuWorkaround
```

## What it does

The launcher:

1. Finds Claude Desktop in the current MSIX/AppX package first.
2. Falls back to common Win32 install paths, Start Menu/Desktop shortcuts, and
   Windows uninstall registry entries.
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
```

If Claude is installed in a custom location that cannot be discovered
automatically, pass it explicitly:

```powershell
.\Start-ClaudeDesktopProxy.ps1 -ClaudeExe "C:\Path\To\Claude.exe"
```

## Safety notes

- This does not remove `%APPDATA%\Claude`, `%LOCALAPPDATA%\Packages`, workspace
  folders, plugins, sessions, or settings.
- This does not patch `app.asar` or the signed MSIX payload.
- This does not set machine-wide proxy settings.
- This is a workaround, not a substitute for a proper upstream fix in Claude
  Desktop's Windows proxy handling.
- Do not use this project to bypass authentication, subscriptions, rate limits,
  regional availability, or any Anthropic policy.

## Upstream fix suggestion

Claude Desktop should provide a supported proxy configuration path for Windows
Desktop, including the main Electron webview and the Claude Code / MCP child
processes. For MSIX builds, it would also help to support an official way to pass
safe Chromium/Electron startup flags or expose equivalent settings in the app UI.
