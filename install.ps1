<#
.SYNOPSIS
Setup Terminal Profile with dot source github repo

.DESCRIPTION
- Installs `Windows Terminal`, `Neovim`, `Git`, `PowerShell 7` as well as other packages using the scoop package manager
- Deploys Custom Profile
- Deploys Custom Profile Script

.AUTHOR
Matalus : https://github.com/Matalus
.
#>

# Get Working Dir
$ProfileDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Force Load PowerShell-Yaml
$PowerShellYaml = Get-Module -Name "PowerShell-Yaml" -ListAvailable -ErrorAction SilentlyContinue
if (!($PowerShellYaml)) {
  Install-Module -Name PowerShell-Yaml -Force
  Import-Module PowerShell-Yaml -Force -ErrorAction SilentlyContinue
}

# Force Load Profile functions
Write-Host -ForegroundColor White "Loading Profile Functions:" -NoNewline
Try {
  Import-Module "$ProfileDir\profile_functions.psm1" -Force -ErrorAction SilentlyContinue
  Write-Host -ForegroundColor Green " OK ✅"
}
Catch {
  Write-Host -ForegroundColor Red " Fail ❌"
}

# Load Profile Defaults
$Defaults = Get-Content $ProfileDir\defaults.yaml | ConvertFrom-Yaml

# Get PowerShell Info from custom function
$Global:PSInfo = Get-PSInfo
# Check if Admin, throw error it not
if (!($PSInfo.is_admin)) {
  throw "Stopping: you must run 'install.ps1' as Administrator"
}

# Scoop Config Path
$ScoopConfigPath = "$ProfileDir\scoop.yaml"

# Get Scoop Package Status
$ScoopStatus = Get-ScoopPackages -ScoopConfigPath $ScoopConfigPath -PSInfo $Global:PSInfo

# Get PowerShell Temp Profiles
## The reason we don't use $PROFILE.CurrentUserAllHosts is because we don't know what verson of
## Powershell you'll run the install script with and it invert the symlinks
$TempProfile = Get-PSProfile
$PS5TempProfile = $TempProfile.PS5Profile
$PS7TempProfile = $TempProfile.PS7Profile

# Setup Symlinks
# TODO setup symlink handings and move into function
$SymLinkConfigPath = "$ProfileDir\symlinks.yaml"
$SymLinks = Get-Content $SymLinkConfigPath | ConvertFrom-Yaml

ForEach ($Symlink in $SymLinks.Symlinks) {
  # Check if path exists 
  $SymLinkPath = $ExecutionContext.InvokeCommand.ExpandString($Symlink.target)
  $SymLinkSource = "$ProfileDir\$($Symlink.source)"
  Write-Host "Checking Symlink: $($SymLinkPath):" -ForegroundColor White -NoNewline
  $TestTarget = Test-Path $SymLinkPath
  
  if ($TestTarget) {
    # check if symlink already exists
    $SymLinkExists = Get-Item $SymLinkPath -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -match "ReparsePoint" } 
  | Where-Object { $_.FullName -eq $SymLinkPath -and $_.Target -eq $SymLinkSource }
    if ($SymLinkExists) {
      Write-Host -ForegroundColor Green " OK ✅"
    }
    else {
      Write-Host -ForegroundColor Yellow " missing ❌"
      $Contents = Get-ChildItem $SymLinkPath -Recurse -Force -ErrorAction SilentlyContinue
      if ($Contents) {
        # attempt to rename dir
        $Leaf = Split-Path -Leaf $SymLinkPath
        $Parent = Split-Path -Parent $SymLinkPath
        $BackupPath = "$($Parent)\$($Leaf).$(get-date -Format "yyyyddMM-hhmm").BAK"
        Write-Host -ForegroundColor Yellow "Backing up current directory: $($SymLinkPath) to: $($BackupPath) 💾"
        # Throw error if data can't be moved to avoid
        Move-Item -Path $SymLinkPath -Destination $BackupPath -Verbose -ErrorAction Stop
      }
      Write-Host -ForegroundColor Yellow " missing ⚠️"
      # Create Missing Symlinks
      Write-Host " ▶️  Creating Symlink: $($SymLinkSource) --> $($SymLinkPath) ..."
      New-Item -ItemType SymbolicLink -Target $SymLinkSource -Path $SymLinkPath -Verbose  
  
    }
  }  
}

# Get WindowsTerminal LocalState paths
[array]$TermPaths = Get-ChildItem "$($env:LOCALAPPDATA)\Packages" -Force | Where-Object {
  $_.Name -match "Microsoft.WindowsTerminal.*" 
} | Get-ChildItem -Recurse -Include "settings.json"

$DefaultProfile = $TerminalSettings | Where-Object { $_.Name -eq $Defaults.default_terminal }

if ($TermPaths) {
  # Load Default Terminals
  $TerminalSettings = Get-Content "$ProfileDir\terminals.json" | ConvertFrom-Json

  ForEach ($TermPath in $TermPaths) {
    Try {
      $ChangeCount = 0
      $CurrentSettings = Get-Content $TermPath.FullName | ConvertFrom-Json
      Write-Host "Found Settings: $($TermPath.FullName)"

      if ($CurrentSettings.defaultProfile -ne $DefaultProfile.guid) {
        write-host -ForegroundColor Cyan "Updating Default Terminal Profile to: $($DefaultProfile.name) : $($DefaultProfile.guid)"
        $CurrentSettings.defaultProfile = $DefaultProfile.guid
        $ChangeCount++
      }
      ForEach ($TermProfile in $TerminalSettings) {
        Write-Host "Checking Profile: $($TermProfile.Name) : $($TermProfile.guid):" -NoNewline

        # check font
        $NFString = "$($Defaults.nerd_font),$($Defaults.fallback_font)"
        if ($TermProfile.face -and $TermProfile.face.font -ne $NFString) {
          $TermProfile.face.font = $NFString
        }
        # check if profile exists in settings.json
        if ($TermProfile.guid -notin $CurrentSettings.profiles.guid) {
          Write-Host -ForegroundColor Yellow " Patching ⚠️"
          $CurrentSettings.profiles += $TermProfile
          $ChangeCount++
        }
        else {
          Write-Host -ForegroundColor Green " OK ✅"
        }
        if ($ChangeCount -ge 1) {
          # Backup old settings
          $BackupSettingsPath = $TermPath.FullName -replace "settings.json", "settings.bak.json"
          "Backing up: $($TermPath.FullName) --> settings.bak.json 💾"
          Move-Item -Path $TermPath.FullName -Destination $BackupSettingsPath -Verbose

          # Export Updated Settings file
          $CurrentSettings | ConvertTo-Json -Depth 10 | Set-Content $TermPath.FullName -Verbose
        }
      }
    }
    Catch {}
  }
}

# Load oh-my-posh
Import-Module oh-my-posh -Force
Try { Set-PoshPrompt -Theme $Defaults.posh_prompt }Catch {}
# Set preferred Nerd Font
Try { Set-ConsoleFont -Name $Defaults.nerd_font -Height 17 }Catch {}
# Load Terminal Icons
Try { Import-Module Terminal-Icons -Force }Catch {}
# Perform basic PSReadline config
Try { Import-Module PSReadLine -Force }Catch {}
Set-PSreadLineOption -PredictionViewStyle ListView -PredictionSource HistoryAndPlugin

# TODO Setup WSL Instances

# Run PS7 Profile
& $PROFILE.CurrentUserAllHosts