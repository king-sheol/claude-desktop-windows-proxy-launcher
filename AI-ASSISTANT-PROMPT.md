# AI Assistant Setup Prompt

Use this prompt with an AI assistant that can operate on your Windows machine
through a terminal or desktop automation tool. The assistant should install the
launcher, run dry-run checks first, and create an optional shortcut for you.
Plain web chat cannot do this by itself unless it has access to your local
terminal or can guide you step by step.

Do not paste private Claude logs, tokens, cookies, account data, or full proxy
credentials into public chats. If your proxy address is sensitive, keep it local.

## Copy/paste prompt

```text
I need help installing this unofficial Claude Desktop Windows proxy launcher:
https://github.com/king-sheol/claude-desktop-windows-proxy-launcher

Context:
- Claude Desktop on Windows may fail after an update with symptoms like startup
  crash, Windows Repair/Restore loop, blank/white screen, "Could not connect to
  Claude", ERR_TIMED_OUT, HTTP 403, or Electron/Chromium/GPU-process launch
  errors.
- My browser can reach https://claude.ai, but Claude Desktop may not use the
  same proxy path.
- I want a safe install that does not delete or modify my Claude data.

Your job:
1. Work only on my local machine.
2. Create a dedicated folder for this launcher, for example:
   %USERPROFILE%\Documents\ClaudeDesktopProxyLauncher
   If that folder already exists and is not empty, do not delete anything. Ask
   me whether to reuse it or create a new folder.
3. Download or clone the public repository into that folder:
   - If git is available, clone the repository:
     git clone https://github.com/king-sheol/claude-desktop-windows-proxy-launcher.git "%USERPROFILE%\Documents\ClaudeDesktopProxyLauncher"
   - If git is not available, download the repository ZIP from:
     https://github.com/king-sheol/claude-desktop-windows-proxy-launcher/archive/refs/heads/main.zip
     Then extract it and copy the files into:
     %USERPROFILE%\Documents\ClaudeDesktopProxyLauncher
4. Verify these files are present:
   - Start-ClaudeDesktopProxy.ps1
   - Start-ClaudeDesktopProxy.cmd
   - Install-Shortcut.ps1
5. Inspect the scripts before running them and summarize what they do.

Safety rules:
- Do not delete Claude data, workspaces, chats, settings, plugins, or skills.
- Do not remove or modify these folders:
  %APPDATA%\Claude
  %LOCALAPPDATA%\Packages
  %LOCALAPPDATA%\AnthropicClaude
  %USERPROFILE%\Documents\Claude Workspace
- Do not patch, decompile, or modify app.asar, MSIX/AppX packages, or Anthropic
  application files.
- Do not change machine-wide proxy settings, WinHTTP settings, firewall rules,
  DNS settings, Hyper-V settings, or Windows services unless I explicitly ask.
- Do not replace the official Claude shortcut. Only create a separate shortcut
  named "Claude Desktop Proxy Launcher".
- Do not install or run unsigned EXE files for this workaround. Use the readable
  PowerShell/CMD scripts from the repository.
- Do not paste my proxy address, tokens, cookies, logs, or account identifiers
  into any public place.
- In the final answer, do not print my full proxy address unless I explicitly
  ask. Say whether the proxy was resolved from Windows/env instead.

Run these checks first:

cd "%USERPROFILE%\Documents\ClaudeDesktopProxyLauncher"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ClaudeDesktopProxy.ps1 -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1 -DryRun -Scope Both

Read the dry-run output carefully:
- Confirm the launcher found Claude.exe.
- Confirm whether a proxy was resolved from Windows or environment variables.
- Confirm the shortcut target points to Start-ClaudeDesktopProxy.cmd.
- Confirm no command deletes or modifies Claude user data.

If dry-run looks safe, ask me before making changes. After I confirm, create the
shortcut:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1 -Scope Both

Then launch Claude through the proxy launcher:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ClaudeDesktopProxy.ps1 -RestartExisting

If my proxy can change over time, do not hard-code -ProxyServer into the
shortcut. Let the launcher read the current Windows/env proxy each time.

Only use -ProxyServer if I explicitly give you a proxy URL and ask you to bake
it into the shortcut, for example:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Shortcut.ps1 -Scope Both -ProxyServer "http://127.0.0.1:10808"

If Claude.exe is not found:
- Check installed MSIX/AppX packages with Get-AppxPackage.
- Check common per-user install paths under %LOCALAPPDATA%.
- Check Start Menu/Desktop shortcuts.
- If still not found, ask me for the Claude.exe location instead of guessing.

If no proxy is found:
- Ask me whether I use a local/corporate proxy or VPN.
- Do not invent a proxy address.
- You may show me how to check Windows proxy settings locally, but do not post
  the values publicly.

Final verification:
- Confirm the new "Claude Desktop Proxy Launcher" shortcut exists.
- Confirm it points to Start-ClaudeDesktopProxy.cmd.
- If a proxy was resolved, confirm the launched Claude process includes a
  --proxy-server argument.
- Tell me exactly what you changed and what you did not change.
```

## Notes for AI assistants

Prefer dry-run output and explicit confirmation over guessing. The goal is to
help the user keep their existing Claude setup intact while creating a separate
launcher path that can be removed easily.
