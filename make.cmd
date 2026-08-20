@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set CHART=charts\timeseries
set GRAFANA_IMAGE=ghcr.io/eduard-kolotushin/timeseries-grafana:0.1.0
set BASELINES_IMAGE=ghcr.io/eduard-kolotushin/timeseries-baselines:0.1.0

if "%~1"=="" goto :lint
if /I "%~1"=="all" goto :lint
if /I "%~1"=="help" goto :help
if /I "%~1"=="lint" goto :lint
if /I "%~1"=="helm-deps" goto :helm-deps
if /I "%~1"=="docker-grafana" goto :docker-grafana
if /I "%~1"=="docker-baselines" goto :docker-baselines
echo Unknown target: %~1
exit /b 1

:help
echo make lint             helm dependency update, lint, template
echo make docker-grafana   build Grafana-with-plugin image
echo make docker-baselines build worker image
exit /b 0

:helm-deps
helm dependency update %CHART%
exit /b %ERRORLEVEL%

:lint
call "%~f0" helm-deps
if errorlevel 1 exit /b 1
helm lint %CHART% -f ci\values.yaml
if errorlevel 1 exit /b 1
helm template test %CHART% -f ci\values.yaml > NUL
exit /b %ERRORLEVEL%

:docker-grafana
docker build -f docker\grafana\Dockerfile -t %GRAFANA_IMAGE% docker\grafana
exit /b %ERRORLEVEL%

:docker-baselines
docker build -f docker\baselines\Dockerfile -t %BASELINES_IMAGE% docker\baselines
exit /b %ERRORLEVEL%
