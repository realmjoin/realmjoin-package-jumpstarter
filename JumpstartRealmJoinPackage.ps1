Param(
    [string] $RepositoryPath,
    [string] $RepositoryName,
    [string] $RepositoryNamespace,
    [string] $GitlabPersonalAccessToken,
    [switch] $GitUseSsh,
    [switch] $DoNotQueryParameters,
    [switch] $DoNotCreateRepository,
    [switch] $DoNotCloneRepository,
    [switch] $DoNotAddSubmodule
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2
$currentDirectory = (Get-Location).Path


if (-not $DoNotQueryParameters) {
    if (-not $repositoryPath) {
        $repositoryPath = Read-Host "Please enter the RealmJoin GitLab repository path (leave empty for current folder name)"
    }
    if (-not $repositoryName) {
        $repositoryName = Read-Host "Please enter the RealmJoin GitLab repository name (leave empty for repository path)"
    }
    if (-not $repositoryNamespace) {
        $repositoryNamespace = Read-Host "Please enter the RealmJoin GitLab repository namespace (leave empty for 'generic-packages')"
    }
    if (-not $gitlabPersonalAccessToken) {
        $gitlabPersonalAccessToken = Read-Host "Please enter your RealmJoin GitLab Personal Access Token"
    }
    if (-not $gitUseSsh) {
        $gitUseSsh = [switch]((Read-Host "Use SSH for Git (default is https)") -in "y","j","1","true")
    }
}

if (-not $repositoryPath) {
    $repositoryPath = [System.IO.Path]::GetFileName($currentDirectory)
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
    "git clone $repositoryUrl $currentDirectory"
    git clone $repositoryUrl $currentDirectory
}


if (-not $DoNotAddSubmodule) {
    git submodule add --name "realmjoin-gitlab-ci-helpers" "$($gitRepoPrefix)generic-packages/realmjoin-gitlab-ci-helpers.git" ".realmjoin-gitlab-ci-helpers"
    git config --file ".gitmodules" "submodule.realmjoin-gitlab-ci-helpers.url" "../../generic-packages/realmjoin-gitlab-ci-helpers.git"
}
