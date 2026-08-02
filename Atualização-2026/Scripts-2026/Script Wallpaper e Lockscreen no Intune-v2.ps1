# Script Wallpaper e Lockscreen no Intune
# Créditos: Gabriel Luiz - www.gabrielluiz.com
# Validação SHA256, atualização automática, rotação de logs e tarefa agendada

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# =========================================================
# VARIÁVEIS
# =========================================================
$PackageName = "Wallpaper"
$Version = "1.2"

$WallpaperUri  = "https://vhdxgabrielluiz.blob.core.windows.net/vhdx/wallpaper-gabrielluiz.png"
$LockscreenUri = "https://vhdxgabrielluiz.blob.core.windows.net/vhdx/lock-screen-gabrielluiz.png"

$WallpaperLocalIMG  = "C:\Windows\System32\Desktop.png"
$LockscreenLocalIMG = "C:\Windows\System32\Lockscreen.png"

$BaseFolder       = "C:\ProgramData\WallpaperCorp"
$TempFolder       = Join-Path $BaseFolder "Temp"
$LogFolder        = Join-Path $BaseFolder "Logs"
$MetadataFolder   = Join-Path $BaseFolder "Metadata"
$ScriptsFolder    = Join-Path $BaseFolder "Scripts"

$ScriptLog = Join-Path $LogFolder "WallpaperScript.log"
$IntuneLog = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\Wallpaper-install.log"

$MaxLogSizeMB     = 5
$LogRetentionDays = 30

$ValidationFolder = "C:\ProgramData\scloud\Validation"
$ValidationFile   = Join-Path $ValidationFolder $PackageName

$WallpaperHashFile  = Join-Path $MetadataFolder "wallpaper.sha256"
$LockscreenHashFile = Join-Path $MetadataFolder "lockscreen.sha256"

$TaskName = "Valida o Wallpaper and Lockscreen"
$CurrentScriptDestination = Join-Path $ScriptsFolder "Set-WallpaperAndLockscreen.ps1"

$TranscriptStarted = $false

# =========================================================
# FUNÇÕES
# =========================================================
function Initialize-Folders {
    $folders = @(
        $BaseFolder,
        $TempFolder,
        $LogFolder,
        $MetadataFolder,
        $ScriptsFolder,
        $ValidationFolder,
        (Split-Path -Path $IntuneLog -Parent)
    )

    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
    }
}

function Initialize-Utf8Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    try {
        $logDirectory = Split-Path -Path $LogPath -Parent
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        $utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)
        $createNewLog = $false

        if (Test-Path -LiteralPath $LogPath) {
            $bytes = [System.IO.File]::ReadAllBytes($LogPath)
            $hasUtf8Bom = (
                $bytes.Length -ge 3 -and
                $bytes[0] -eq $utf8Bom[0] -and
                $bytes[1] -eq $utf8Bom[1] -and
                $bytes[2] -eq $utf8Bom[2]
            )

            if (-not $hasUtf8Bom) {
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $backupPath = Join-Path $logDirectory "WallpaperScript_EncodingBackup_$timestamp.log"
                Move-Item -LiteralPath $LogPath -Destination $backupPath -Force
                $createNewLog = $true
            }
        }
        else {
            $createNewLog = $true
        }

        if ($createNewLog) {
            [System.IO.File]::WriteAllBytes($LogPath, $utf8Bom)
        }
    }
    catch {
        Write-Host "Não foi possível preparar o log UTF-8: $($_.Exception.Message)"
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp [$Level] $Message"

    try {
        $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::AppendAllText(
            $ScriptLog,
            $line + [Environment]::NewLine,
            $utf8WithBom
        )
    }
    catch {
        Write-Host "Não foi possível gravar no log principal: $($_.Exception.Message)"
    }

    Write-Host $line
}

