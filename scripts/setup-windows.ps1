# Installs what building word2pdf on Windows (ARM64 or x64) needs, the way LibreOffice's own
# .config/*.winget files set up a build machine: Visual Studio 2022 with the C++ tools for both
# architectures, Git for Windows and Python, WSL1 with Ubuntu (autogen.sh and configure run there,
# the build itself in Git Bash), Strawberry Perl portable, and LibreOffice's Windows builds of GNU
# make, pkgconf and jom. Java, Ant and JUnit are left out: word2pdf is built --without-java.
#
#   powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1   (elevated)
#
# Every step skips what is already in place, so run it again after the reboot it asks for.
[CmdletBinding()]
param(
    [string]$Tools = "C:\lo-tools",
    [string]$Workspace = "C:\word2pdf",
    [switch]$NoDefenderExclusion
)
$ErrorActionPreference = "Stop"
# Invoke-WebRequest is many times slower while it draws a progress bar
$ProgressPreference = "SilentlyContinue"

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "run this from an elevated PowerShell"
}
# the machine's, not this process's: an emulated x64 PowerShell sees PROCESSOR_ARCHITECTURE=AMD64
$arch = if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") { "arm64" } else { "x64" }
$rebootNeeded = $false

function Step($message) { Write-Host "==> $message" -ForegroundColor Cyan }

# For programs, whose failures show in $LASTEXITCODE: Windows PowerShell turns their stderr
# output into a terminating error when the script's output is redirected.
function Native {
    $ErrorActionPreference = "Continue"
    $program, $arguments = $args
    & $program @arguments 2>&1 | ForEach-Object { "$_" }
}

function Download($uri, $sha256) {
    $file = Join-Path "$Tools\downloads" ([IO.Path]::GetFileName(([Uri]$uri).AbsolutePath))
    if (-not (Test-Path $file) -or (Get-FileHash $file -Algorithm SHA256).Hash -ne $sha256) {
        Write-Host "    downloading $uri"
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile "$file.part"
        $actual = (Get-FileHash "$file.part" -Algorithm SHA256).Hash
        if ($actual -ne $sha256) { throw "$uri`: SHA-256 $actual, expected $sha256" }
        Move-Item -Force "$file.part" $file
    }
    $file
}

