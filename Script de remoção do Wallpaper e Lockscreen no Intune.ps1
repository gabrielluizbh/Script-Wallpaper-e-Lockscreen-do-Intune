# Script de remoção do Wallpaper e Lockscreen no Intune - Créditos: Gabriel Luiz - www.gabrielluiz.com


param(
    [switch]$PurgeLogs
)

$ErrorActionPreference = "Stop"

# ===== Variáveis (devem refletir o instalador) =====
$PackageName        = "Wallpaper"
$Version            = "1.0"

$WallpaperLocalIMG  = "C:\Windows\System32\Desktop.jpg"
$LockscreenLocalIMG = "C:\Windows\System32\Lockscreen.jpg"

$LogFolder          = "C:\WallpaperLog"
$ScriptLog          = Join-Path $LogFolder "WallpaperScript-Uninstall.log"
$IntuneLog          = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\$PackageName-uninstall.log"

$ValidationFile     = "C:\ProgramData\scloud\Validation\$PackageName"

# Chaves CSP
$RegKeyCSP          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$DesktopPath        = "DesktopImagePath"
$DesktopStatus      = "DesktopImageStatus"
$DesktopUrl         = "DesktopImageUrl"
$LockScreenPath     = "LockScreenImagePath"
$LockScreenStatus   = "LockScreenImageStatus"
$LockScreenUrl      = "LockScreenImageUrl"

# Chave Spotlight (por usuário)
$SpotlightRelPath   = "Software\Policies\Microsoft\Windows\CloudContent"
$SpotlightValueName = "DisableWindowsSpotlightFeatures"

# ===== Logging =====
if (-not (Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}
Start-Transcript -Path $IntuneLog -Force
function Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $ScriptLog -Value "$ts - $Message"
    Write-Host $Message
}
Log "==== Início do script de remoção em $(Get-Date) ===="

# ===== Funções utilitárias =====
function Remove-RegistryValueIfExists {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )
    try {
        if (Test-Path $Path) {
            $props = (Get-ItemProperty -Path $Path -ErrorAction Stop) | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            if ($props -contains $Name) {
                Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
                Log "Removido valor '$Name' de '$Path'."
            }
        }
    } catch {
        Log "Aviso: não foi possível remover $Name de $Path. $_"
    }
}

function Try-DeleteFile {
    param([Parameter(Mandatory)][string]$Path)
    try {
        if (Test-Path $Path) {
            try { (Get-Item $Path).Attributes = 'Normal' } catch {}
            Remove-Item -Path $Path -Force -ErrorAction Stop
            Log "Arquivo removido: $Path"
        } else {
            Log "Arquivo não encontrado (ok): $Path"
        }
    } catch {
        Log "Aviso: falha ao remover arquivo $Path. $_"
    }
}

# ===== 1) Reativar Windows Spotlight (HKCU por usuário carregado) =====
try {
    Log "Reativando Windows Spotlight para usuários carregados (hives em HKEY_USERS)..."
    $loadedSids = Get-ChildItem Registry::HKEY_USERS | Where-Object {
        $_.Name -notmatch "\\.DEFAULT$" -and $_.Name -notmatch "_Classes$"
    }

    foreach ($sidKey in $loadedSids) {
        $cloudContentKey = "Registry::${($sidKey.Name)}\$SpotlightRelPath"
        try {
            if (Test-Path $cloudContentKey) {
                try {
                    $props = (Get-ItemProperty -Path $cloudContentKey -ErrorAction SilentlyContinue)
                    if ($null -ne $props) {
                        if (($props.PSObject.Properties.Name) -contains $SpotlightValueName) {
                            Set-ItemProperty -Path $cloudContentKey -Name $SpotlightValueName -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            Remove-ItemProperty -Path $cloudContentKey -Name $SpotlightValueName -Force -ErrorAction SilentlyContinue
                            Log "Spotlight reativado para hive $($sidKey.PSChildName) (valor removido)."
                        } else {
                            Log "Nenhum valor de desativação do Spotlight encontrado para hive $($sidKey.PSChildName)."
                        }
                    }
                } catch {
                    # <<< Linha corrigida: evita $variavel: que quebra o parser >>>
                    Log ("Aviso ao tratar Spotlight em {0}: {1}" -f $cloudContentKey, $_)
                }
                try {
                    $subProps = (Get-Item $cloudContentKey -ErrorAction SilentlyContinue).Property
                    if (-not $subProps -or $subProps.Count -eq 0) {
                        Remove-Item -Path $cloudContentKey -Force -ErrorAction SilentlyContinue
                        Log "Chave CloudContent vazia removida: $cloudContentKey"
                    }
                } catch {}
            } else {
                Log "Chave CloudContent não existe para hive $($sidKey.PSChildName) (ok)."
            }
        } catch {
            Log ("Aviso: falha ao processar Spotlight para hive {0}. {1}" -f $sidKey.PSChildName, $_)
        }
    }
} catch {
    Log "Erro geral ao reativar Spotlight: $_"
}

