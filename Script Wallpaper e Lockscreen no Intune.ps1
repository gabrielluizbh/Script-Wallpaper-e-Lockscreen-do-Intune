# Script Wallpaper e Lockscreen no Intune - Créditos Gabriel Luiz - www.gabrielluiz.com


$PackageName = "Wallpaper"
$Version = "1.0"
$ErrorActionPreference = "Stop"

# Caminhos
$WallpaperUri   = "https://testeintuneimagens.blob.core.windows.net/teste/Imagens/wallpaper.jpg"
$LockscreenUri  = "https://testeintuneimagens.blob.core.windows.net/teste/Imagens/lockscreen.jpg"
$WallpaperLocalIMG  = "C:\Windows\System32\Desktop.jpg"
$LockscreenLocalIMG = "C:\Windows\System32\Lockscreen.jpg"
$LogFolder = "C:\WallpaperLog"
$ScriptLog = "$LogFolder\WallpaperScript.log"
$IntuneLog = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$PackageName-install.log"

# Criar pasta de log
if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

# Iniciar logs
Start-Transcript -Path $IntuneLog -Force
Add-Content -Path $ScriptLog -Value "==== Início do script Wallpaper em $(Get-Date) ===="

Function Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $ScriptLog -Value "$timestamp - $message"
    Write-Host $message
}

Log "Iniciando aplicação de imagens de wallpaper e lockscreen via CSP..."

# ========================================
# Desativa Spotlight (recomendado para lockscreen)
# ========================================
try {
    $spotlightReg = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $spotlightReg)) {
        New-Item -Path $spotlightReg -Force | Out-Null
        Log "Chave de registro do Spotlight criada."
    }
    Set-ItemProperty -Path $spotlightReg -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord -Force
    Log "Spotlight desativado com sucesso."
} catch {
    Log "Erro ao desativar Spotlight: $_"
}

# ========================================
# Função de download e validação
# ========================================
function Download-Image {
    param (
        [string]$Url,
        [string]$Destination
    )
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        if ((Get-Item $Destination).Length -lt 10000) {
            throw "Imagem inválida ou corrompida: $Destination"
        }
        Log "Imagem baixada com sucesso: $Destination"
    } catch {
        Log "Erro ao baixar imagem ${Url}: $_"
        throw
    }
}

Download-Image -Url $WallpaperUri -Destination $WallpaperLocalIMG
Download-Image -Url $LockscreenUri -Destination $LockscreenLocalIMG

# ========================================
# Aplicar via Personalization CSP
# ========================================
$RegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$DesktopPath = "DesktopImagePath"
$DesktopStatus = "DesktopImageStatus"
$DesktopUrl = "DesktopImageUrl"
$LockScreenPath = "LockScreenImagePath"
$LockScreenStatus = "LockScreenImageStatus"
$LockScreenUrl = "LockScreenImageUrl"
$StatusValue = 1

if (!(Test-Path $RegKeyPath)) {
    New-Item -Path $RegKeyPath -Force | Out-Null
    Log "Chave PersonalizationCSP criada."
}

# Tela de bloqueio
Set-ItemProperty -Path $RegKeyPath -Name $LockScreenStatus -Value $StatusValue -Type DWord -Force
Set-ItemProperty -Path $RegKeyPath -Name $LockScreenPath -Value $LockscreenLocalIMG -Type String -Force
Set-ItemProperty -Path $RegKeyPath -Name $LockScreenUrl -Value $LockscreenLocalIMG -Type String -Force
Log "Tela de bloqueio configurada via CSP."

# Papel de parede
Set-ItemProperty -Path $RegKeyPath -Name $DesktopStatus -Value $StatusValue -Type DWord -Force
Set-ItemProperty -Path $RegKeyPath -Name $DesktopPath -Value $WallpaperLocalIMG -Type String -Force
Set-ItemProperty -Path $RegKeyPath -Name $DesktopUrl -Value $WallpaperLocalIMG -Type String -Force
Log "Wallpaper configurado via CSP."

# ========================================
# Registro da instalação
# ========================================
$ValidationFile = "C:\ProgramData\scloud\Validation\$PackageName"
New-Item -Path $ValidationFile -ItemType File -Force -Value $Version | Out-Null
Log "Validação de instalação registrada em: $ValidationFile"

Log "==== Fim do script Wallpaper em $(Get-Date) ===="

Stop-Transcript
