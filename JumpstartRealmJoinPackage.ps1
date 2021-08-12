Param(
    [string] $vendorName,
    [string] $applicationName,
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
    while (-not $applicationName) { # we really need this, so we loop until we get it
        $applicationName = (Read-Host "Application name").Trim()
    }
    if (-not $repositoryName) {
        $repoNameDefault = "$vendorName $applicationName".Trim()
        $repositoryName = (Read-Host "Repository name (default: '$repoNameDefault')").Trim()
        if (-not $repositoryName) { $repositoryName = $repoNameDefault }
    }
    if (-not $repositoryPath) {
        $repoPathDefault = ($repositoryName -ireplace '[-_ ]+', '-' -ireplace '[^a-z0-9-]').Trim('-').ToLowerInvariant()
        $repositoryPath = (Read-Host "Repository path (default: $repoPathDefault)").Trim()
        if (-not $repositoryPath) { $repositoryPath = $repoPathDefault }
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
} else {
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

    } else {
        Copy-Item "$PSScriptRoot\..\package-templates\*" "." -Recurse -Force
    }

    if ((-not $DoNotRunTemplateScript) -and (Test-Path "Jumpstart.ps1")) {
        Write-Host
        & ".\Jumpstart.ps1" -VendorName:$vendorName -ApplicationName:$applicationName `
            -RepositoryPath:$RepositoryPath -RepositoryNamespace:$RepositoryNamespace `
            -GitUseSsh:$gitUseSsh @RemainingArgumentsToPassToTemplate
    }

}

