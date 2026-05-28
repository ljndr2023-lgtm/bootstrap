#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap - Instalación automática en Windows
    Chrome + Steam + Epic Games + Drivers GPU
.DESCRIPTION
    Descarga e instala Google Chrome, Steam, Heroic Games Launcher (Epic),
    y drivers NVIDIA/AMD según la GPU detectada.
#>

$Host.UI.RawUI.WindowTitle = "Bootstrap - Instalando..."
$ErrorActionPreference = "Stop"

function Write-Log   { Write-Host "[✓] $args" -ForegroundColor Green }
function Write-Warn  { Write-Host "[!] $args" -ForegroundColor Yellow }
function Write-Err   { Write-Host "[✗] $args" -ForegroundColor Red; exit 1 }
function Write-Info  { Write-Host "[i] $args" -ForegroundColor Cyan }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Err "Ejecuta como Administrador (botón derecho > Ejecutar como administrador)"
    }
}

function Install-Choco {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        refreshenv
    }
}

function Install-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# === DRIVERS ===
function Setup-Drivers {
    Write-Info "--- Detectando GPU ---"

    $gpu = (Get-WmiObject Win32_VideoController).Name
    Write-Info "GPU detectada: $gpu"

    if ($gpu -match "NVIDIA") {
        Write-Log "GPU NVIDIA detectada"
        $choice = Read-Host "¿Instalar driver NVIDIA? (s/N)"
        if ($choice -eq "s") {
            if (Install-Winget) {
                winget install -e --id Nvidia.GeForceExperience --accept-package-agreements --accept-source-agreements
            } else {
                Write-Info "Descargando driver NVIDIA..."
                $url = "https://us.download.nvidia.com/Windows/latest/NVIDIA-latest-win.exe"
                Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\nvidia_driver.exe"
                Start-Process -Wait -FilePath "$env:TEMP\nvidia_driver.exe" -ArgumentList "-s -noreboot"
            }
        }
    } elseif ($gpu -match "AMD" -or $gpu -match "Radeon") {
        Write-Log "GPU AMD detectada"
        $choice = Read-Host "¿Abrir página de drivers AMD para descargar? (s/N)"
        if ($choice -eq "s") {
            Start-Process "https://www.amd.com/es/support"
        }
    } elseif ($gpu -match "Intel") {
        Write-Log "GPU Intel detectada"
        Write-Info "Windows Update suele manejar los drivers Intel automáticamente."
    } else {
        Write-Warn "GPU no reconocida. Instala drivers manualmente si es necesario."
    }
}

# === CHROME ===
function Setup-Chrome {
    Write-Info "--- Google Chrome ---"
    if (Test-Path "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") {
        Write-Log "Chrome ya instalado"
        return
    }
    if (Install-Winget) {
        winget install -e --id Google.Chrome --accept-package-agreements --accept-source-agreements
    } else {
        Write-Info "Descargando Chrome..."
        $url = "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe"
        Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\chrome_installer.exe"
        Start-Process -Wait -FilePath "$env:TEMP\chrome_installer.exe" -ArgumentList "/silent /install"
    }
    Write-Log "Chrome instalado"
}

# === STEAM ===
function Setup-Steam {
    Write-Info "--- Steam ---"
    if (Test-Path "$env:ProgramFiles(x86)\Steam\steam.exe") {
        Write-Log "Steam ya instalado"
        return
    }
    if (Install-Winget) {
        winget install -e --id Valve.Steam --accept-package-agreements --accept-source-agreements
    } else {
        Write-Info "Descargando Steam..."
        $url = "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe"
        Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\steam_setup.exe"
        Start-Process -Wait -FilePath "$env:TEMP\steam_setup.exe" -ArgumentList "/S"
    }
    Write-Log "Steam instalado"
}

# === EPIC GAMES ===
function Setup-Epic {
    Write-Info "--- Heroic Games Launcher (Epic Games) ---"
    if (Test-Path "$env:LOCALAPPDATA\Heroic\Heroic.exe") {
        Write-Log "Heroic ya instalado"
        return
    }

    # Intentar con winget
    if (Install-Winget) {
        try {
            winget install -e --id HeroicGamesLauncher.HeroicGamesLauncher --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -eq 0) { Write-Log "Heroic instalado"; return }
        } catch {}
    }

    # Fallback: descargar desde GitHub
    Write-Info "Descargando Heroic Games Launcher..."
    $api = Invoke-RestMethod "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest"
    $asset = $api.assets | Where-Object { $_.name -like "*x64*setup*exe*" } | Select-Object -First 1
    if (-not $asset) {
        Write-Warn "No se encontró Heroic vía winget/GitHub. Instálalo manualmente desde:"
        Write-Warn "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases"
        return
    }
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile "$env:TEMP\heroic_setup.exe"
    Start-Process -Wait -FilePath "$env:TEMP\heroic_setup.exe" -ArgumentList "/S"
    Write-Log "Heroic Games Launcher instalado"
}

# === MAIN ===
function Main {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  BOOTSTRAP WINDOWS" -ForegroundColor Green
    Write-Host "  Chrome + Steam + Epic + Drivers" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    ""

    Test-Admin

    Write-Host "`n¿Qué quieres instalar?" -ForegroundColor Cyan
    Write-Host " [1] Todo (drivers + Chrome + Steam + Epic)"
    Write-Host " [2] Solo programas (Chrome + Steam + Epic)"
    Write-Host " [3] Solo drivers"
    Write-Host " [4] Solo Chrome"
    Write-Host " [5] Solo Steam"
    Write-Host " [6] Solo Epic (Heroic Launcher)"
    $choice = Read-Host "`nElige (1-6)"

    switch ($choice) {
        "1" { Setup-Drivers; Setup-Chrome; Setup-Steam; Setup-Epic }
        "2" { Setup-Chrome; Setup-Steam; Setup-Epic }
        "3" { Setup-Drivers }
        "4" { Setup-Chrome }
        "5" { Setup-Steam }
        "6" { Setup-Epic }
        default { Write-Err "Opción inválida" }
    }

    "`n"
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  LISTO!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Info "Reinicia el PC si instalaste drivers."
    Read-Host "`nPresiona Enter para salir"
}

Main
