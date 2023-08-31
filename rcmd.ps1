# Source file: rcmd.ps1
<#
.SYNOPSIS
A script for various automated tasks for R package management
#>
[CmdletBinding()]

PARAM ( 
    [string]$PackageName = "naijR",

    [ValidateSet("Source", "Binary", "Both")]
    [string]$BuildPackage,

    [ValidateSet("Basic", "Full")]$ReviewPackage,

    [switch]$Check,
    [switch]$Test,
    [switch]$Install,
    [switch]$BuildSite
)

# === Internals =====================
# R CMD Executable
$RCMD = "Rcmd.exe"

# Default colouring for messaging
$DefaultColour = "DarkYellow"

# Script block for retrieving the value for a given key in the package's DESCRIPTION
$getPkgDescriptor = {
    param([string]$Key)
    $private:desc = Join-Path $PackageName -ChildPath "DESCRIPTION" | `
                    Resolve-Path
    
    if (-not (Test-Path $desc)) {
        throw "'$PackageName' is not an R package"
    }
    # TODO: Address case of multiline values
    $private:line = Get-Content $desc | Where-Object { $_.StartsWith($Key)}
    $line.Split(": ")[1]
}


# Script block for building a source package
$buildSourcePackage = {
    Write-Host "Building source package" -ForegroundColor $DefaultColour
    $private:opts = $null
    & $RCMD build $opts $PackageName
}


# === Main program flow ================================
$source_version = Invoke-Command $getPkgDescriptor -ArgumentList "Version"
Write-Host "$PackageName : Package version is $source_version" -ForegroundColor $DefaultColour

if ($Test) {
    Rscript.exe -e "devtools::test('$PackageName')"
}

if ($BuildPackage -eq "Source" -or $BuildPackage -eq "Both") {
    Invoke-Command $buildSourcePackage
}

if ($BuildPackage -eq "Binary" -or $BuildPackage -eq "Both") {
    Write-Host "Building binary package" -ForegroundColor $DefaultColour
    $pvt = $PSVersionTable

    if ($pvt.Platform -ne "Win32NT") {
        throw "Binary build is only supported on Windows"
    }
    & $RCMD INSTALL --build $PackageName
}

if ($BuildPackage -eq "Both" -and $source_version -notmatch "^(\d\.){3}9\d{3}$") {
    $archDir = "arch"
    $archPath = Resolve-Path $archDir

    if (-not (Test-Path $archPath)) {
        throw "Directory '$archPath' was not found"
    }
    Write-Host "Moving built source and binary archives to '$archPath'"
    $archWildcard = $PackageName + "_" + $source_version + ".*"
    Move-Item -Path $archWildcard -Destination $archPath -Force
}

if ($null -ne $ReviewPackage) {
    Write-Host "Running automated review of the package" -ForegroundColor $DefaultColour
    $rvpkg = $ReviewPackage.ToLower()
    $gp = "goodpractice"
    $repo = "https://cran.rstudio.com"
    $dttm = Get-Date -Format "yyyy-MM-dd_HHmm"
    $gpLogFile = $gp + "-" + $rvpkg + "_" + $dttm +  ".log"
    $gpLogPath = Resolve-Path "logs"

    if (-not (Test-Path $gpLogPath)) {
        throw "The directory '$gpLogPath' was not found"
    }
    $gpFilepath = Join-Path -Path $gpLogPath -ChildPath $gpLogFile

    Rscript -e "if (!requireNamespace('$gp')) install.packages('$gp', repos = '$repo'); library($gp)" `
            -e "chks <- all_checks(); if ('$rvpkg' == 'basic') chks <- chks[!grepl('^rcmd', chks)]" `
            -e "gp('$PackageName', checks = chks, quiet = FALSE)" | `
                Out-File -FilePath $gpFilepath -Encoding "ascii"
}

if ($Check -or $Install) {
    $tarext = ".tar.gz"
    $tarWildcard = "_*.9*" + $tarext
    $tarballPattern = $PackageName + $tarWildcard

    $latest_build = Get-ChildItem -Filter $tarballPattern | `
        Select-Object -Property Name | `
        Sort-Object -Bottom 1

    $tarball = $latest_build.Name
    $built_version = $tarball.Replace($PackageName + "_", "").Replace($tarext, "")

    if ($built_version -ne $source_version) {
        Invoke-Command $buildSourcePackage
        $tarball = $tarball.Replace($built_version, $source_version)
    }

    if ($Check) {
        Write-Host "Checking the package" -ForegroundColor $DefaultColour
        & $RCMD check --as-cran --no-tests $tarball
    }
        
    if ($Install) {
        Write-Host "Installing '$PackageName'" -ForegroundColor $DefaultColour
        & $RCMD INSTALL $tarball
        Rscript.exe -e "cat('version', as.character(packageVersion('$PackageName')), 'installed\n')"
    }
}

if ($BuildSite) {
    Write-Host "Building the package website" -ForegroundColor $DefaultColour
    Push-Location $PackageName
    $currBranch = git branch --show-current
    Pop-Location
    $recommBranch = "dev"

    if ($currBranch -ne $recommBranch) {
        Write-Error "Git is not on the recommended '$recommBranch' branch for building the site"
        throw "Git is currently on branch '$currBranch'"
    }
    Rscript.exe -e "pkgdown::build_site(pkg = '$PackageName', preview = FALSE, lazy = TRUE)"
}

