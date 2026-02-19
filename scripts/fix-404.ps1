param(
  [string]$ComposeFile = "infra/docker-compose/saas.dev.yml",
  [string]$PostgresContainer = "aioc-postgres",
  [string]$DbUser = "aioc",
  [string]$DbName = "aioc",
  [string]$ApiBase = "http://127.0.0.1:8080/api/v1",
  [string]$SmokeEmail = "user@aioc.internal",
  [string]$SmokePassword = "123456",
  [switch]$SkipSmokeCheck
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

function Assert-ApiOk($resp, $name) {
  if ($null -eq $resp) { throw "${name}: empty response" }
  if ($resp.code -ne 1) { throw "$name failed: $($resp.msg)" }
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

  $m004 = Join-Path $repoRoot "server/migrations/004_role_project_output.sql"
  $m005 = Join-Path $repoRoot "server/migrations/005_user_sources_library.sql"
  if (-not (Test-Path $m004)) { throw "Missing migration file: $m004" }
  if (-not (Test-Path $m005)) { throw "Missing migration file: $m005" }

  Step "Rebuild and start services"
  Run "docker compose -f `"$ComposeFile`" up -d --build postgres redis gateway core engine-openclaw"

  Step "Check postgres container"
  Run "docker ps --filter name=$PostgresContainer --format `"table {{.Names}}`t{{.Status}}`""

  Step "Apply migration 004 if needed"
  $q004 = "select case when to_regclass('public.projects') is not null and to_regclass('public.project_sources') is not null and to_regclass('public.project_artifacts') is not null then 1 else 0 end;"
  $has004 = (docker exec $PostgresContainer psql -U $DbUser -d $DbName -tAc $q004).Trim()
  if ($has004 -eq "1") {
    Write-Host "Migration 004 already present, skip." -ForegroundColor Yellow
  } else {
    Get-Content $m004 -Raw | docker exec -i $PostgresContainer psql -v ON_ERROR_STOP=1 -U $DbUser -d $DbName
    Write-Host "Migration 004 applied." -ForegroundColor Green
  }

  Step "Apply migration 005 if needed"
  $q005 = "select case when to_regclass('public.user_sources') is not null then 1 else 0 end;"
  $has005 = (docker exec $PostgresContainer psql -U $DbUser -d $DbName -tAc $q005).Trim()
  if ($has005 -eq "1") {
    Write-Host "Migration 005 already present, skip." -ForegroundColor Yellow
  } else {
    Get-Content $m005 -Raw | docker exec -i $PostgresContainer psql -v ON_ERROR_STOP=1 -U $DbUser -d $DbName
    Write-Host "Migration 005 applied." -ForegroundColor Green
  }

  Step "Check health endpoint"
  $health = Get-HttpStatus "$ApiBase/health"
  if ($health -ne 200) {
    throw "Health check failed: $ApiBase/health -> $health"
  }
  Write-Host "health = 200" -ForegroundColor Green

  Step "Check route status (expect 401 or 200, not 404)"
  $projects = Get-HttpStatus "$ApiBase/projects"
  $sources = Get-HttpStatus "$ApiBase/sources"
  if ($projects -eq 404) { throw "/projects is still 404. Gateway route may be stale." }
  if ($sources -eq 404) { throw "/sources is still 404. Gateway route may be stale." }
  Write-Host "projects status = $projects" -ForegroundColor Green
  Write-Host "sources  status = $sources" -ForegroundColor Green

  if (-not $SkipSmokeCheck) {
    Step "Run authenticated smoke checks"

    $loginBody = @{ email = $SmokeEmail; password = $SmokePassword } | ConvertTo-Json
    $login = Invoke-RestMethod -Method POST -Uri "$ApiBase/auth/login" -ContentType "application/json" -Body $loginBody -TimeoutSec 10
    Assert-ApiOk $login "auth/login"
    $token = $login.data.access_token
    if ([string]::IsNullOrWhiteSpace($token)) {
      throw "auth/login returned empty access token"
    }
    $headers = @{ Authorization = "Bearer $token" }

    $uc = Invoke-RestMethod -Method GET -Uri "$ApiBase/client/use-cases" -Headers $headers -TimeoutSec 10
    Assert-ApiOk $uc "client/use-cases"
    $rolesCount = @($uc.data.roles).Count
    $genericCount = @($uc.data.generic_skills).Count
    Write-Host "use-cases roles=$rolesCount generic=$genericCount" -ForegroundColor Green

    $sk = Invoke-RestMethod -Method GET -Uri "$ApiBase/client/skills" -Headers $headers -TimeoutSec 10
    Assert-ApiOk $sk "client/skills"
    $skillsCount = @($sk.data).Count
    Write-Host "skills count=$skillsCount" -ForegroundColor Green

    $pj = Invoke-RestMethod -Method GET -Uri "$ApiBase/projects" -Headers $headers -TimeoutSec 10
    Assert-ApiOk $pj "projects list"
    $src = Invoke-RestMethod -Method GET -Uri "$ApiBase/sources" -Headers $headers -TimeoutSec 10
    Assert-ApiOk $src "sources list"
    Write-Host "projects count=$(@($pj.data).Count), sources count=$(@($src.data).Count)" -ForegroundColor Green
  } else {
    Write-Host "Skip smoke checks: -SkipSmokeCheck" -ForegroundColor Yellow
  }

  Step "Done"
  Write-Host "Start Flutter with:" -ForegroundColor Cyan
  Write-Host "flutter run --host-vmservice-port 8181 --dart-define=AIOC_API_BASE_URL=$ApiBase"
}
catch {
  Write-Host ""
  Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
