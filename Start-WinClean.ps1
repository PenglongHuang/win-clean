#Requires -Version 5.1
param([switch]$NoBrowser,[string]$Drives,[string]$DataDir=(Join-Path $env:LOCALAPPDATA 'win-clean'),[string]$OpenRun)
& "$PSScriptRoot\engine\product-server.ps1" -NoBrowser:$NoBrowser -InitialDrives $Drives -DataDir $DataDir -OpenRun $OpenRun
