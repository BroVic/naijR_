# Source file: rcmd.ps1
#
# Script for batch execution of R, with the naijR package as the default

[CmdletBinding()]

PARAM ( 
    [string]$Pkgname = "naijR",
    [switch]$Build,
    [switch]$Check,
    [switch]$Test
)

# === Internal functions =====================
# Retrieves the value for a give field in the package's DESCRIPTION file
function Get-PkgDescriptor ([string]$Key) {
    $descrfile = "DESCRIPTION"
    Write-Host "Checking $descrfile key '$Key'" -ForegroundColor DarkYellow
    $descrfile = Join-Path $pkgname -ChildPath $descrfile | Resolve-Path
    $line = Get-Content $descrfile | Where-Object { $_.StartsWith($Key)}
    $line.Split(": ")[1]
    # & "Rscript" -e "as.symbol(unname(read.dcf('$descrfile')[, '$Key']))"
}


# Builds a source package
function buildPackage {
    Write-Host "Building the package" -ForegroundColor DarkYellow
    $opts = $null
    
    if ($pkgname -eq "naijR") {
        $opts = "--resave-data"
        Write-Host "Using option(s) '$opts'" -ForegroundColor DarkYellow
    }
    & "Rcmd.exe" build $opts $pkgname
}


# === Main program flow ================================
$source_version = Get-PkgDescriptor -Key "Version"
Write-Host "$pkgname : Package version is $source_version" -ForegroundColor DarkYellow

if ($Test) {
    Rscript.exe -e "devtools::test('$pkgname')"
}

if ($Build) {
    buildPackage
}

if ($Check) {
    $tarext = ".tar.gz"
    $wildcard = "_*.9*" + $tarext
    $pattern = $pkgname + $wildcard

    $latest_build = Get-ChildItem -Filter $pattern | `
        Select-Object -Property Name | `
        Sort-Object -Bottom 1

    $tarball = $latest_build.Name
    $built_version = $tarball.Replace($pkgname + "_", "").Replace($tarext, "")

    if ($built_version -ne $source_version) {
        buildPackage
        $tarball = $tarball.Replace($built_version, $source_version)
    }

    Write-Host "Checking the package" -ForegroundColor DarkYellow
    & "Rcmd.exe" check --as-cran --no-tests $tarball
}