# SIG # Begin signature block
# MIIsdAYJKoZIhvcNAQcCoIIsZTCCLGECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUahtsT1ikx6egi10So31rJUl1
# BIeggiY3MIIDXzCCAkegAwIBAgILBAAAAAABIVhTCKIwDQYJKoZIhvcNAQELBQAw
# TDEgMB4GA1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjMxEzARBgNVBAoTCkds
# b2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMDkwMzE4MTAwMDAwWhcN
# MjkwMzE4MTAwMDAwWjBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBS
# MzETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMwldpB5BngiFvXAg7aEyiie/QV2
# EcWtiHL8RgJDx7KKnQRfJMsuS+FggkbhUqsMgUdwbN1k0ev1LKMPgj0MK66X17YU
# hhB5uzsTgHeMCOFJ0mpiLx9e+pZo34knlTifBtc+ycsmWQ1z3rDI6SYOgxXG71uL
# 0gRgykmmKPZpO/bLyCiR5Z2KYVc3rHQU3HTgOu5yLy6c+9C7v/U9AOEGM+iCK65T
# pjoWc4zdQQ4gOsC0p6Hpsk+QLjJg6VfLuQSSaGjlOCZgdbKfd/+RFO+uIEn8rUAV
# SNECMWEZXriX7613t2Saer9fwRPvm2L7DWzgVGkWqQPabumDk3F2xmmFghcCAwEA
# AaNCMEAwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYE
# FI/wS3+oLkUkrk1Q+mOai97i3Ru8MA0GCSqGSIb3DQEBCwUAA4IBAQBLQNvAUKr+
# yAzv95ZURUm7lgAJQayzE4aGKAczymvmdLm6AC2upArT9fHxD4q/c2dKg8dEe3jg
# r25sbwMpjjM5RcOO5LlXbKr8EpbsU8Yt5CRsuZRj+9xTaGdWPoO4zzUhw8lo/s7a
# wlOqzJCK6fBdRoyV3XpYKBovHd7NADdBj+1EbddTKJd+82cEHhXXipa0095MJ6RM
# G3NzdvQXmcIfeg7jLQitChws/zyrVQ4PkX4268NXSb7hLi18YIvDQVETI53O9zJr
# lAGomecsMx86OyXShkDOOyyGeMlhLxS67ttVb9+E7gUJTb0o2HLO02JQZR7rkpeD
# MdmztcpHWD9fMIIFQTCCBCmgAwIBAgIRAOjm9712ZEua0SQBWYyk3xIwDQYJKoZI
# hvcNAQELBQAwfDELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hl
# c3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVk
# MSQwIgYDVQQDExtTZWN0aWdvIFJTQSBDb2RlIFNpZ25pbmcgQ0EwHhcNMjAxMjAx
# MDAwMDAwWhcNMjMxMjAxMjM1OTU5WjCBpzELMAkGA1UEBhMCREUxDjAMBgNVBBEM
# BTYzMDY1MQ8wDQYDVQQIDAZIZXNzZW4xEjAQBgNVBAcMCU9GRkVOQkFDSDEVMBMG
# A1UECQwMS2Fpc2Vyc3RyIDM5MSUwIwYDVQQKDBxHbMO8Y2sgJiBLYW5qYSBDb25z
# dWx0aW5nIEFHMSUwIwYDVQQDDBxHbMO8Y2sgJiBLYW5qYSBDb25zdWx0aW5nIEFH
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2xaXdwfrzRCR4P/sFv8H
# 6ig4cel2Arv9g3UyiqmStkKNK7RS+sSCOzP8FfL06/1xMgiMb9skiWJQvi5two86
# QbIAmTDDpNsQcHRqeEJMbx8mYcQoyRVkykb8cjYbCxfvF/ixp0ifJXL9sh5yciDw
# y2CLJgzD5rJN1m7ohPeU4ZXjk0WlZjEwDKWq7VpJzmN7y6odgeg3fFZddeCHYrwb
# uFQPUxr7E8GsJKTaKK9m0Exj6D42Fg2f6oXpIb+qflhp1mtgcZb/24GsznwJ/xM6
# FiHVtzowUn89baT8Yw/6K3BiOp6JaYQvW9ia9Qktk+mo3mXN60ND4L/Zwq0gHTmW
# ZwIDAQABo4IBkDCCAYwwHwYDVR0jBBgwFoAUDuE6qFM6MdWKvsG7rWcaA4WtNA4w
# HQYDVR0OBBYEFLcNTqIUH7puT+HgZjH+tysJVStfMA4GA1UdDwEB/wQEAwIHgDAM
# BgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMBEGCWCGSAGG+EIBAQQE
# AwIEEDBKBgNVHSAEQzBBMDUGDCsGAQQBsjEBAgEDAjAlMCMGCCsGAQUFBwIBFhdo
# dHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZngQwBBAEwQwYDVR0fBDwwOjA4oDag
# NIYyaHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUlNBQ29kZVNpZ25pbmdD
# QS5jcmwwcwYIKwYBBQUHAQEEZzBlMD4GCCsGAQUFBzAChjJodHRwOi8vY3J0LnNl
# Y3RpZ28uY29tL1NlY3RpZ29SU0FDb2RlU2lnbmluZ0NBLmNydDAjBggrBgEFBQcw
# AYYXaHR0cDovL29jc3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQELBQADggEBACOR
# SLYOEFgyrQmwbaTntFf0xnLioyjIYYLpBBd5PMl4Ks1S9pFmqz1+iCBXbcckPZwM
# Z0RbEss4H1YJctFQdowg6o9fKd/niLKosSkcM0I5IMczwI8wswodJhGLLAsG1lMk
# /OjeU1qcIFRjfzJEgmB7Ewr/ftcLkEEc0mtjfCS99olEEmOZswe1KKV9v+4iF8bX
# rdNvqwxexEVPS8PpULOaBbnhZ1ejaCSEfB/DO9xZiuG79vaikjYDoRIoS9VZ9MCc
# yNomooBpUPiosOaD5mypnCh8YHMDoVP1eo9puQVWfUmhqgIEeY8iEEAtTugYCozd
# uGSWplf6MuJk+dmJCIUwggVHMIIEL6ADAgECAg0B8kBCQM79ItvpbHH8MA0GCSqG
# SIb3DQEBDAUAMEwxIDAeBgNVBAsTF0dsb2JhbFNpZ24gUm9vdCBDQSAtIFIzMRMw
# EQYDVQQKEwpHbG9iYWxTaWduMRMwEQYDVQQDEwpHbG9iYWxTaWduMB4XDTE5MDIy
# MDAwMDAwMFoXDTI5MDMxODEwMDAwMFowTDEgMB4GA1UECxMXR2xvYmFsU2lnbiBS
# b290IENBIC0gUjYxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2Jh
# bFNpZ24wggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCVB+hzymb57BTK
# ezz3DQjxtEULLIK0SMbrWzyug7hBkjMUpG9/6SrMxrCIa8W2idHGsv8UzlEUIexK
# 3RtaxtaH7k06FQbtZGYLkoDKRN5zlE7zp4l/T3hjCMgSUG1CZi9NuXkoTVIaihqA
# txmBDn7EirxkTCEcQ2jXPTyKxbJm1ZCatzEGxb7ibTIGph75ueuqo7i/voJjUNDw
# GInf5A959eqiHyrScC5757yTu21T4kh8jBAHOP9msndhfuDqjDyqtKT285VKEgdt
# /Yyyic/QoGF3yFh0sNQjOvddOsqi250J3l1ELZDxgc1Xkvp+vFAEYzTfa5MYvms2
# sjnkrCQ2t/DvthwTV5O23rL44oW3c6K4NapF8uCdNqFvVIrxclZuLojFUUJEFZTu
# o8U4lptOTloLR/MGNkl3MLxxN+Wm7CEIdfzmYRY/d9XZkZeECmzUAk10wBTt/Tn7
# g/JeFKEEsAvp/u6P4W4LsgizYWYJarEGOmWWWcDwNf3J2iiNGhGHcIEKqJp1HZ46
# hgUAntuA1iX53AWeJ1lMdjlb6vmlodiDD9H/3zAR+YXPM0j1ym1kFCx6WE/TSwhJ
# xZVkGmMOeT31s4zKWK2cQkV5bg6HGVxUsWW2v4yb3BPpDW+4LtxnbsmLEbWEFIoA
# GXCDeZGXkdQaJ783HjIH2BRjPChMrwIDAQABo4IBJjCCASIwDgYDVR0PAQH/BAQD
# AgEGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFK5sBaOTE+Ki5+LXHNbH8H/I
# Z1OgMB8GA1UdIwQYMBaAFI/wS3+oLkUkrk1Q+mOai97i3Ru8MD4GCCsGAQUFBwEB
# BDIwMDAuBggrBgEFBQcwAYYiaHR0cDovL29jc3AyLmdsb2JhbHNpZ24uY29tL3Jv
# b3RyMzA2BgNVHR8ELzAtMCugKaAnhiVodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29t
# L3Jvb3QtcjMuY3JsMEcGA1UdIARAMD4wPAYEVR0gADA0MDIGCCsGAQUFBwIBFiZo
# dHRwczovL3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzANBgkqhkiG9w0B
# AQwFAAOCAQEASaxexYPzWsthKk2XShUpn+QUkKoJ+cR6nzUYigozFW1yhyJOQT9t
# Cp4YrtviX/yV0SyYFDuOwfA2WXnzjYHPdPYYpOThaM/vf2VZQunKVTm808Um7nE4
# +tchAw+3TtlbYGpDtH0J0GBh3artAF5OMh7gsmyePLLCu5jTkHZqaa0a3KiJ2lhP
# 0sKLMkrOVPs46TsHC3UKEdsLfCUn8awmzxFT5tzG4mE1MvTO3YPjGTrrwmijcgDI
# JDxOuFM8sRer5jUs+dNCKeZfYAOsQmGmsVdqM0LfNTGGyj43K9rE2iT1ThLytrm3
# R+q7IK1hFregM+Mtiae8szwBfyMagAk06TCCBYEwggRpoAMCAQICEDlyRDr5IrdR
# 19NsEN0xNZUwDQYJKoZIhvcNAQEMBQAwezELMAkGA1UEBhMCR0IxGzAZBgNVBAgM
# EkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBwwHU2FsZm9yZDEaMBgGA1UECgwR
# Q29tb2RvIENBIExpbWl0ZWQxITAfBgNVBAMMGEFBQSBDZXJ0aWZpY2F0ZSBTZXJ2
# aWNlczAeFw0xOTAzMTIwMDAwMDBaFw0yODEyMzEyMzU5NTlaMIGIMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKTmV3IEplcnNleTEUMBIGA1UEBxMLSmVyc2V5IENpdHkx
# HjAcBgNVBAoTFVRoZSBVU0VSVFJVU1QgTmV0d29yazEuMCwGA1UEAxMlVVNFUlRy
# dXN0IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTCCAiIwDQYJKoZIhvcNAQEB
# BQADggIPADCCAgoCggIBAIASZRc2DsPbCLPQrFcNdu3NJ9NMrVCDYeKqIE0JLWQJ
# 3M6Jn8w9qez2z8Hc8dOx1ns3KBErR9o5xrw6GbRfpr19naNjQrZ28qk7K5H44m/Q
# 7BYgkAk+4uh0yRi0kdRiZNt/owbxiBhqkCI8vP4T8IcUe/bkH47U5FHGEWdGCFHL
# hhRUP7wz/n5snP8WnRi9UY41pqdmyHJn2yFmsdSbeAPAUDrozPDcvJ5M/q8FljUf
# V1q3/875PbcstvZU3cjnEjpNrkyKt1yatLcgPcp/IjSufjtoZgFE5wFORlObM2D3
# lL5TN5BzQ/Myw1Pv26r+dE5px2uMYJPexMcM3+EyrsyTO1F4lWeL7j1W/gzQaQ8b
# D/MlJmszbfduR/pzQ+V+DqVmsSl8MoRjVYnEDcGTVDAZE6zTfTen6106bDVc20HX
# EtqpSQvf2ICKCZNijrVmzyWIzYS4sT+kOQ/ZAp7rEkyVfPNrBaleFoPMuGfi6BOd
# zFuC00yz7Vv/3uVzrCM7LQC/NVV0CUnYSVgaf5I25lGSDvMmfRxNF7zJ7EMm0L9B
# X0CpRET0medXh55QH1dUqD79dGMvsVBlCeZYQi5DGky08CVHWfoEHpPUJkZKUIGy
# 3r54t/xnFeHJV4QeD2PW6WK61l9VLupcxigIBCU5uA4rqfJMlxwHPw1S9e3vL4IP
# AgMBAAGjgfIwge8wHwYDVR0jBBgwFoAUoBEKIz6W8Qfs4q8p74Klf9AwpLQwHQYD
# VR0OBBYEFFN5v1qqK0rPVIDh2JvAnfKyA2bLMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBEGA1UdIAQKMAgwBgYEVR0gADBDBgNVHR8EPDA6MDigNqA0
# hjJodHRwOi8vY3JsLmNvbW9kb2NhLmNvbS9BQUFDZXJ0aWZpY2F0ZVNlcnZpY2Vz
# LmNybDA0BggrBgEFBQcBAQQoMCYwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmNv
# bW9kb2NhLmNvbTANBgkqhkiG9w0BAQwFAAOCAQEAGIdR3HQhPZyK4Ce3M9AuzOzw
# 5steEd4ib5t1jp5y/uTW/qofnJYt7wNKfq70jW9yPEM7wD/ruN9cqqnGrvL82O6j
# e0P2hjZ8FODN9Pc//t64tIrwkZb+/UNkfv3M0gGhfX34GRnJQisTv1iLuqSiZgR2
# iJFODIkUzqJNyTKzuugUGrxx8VvwQQuYAAoiAxDlDLH5zZI3Ge078eQ6tvlFEyZ1
# r7uq7z97dzvSxAKRPRkA0xdcOds/exgNRc2ThZYvXd9ZFk8/Ub3VRRg/7UqO6AZh
# dCMWtQ1QcydER38QXYkqa4UxFMToqWpMgLxqeM+4f452cpkMnf7XkQgWoaNflTCC
# BfUwggPdoAMCAQICEB2iSDBvmyYY0ILgln0z02owDQYJKoZIhvcNAQEMBQAwgYgx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpOZXcgSmVyc2V5MRQwEgYDVQQHEwtKZXJz
# ZXkgQ2l0eTEeMBwGA1UEChMVVGhlIFVTRVJUUlVTVCBOZXR3b3JrMS4wLAYDVQQD
# EyVVU0VSVHJ1c3QgUlNBIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4XDTE4MTEw
# MjAwMDAwMFoXDTMwMTIzMTIzNTk1OVowfDELMAkGA1UEBhMCR0IxGzAZBgNVBAgT
# EkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UEChMP
# U2VjdGlnbyBMaW1pdGVkMSQwIgYDVQQDExtTZWN0aWdvIFJTQSBDb2RlIFNpZ25p
# bmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCGIo0yhXoYn0nw
# li9jCB4t3HyfFM/jJrYlZilAhlRGdDFixRDtsocnppnLlTDAVvWkdcapDlBipVGR
# EGrgS2Ku/fD4GKyn/+4uMyD6DBmJqGx7rQDDYaHcaWVtH24nlteXUYam9CflfGqL
# lR5bYNV+1xaSnAAvaPeX7Wpyvjg7Y96Pv25MQV0SIAhZ6DnNj9LWzwa0VwW2TqE+
# V2sfmLzEYtYbC43HZhtKn52BxHJAteJf7wtF/6POF6YtVbC3sLxUap28jVZTxvC6
# eVBJLPcDuf4vZTXyIuosB69G2flGHNyMfHEo8/6nxhTdVZFuihEN3wYklX0Pp6F8
# OtqGNWHTAgMBAAGjggFkMIIBYDAfBgNVHSMEGDAWgBRTeb9aqitKz1SA4dibwJ3y
# sgNmyzAdBgNVHQ4EFgQUDuE6qFM6MdWKvsG7rWcaA4WtNA4wDgYDVR0PAQH/BAQD
# AgGGMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0lBBYwFAYIKwYBBQUHAwMGCCsG
# AQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRw
# Oi8vY3JsLnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1
# dGhvcml0eS5jcmwwdgYIKwYBBQUHAQEEajBoMD8GCCsGAQUFBzAChjNodHRwOi8v
# Y3J0LnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0UlNBQWRkVHJ1c3RDQS5jcnQwJQYI
# KwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20wDQYJKoZIhvcNAQEM
# BQADggIBAE1jUO1HNEphpNveaiqMm/EAAB4dYns61zLC9rPgY7P7YQCImhttEAcE
# T7646ol4IusPRuzzRl5ARokS9At3WpwqQTr81vTr5/cVlTPDoYMot94v5JT3hTOD
# LUpASL+awk9KsY8k9LOBN9O3ZLCmI2pZaFJCX/8E6+F0ZXkI9amT3mtxQJmWunjx
# ucjiwwgWsatjWsgVgG10Xkp1fqW4w2y1z99KeYdcx0BNYzX2MNPPtQoOCwR/oEuu
# u6Ol0IQAkz5TXTSlADVpbL6fICUQDRn7UJBhvjmPeo5N9p8OHv4HURJmgyYZSJXO
# SsnBf/M6BZv5b9+If8AjntIeQ3pFMcGcTanwWbJZGehqjSkEAnd8S0vNcL46slVa
# eD68u28DECV3FTSK+TbMQ5Lkuk/xYpMoJVcp+1EZx6ElQGqEV8aynbG8HArafGd+
# fS7pKEwYfsR7MUFxmksp7As9V1DSyt39ngVR5UR43QHesXWYDVQk/fBO4+L4g71y
# uss9Ou7wXheSaG3IYfmm8SoKC6W59J7umDIFhZ7r+YMp08Ysfb06dy6LN0KgaoLt
# O0qqlBCk4Q34F8W2WnkzGJLjtXX4oemOCiUe5B7xn1qHI/+fpFGe+zmAEc3btcSn
# qIBv5VPU4OOiwtJbGvoyJi1qV3AcPKRYLqPzW0sH3DJZ84enGm1YMIIGWTCCBEGg
# AwIBAgINAewckkDe/S5AXXxHdDANBgkqhkiG9w0BAQwFADBMMSAwHgYDVQQLExdH
# bG9iYWxTaWduIFJvb3QgQ0EgLSBSNjETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEG
# A1UEAxMKR2xvYmFsU2lnbjAeFw0xODA2MjAwMDAwMDBaFw0zNDEyMTAwMDAwMDBa
# MFsxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYD
# VQQDEyhHbG9iYWxTaWduIFRpbWVzdGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0MIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA8ALiMCP64BvhmnSzr3WDX6lH
# UsdhOmN8OSN5bXT8MeR0EhmW+s4nYluuB4on7lejxDXtszTHrMMM64BmbdEoSsEs
# u7lw8nKujPeZWl12rr9EqHxBJI6PusVP/zZBq6ct/XhOQ4j+kxkX2e4xz7yKO25q
# xIjw7pf23PMYoEuZHA6HpybhiMmg5ZninvScTD9dW+y279Jlz0ULVD2xVFMHi5lu
# uFSZiqgxkjvyen38DljfgWrhsGweZYIq1CHHlP5CljvxC7F/f0aYDoc9emXr0Vap
# Lr37WD21hfpTmU1bdO1yS6INgjcZDNCr6lrB7w/Vmbk/9E818ZwP0zcTUtklNO2W
# 7/hn6gi+j0l6/5Cx1PcpFdf5DV3Wh0MedMRwKLSAe70qm7uE4Q6sbw25tfZtVv6K
# HQk+JA5nJsf8sg2glLCylMx75mf+pliy1NhBEsFV/W6RxbuxTAhLntRCBm8bGNU2
# 6mSuzv31BebiZtAOBSGssREGIxnk+wU0ROoIrp1JZxGLguWtWoanZv0zAwHemSX5
# cW7pnF0CTGA8zwKPAf1y7pLxpxLeQhJN7Kkm5XcCrA5XDAnRYZ4miPzIsk3bZPBF
# n7rBP1Sj2HYClWxqjcoiXPYMBOMp+kuwHNM3dITZHWarNHOPHn18XpbWPRmwl+qM
# UJFtr1eGfhA3HWsaFN8CAwEAAaOCASkwggElMA4GA1UdDwEB/wQEAwIBhjASBgNV
# HRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBTqFsZp5+PLV0U5M6TwQL7Qw71lljAf
# BgNVHSMEGDAWgBSubAWjkxPioufi1xzWx/B/yGdToDA+BggrBgEFBQcBAQQyMDAw
# LgYIKwYBBQUHMAGGImh0dHA6Ly9vY3NwMi5nbG9iYWxzaWduLmNvbS9yb290cjYw
# NgYDVR0fBC8wLTAroCmgJ4YlaHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9yb290
# LXI2LmNybDBHBgNVHSAEQDA+MDwGBFUdIAAwNDAyBggrBgEFBQcCARYmaHR0cHM6
# Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wDQYJKoZIhvcNAQEMBQAD
# ggIBAH/iiNlXZytCX4GnCQu6xLsoGFbWTL/bGwdwxvsLCa0AOmAzHznGFmsZQEkl
# CB7km/fWpA2PHpbyhqIX3kG/T+G8q83uwCOMxoX+SxUk+RhE7B/CpKzQss/swlZl
# Hb1/9t6CyLefYdO1RkiYlwJnehaVSttixtCzAsw0SEVV3ezpSp9eFO1yEHF2cNIP
# lvPqN1eUkRiv3I2ZOBlYwqmhfqJuFSbqtPl/KufnSGRpL9KaoXL29yRLdFp9coY1
# swJXH4uc/LusTN763lNMg/0SsbZJVU91naxvSsguarnKiMMSME6yCHOfXqHWmc7p
# fUuWLMwWaxjN5Fk3hgks4kXWss1ugnWl2o0et1sviC49ffHykTAFnM57fKDFrK9R
# BvARxx0wxVFWYOh8lT0i49UKJFMnl4D6SIknLHniPOWbHuOqhIKJPsBK9SH+YhDt
# HTD89szqSCd8i3VCf2vL86VrlR8EWDQKie2CUOTRe6jJ5r5IqitV2Y23JSAOG1Gg
# 1GOqg+pscmFKyfpDxMZXxZ22PLCLsLkcMe+97xTYFEBsIB3CLegLxo1tjLZx7VIh
# /j72n585Gq6s0i96ILH0rKod4i0UnfqWah3GPMrz2Ry/U02kR1l8lcRDQfkl4iwQ
# foH5DZSnffK1CfXYYHJAUJUg1ENEvvqglecgWbZ4xqRqqiKbMIIGZTCCBE2gAwIB
# AgIQAYTTqM43getX9P2He4OusjANBgkqhkiG9w0BAQsFADBbMQswCQYDVQQGEwJC
# RTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTExMC8GA1UEAxMoR2xvYmFsU2ln
# biBUaW1lc3RhbXBpbmcgQ0EgLSBTSEEzODQgLSBHNDAeFw0yMTA1MjcxMDAwMTZa
# Fw0zMjA2MjgxMDAwMTVaMGMxCzAJBgNVBAYTAkJFMRkwFwYDVQQKDBBHbG9iYWxT
# aWduIG52LXNhMTkwNwYDVQQDDDBHbG9iYWxzaWduIFRTQSBmb3IgTVMgQXV0aGVu
# dGljb2RlIEFkdmFuY2VkIC0gRzQwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGK
# AoIBgQDiopu2Sfs0SCgjB4b9UhNNusuqNeL5QBwbe2nFmCrMyVzvJ8bsuCVlwz8d
# ROfe4QjvBBcAlZcM/dtdg7SI66COm0+DuvnfXhhUagIODuZU8DekHpxnMQW1N3F8
# en7YgWUz5JrqsDE3x2a0o7oFJ+puUoJY2YJWJI3567MU+2QAoXsqH3qeqGOR5tjR
# IsY/0p04P6+VaVsnv+hAJJnHH9l7kgUCfSjGPDn3es33ZSagN68yBXeXauEQG5iF
# LISt5SWGfHOezYiNSyp6nQ9Zeb3y2jZ+Zqwu+LuIl8ltefKz1NXMGvRPi0WVdvKH
# lYCOKHm6/cVwr7waFAKQfCZbEYtd9brkEQLFgRxmaEveaM6dDIhhqraUI53gpDxG
# XQRR2z9ZC+fsvtLZEypH70sSEm7INc/uFjK20F+FuE/yfNgJKxJewMLvEzFwNnPc
# 1ldU01dgnhwQlfDmqi8Qiht+yc2PzlBLHCWowBdkURULjM/XyV1KbEl0rlrxagZ1
# Pok3O5ECAwEAAaOCAZswggGXMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUBAf8EDDAK
# BggrBgEFBQcDCDAdBgNVHQ4EFgQUda8nP7jbmuxvHO7DamT2v4Q1sM4wTAYDVR0g
# BEUwQzBBBgkrBgEEAaAyAR4wNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xv
# YmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wCQYDVR0TBAIwADCBkAYIKwYBBQUHAQEE
# gYMwgYAwOQYIKwYBBQUHMAGGLWh0dHA6Ly9vY3NwLmdsb2JhbHNpZ24uY29tL2Nh
# L2dzdHNhY2FzaGEzODRnNDBDBggrBgEFBQcwAoY3aHR0cDovL3NlY3VyZS5nbG9i
# YWxzaWduLmNvbS9jYWNlcnQvZ3N0c2FjYXNoYTM4NGc0LmNydDAfBgNVHSMEGDAW
# gBTqFsZp5+PLV0U5M6TwQL7Qw71lljBBBgNVHR8EOjA4MDagNKAyhjBodHRwOi8v
# Y3JsLmdsb2JhbHNpZ24uY29tL2NhL2dzdHNhY2FzaGEzODRnNC5jcmwwDQYJKoZI
# hvcNAQELBQADggIBADiTt301iTTqGtaqes6NhNvhNLd0pf/YXZQ2JY/SgH6hZbGb
# zzVRXdugS273IUAu7E9vFkByHHUbMAAXOY/IL6RxziQzJpDV5P85uWHvC8o58y1e
# jaD/TuFWZB/UnHYEpERcPWKFcC/5TqT3hlbbekkmQy0Fm+LDibc6oS0nJxjGQ4vc
# Q6G2ci0/2cY0igLTYjkp8H0o0KnDZIpGbbNDHHSL3bmmCyF7EacfXaLbjOBV02n6
# d9FdFLmW7JFFGxtsfkJAJKTtQMZl+kGPSDGc47izF1eCecrMHsLQT08FDg1512nd
# laFxXYqe51rCT6gGDwiJe9tYyCV9/2i8KKJwnLsMtVPojgaxsoKBhxKpXndMk6sY
# +ERXWBHL9pMVSTG3U1Ah2tX8YH/dMMWsUUQLZ6X61nc0rRIfKPuI2lGbRJredw7u
# MhJgVgyRnViPvJlX8r7NucNzJBnad6bk7PHeb+C8hB1vw/Hb4dVCUYZREkImPtPq
# E/QonK1NereiuhRqP0BVWE6MZRyz9nXWf64PhIAvvoh4XCcfRxfCPeRpnsuunu8C
# aIg3EMJsJorIjGWQU02uXdq4RhDUkAqK//QoQIHgUsjyAWRIGIR4aiL6ypyqDh3F
# jnLDNiIZ6/iUH7/CxQFW6aaA6gEdEzUH4rl0FP2aOJ4D0kn2TOuhvRwU0uOZMYIF
# pzCCBaMCAQEwgZEwfDELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFu
# Y2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEYMBYGA1UEChMPU2VjdGlnbyBMaW1p
# dGVkMSQwIgYDVQQDExtTZWN0aWdvIFJTQSBDb2RlIFNpZ25pbmcgQ0ECEQDo5ve9
# dmRLmtEkAVmMpN8SMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgACh
# AoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAM
# BgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRMoOcJlKBo+VggsVZQTsOJHA+O
# VjANBgkqhkiG9w0BAQEFAASCAQCMTtL3QAmCbVHmqLtLsARtNbdCU6Qk85TmoTzl
# umJXEKbr8xJ2zOZ6Z++icrQbCXCffQ0HXyXQ6dEjwEgHcZgpSPQIeWesvkRlauml
# SM8cn1wMq8F7J7eN9xbCSmQynC3XBSecWOu1rBqRj7suYICRMIyo9TMX/s2d8xvq
# hkZ8LEXWM0HduNd1Ae1sIfpRfZDQsbE2raOrHEr0H94KLCVm9K44hcgNMQlJgWxq
# BIpYrwZfXeKtW2Y4q4o8lvT42AXf8M5YJg1VlGNR1FnWHszLrRkldJJ1Wh8RhWch
# ZEROAHEqaT6KfKQFRbh9A8elvF6j6/8GXzdXJT5wXGfJjO6OoYIDcDCCA2wGCSqG
# SIb3DQEJBjGCA10wggNZAgEBMG8wWzELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEds
# b2JhbFNpZ24gbnYtc2ExMTAvBgNVBAMTKEdsb2JhbFNpZ24gVGltZXN0YW1waW5n
# IENBIC0gU0hBMzg0IC0gRzQCEAGE06jON4HrV/T9h3uDrrIwDQYJYIZIAWUDBAIB
# BQCgggE/MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8X
# DTIxMDgxMjA1MjYyMVowLQYJKoZIhvcNAQk0MSAwHjANBglghkgBZQMEAgEFAKEN
# BgkqhkiG9w0BAQsFADAvBgkqhkiG9w0BCQQxIgQgnV1UR0Ov8nVSHUxlJ/S6xDIL
# 7+F99PimSHsKAzXlxfUwgaQGCyqGSIb3DQEJEAIMMYGUMIGRMIGOMIGLBBTdV7Wz
# hzyGGynGrsRzGvvojXXBSTBzMF+kXTBbMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQ
# R2xvYmFsU2lnbiBudi1zYTExMC8GA1UEAxMoR2xvYmFsU2lnbiBUaW1lc3RhbXBp
# bmcgQ0EgLSBTSEEzODQgLSBHNAIQAYTTqM43getX9P2He4OusjANBgkqhkiG9w0B
# AQsFAASCAYCbyAo8bbWP5sizWWzZafaEfsgisqiZyS2p4Lk9FR+ObfsVToJR0UT1
# P0f8MTkaozI8XrmOWR/3GKBOAJdRU94tBEVL9TcMIRoy1wsaz2t1eG/5gsB3GE8e
# NHMgnnWyE5OLJ4zVR29Axy6RhB313GSpPi+v+/CbTxAqz7yr0qcDQ4seeqJmZnx7
# wqbeVvtTulZmYVZ7zIFxME8OMXt+04acYi0lm0Q/dlYCKonjXD/X8UCxnBZFWWhW
# gSYYJSkEo/l7DQcncRdyqwQhQNtGOURxgfYA0U+iYaxQEaRfdKd7QC0MENRHeRvw
# oE7kZpSliYDSOifvNsjZgwPxZxDCbcG8WFrwYusVLdgTV1dYjivIHzk3KpoXvW/N
# /jzZJF545H7EslyOdV/Hk79nIkUJT4nSk1y6BcvOfKUQmHJA8pNyyPyFSpraUN/B
# EYLrkVGr2tkuSQtiXK1zU2NnQaGTTZH4Y0mAchy9Vw34ENEoO6bkIP9R6djuV4xu
# PwyN2hVmMcg=
# SIG # End signature block