function Invoke-LogMaintenance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [int]$MaxSizeMB = 5,
        [int]$RetentionDays = 30
    )

    try {
        $logDirectory = Split-Path -Path $LogPath -Parent
        $logBaseName  = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
        $logExtension = [System.IO.Path]::GetExtension($LogPath)
        $cutoffDate   = (Get-Date).AddDays(-$RetentionDays)

        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        if (Test-Path -LiteralPath $LogPath) {
            $logFile = Get-Item -LiteralPath $LogPath -ErrorAction Stop
            $isOversized = $logFile.Length -ge ($MaxSizeMB * 1MB)
            $isOld       = $logFile.LastWriteTime -le $cutoffDate

            if ($isOversized -or $isOld) {
                $timestamp   = Get-Date -Format "yyyyMMdd-HHmmss"
                $archiveName = "{0}_{1}{2}" -f $logBaseName, $timestamp, $logExtension
                $archivePath = Join-Path $logDirectory $archiveName

                Move-Item -LiteralPath $LogPath -Destination $archivePath -Force
            }
        }

        Get-ChildItem -LiteralPath $logDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.BaseName -like "$logBaseName`_*" -and
                $_.Extension -eq $logExtension -and
                $_.LastWriteTime -le $cutoffDate
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "Falha na manutenção do log '$LogPath': $($_.Exception.Message)"
    }
}

function Start-ScriptTranscript {
    try {
        Start-Transcript -Path $IntuneLog -Append -Force | Out-Null
        $script:TranscriptStarted = $true
    }
    catch {
        Write-Log -Message "Falha ao iniciar transcript: $($_.Exception.Message)" -Level "WARN"
    }
}

function Stop-ScriptTranscript {
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }
}

function Get-FileSHA256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    }
    catch {
        Write-Log -Message "Erro ao calcular o hash de '$Path': $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

function Download-FileWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [int]$Retries = 3
    )

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Destination) {
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            }

            Write-Log -Message "Tentativa $attempt de download: $Url"

            Invoke-WebRequest `
                -Uri $Url `
                -OutFile $Destination `
                -UseBasicParsing `
                -TimeoutSec 120 `
                -Headers @{ "Cache-Control" = "no-cache" }

            if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
                throw "O arquivo não foi criado após o download."
            }

            $downloadedFile = Get-Item -LiteralPath $Destination
            if ($downloadedFile.Length -lt 10000) {
                throw "O arquivo baixado possui somente $($downloadedFile.Length) bytes."
            }

            $downloadedHash = Get-FileSHA256 -Path $Destination
            if ([string]::IsNullOrWhiteSpace($downloadedHash)) {
                throw "Não foi possível calcular o hash do arquivo baixado."
            }

            Write-Log -Message "Download concluído com sucesso: $Destination"
            return
        }
        catch {
            Write-Log -Message "Falha na tentativa $attempt de download de '$Url': $($_.Exception.Message)" -Level "WARN"

            if ($attempt -lt $Retries) {
                Start-Sleep -Seconds 5
            }
        }
    }

    throw "Falha ao baixar '$Url' após $Retries tentativas."
}

function Sync-ImageIfChanged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $true)]
        [string]$HashFilePath
    )

    $tempFile = Join-Path $TempFolder "$Name.download"

    try {
        Download-FileWithRetry -Url $Url -Destination $tempFile

        $remoteHash = Get-FileSHA256 -Path $tempFile
        $localHash  = Get-FileSHA256 -Path $DestinationPath

        Write-Log -Message "$Name - Hash baixado: $remoteHash"
        Write-Log -Message "$Name - Hash local: $localHash"

        $changed = [string]::IsNullOrWhiteSpace($localHash) -or ($remoteHash -ne $localHash)

        if ($changed) {
            Copy-Item -LiteralPath $tempFile -Destination $DestinationPath -Force

            $copiedHash = Get-FileSHA256 -Path $DestinationPath
            if ($copiedHash -ne $remoteHash) {
                throw "O hash do arquivo copiado não corresponde ao hash baixado."
            }

            Set-Content -LiteralPath $HashFilePath -Value $copiedHash -Encoding ASCII -Force
            Write-Log -Message "$Name atualizado com sucesso."
        }
        else {
            Set-Content -LiteralPath $HashFilePath -Value $remoteHash -Encoding ASCII -Force
            Write-Log -Message "$Name já está atualizado. Nenhuma substituição foi necessária."
        }

        return [PSCustomObject]@{
            Name       = $Name
            Changed    = $changed
            LocalHash  = Get-FileSHA256 -Path $DestinationPath
            RemoteHash = $remoteHash
        }
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Disable-SpotlightPolicy {
    $spotlightReg = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"

    try {
        if (-not (Test-Path -LiteralPath $spotlightReg)) {
            New-Item -Path $spotlightReg -Force | Out-Null
        }

        New-ItemProperty `
            -Path $spotlightReg `
            -Name "DisableWindowsSpotlightFeatures" `
            -PropertyType DWord `
            -Value 1 `
            -Force | Out-Null

        Write-Log -Message "Windows Spotlight desativado via política do computador."
    }
    catch {
        Write-Log -Message "Não foi possível desativar o Windows Spotlight: $($_.Exception.Message)" -Level "WARN"
    }
}

