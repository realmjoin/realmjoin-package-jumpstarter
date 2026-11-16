Param(
    [string] $vendorName,
    [string] $applicationName,
    [switch] $isMacOsPackage,
    [string] $repositoryName,
    [string] $repositoryPath,
    [string] $repositoryNamespace,
    [string] $gitlabPersonalAccessToken = $Env:GitLabToken,
    [switch] $gitUseSsh,
    [switch] $doNotQueryParameters,
    [switch] $doNotCreateRepository,
    [switch] $doNotCloneRepository,
    [switch] $doNotCopyTemplate,
    [switch] $doNotRunTemplateScript,
    [switch] $debugUseLocalTemplates,
    [Parameter(ValueFromRemainingArguments = $true)] $remainingArgumentsToPassToTemplate

)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2
Write-Host


if (-not $gitlabPersonalAccessToken) {
    # try to read token from file
    $gitlabPersonalAccessToken = Get-Content "gl.token" -ErrorAction SilentlyContinue
    if (-not $gitlabPersonalAccessToken) {
        $gitlabPersonalAccessToken = Get-Content "..\gl.token" -ErrorAction SilentlyContinue
    }
}

if (-not $DoNotQueryParameters) {

    Write-Host "*** Querying missing package parameters ***"
    Write-Host "* For vendor name, use a short name, e.g. just 'Microsoft' instead of "
    Write-Host "  'Microsoft Corporation'."
    Write-Host "* For config packages or packages with very simple names (e.g. open source "
    Write-Host "  projects like 'Putty' etc.), vendor name may be left empty."
    Write-Host "* For organic packages, use 'Organic' as vendor name and the full appliction name "
    Write-Host "  incl. vendor as application name, e.g. 'Organic' and 'Microsoft Coding Toolbox'."
    Write-Host

    if (-not $vendorName) {
        $vendorName = (Read-Host "Vendor name").Trim()
    }

    # we really need this, so we loop until we get it
    while (-not $applicationName) {
        $applicationName = (Read-Host "Application name").Trim()
    }

    if (-not $PSBoundParameters.ContainsKey("isMacOsPackage")) {
        $isMacOsPackage = [switch]((Read-Host "Is this a macOS package [y/N] (default is no)") -in "y", "j", "1", "true")
    }

    if (-not $repositoryName) {
        $repoNameDefault = "$vendorName $applicationName".Trim()
        if ($isMacOsPackage) { $repoNameDefault += " macOS" }
        $repositoryName = (Read-Host "Repository name (default: '$repoNameDefault')").Trim()
        if (-not $repositoryName) { $repositoryName = $repoNameDefault }
    }
    if ($isMacOsPackage -and $repositoryName -inotlike "*macOS") { $repositoryName += " macOS" }

    if (-not $repositoryPath) {
        $repoPathDefault = ($repositoryName -ireplace '[-_ ]+', '-' -ireplace '[^a-z0-9-]').Trim('-').ToLowerInvariant()
        $repositoryPath = (Read-Host "Repository path (default: $repoPathDefault)").Trim()
        if (-not $repositoryPath) { $repositoryPath = $repoPathDefault }
    }
    if ($isMacOsPackage -and $repositoryPath -inotlike "*macos") { $repositoryPath += "-macos" }

    if (-not $repositoryNamespace) {
        $repositoryNamespace = Read-Host "Repository namespace (leave empty for 'generic-packages', Format: {customer}-packages)"
    }

    if (-not $gitlabPersonalAccessToken) {
        $gitlabPersonalAccessToken = Read-Host "Personal Access Token (to automate, set env var GitLabToken or create gl.token file)"
    }

    if (-not $PSBoundParameters.ContainsKey("GitUseSsh")) {
        $gitUseSsh = [switch]((Read-Host "Use SSH for Git [y/N] (default is https)") -in "y", "j", "1", "true")
    }

}
else {

    if (-not ($applicationName)) {
        throw "ERROR: Need ApplicationName if passing -DoNotQueryParameters"
    }
    if (-not $repositoryName) {
        $repositoryName = "$vendorName $applicationName".Trim()
    }
    if (-not $repositoryPath) {
        $repositoryPath = ($repositoryName -ireplace '[-_ ]+', '-' -ireplace '[^a-z0-9-]').Trim('-').ToLowerInvariant()
    }

}


New-Item $repositoryPath -Type Directory -ErrorAction SilentlyContinue | Out-Null
Set-Location $repositoryPath

if (-not $repositoryNamespace) {
    $repositoryNamespace = "generic-packages"
}

if ($gitUseSsh) {
    $gitRepoPrefix = "git@gitlab.realmjoin.com:"
}
else {
    $gitRepoPrefix = "https://gitlab.realmjoin.com/"
}


if (-not $DoNotCreateRepository) {

    $gitLabApiUriStub = "https://gitlab.realmjoin.com/api/v4"
    $gitLabHeaders = @{ "PRIVATE-TOKEN" = $gitlabPersonalAccessToken }

    $matchingGroups = Invoke-RestMethod "$gitLabApiUriStub/groups?search=$([System.Uri]::EscapeDataString($repositoryNamespace))&all_available=true&per_page=100" -Headers $gitLabHeaders
    # match at beginning of path only
    $matchingGroups = @($matchingGroups | Where-Object { $_.path -ilike "$repositoryNamespace*" })
    if ($matchingGroups.Count -ne 1) {
        Throw "Namespace could not be identified exactly (found $($matchingGroups.full_path -join ', '))."
    }
    $namespace_id = $matchingGroups[0].id;
    $RepositoryNamespace = $matchingGroups[0].full_path

    $postParams = @{ name = $repositoryName; path = $repositoryPath; namespace_id = $namespace_id; lfs_enabled = $true }
    $apiResult = Invoke-RestMethod "$gitLabApiUriStub/projects" -Headers $gitLabHeaders -Method POST -Body $postParams
    if ($gitUseSsh) {
        $repositoryUrl = $apiResult.ssh_url_to_repo
    }
    else {
        $repositoryUrl = $apiResult.http_url_to_repo
    }

    "Successfully created repository $repositoryUrl"
    ""

}
else {

    $repositoryUrl = "$gitRepoPrefix$repositoryNamespace/$repositoryPath.git"

}

Write-Debug "VendorName:          $vendorName"
Write-Debug "ApplicationName:     $applicationName"
Write-Debug "RepositoryName:      $repositoryName"
Write-Debug "RepositoryPath:      $repositoryPath"
Write-Debug "RepositoryNamespace: $repositoryNamespace"

if (-not $DoNotCloneRepository) {

    git clone $repositoryUrl .

}
elseif (-not (Test-Path ".git" -PathType Container)) {

    git init

}


if (-not $DoNotCopyTemplate) {

    if (-not $debugUseLocalTemplates) {

        git clone --depth 1 "$($gitRepoPrefix)common/package-templates.git" "_template"

        Remove-Item "_template\.git" -Recurse -Force
        Copy-Item "_template\*" "." -Recurse -Force
        Remove-Item "_template" -Recurse -Force

    }
    else {
        Copy-Item "$PSScriptRoot\..\package-templates\*" "." -Recurse -Force
    }

    if ((-not $DoNotRunTemplateScript) -and (Test-Path "Jumpstart.ps1")) {
        Write-Host
        & ".\Jumpstart.ps1" -VendorName:$vendorName -ApplicationName:$applicationName -IsMacOsPackage:$isMacOsPackage `
            -RepositoryPath:$RepositoryPath -RepositoryNamespace:$RepositoryNamespace `
            -GitUseSsh:$gitUseSsh @RemainingArgumentsToPassToTemplate
    }

}
