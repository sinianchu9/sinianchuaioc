param(
  [string]$ComposeFile = "infra/docker-compose/saas.dev.yml",
  [string]$OverrideFile = "infra/docker-compose/saas.tooling.override.yml",
  [string]$EnvFile = ".env.tool-control-center.local",
  [string]$PostgresContainer = "aioc-postgres",
  [string]$DbUser = "aioc",
  [string]$DbName = "aioc",
  [string]$ApiBase = "http://127.0.0.1:8080/api/v1",
  [string]$MasterKey = "",
  [switch]$SkipServiceRestart
)

$ErrorActionPreference = "Stop"

function Step($msg) {
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor Cyan
}

function Run($cmd) {
  Write-Host "PS> $cmd" -ForegroundColor DarkGray
  Invoke-Expression $cmd
}

function Get-HttpStatus($url) {
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Method GET -TimeoutSec 10
    return [int]$resp.StatusCode
  } catch {
    if ($_.Exception.Response) {
      return [int]$_.Exception.Response.StatusCode
    }
    throw
  }
}

function New-Base64Key32 {
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return [Convert]::ToBase64String($bytes)
}

try {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $repoRoot = Resolve-Path (Join-Path $scriptDir "..")
  Set-Location $repoRoot

  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker command not found. Please start Docker Desktop first."
  }

  if (-not (Test-Path $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
  }

  $m006 = Join-Path $repoRoot "server/migrations/006_tool_control_center.sql"
  if (-not (Test-Path $m006)) {
    throw "Missing migration file: $m006"
  }

  if ([string]::IsNullOrWhiteSpace($MasterKey)) {
    $MasterKey = New-Base64Key32
  }

  Step "Write env file with MASTER_KEY"
  @"
MASTER_KEY=$MasterKey
"@ | Set-Content -Encoding ascii $EnvFile
  Write-Host "Wrote $EnvFile" -ForegroundColor Green

  Step "Write compose override for gateway MASTER_KEY"
  @"
services:
  gateway:
    environment:
      - MASTER_KEY=`${MASTER_KEY}
"@ | Set-Content -Encoding ascii $OverrideFile
  Write-Host "Wrote $OverrideFile" -ForegroundColor Green

  if (-not $SkipServiceRestart) {
    Step "Rebuild and restart services with tool control center env"
    Run "docker compose --env-file `"$EnvFile`" -f `"$ComposeFile`" -f `"$OverrideFile`" up -d --build postgres redis gateway core engine-openclaw"
  } else {
    Write-Host "Skip service restart: -SkipServiceRestart" -ForegroundColor Yellow
  }

  Step "Apply migration 006 if needed"
  $q006 = "select case when to_regclass('public.integrations') is not null and to_regclass('public.integration_secrets') is not null and to_regclass('public.tool_status') is not null then 1 else 0 end;"
  $has006 = (docker exec $PostgresContainer psql -U $DbUser -d $DbName -tAc $q006).Trim()
  if ($has006 -eq "1") {
    Write-Host "Migration 006 already present, skip." -ForegroundColor Yellow
  } else {
    Get-Content $m006 -Raw | docker exec -i $PostgresContainer psql -v ON_ERROR_STOP=1 -U $DbUser -d $DbName
    Write-Host "Migration 006 applied." -ForegroundColor Green
  }

  Step "Check health"
  $health = Get-HttpStatus "$ApiBase/health"
  if ($health -ne 200) {
    throw "Health check failed: $ApiBase/health -> $health"
  }
  Write-Host "health = 200" -ForegroundColor Green

  Step "Check admin routes (expect 401 or 403 or 200, not 404)"
  $toolsStatus = Get-HttpStatus "$ApiBase/admin/tools"
  $intsStatus = Get-HttpStatus "$ApiBase/admin/integrations"
  $summaryStatus = Get-HttpStatus "$ApiBase/admin/status/summary"

  if ($toolsStatus -eq 404) { throw "/admin/tools is still 404." }
  if ($intsStatus -eq 404) { throw "/admin/integrations is still 404." }
  if ($summaryStatus -eq 404) { throw "/admin/status/summary is still 404." }

  Write-Host "admin/tools status = $toolsStatus" -ForegroundColor Green
  Write-Host "admin/integrations status = $intsStatus" -ForegroundColor Green
  Write-Host "admin/status/summary status = $summaryStatus" -ForegroundColor Green

  Step "Done"
  Write-Host "Tool control center initialization finished." -ForegroundColor Green
  Write-Host "MASTER_KEY saved in $EnvFile" -ForegroundColor Cyan
  Write-Host "Run Flutter with:" -ForegroundColor Cyan
  Write-Host "flutter run --host-vmservice-port 8181 --dart-define=AIOC_API_BASE_URL=$ApiBase"
}
catch {
  Write-Host ""
  Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
