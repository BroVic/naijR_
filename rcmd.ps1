# Source file: rcmd.ps1
#
# Script for batch execution of R, with the naijR package as the default

[CmdletBinding()]

PARAM ( 
    [string]$PackageName = "naijR",
    [switch]$BuildPackage,
    [switch]$Check,
    [switch]$Test,
    [switch]$BuildSite
)

# === Internal functions =====================
# Retrieves the value for a given field in the package's DESCRIPTION file
function Get-PkgDescriptor ([string]$Key) {
    $descrfile = "DESCRIPTION"
    Write-Host "Checking $descrfile key '$Key'" -ForegroundColor DarkYellow
    $descrfile = Join-Path $PackageName -ChildPath $descrfile | `
                    Resolve-Path
    $line = Get-Content $descrfile | `
                Where-Object { $_.StartsWith($Key)}
    $line.Split(": ")[1]
    # & "Rscript" -e "as.symbol(unname(read.dcf('$descrfile')[, '$Key']))"
}


# Builds a source package
function buildSourcePackage {
    Write-Host "Building the package" -ForegroundColor DarkYellow
    $opts = $null
    & "Rcmd.exe" build $opts $PackageName
}


# === Main program flow ================================
$source_version = Get-PkgDescriptor -Key "Version"
Write-Host "$PackageName : Package version is $source_version" -ForegroundColor DarkYellow

if ($Test) {
    Rscript.exe -e "devtools::test('$PackageName')"
}

if ($BuildPackage) {
    buildSourcePackage
}

if ($Check) {
    $tarext = ".tar.gz"
    $wildcard = "_*.9*" + $tarext
    $pattern = $PackageName + $wildcard

    $latest_build = Get-ChildItem -Filter $pattern | `
        Select-Object -Property Name | `
        Sort-Object -Bottom 1

    $tarball = $latest_build.Name
    $built_version = $tarball.Replace($PackageName + "_", "").Replace($tarext, "")

    if ($built_version -ne $source_version) {
        buildSourcePackage
        $tarball = $tarball.Replace($built_version, $source_version)
    }

    Write-Host "Checking the package" -ForegroundColor DarkYellow
    & "Rcmd.exe" check --as-cran --no-tests $tarball
}

if ($BuildSite) {
    Write-Host "Building the package website" -ForegroundColor DarkYellow
    $currBranch = git branch --show-current

    if ($currBranch -ne "master") {
        Write-Error "Git is not on the recommended 'master' branch for building the site"
        throw "Git is currently on branch '$currBranch'"
    }
    Rscript.exe -e "pkgdown::build_site(pkg = '$PackageName', preview = FALSE, lazy = TRUE)"
}
