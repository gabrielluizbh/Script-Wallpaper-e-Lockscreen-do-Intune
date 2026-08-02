# Script de remoção do Wallpaper e Lockscreen no Intune
# Remove tudo que é criado pelo script:
# "Script Wallpaper e Lockscreen no Intune-v2.ps1"
# Créditos: Gabriel Luiz - www.gabrielluiz.com

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

# =========================================================
# VARIÁVEIS
# =========================================================
$TaskName = "Valida o Wallpaper and Lockscreen"

$WallpaperLocalIMG  = "C:\Windows\System32\Desktop.png"
$LockscreenLocalIMG = "C:\Windows\System32\Lockscreen.png"

$BaseFolder       = "C:\ProgramData\WallpaperCorp"
$ValidationFile   = "C:\ProgramData\scloud\Validation\Wallpaper"
$ValidationFolder = "C:\ProgramData\scloud\Validation"
$ScloudFolder     = "C:\ProgramData\scloud"

$IntuneLogFolder = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$IntuneLog       = Join-Path $IntuneLogFolder "Wallpaper-install.log"

$PersonalizationCSP = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$SpotlightReg       = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"

$RestartDelaySeconds = 600
$RestartMessage = "A remoção do Script Wallpaper e Lockscreen foi concluída. Este computador será reiniciado em 10 minutos. Salve todo o seu trabalho antes da reinicialização."

# =========================================================
# FUNÇÕES
# =========================================================
function Write-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "SUCESSO", "AVISO", "ERRO")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "$timestamp [$Level] $Message"
}

function Remove-FileSafely {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            Write-Status "Arquivo removido: $Path" "SUCESSO"
        }
        else {
            Write-Status "Arquivo não encontrado; nenhuma ação necessária: $Path"
        }
    }
    catch {
        Write-Status "Não foi possível remover o arquivo $Path. $($_.Exception.Message)" "ERRO"
    }
}

function Remove-FolderSafely {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Status "Pasta removida: $Path" "SUCESSO"
        }
        else {
            Write-Status "Pasta não encontrada; nenhuma ação necessária: $Path"
        }
    }
    catch {
        Write-Status "Não foi possível remover a pasta $Path. $($_.Exception.Message)" "ERRO"
    }
}

function Remove-EmptyFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (Test-Path -LiteralPath $Path) {
            $remainingItems = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop

            if ($null -eq $remainingItems -or @($remainingItems).Count -eq 0) {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
                Write-Status "Pasta vazia removida: $Path" "SUCESSO"
            }
            else {
                Write-Status "A pasta não foi removida porque contém outros arquivos: $Path" "AVISO"
            }
        }
    }
    catch {
        Write-Status "Não foi possível verificar ou remover a pasta $Path. $($_.Exception.Message)" "ERRO"
    }
}

function Remove-RegistryValueSafely {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        if (Test-Path -LiteralPath $Path) {
            $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue

            if ($null -ne $property) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
                Write-Status "Propriedade de registro removida: $Path\$Name" "SUCESSO"
            }
            else {
                Write-Status "Propriedade de registro não encontrada: $Path\$Name"
            }
        }
        else {
            Write-Status "Chave de registro não encontrada: $Path"
        }
    }
    catch {
        Write-Status "Não foi possível remover $Path\$Name. $($_.Exception.Message)" "ERRO"
    }
}

function Remove-RegistryKeyIfEmpty {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }

        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $customValues = @($key.GetValueNames())
        $subKeys = @($key.GetSubKeyNames())

        if ($customValues.Count -eq 0 -and $subKeys.Count -eq 0) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            Write-Status "Chave de registro vazia removida: $Path" "SUCESSO"
        }
        else {
            Write-Status "A chave foi mantida porque contém outras configurações: $Path" "AVISO"
        }
    }
    catch {
        Write-Status "Não foi possível verificar ou remover a chave $Path. $($_.Exception.Message)" "ERRO"
    }
}

function Remove-WallpaperScheduledTask {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

        if ($null -ne $task) {
            try {
                Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            }
            catch {
                # A tarefa pode não estar em execução.
            }

            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Status "Tarefa agendada removida: $TaskName" "SUCESSO"
        }
        else {
            Write-Status "Tarefa agendada não encontrada: $TaskName"
        }
    }
    catch {
        Write-Status "Não foi possível remover a tarefa agendada $TaskName. $($_.Exception.Message)" "ERRO"
    }
}

