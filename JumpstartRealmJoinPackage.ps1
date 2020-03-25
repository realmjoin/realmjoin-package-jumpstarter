Param(
    [string] $RepositoryPath,
    [string] $RepositoryName,
    [string] $RepositoryNamespace,
    [string] $GitlabPersonalAccessToken = $Env:GitLabToken,
    [switch] $GitUseSsh,
    [switch] $DoNotQueryParameters,
    [switch] $DoNotCreateRepository,
    [switch] $DoNotCloneRepository,
    [switch] $DoNotCopyTemplate,
    [switch] $DoNotRunTemplateScript,
    [Parameter(ValueFromRemainingArguments = $true)] $RemainingArgumentsToPassToTemplate

)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2


if (-not $gitlabPersonalAccessToken) {
    # try to read token from file
    $gitlabPersonalAccessToken = Get-Content "gl.token" -ErrorAction SilentlyContinue
    if (-not $gitlabPersonalAccessToken) {
        $gitlabPersonalAccessToken = Get-Content "..\gl.token" -ErrorAction SilentlyContinue
    }
}

if (-not $DoNotQueryParameters) {
    Write-Host "Querying missing parameters about RealmJoin GitLab:"
    if (-not $repositoryPath) {
        $repositoryPath = Read-Host "Repository path (leave empty for current folder name, Format: {vendor}-{productname})"
    }
    if (-not $repositoryName) {
        $repositoryName = Read-Host "Repository name (leave empty for repository path)"
    }
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

if ($repositoryPath) {
    New-Item $repositoryPath -Type Directory -ErrorAction SilentlyContinue | Out-Null
    Set-Location $repositoryPath
}
else {
    $repositoryPath = [System.IO.Path]::GetFileName((Get-Location).Path)
}
if (-not $repositoryName) {
    $repositoryName = $repositoryPath
}
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

    $matchingNamespaces = Invoke-RestMethod "$gitLabApiUriStub/namespaces?search=$repositoryNamespace" -Headers $gitLabHeaders
    # ignore username namespaces and match at beginning only
    $matchingNamespaces = @($matchingNamespaces | Where-Object { $_.kind -ieq "group" -and $_.path -ilike "$repositoryNamespace*" })
    if ($matchingNamespaces.length -ne 1) {
        Throw "Namespace could not be identified exactly (found $($matchingNamespaces | Select-Object -ExpandProperty full_path))."
    }
    $namespace_id = $matchingNamespaces[0].id;
    $RepositoryNamespace = $matchingNamespaces[0].full_path

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


if (-not $DoNotCloneRepository) {

    git clone $repositoryUrl .

}
elseif (-not (Test-Path ".git" -PathType Container)) {

    git init

}


if (-not $DoNotCopyTemplate) {

    git clone --depth 1 "$($gitRepoPrefix)common/package-templates.git" "_template"

    Remove-Item "_template\.git" -Recurse -Force
    Copy-Item "_template\*" "." -Recurse -Force
    Remove-Item "_template" -Recurse -Force

    if ((-not $DoNotRunTemplateScript) -and (Test-Path "Jumpstart.ps1")) {
        & ".\Jumpstart.ps1" -RepositoryPath:$RepositoryPath -RepositoryName:$RepositoryName -RepositoryNamespace:$RepositoryNamespace -GitUseSsh:$gitUseSsh @RemainingArgumentsToPassToTemplate
    }

}
