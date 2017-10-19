Param(
    [string] $RepositoryPath,
    [string] $RepositoryName,
    [string] $RepositoryNamespace,
    [string] $GitlabPersonalAccessToken,
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
    # try reading token from file
    $fileToken = "gl.token"
    $fileTest = Join-Path $(Get-Location).Path $fileToken
    if ( Test-Path -PathType Leaf -Path $fileTest ) {
        $gitlabPersonalAccessToken = Get-Content -Path $fileTest
    } else {
        $fileTest = Join-Path (Split-Path $(get-location) -parent) $fileToken
        if ( Test-Path -PathType Leaf -Path $fileTest ) {
            $gitlabPersonalAccessToken = Get-Content -Path $fileTest
        }
    }
}

if (-not $DoNotQueryParameters) {
    Write-Host "Querying missing parameters about RealmJoin GitLab:"
    if (-not $repositoryPath) {
        $repositoryPath = Read-Host "Repository path (leave empty for current folder name, Format: {VENDOR}-{PRODUCTNAME})"
    }
    if (-not $repositoryName) {
        $repositoryName = Read-Host "Repository name (leave empty for repository path)"
    }
    if (-not $repositoryNamespace) {
        $repositoryNamespace = Read-Host "Repository namespace (leave empty for 'generic-packages', Format: {CUSTOMER}-packages)"
    }
    if (-not $gitlabPersonalAccessToken) {
        $gitlabPersonalAccessToken = Read-Host "Personal Access Token (to automate, create gl.token file)"
    }
    if (-not $gitUseSsh) {
        $gitUseSsh = [switch]((Read-Host "Use SSH for Git [y/N] (default is https)") -in "y","j","1","true")
    }
}

if ($repositoryPath) {
        New-Item $repositoryPath -Type Directory -ErrorAction SilentlyContinue | Out-Null
        Set-Location $repositoryPath
    } else {
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
} else {
    $gitRepoPrefix = "https://gitlab.realmjoin.com/"
}


if (-not $DoNotCreateRepository) {

    $gitLabApiUriStub = "https://gitlab.realmjoin.com/api/v4"
    $gitLabHeaders = @{"PRIVATE-TOKEN" = $gitlabPersonalAccessToken}

    $apiResult = Invoke-RestMethod "$gitLabApiUriStub/namespaces?search=$repositoryNamespace" -Headers $gitLabHeaders
    if ($apiResult.length -ne 1) { Throw "Namespace could not be identified exactly (`$apiResult.length = $($apiResult.length))." }
    $namespace_id = $apiResult[0].id;

    $postParams = @{name = $repositoryName; path = $repositoryPath; namespace_id = $namespace_id; lfs_enabled = $true}
    $apiResult = Invoke-RestMethod "$gitLabApiUriStub/projects" -Headers $gitLabHeaders -Method POST -Body $postParams
    if ($gitUseSsh) {
        $repositoryUrl = $apiResult.ssh_url_to_repo
    } else {
        $repositoryUrl = $apiResult.http_url_to_repo
    }

    "Successfully created repository $repositoryUrl"
    ""

} else {

    $repositoryUrl = "$gitRepoPrefix$repositoryNamespace/$repositoryPath.git"

}


if (-not $DoNotCloneRepository) {

    git clone $repositoryUrl .

} elseif (-not (Test-Path ".git" -PathType Container)) {

    git init

}


if (-not $DoNotCopyTemplate) {

    git clone --branch beta "$($gitRepoPrefix)generic-packages/template-choco.git" "_template"

    Remove-Item "_template\.git" -Recurse -Force
    Copy-Item "_template\*" "." -Recurse -Force
    Remove-Item "_template" -Recurse -Force

    if ((-not $DoNotRunTemplateScript) -and (Test-Path "Jumpstart.ps1")) {
        & ".\Jumpstart.ps1" -RepositoryPath:$RepositoryPath -RepositoryName:$RepositoryName -RepositoryNamespace:$RepositoryNamespace -GitUseSsh:$gitUseSsh @RemainingArgumentsToPassToTemplate
    }

    git add ".git*"

}

