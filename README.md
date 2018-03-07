# realmjoin-package-jumpstarter

## Usage
JumpstartRealmJoinPackage.ps1 [-RepositoryPath \<string\>] [-RepositoryName \<string\>] [-RepositoryNamespace \<string\>] [-GitlabPersonalAccessToken \<string\>] [-GitUseSsh] [-DoNotQueryParameters] [-DoNotCreateRepository] [-DoNotCloneRepository] [-DoNotCopyTemplate] [-DoNotRunTemplateScript] [\<CommonParameters\>]

## Run Directly from GitHub (without parameters)
```
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/realmjoin/realmjoin-package-jumpstarter/master/JumpstartRealmJoinPackage.ps1'))"
```

## Run Directly from GitHub With Parameters
```
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "iex ('& {' + ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/realmjoin/realmjoin-package-jumpstarter/master/JumpstartRealmJoinPackage.ps1')) + '} -RepositoryPath new_project -RepositoryName ''New Project Test'' -GitlabPersonalAccessToken REPLACE_ME -DoNotQueryParameters')"
```