function Apply-PersonalizationCSP {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WallpaperPath,

        [Parameter(Mandatory = $true)]
        [string]$LockscreenPath
    )

    $regKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

    if (-not (Test-Path -LiteralPath $regKeyPath)) {
        New-Item -Path $regKeyPath -Force | Out-Null
    }

    $properties = @{
        LockScreenImageStatus = 1
        LockScreenImagePath   = $LockscreenPath
        LockScreenImageUrl    = $LockscreenPath
        DesktopImageStatus    = 1
        DesktopImagePath      = $WallpaperPath
        DesktopImageUrl       = $WallpaperPath
    }

    foreach ($property in $properties.GetEnumerator()) {
        $propertyType = if ($property.Key -like "*Status") { "DWord" } else { "String" }

        New-ItemProperty `
            -Path $regKeyPath `
            -Name $property.Key `
            -PropertyType $propertyType `
            -Value $property.Value `
            -Force | Out-Null
    }

    Write-Log -Message "Wallpaper e tela de bloqueio configurados no PersonalizationCSP."
}

function Register-Validation {
    Set-Content -LiteralPath $ValidationFile -Value $Version -Encoding ASCII -Force
    Write-Log -Message "Arquivo de validação atualizado: $ValidationFile"
}

function Save-ScriptForScheduledTask {
    $currentPath = $PSCommandPath

    if ([string]::IsNullOrWhiteSpace($currentPath) -or -not (Test-Path -LiteralPath $currentPath)) {
        throw "Não foi possível identificar o caminho do script em execução."
    }

    $sourceFullPath      = [System.IO.Path]::GetFullPath($currentPath)
    $destinationFullPath = [System.IO.Path]::GetFullPath($CurrentScriptDestination)

    # Quando o script já é executado pela tarefa, origem e destino são iguais.
    if ($sourceFullPath.Equals($destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Log -Message "O script já está no caminho usado pela tarefa agendada."
        return
    }

    Copy-Item -LiteralPath $currentPath -Destination $CurrentScriptDestination -Force
    Write-Log -Message "Cópia do script atualizada em: $CurrentScriptDestination"
}

function Test-ScheduledTaskConfiguration {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop

        $expectedArgument = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$CurrentScriptDestination`""
        $actionMatches = $task.Actions.Count -eq 1 -and
            $task.Actions[0].Execute -ieq "powershell.exe" -and
            $task.Actions[0].Arguments -eq $expectedArgument

        $expectedTimes = @("08:00", "12:00", "16:00")
        $dailyTimes = @(
            $task.Triggers |
                Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" } |
                ForEach-Object { ([datetime]$_.StartBoundary).ToString("HH:mm") }
        )

        $hasStartup = @($task.Triggers | Where-Object {
            $_.CimClass.CimClassName -eq "MSFT_TaskBootTrigger"
        }).Count -ge 1

        $timesMatch = @($expectedTimes | Where-Object { $_ -notin $dailyTimes }).Count -eq 0

        return $actionMatches -and $hasStartup -and $timesMatch
    }
    catch {
        return $false
    }
}