function Remove-IntuneWallpaperLogs {
    try {
        if (-not (Test-Path -LiteralPath $IntuneLogFolder)) {
            Write-Status "Pasta de logs do Intune não encontrada."
            return
        }

        $logFiles = Get-ChildItem -LiteralPath $IntuneLogFolder -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "Wallpaper-install.log" -or
                $_.Name -like "Wallpaper-install_*.log"
            }

        foreach ($logFile in $logFiles) {
            try {
                Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop
                Write-Status "Log do Intune removido: $($logFile.FullName)" "SUCESSO"
            }
            catch {
                Write-Status "Não foi possível remover o log $($logFile.FullName). $($_.Exception.Message)" "ERRO"
            }
        }

        if (@($logFiles).Count -eq 0) {
            Write-Status "Nenhum log Wallpaper-install foi encontrado no diretório do Intune."
        }
    }
    catch {
        Write-Status "Erro durante a remoção dos logs do Intune. $($_.Exception.Message)" "ERRO"
    }
}

function Show-RestartNotification {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        $msgExe = Join-Path $env:SystemRoot "System32\msg.exe"

        if (Test-Path -LiteralPath $msgExe) {
            & $msgExe * /TIME:600 $Message 2>$null
            Write-Status "Mensagem de reinicialização enviada aos usuários conectados." "SUCESSO"
        }
        else {
            Write-Status "O utilitário msg.exe não foi encontrado." "AVISO"
        }
    }
    catch {
        Write-Status "Não foi possível exibir a mensagem para os usuários. $($_.Exception.Message)" "AVISO"
    }
}

function Schedule-Restart {
    param(
        [Parameter(Mandatory = $true)]
        [int]$DelaySeconds,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        # Cancela apenas uma reinicialização anteriormente programada para evitar duplicidade.
        & "$env:SystemRoot\System32\shutdown.exe" /a 2>$null | Out-Null

        # Agenda a reinicialização sem o parâmetro /c. O parâmetro /c gera um segundo aviso do Windows.
        # O único aviso exibido ao usuário será o enviado pela função Show-RestartNotification.
        & "$env:SystemRoot\System32\shutdown.exe" /r /t $DelaySeconds | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Status "Reinicialização agendada para daqui a 10 minutos." "SUCESSO"
        }
        else {
            Write-Status "O comando de reinicialização retornou o código $LASTEXITCODE." "ERRO"
        }
    }
    catch {
        Write-Status "Não foi possível agendar a reinicialização. $($_.Exception.Message)" "ERRO"
    }
}

# =========================================================
# EXECUÇÃO
# =========================================================
Write-Status "=================================================="
Write-Status "Iniciando a remoção do Script Wallpaper e Lockscreen"
Write-Status "Executando como: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Status "=================================================="

# 1. Impede novas execuções do instalador.
Remove-WallpaperScheduledTask

# 2. Remove as configurações criadas no PersonalizationCSP.
$personalizationValues = @(
    "DesktopImagePath",
    "DesktopImageStatus",
    "DesktopImageUrl",
    "LockScreenImagePath",
    "LockScreenImageStatus",
    "LockScreenImageUrl"
)

foreach ($valueName in $personalizationValues) {
    Remove-RegistryValueSafely -Path $PersonalizationCSP -Name $valueName
}

Remove-RegistryKeyIfEmpty -Path $PersonalizationCSP

# 3. Remove a política de Spotlight criada pelo instalador.
Remove-RegistryValueSafely -Path $SpotlightReg -Name "DisableWindowsSpotlightFeatures"
Remove-RegistryKeyIfEmpty -Path $SpotlightReg

# 4. Remove as imagens copiadas para o System32.
Remove-FileSafely -Path $WallpaperLocalIMG
Remove-FileSafely -Path $LockscreenLocalIMG

# 5. Remove o arquivo usado pela regra de detecção do aplicativo.
Remove-FileSafely -Path $ValidationFile
Remove-EmptyFolder -Path $ValidationFolder
Remove-EmptyFolder -Path $ScloudFolder

# 6. Remove script local, hashes, temporários e logs armazenados no WallpaperCorp.
Remove-FolderSafely -Path $BaseFolder

# 7. Remove o transcript e os arquivos arquivados criados no diretório de logs do Intune.
Remove-IntuneWallpaperLogs

Write-Status "=================================================="
Write-Status "Processo de remoção finalizado."
Write-Status "O computador será reiniciado em 10 minutos."
Write-Status "=================================================="

# Exibe apenas o aviso clássico (msg.exe) e agenda a reinicialização sem aviso adicional.
Show-RestartNotification -Message $RestartMessage
Schedule-Restart -DelaySeconds $RestartDelaySeconds -Message $RestartMessage

exit 0
