# Source file: rcmd.ps1
#
# Script for batch execution of R, with the naijR package as the default

[CmdletBinding()]

PARAM ( 
    [string]$PackageName = "naijR",
    [ValidateSet("Source", "Binary", "Both")]
    [string]$BuildPackage,
    [ValidateSet("Basic", "Full")]
    [string]$ReviewPackage,
    [switch]$Check,
    [switch]$Test,
    [switch]$BuildSite
)

# === Internals =====================
# Default colouring for messaging
$DefaultColour = "DarkYellow"

# Retrieves the value for a given field in the package's DESCRIPTION file
$getPkgDescriptor = {
    param([string]$Key)
    $desc = Join-Path $PackageName -ChildPath "DESCRIPTION" | `
                    Resolve-Path
    
    if (-not (Test-Path $desc)) {
        throw "'$PackageName' is not an R package"
    }
    $line = Get-Content $desc | Where-Object { $_.StartsWith($Key)}
    $line.Split(": ")[1]
}


# Script block for building a source package
$buildSourcePackage = {
    Write-Host "Building source package" -ForegroundColor $DefaultColour
    $opts = $null
    & "Rcmd.exe" build $opts $PackageName
}


# === Main program flow ================================
$source_version = & $getPkgDescriptor -Key "Version"
Write-Host "$PackageName : Package version is $source_version" -ForegroundColor $DefaultColour

if ($Test) {
    Rscript.exe -e "devtools::test('$PackageName')"
}

if ($BuildPackage -eq "Source" -or $BuildPackage -eq "Both") {
    & $buildSourcePackage
}

if ($BuildPackage -eq "Binary" -or $BuildPackage -eq "Both") {
    Write-Host "Building binary package" -ForegroundColor $DefaultColour
    $pvt = $PSVersionTable

    if ($pvt.Platform -ne "Win32NT") {
        throw "Binary build is only supported on Windows"
    }
    & "Rcmd.exe" INSTALL --build $PackageName
}

if ($BuildPackage -eq "Both") {
    $archDir = "arch"
    $archPath = Resolve-Path $archDir

    if (-not (Test-Path $archPath)) {
        throw "Directory '$archPath' was not found"
    }
    Write-Host "Moving built source and binary archives to '$archPath'"
    $archWildcard = $PackageName + "_" + $source_version + ".*"
    Move-Item -Path $archWildcard-Destination $archPath -Force
}

if ($ReviewPackage -ne $null) {
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

if ($Check) {
    $tarext = ".tar.gz"
    $tarWildcard = "_*.9*" + $tarext
    $pattern = $PackageName + $tarWildcard

    $latest_build = Get-ChildItem -Filter $pattern | `
        Select-Object -Property Name | `
        Sort-Object -Bottom 1

    $tarball = $latest_build.Name
    $built_version = $tarball.Replace($PackageName + "_", "").Replace($tarext, "")

    if ($built_version -ne $source_version) {
        & $buildSourcePackage
        $tarball = $tarball.Replace($built_version, $source_version)
    }

    Write-Host "Checking the package" -ForegroundColor $DefaultColour
    & "Rcmd.exe" check --as-cran --no-tests $tarball
}

if ($BuildSite) {
    Write-Host "Building the package website" -ForegroundColor $DefaultColour
    $currBranch = git branch --show-current

    if ($currBranch -ne "master") {
        Write-Error "Git is not on the recommended 'master' branch for building the site"
        throw "Git is currently on branch '$currBranch'"
    }
    Rscript.exe -e "pkgdown::build_site(pkg = '$PackageName', preview = FALSE, lazy = TRUE)"
}