# ===== 2) Remover configurações do PersonalizationCSP (HKLM) =====
try {
    if (Test-Path $RegKeyCSP) {
        Log "Removendo valores do PersonalizationCSP em $RegKeyCSP..."
        Remove-RegistryValueIfExists -Path $RegKeyCSP -Name $DesktopStatus
        Remove-RegistryValueIfExists -Path $RegKeyCSP -Name $DesktopPath
        Remove-RegistryValueIfExists -Path $RegKeyCSP -Name $DesktopUrl
        Remove-RegistryValueIfExists -Path $RegKeyCSP -Name $LockScreenStatus
        Remove-RegistryValueIfExists -Path $RegKeyCSP -Name $LockScreenPath
        Remove-RegistryValueIfExists -Path $RegKeyCSP -Name $LockScreenUrl

        try {
            $remaining = (Get-ItemProperty -Path $RegKeyCSP -ErrorAction SilentlyContinue) `
                | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            if (-not $remaining -or $remaining.Count -eq 0) {
                Remove-Item -Path $RegKeyCSP -Recurse -Force -ErrorAction SilentlyContinue
                Log "Chave PersonalizationCSP removida (sem valores restantes)."
            } else {
                Log "Chave PersonalizationCSP mantida (ainda há outros valores definidos por terceiros)."
            }
        } catch {
            Log "Aviso ao tentar remover a chave PersonalizationCSP: $_"
        }
    } else {
        Log "Chave PersonalizationCSP não existe (ok)."
    }
} catch {
    Log "Erro ao limpar PersonalizationCSP: $_"
}

# ===== 3) Excluir imagens locais =====
Try-DeleteFile -Path $WallpaperLocalIMG
Try-DeleteFile -Path $LockscreenLocalIMG

# ===== 4) Remover arquivo de validação =====
try {
    if (Test-Path $ValidationFile) {
        Remove-Item -Path $ValidationFile -Force -ErrorAction Stop
        Log "Arquivo de validação removido: $ValidationFile"
        $parent = Split-Path $ValidationFile -Parent
        try {
            if (Test-Path $parent) {
                $items = Get-ChildItem -Path $parent -Force
                if ($items.Count -eq 0) {
                    Remove-Item -Path $parent -Force -ErrorAction SilentlyContinue
                    Log "Pasta de validação removida (vazia): $parent"
                }
            }
        } catch {}
    } else {
        Log "Arquivo de validação não encontrado (ok): $ValidationFile"
    }
} catch {
    Log "Aviso ao remover validação: $_"
}

# ===== 5) Opcional: limpar logs =====
if ($PurgeLogs) {
    try {
        if (Test-Path $LogFolder) {
            Remove-Item -Path $LogFolder -Recurse -Force -ErrorAction Stop
            Log "Pasta de logs removida: $LogFolder"
        } else {
            Log "Pasta de logs não encontrada (ok)."
        }
    } catch {
        Log "Aviso: falha ao remover logs. $_"
    }
} else {
    Log "Pasta de logs preservada: $LogFolder (use -PurgeLogs para excluir)."
}

Log "==== Fim do script de remoção em $(Get-Date) ===="
try { Stop-Transcript | Out-Null } catch {}
exit 0