function WingetInstall($id, [string[]]$extra) {
    Native winget list --exact --id $id --accept-source-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "    $id already installed"; return }
    Native winget install --exact --id $id --silent --disable-interactivity `
        --accept-source-agreements --accept-package-agreements @extra
    if ($LASTEXITCODE -ne 0) { throw "winget install $id failed ($LASTEXITCODE)" }
}

New-Item -ItemType Directory -Force "$Tools\downloads", "$Tools\bin" | Out-Null

Step "Git for Windows, Python"
# The ARM64 Git for Windows puts clangarm64/ on the PATH, which is how LibreOffice's configure
# recognises a native ARM64 build environment.
WingetInstall Git.Git @("--scope", "machine", "--architecture", $arch)
WingetInstall Python.Python.3.13 @("--scope", "machine", "--architecture", $arch)

Step "Visual Studio 2022 with the C++ tools for x64 and ARM64"
$components = @(
    "Microsoft.VisualStudio.Workload.NativeDesktop",
    # configure looks Visual Studio up by this component, also for ARM64 builds
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "Microsoft.VisualStudio.Component.VC.Tools.ARM64",
    "Microsoft.VisualStudio.Component.VC.ATL",
    "Microsoft.VisualStudio.Component.VC.ATL.ARM64",
    "Microsoft.VisualStudio.Component.VC.CMake.Project",
    "Microsoft.VisualStudio.Component.VC.Llvm.Clang",
    "Microsoft.VisualStudio.Component.VC.Redist.MSM",
    "Microsoft.VisualStudio.Component.Windows11SDK.22621",
    # 4.8.1 is the first with ARM64 libraries (configure checks for mscoree.lib)
    "Microsoft.Net.Component.4.8.1.SDK"
)
$addArgs = $components | ForEach-Object { "--add"; $_ }
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = if (Test-Path $vswhere) { & $vswhere -version "[17,18)" -products * -property installationPath | Select-Object -First 1 }
if (-not $vsPath) {
    $bootstrapper = "$Tools\downloads\vs_community.exe"
    Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/vs/17/release/vs_community.exe" -OutFile $bootstrapper
    $p = Start-Process -Wait -PassThru $bootstrapper -ArgumentList (@("--quiet", "--wait", "--norestart", "--nocache") + $addArgs)
} else {
    $p = Start-Process -Wait -PassThru "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe" `
        -ArgumentList (@("modify", "--installPath", "`"$vsPath`"", "--quiet", "--norestart") + $addArgs)
}
switch ($p.ExitCode) {
    0 {}
    3010 { $rebootNeeded = $true }
    default { throw "Visual Studio installer failed with exit code $($p.ExitCode), logs in $env:TEMP\dd_*.log" }
}

Step "make, pkgconf, jom, Strawberry Perl"
# x64 executables; on ARM64 Windows they run under emulation. Not the 32-bit make 4.2.1 of
# LibreOffice's winget setup: System32 is redirected for 32-bit programs, so it cannot start
# wsl.exe, which the build runs bison, gperf etc. with.
$make = Download "https://dev-www.libreoffice.org/extern/make-4.4.1-msvc.exe" "3CBF585A213001FBDEDC5269621A3617D5067ABA8F9DC8947054B76F30035E3D"
Copy-Item $make "$Tools\bin\make.exe"
$pkgconf = Download "https://dev-www.libreoffice.org/extern/pkgconf-2.4.3.exe" "791CD6DBC56F7268FBF9C4652D6634B0F5C59687AB4E504565E58245952EDD41"
Copy-Item $pkgconf "$Tools\bin\pkgconf-2.4.3.exe"
$jom = Download "https://download.qt.io/official_releases/jom/jom_1_1_4.zip" "D533C1EF49214229681E90196ED2094691E8C4A0A0BEF0B2C901DEBCB562682B"
if (-not (Test-Path "$Tools\bin\jom.exe")) {
    Expand-Archive -Force $jom "$Tools\downloads\jom"
    Copy-Item "$Tools\downloads\jom\jom.exe" "$Tools\bin\jom.exe"
}
$spp = Download "https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54001_64bit_UCRT/strawberry-perl-5.40.0.1-64bit-portable.zip" "754F3E2A8E473DC68D1540C7802FB166A025F35EF18960C4564A31F8B5933907"
if (-not (Test-Path "$Tools\spp\perl\bin\perl.exe")) {
    Expand-Archive -Force $spp "$Tools\spp"
}
if (-not (Test-Path "$Tools\spp\perl\site\lib\Font\TTF.pm")) {
    $savedPath = $env:Path
    $env:Path = "$Tools\spp\c\bin;$Tools\spp\perl\site\bin;$Tools\spp\perl\bin;$env:Path"
    Native cpanm --notest Font::TTF
    $env:Path = $savedPath
    if (-not (Test-Path "$Tools\spp\perl\site\lib\Font\TTF.pm")) { throw "cpanm Font::TTF failed" }
}

Step "WSL1"
# WSL2 needs nested virtualisation, which most VMs do not offer; configure only needs WSL1.
# The wsl.exe that comes with Windows is a stub that can only install this package.
WingetInstall Microsoft.WSL
if ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State -ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart | Out-Null
    $rebootNeeded = $true
}

Step "Git settings, long paths$(if (-not $NoDefenderExclusion) { ', Defender exclusions' })"
$git = "$env:ProgramFiles\Git\cmd\git.exe"
Native $git config --global core.autocrlf false
Native $git config --global core.longpaths true
Native $git config --global protocol.version 2
Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem LongPathsEnabled 1 -Type DWord
if (-not $NoDefenderExclusion) {
    # real-time scanning of every file the build writes slows it down considerably
    New-Item -ItemType Directory -Force $Workspace | Out-Null
    Add-MpPreference -ExclusionPath $Workspace, $Tools
}

if ($rebootNeeded) {
    Write-Host "`nReboot, then run this script again to finish (WSL distribution)." -ForegroundColor Yellow
    exit 0
}

Step "Ubuntu 24.04 in WSL1"
# wsl.exe writes UTF-16
$distros = (Native wsl.exe --list --quiet) -replace "`0", "" | Where-Object { $_ }
if ($distros -notcontains "Ubuntu-24.04") {
    # Imported from Ubuntu's image: wsl --install wants WSL2's virtual machine platform, and
    # without it reports success having installed nothing.
    $image = @{
        arm64 = @("arm64", "E113B8C49AF3AB49B992B8E29550FC921E689F211ABC338176F8243786173A32")
        x64 = @("amd64", "2A790896740B14D637DBDC583CCE1BA081AC53B9E9CDB46DC09A2F73ABBD9934")
    }[$arch]
    $rootfs = Download "https://cloud-images.ubuntu.com/wsl/releases/24.04/20240423/ubuntu-noble-wsl-$($image[0])-24.04lts.rootfs.tar.gz" $image[1]
    New-Item -ItemType Directory -Force "$Tools\wsl\Ubuntu-24.04" | Out-Null
    Native wsl.exe --import Ubuntu-24.04 "$Tools\wsl\Ubuntu-24.04" $rootfs --version 1
    if ($LASTEXITCODE -ne 0) { throw "importing Ubuntu-24.04 failed" }
}
$aptPackages = "autoconf automake bison flex gperf make nasm pkg-config zip libfont-ttf-perl"
Native wsl.exe -d Ubuntu-24.04 -u root -- sh -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -q && apt-get install -y -q $aptPackages"
if ($LASTEXITCODE -ne 0) { throw "apt-get in Ubuntu-24.04 failed" }
# configure runs as a regular user, not as root, which an imported distribution defaults to
Native wsl.exe -d Ubuntu-24.04 -u root -- sh -c "id lo >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo lo; printf '[user]\ndefault=lo\n' > /etc/wsl.conf; echo 'lo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/lo"
if ($LASTEXITCODE -ne 0) { throw "creating the WSL user failed" }
Native wsl.exe --terminate Ubuntu-24.04 | Out-Null

Write-Host "`nDone. Tools are in $Tools; build from Git Bash with scripts/build-windows.sh." -ForegroundColor Green
