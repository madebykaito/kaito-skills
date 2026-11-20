# Runs once, at the first logon of the test VM (see autounattend.xml).
# Installs the UTM drivers, OpenSSH, Git for Windows and Node 22, then trims the disk and shuts down.
# Log: C:\kaito-firstboot.log. tests/windows/build.sh waits for the shutdown.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Start-Transcript -Path C:\kaito-firstboot.log
$media = Split-Path -Parent $MyInvocation.MyCommand.Path
$tmp = 'C:\kaito-install'
New-Item -ItemType Directory -Force $tmp | Out-Null

function Get-Url($url, $out) {
  for ($i = 1; $i -le 5; $i++) {
    try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out; return } catch { Start-Sleep 10 }
  }
  throw "download failed: $url"
}
function Run($exe, $argList) {
  $p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru
  if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "$exe exited $($p.ExitCode)" }
}

try {
  # Drivers (network, display, agent) from UTM's guest tools disc.
  $tools = Get-PSDrive -PSProvider FileSystem | ForEach-Object { Get-ChildItem "$($_.Root)utm-guest-tools*.exe" -ErrorAction SilentlyContinue } | Select-Object -First 1
  if (-not $tools) { throw 'UTM guest tools disc not found' }
  Run $tools.FullName '/S'

  # Wait for the network.
  for ($i = 0; $i -lt 60 -and -not (Test-NetConnection github.com -Port 443 -InformationLevel Quiet); $i++) { Start-Sleep 5 }

  # Defender and Windows Update stay as they are: changing them makes Defender block this script.
  powercfg /hibernate off

  $gh = @{ 'User-Agent' = 'kaito-skills-test-vm' }

  # OpenSSH server, Git Bash as its shell, key-only login for the admin user.
  $rel = Invoke-RestMethod -Headers $gh https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest
  $msi = $rel.assets | Where-Object { $_.name -match 'ARM64.*\.msi$' } | Select-Object -First 1
  Get-Url $msi.browser_download_url "$tmp\openssh.msi"
  Run msiexec.exe "/i `"$tmp\openssh.msi`" /qn"

  $rel = Invoke-RestMethod -Headers $gh https://api.github.com/repos/git-for-windows/git/releases/latest
  $exe = $rel.assets | Where-Object { $_.name -match '^Git-.*-arm64\.exe$' } | Select-Object -First 1
  Get-Url $exe.browser_download_url "$tmp\git.exe"
  Run "$tmp\git.exe" '/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES'

  $v = ((Invoke-RestMethod https://nodejs.org/dist/index.json) | Where-Object { $_.version -like 'v22.*' } | Select-Object -First 1).version
  Get-Url "https://nodejs.org/dist/$v/node-$v-arm64.msi" "$tmp\node.msi"
  Run msiexec.exe "/i `"$tmp\node.msi`" /qn"

  $ssh = 'C:\ProgramData\ssh'
  New-Item -ItemType Directory -Force $ssh | Out-Null
  Copy-Item "$media\authorized_keys" "$ssh\administrators_authorized_keys"
  icacls "$ssh\administrators_authorized_keys" /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
  Add-Content "$ssh\sshd_config" "`nPasswordAuthentication no"
  New-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value 'C:\Program Files\Git\bin\bash.exe' -PropertyType String -Force | Out-Null
  if (-not (Get-NetFirewallRule -Name kaito-sshd -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name kaito-sshd -DisplayName 'OpenSSH (test VM)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null
  }
  Set-Service sshd -StartupType Automatic
  Restart-Service sshd

  # Leave as little on disk as possible: installers, temp files, then hand free space back to the host.
  Remove-Item -Recurse -Force $tmp, "$env:TEMP\*", 'C:\Windows\Temp\*' -ErrorAction SilentlyContinue
  Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
  Optimize-Volume -DriveLetter C -ReTrim
  Set-Content C:\kaito-ready 'ok'
} catch {
  Write-Host "firstboot failed: $_"
  Set-Content C:\kaito-ready "failed: $_"
} finally {
  Stop-Transcript
  Stop-Computer -Force
}