function Ensure-ScheduledTask {
    Save-ScriptForScheduledTask

    if (Test-ScheduledTaskConfiguration) {
        Write-Log -Message "A tarefa agendada já está configurada corretamente."
        return
    }

    $taskActionArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$CurrentScriptDestination`""
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskActionArguments

    $triggers = @(
        (New-ScheduledTaskTrigger -AtStartup),
        (New-ScheduledTaskTrigger -Daily -At "08:00"),
        (New-ScheduledTaskTrigger -Daily -At "12:00"),
        (New-ScheduledTaskTrigger -Daily -At "16:00")
    )

    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $triggers `
        -Principal $principal `
        -Settings $settings `
        -Description "Valida os hashes e atualiza o wallpaper e a tela de bloqueio quando houver alteração." `
        -Force | Out-Null

    Write-Log -Message "Tarefa agendada criada ou corrigida: inicialização, 08:00, 12:00 e 16:00."
}

# =========================================================
# EXECUÇÃO
# =========================================================
$exitCode = 0

try {
    Initialize-Folders

    Invoke-LogMaintenance -LogPath $ScriptLog -MaxSizeMB $MaxLogSizeMB -RetentionDays $LogRetentionDays
    Invoke-LogMaintenance -LogPath $IntuneLog -MaxSizeMB $MaxLogSizeMB -RetentionDays $LogRetentionDays

    # Garante que o log seja reconhecido corretamente como UTF-8 pelo Bloco de Notas.
    Initialize-Utf8Log -LogPath $ScriptLog

    Start-ScriptTranscript

    Write-Log -Message "=================================================="
    Write-Log -Message "Início do script Wallpaper/Lockscreen - Versão $Version"
    Write-Log -Message "Executando como: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log -Message "=================================================="

    Disable-SpotlightPolicy

    $wallpaperResult = Sync-ImageIfChanged `
        -Name "Wallpaper" `
        -Url $WallpaperUri `
        -DestinationPath $WallpaperLocalIMG `
        -HashFilePath $WallpaperHashFile

    $lockscreenResult = Sync-ImageIfChanged `
        -Name "Lockscreen" `
        -Url $LockscreenUri `
        -DestinationPath $LockscreenLocalIMG `
        -HashFilePath $LockscreenHashFile

    Apply-PersonalizationCSP `
        -WallpaperPath $WallpaperLocalIMG `
        -LockscreenPath $LockscreenLocalIMG

    Register-Validation
    Ensure-ScheduledTask

    Write-Log -Message "Wallpaper alterado: $($wallpaperResult.Changed)"
    Write-Log -Message "Lockscreen alterado: $($lockscreenResult.Changed)"
    Write-Log -Message "Script finalizado com sucesso."
}
catch {
    $exitCode = 1

    try {
        Write-Log -Message "Erro fatal: $($_.Exception.Message)" -Level "ERROR"
        Write-Log -Message "Linha: $($_.InvocationInfo.ScriptLineNumber)" -Level "ERROR"
        Write-Log -Message "Comando: $($_.InvocationInfo.Line)" -Level "ERROR"
    }
    catch {
        Write-Host "Erro fatal: $($_.Exception.Message)"
    }
}
finally {
    try {
        Write-Log -Message "Fim do processamento em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
    catch {
    }

    Stop-ScriptTranscript
}

exit $exitCode
