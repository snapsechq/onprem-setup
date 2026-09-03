# --- Configuration & Styling ---
$ErrorActionPreference = "Stop"

# --- Constants ---
$INSTALL_FILE = ".installed"
$ENV_FILE = ".env"
$ENV_EXAMPLE = ".env.example"
$COMPOSE_FILE = if ($env:COMPOSE_FILE) { $env:COMPOSE_FILE } else { "docker-compose.yaml" }
$MONGO_KEYFILE = "configs/mongo-keyfile"

# --- Logging Helpers ---
function Print-Banner {
    Write-Host "`n==============================================" -ForegroundColor Purple
    Write-Host "   Snapsec On-Prem Setup Utility (PowerShell) " -ForegroundColor Purple
    Write-Host "==============================================`n" -ForegroundColor Purple
}

function Write-LogInfo($msg) { Write-Host "[INFO] $msg" -ForegroundColor Blue }
function Write-LogSuccess($msg) { Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-LogWarn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-LogError($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-LogStep($msg) { Write-Host "`n➜ $msg" -ForegroundColor Cyan }

function Ensure-MongoKeyfile {
    Write-LogStep "Checking MongoDB keyfile..."
    $keyfileDir = Split-Path -Parent $MONGO_KEYFILE
    if ($keyfileDir -and -not (Test-Path $keyfileDir)) {
        New-Item -ItemType Directory -Path $keyfileDir -Force | Out-Null
    }
    if (-not (Test-Path $MONGO_KEYFILE)) {
        Write-LogInfo "Generating MongoDB keyfile ($MONGO_KEYFILE)..."
        if (Get-Command openssl -ErrorAction SilentlyContinue) {
            openssl rand -base64 756 | Out-File -FilePath $MONGO_KEYFILE -Encoding ascii -NoNewline
        } else {
            $bytes = New-Object byte[] 756
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($bytes)
            $base64 = [Convert]::ToBase64String($bytes)
            [System.IO.File]::WriteAllText((Join-Path (Get-Location) $MONGO_KEYFILE), $base64, [System.Text.Encoding]::ASCII)
        }
        Write-LogSuccess "MongoDB keyfile generated successfully."
    } else {
        Write-LogInfo "MongoDB keyfile ($MONGO_KEYFILE) already exists."
    }
}

function Invoke-Database {
    param($Action, $Target)
    if ($Action -eq "enable" -and $Target -eq "replicaset") {
        Write-LogInfo "Executing MongoDB replica set initialization script..."
        $phaseCmd = Get-Command phase -ErrorAction SilentlyContinue
        $initScript = ".\scripts\init-mongo-rs.sh"
        if ($phaseCmd) {
            phase run -- bash $initScript
        } else {
            bash $initScript
        }
    } else {
        Write-LogError "Usage: .\setup.ps1 database enable replicaset"
        exit 1
    }
}

function Initiate-MongoReplSet {
    Invoke-Database "enable" "replicaset"
}

function Check-IsInstalled {
    if (-not (Test-Path $INSTALL_FILE)) {
        Write-LogError "Application is not installed. Please run '.\setup.ps1 install' first."
        exit 1
    }
}

function Mark-Installed {
    New-Item -ItemType File -Path $INSTALL_FILE -Force | Out-Null
    Write-LogInfo "Installation state saved."
}

function Handle-Install {
    Print-Banner
    if (Test-Path $INSTALL_FILE) {
        Write-LogInfo "Application is already installed. Running in verification/maintenance mode."
    } else {
        Write-LogInfo "Starting fresh installation..."
    }

    Ensure-MongoKeyfile

    Write-LogStep "Provisioning Containers"
    docker compose pull
    docker compose down 2>$null
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-LogError "Failed to start services."
        exit 1
    }

    Initiate-MongoReplSet
    Mark-Installed
    Write-LogSuccess "Installation completed successfully!"
}

function Handle-Update {
    Print-Banner
    Check-IsInstalled
    Write-LogInfo "Starting update process..."
    Ensure-MongoKeyfile

    docker compose pull
    docker compose down 2>$null
    docker compose up -d --remove-orphans
    Initiate-MongoReplSet
    Write-LogSuccess "Application updated successfully!"
}

function Handle-Start {
    Print-Banner
    Check-IsInstalled
    Write-LogInfo "Starting infrastructure..."
    Ensure-MongoKeyfile

    docker compose down 2>$null
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-LogError "Failed to start services."
        exit 1
    }
    Initiate-MongoReplSet
    Write-LogSuccess "Infrastructure started successfully!"
}

function Handle-Stop {
    Print-Banner
    Check-IsInstalled
    Write-LogInfo "Stopping infrastructure..."
    docker compose down
    Write-LogSuccess "Infrastructure stopped successfully!"
}

param (
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1)]
    [string]$Arg1,
    [Parameter(Position=2)]
    [string]$Arg2
)

switch ($Command) {
    "install"  { Handle-Install }
    "update"   { Handle-Update }
    "start"    { Handle-Start }
    "stop"     { Handle-Stop }
    "database" { Invoke-Database $Arg1 $Arg2 }
    default    {
        Write-Host "Usage: .\setup.ps1 [install|update|start|stop|database enable replicaset]"
    }
}
