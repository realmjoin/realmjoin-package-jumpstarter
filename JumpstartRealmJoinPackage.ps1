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

# SIG # Begin signature block
# MIIm+wYJKoZIhvcNAQcCoIIm7DCCJugCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAw7FPGuurmcKrB
# U2UWcexjSCYDo8LWz+3Svx9fsCUsAKCCDpgwggboMIIE0KADAgECAhB3vQ4Ft1kL
# th1HYVMeP3XtMA0GCSqGSIb3DQEBCwUAMFMxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMSkwJwYDVQQDEyBHbG9iYWxTaWduIENvZGUgU2ln
# bmluZyBSb290IFI0NTAeFw0yMDA3MjgwMDAwMDBaFw0zMDA3MjgwMDAwMDBaMFwx
# CzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQD
# EylHbG9iYWxTaWduIEdDQyBSNDUgRVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMsg75ceuQEyQ6BbqYoj/SBerjgS
# i8os1P9B2BpV1BlTt/2jF+d6OVzA984Ro/ml7QH6tbqT76+T3PjisxlMg7BKRFAE
# eIQQaqTWlpCOgfh8qy+1o1cz0lh7lA5tD6WRJiqzg09ysYp7ZJLQ8LRVX5YLEeWa
# tSyyEc8lG31RK5gfSaNf+BOeNbgDAtqkEy+FSu/EL3AOwdTMMxLsvUCV0xHK5s2z
# BZzIU+tS13hMUQGSgt4T8weOdLqEgJ/SpBUO6K/r94n233Hw0b6nskEzIHXMsdXt
# HQcZxOsmd/KrbReTSam35sOQnMa47MzJe5pexcUkk2NvfhCLYc+YVaMkoog28vmf
# vpMusgafJsAMAVYS4bKKnw4e3JiLLs/a4ok0ph8moKiueG3soYgVPMLq7rfYrWGl
# r3A2onmO3A1zwPHkLKuU7FgGOTZI1jta6CLOdA6vLPEV2tG0leis1Ult5a/dm2tj
# IF2OfjuyQ9hiOpTlzbSYszcZJBJyc6sEsAnchebUIgTvQCodLm3HadNutwFsDeCX
# pxbmJouI9wNEhl9iZ0y1pzeoVdwDNoxuz202JvEOj7A9ccDhMqeC5LYyAjIwfLWT
# yCH9PIjmaWP47nXJi8Kr77o6/elev7YR8b7wPcoyPm593g9+m5XEEofnGrhO7izB
# 36Fl6CSDySrC/blTAgMBAAGjggGtMIIBqTAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUJZ3Q
# /FkJhmPF7POxEztXHAOSNhEwHwYDVR0jBBgwFoAUHwC/RoAK/Hg5t6W0Q9lWULvO
# ljswgZMGCCsGAQUFBwEBBIGGMIGDMDkGCCsGAQUFBzABhi1odHRwOi8vb2NzcC5n
# bG9iYWxzaWduLmNvbS9jb2Rlc2lnbmluZ3Jvb3RyNDUwRgYIKwYBBQUHMAKGOmh0
# dHA6Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0L2NvZGVzaWduaW5ncm9v
# dHI0NS5jcnQwQQYDVR0fBDowODA2oDSgMoYwaHR0cDovL2NybC5nbG9iYWxzaWdu
# LmNvbS9jb2Rlc2lnbmluZ3Jvb3RyNDUuY3JsMFUGA1UdIAROMEwwQQYJKwYBBAGg
# MgECMDQwMgYIKwYBBQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNpZ24uY29tL3Jl
# cG9zaXRvcnkvMAcGBWeBDAEDMA0GCSqGSIb3DQEBCwUAA4ICAQAldaAJyTm6t6E5
# iS8Yn6vW6x1L6JR8DQdomxyd73G2F2prAk+zP4ZFh8xlm0zjWAYCImbVYQLFY4/U
# ovG2XiULd5bpzXFAM4gp7O7zom28TbU+BkvJczPKCBQtPUzosLp1pnQtpFg6bBNJ
# +KUVChSWhbFqaDQlQq+WVvQQ+iR98StywRbha+vmqZjHPlr00Bid/XSXhndGKj0j
# fShziq7vKxuav2xTpxSePIdxwF6OyPvTKpIz6ldNXgdeysEYrIEtGiH6bs+XYXvf
# cXo6ymP31TBENzL+u0OF3Lr8psozGSt3bdvLBfB+X3Uuora/Nao2Y8nOZNm9/Lws
# 80lWAMgSK8YnuzevV+/Ezx4pxPTiLc4qYc9X7fUKQOL1GNYe6ZAvytOHX5OKSBoR
# HeU3hZ8uZmKaXoFOlaxVV0PcU4slfjxhD4oLuvU/pteO9wRWXiG7n9dqcYC/lt5y
# A9jYIivzJxZPOOhRQAyuku++PX33gMZMNleElaeEFUgwDlInCI2Oor0ixxnJpsoO
# qHo222q6YV8RJJWk4o5o7hmpSZle0LQ0vdb5QMcQlzFSOTUpEYck08T7qWPLd0jV
# +mL8JOAEek7Q5G7ezp44UCb0IXFl1wkl1MkHAHq4x/N36MXU4lXQ0x72f1LiSY25
# EXIMiEQmM2YBRN/kMw4h3mKJSAfa9TCCB6gwggWQoAMCAQICDHdRb8udSSOFPOfC
# RDANBgkqhkiG9w0BAQsFADBcMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFs
# U2lnbiBudi1zYTEyMDAGA1UEAxMpR2xvYmFsU2lnbiBHQ0MgUjQ1IEVWIENvZGVT
# aWduaW5nIENBIDIwMjAwHhcNMjUxMTI3MTUzNzQ4WhcNMjcxMTI4MTUzNzQ4WjCC
# AQwxHTAbBgNVBA8MFFByaXZhdGUgT3JnYW5pemF0aW9uMRIwEAYDVQQFEwlIUkIg
# MTIzODExEzARBgsrBgEEAYI3PAIBAxMCREUxFzAVBgsrBgEEAYI3PAIBAhMGSGVz
# c2VuMSIwIAYLKwYBBAGCNzwCAQETEU9mZmVuYmFjaCBhbSBNYWluMQswCQYDVQQG
# EwJERTEPMA0GA1UECBMGSGVzc2VuMRowGAYDVQQHExFPZmZlbmJhY2ggYW0gTWFp
# bjEZMBcGA1UECQwQS2Fpc2Vyc3RyYcOfZSAzOTEXMBUGA1UEChMOZ2x1ZWNra2Fu
# amEgQUcxFzAVBgNVBAMTDmdsdWVja2thbmphIEFHMIICIjANBgkqhkiG9w0BAQEF
# AAOCAg8AMIICCgKCAgEAiol8Tdae3djHArCHiJ5uV9u/KQTvB0/81SJt581m0hIT
# LLB0kI89eAwPAYEV1nvcLafv2d0dkLUQ8200pnY/RYN75FxcLX4sl9kPPerqNQ8d
# XZTm44s0U0WWtAfqWmO/7Nr7LcQL3XAO7wVwFQ5heLRvmydcuMb9lepdnFtpIPHA
# 97skjNvrqZ603fbGYBlo2wjsomK+0jtJ+tEmAmD5iVhNIwZRb1ZP8hXcs/I38ZIC
# Ww0J5y2RbNrf5jGWNZzpABuZXXEUXlCoVDLtGrcynpu/AmDVzLb2sN8xsJm61Fqg
# MyG7wU83VqsckswOySZOg98dRx/Au6JP2MYvdpKfd4OzHz+e8c007NqQ339/acUE
# k915uwT+TBi8N1w7jU7lTK4oMa/aD1hVc92zGL21pbDNE8SDk9F8V6ZkG89muSUd
# wT5zRZ/novp2h2aRCgguD2v/CauK7ggAb0gWmgijt/rJXV1OBCWhqLi5fjsZLrGo
# 0mtDlscsh9V3+W/FchHNVWgWH2iwaW/VmCUhNEH36FDhWdWVme5YvkBuDce7A7OL
# jXO+kqfbPTcK9/gHrTMEBnFOE5SWylkbuf+e85+EnSc8qnHGjmIpY+ehCO7371e3
# hHrtz5rehWsUPlxy3xDtkFrLnYzUs5tD0kVt5qQPICAv9NfhMOsxZD5qOov4AyMC
# AwEAAaOCAbYwggGyMA4GA1UdDwEB/wQEAwIHgDCBnwYIKwYBBQUHAQEEgZIwgY8w
# TAYIKwYBBQUHMAKGQGh0dHA6Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0
# L2dzZ2NjcjQ1ZXZjb2Rlc2lnbmNhMjAyMC5jcnQwPwYIKwYBBQUHMAGGM2h0dHA6
# Ly9vY3NwLmdsb2JhbHNpZ24uY29tL2dzZ2NjcjQ1ZXZjb2Rlc2lnbmNhMjAyMDBV
# BgNVHSAETjBMMEEGCSsGAQQBoDIBAjA0MDIGCCsGAQUFBwIBFiZodHRwczovL3d3
# dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzAHBgVngQwBAzAJBgNVHRMEAjAA
# MEcGA1UdHwRAMD4wPKA6oDiGNmh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vZ3Nn
# Y2NyNDVldmNvZGVzaWduY2EyMDIwLmNybDATBgNVHSUEDDAKBggrBgEFBQcDAzAf
# BgNVHSMEGDAWgBQlndD8WQmGY8Xs87ETO1ccA5I2ETAdBgNVHQ4EFgQU0irzY9zZ
# lcKSxaxqbiVObGem0c4wDQYJKoZIhvcNAQELBQADggIBAMkTyhDy0N8Kz4L0ZVsd
# O26mRPvDhm9bu8zUnFj2CeFRqbYknoTYqmKRB02CdzYL4vJMHLIRQUQiuIHW3U0C
# tdhIIyhiOFwO+DujpkumR577lDB2Ew6Jjfy3fJAx4C+AknJJ91GX2qpspRXrPaK4
# 46dimmIfR7OEXfbEp7+3lFatXNI0XsoAAC9NKxMVXovR9YPZU98J60Ksp28yq5ef
# 3EFNCI1ySHlHj1gDUOhTdbICQv3+gmyyXEt0cK10PPtOEF7nC9B6WsRxidDQvmqk
# P/Jq4+nVKJAwVqbVi9eMIGXID2Q0GaVLwcHe07CY3+2ieVbM7IGpYDnxb+rEvPgC
# 05L8oYvSkd7CC9BHOV2K5cc6SviTy4j6Wlfhjy1q0wNJ3LqzwzFmyCX88qO3XD+k
# tkLT48lcjIYI+iwtBdAVc9/jGCXU4IGNJyjudvIm54cJHquTscOwxCtG+eW5iMxF
# p2yQCxLpzgLEghAiy1IZWH9u8y7oWJvlyAP70Zb6riYiAs42w/mClT0ODulcfqoo
# Nc5CuKM3ggZOhpF50Q4OJFXpMp825LuMjVGOiunzOlZcCA/sn4G6RUwFLsJNdL8l
# 4aTmxG/SmyCik1bbf390fPWsxZeUJs0Bs/aXU7zf0MOBMqSZS2eHmUpvJCjJ377O
# X9gKLMOy4ZOhctlhJ2D6pDtuMYIXuTCCF7UCAQEwbDBcMQswCQYDVQQGEwJCRTEZ
# MBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEyMDAGA1UEAxMpR2xvYmFsU2lnbiBH
# Q0MgUjQ1IEVWIENvZGVTaWduaW5nIENBIDIwMjACDHdRb8udSSOFPOfCRDANBglg
# hkgBZQMEAgEFAKBqMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQB
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCB6aBZP2Pt5Gg2q
# f4LBV5CAIfAatNeyUIsy0aTkEvT6XzANBgkqhkiG9w0BAQEFAASCAgCHdgd1XM6l
# /o/hp1ZGJEAFtr4Zrw9mPZWnjOFflvQvsMzfT9HwcJsvhEsACabH71dKxy+TqITq
# 0tSnxCGqROePZxgHp9yCs+zHRlysQcabaTrTspogggxurZ0psxiBq5KBUTrJsP0h
# sPWurZtVKXuIj+1NOvRE6+YjJ7jYBcFYZVjEXPm64T24NfuJkHWzu7362ZOSrXSN
# lvt7L/fr49OSqqX8ERTz7sPKl8xI67+QC9eXPPWNB2HwkIPxezRzNI1RK4QBPrER
# SuuyxgWL8Uo07lZjitCxzwIPpSM/JogKwr+sP7zNSL8Hj+Yz7ytP4hWq9n08U9AU
# lYxLsU/CQuBNlhvUhJO9F7cHkzfsZqtkXQ1vmT7PY5GqdLIVSgcUG6erhzp/OXCe
# Cb/KqG7aZnc3HRDzPuHKbvzm+2oXvL8vxxB4o7O2dc2TW/UmPZdRJlfNGVxBqTYE
# 0a+xtq5/Q4YKtT23SySIaHi6Uk8ICuJzP47cAVxqmo4whQYSkMdewSB9Iz1lwZtL
# N66/ojCR5Tpasi1/clCk+8Hf0yqELbZB5FaaDl5UretlW2KZAj/YN8k9e/chEOHd
# Xms+UuAvnSjeZZbltCjSoESeGPvZ07lMnLjtz56EM3HXFKBlp128Sb5c8Vx84GEd
# 2oMMclF+au8+DnHRkUISiIGAvhF30Emwx6GCFLIwghSuBgorBgEEAYI3AwMBMYIU
# njCCFJoGCSqGSIb3DQEHAqCCFIswghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFq
# BgsqhkiG9w0BCRABBKCCAVkEggFVMIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCG
# SAFlAwQCAQUABCAcH1CQ5k9P5JJyZLT7/fRIPBx5ZgeDivDyhqn0S0YFdgIGavNL
# Bqi1GBMyMDI2MTExNjE1NTUwNi43OTVaMASAAgH0oIHppIHmMIHjMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNT
# IEVTTjo3QjFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBS
# U0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHmggg8pMIIHgjCCBWqgAwIBAgITMwAA
# AAXlzw//Zi7JhwAAAAAABTANBgkqhkiG9w0BAQwFADB3MQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMUgwRgYDVQQDEz9NaWNyb3Nv
# ZnQgSWRlbnRpdHkgVmVyaWZpY2F0aW9uIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9y
# aXR5IDIwMjAwHhcNMjAxMTE5MjAzMjMxWhcNMzUxMTE5MjA0MjMxWjBhMQswCQYD
# VQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQD
# EylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJ5851Jj/eDFnwV9Y7UGIqMcHtfn
# lzPREwW9ZUZHd5HBXXBvf7KrQ5cMSqFSHGqg2/qJhYqOQxwuEQXG8kB41wsDJP5d
# 0zmLYKAY8Zxv3lYkuLDsfMuIEqvGYOPURAH+Ybl4SJEESnt0MbPEoKdNihwM5xGv
# 0rGofJ1qOYSTNcc55EbBT7uq3wx3mXhtVmtcCEr5ZKTkKKE1CxZvNPWdGWJUPC6e
# 4uRfWHIhZcgCsJ+sozf5EeH5KrlFnxpjKKTavwfFP6XaGZGWUG8TZaiTogRoAlqc
# evbiqioUz1Yt4FRK53P6ovnUfANjIgM9JDdJ4e0qiDRm5sOTiEQtBLGd9Vhd1Mad
# xoGcHrRCsS5rO9yhv2fjJHrmlQ0EIXmp4DhDBieKUGR+eZ4CNE3ctW4uvSDQVeSp
# 9h1SaPV8UWEfyTxgGjOsRpeexIveR1MPTVf7gt8hY64XNPO6iyUGsEgt8c2PxF87
# E+CO7A28TpjNq5eLiiunhKbq0XbjkNoU5JhtYUrlmAbpxRjb9tSreDdtACpm3rkp
# xp7AQndnI0Shu/fk1/rE3oWsDqMX3jjv40e8KN5YsJBnczyWB4JyeeFMW3JBfdeA
# KhzohFe8U5w9WuvcP1E8cIxLoKSDzCCBOu0hWdjzKNu8Y5SwB1lt5dQhABYyzR3d
# xEO/T1K/BVF3rV69AgMBAAGjggIbMIICFzAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYB
# BAGCNxUBBAMCAQAwHQYDVR0OBBYEFGtpKDo1L0hjQM972K9J6T7ZPdshMFQGA1Ud
# IARNMEswSQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB
# /zAfBgNVHSMEGDAWgBTIftJqhSobyhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5
# oHegdYZzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9z
# b2Z0JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNh
# dGUlMjBBdXRob3JpdHklMjAyMDIwLmNybDCBlAYIKwYBBQUHAQEEgYcwgYQwgYEG
# CCsGAQUFBzAChnVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRz
# L01pY3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENl
# cnRpZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcnQwDQYJKoZIhvcNAQEMBQAD
# ggIBAF+Idsd+bbVaFXXnTHho+k7h2ESZJRWluLE0Oa/pO+4ge/XEizXvhs0Y7+KV
# Yyb4nHlugBesnFqBGEdC2IWmtKMyS1OWIviwpnK3aL5JedwzbeBF7POyg6IGG/Xh
# hJ3UqWeWTO+Czb1c2NP5zyEh89F72u9UIw+IfvM9lzDmc2O2END7MPnrcjWdQnrL
# n1Ntday7JSyrDvBdmgbNnCKNZPmhzoa8PccOiQljjTW6GePe5sGFuRHzdFt8y+bN
# 2neF7Zu8hTO1I64XNGqst8S+w+RUdie8fXC1jKu3m9KGIqF4aldrYBamyh3g4nJP
# j/LR2CBaLyD+2BuGZCVmoNR/dSpRCxlot0i79dKOChmoONqbMI8m04uLaEHAv4qw
# KHQ1vBzbV/nG89LDKbRSSvijmwJwxRxLLpMQ/u4xXxFfR4f/gksSkbJp7oqLwliD
# m/h+w0aJ/U5ccnYhYb7vPKNMN+SZDWycU5ODIRfyoGl59BsXR/HpRGtiJquOYGmv
# A/pk5vC1lcnbeMrcWD/26ozePQ/TWfNXKBOmkFpvPE8CH+EeGGWzqTCjdAsno2jz
# TeNSxlx3glDGJgcdz5D/AAxw9Sdgq/+rY7jjgs7X6fqPTXPmaCAJKVHAP19oEjJI
# BwD1LyHbaEgBxFCogYSOiUIr0Xqcr1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIB
# AgITMwAAAFl82nHpjV71wAAAAAAAWTANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQG
# EwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylN
# aWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAx
# MDgxODU5MDFaFw0yNzAxMDcxODU5MDFaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVy
# YXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3QjFBLTA1
# RTAtRDk0NzE1MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFt
# cGluZyBBdXRob3JpdHkwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCm
# Luf+NHhF/oU/uYxWteOm4nd3QOC512J7b5D9whsOCxgERYZ7yzEif1bbLm8w2nhZ
# 5u8m9ikjO9Fph0Ka3Qlaqb1B+5dLgeIzcO7qy6AEfZChyxNFZTJQ0rQ0sVASN6sL
# Ha473Zr1dJPvf547gxIkpcyU3+w6MHdSt2zuG3kcmhYUfmPLcphAjqpTgH32Kxts
# GXVTOdfkEgUnvjxMpK/Aujp56koqbhfH2bwm+v4bpNGZumcLGosUhyAE9iBBr0u3
# OtyJvI1d2vEdCuotsosNDTZZ00qcMv2X7+4sLCwcIX24wU5/lzpepj8w10EN1fkk
# T/cV2xijrAU8cxone2igB8N6OAIZfVBlix/ZDT91VKJBOiWJI5X6blBmeoEMqg3s
# H8Q+FaGCJaKbeB2dMUL6mo7icfnK/C0fyGeeoCy5sMjM3Xufr7YwaIpa8v4EmcFR
# sIJL5CIKSjwUBxrEgdMt7M6+2O8BG+r9MmWpdV1L1p5894p02klrAhayz1cFZl8t
# 53GOf3duVaTpIbfpuvexljW77DToQDh0Wn7RPY/4YZKDOkbMiXwS54ajHAP8HGr3
# +aI+TXskUHRmXiynJbPXLCkt7AVMz4nccdoojR/Qj2g6v2yyRDl2rGKIVzJ0Yp7v
# n1JPNbPFTuw0Ehen35+aKkh6FfJX9QMervpHUoW/AQIDAQABo4IByzCCAccwHQYD
# VR0OBBYEFI+W5wtfA9L5Z0kYQjojgxhrlzZ2MB8GA1UdIwQYMBaAFGtpKDo1L0hj
# QM972K9J6T7ZPdshMGwGA1UdHwRlMGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRp
# bWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsG
# AQUFBzAChl1odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCB4AwZgYDVR0gBF8wXTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9z
# aXRvcnkuaHRtMAgGBmeBDAEEAjANBgkqhkiG9w0BAQwFAAOCAgEARDIcwv2XI6Rv
# 81ERO89mKeb61MVI7BOV2t7f9kRrxEsL25rJN2yx4UhQGo4KNl0PMaBgz97FISgi
# z3iAkm5Fb+lfLEqfHyfCaLOsq2sH9mFYrPLXFfjju1PUuiRj0M6Zj53H80HOJ3tX
# 6mePh4immyAxKBXXXUE9hIJJPX88QmPxGedmrydu3Un6yPyA5sp/VddDt4kKYNhf
# gvbzU65O51YKA6B2vfkN6WK9CBxp0preYq4Bk+N+s6OVp1z/BcTIbMB9WosokmYl
# c4aK9dAvQudnD9wvPzxKDClF7LS46DztEzJHlv9Ra9fOilw+OUEYAaNMSJoLVk3c
# 1hZ5Q/qe/ogwSLkqzXEVw0WLqv2mGWg4VkiNEmHTyFlYeV717lgN9WvKENEjvqD2
# tzZPNJNPOuMIosidSrG0p2mnn4Pb7KXoIa6WPJYwsMXwlLceR0ETYACTiPCCgAiu
# HdNeDJNIZUTtJUFUR3oKiINvSul6pHN+tFtmSRlHLLZSqJJFY+igB4xsqy0T83qW
# H4mVCauIF8sW6bym9VydhTduvNmlKDV6PUckStXIdH+upOvso/PJM77gu/ryVrTQ
# 7P1KSDOh4ZtJFOuCVCezDBEHAHO5KX7expu2HkSvqCoKlIGFwn5s21/JyVyWZz2v
# AA1lbCKrLjQMQiNAmV5FC6H6qOQXus8xggPUMIID0AIBATB4MGExCzAJBgNVBAYT
# AlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1p
# Y3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAWXza
# cemNXvXAAAAAAABZMA0GCWCGSAFlAwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYL
# KoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIHwtyY0AG8VQgzR5aI+r8wMdtf5V
# zp+tdNoqVLNNwtbpMIHdBgsqhkiG9w0BCRACLzGBzTCByjCBxzCBoAQgy0W6sduG
# 6bHFxCfh44/ca3FFcO0fDssjH0gdmBit/rwwfDBlpGMwYTELMAkGA1UEBhMCVVMx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9z
# b2Z0IFB1YmxpYyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjACEzMAAABZfNpx6Y1e
# 9cAAAAAAAFkwIgQgxrEARZEbLfa50NbzjhohEGU109eHnCgoHXOXmP4fD8gwDQYJ
# KoZIhvcNAQELBQAEggIAdm3+YrAYYVkC0hQi0nvd0VCjIlHe6esBfBpR7AW/Z7dX
# RKuNicXSvwt1z5aqqQ7VsjjDUoXSdzxVlx1WdpYyNXU+x4vlac5oRs6+LYUR9Fag
# yK4CcdaXnJWwQYurYR91nJeu9KRGidNH3tAskipjWXPZjkec5mNWkYqYcUMc5Qv4
# lg3habAIyZaeQQQRtDq0nixzAf092nbNP9MNMWn5EBD9s6i7g7sLggT2NBl2PHwi
# 5yfnBDr4J/VTvcNo+WP63Nv/SrjfTEiFOlZVzocv1BiV5IANRcwDpulSRq1gyFs+
# FoloIdpY9J1g2FpXI3/XyEB67eEzQTcp3UIFPhKjoDAn8VnpCmOKeK2za/bTZ/IP
# RD/epr40ZRmifN1+t/6OIwsXXzsXwPQBP0T+gngHymGNJ8x0XRp0BX6G7YMNvNXi
# YWmInaIdf0B24m9PPWJQtZSMlX5zz0JsQC4JzWqSrJrCJHfh9ARImgyMJGnhBmmt
# GELp2KhDOEO0aDSvyi9TsBGYC492GQ5EYAJl+Ch41LxFUIet4qWh9GwPYYmRLXiT
# bVZ+AWVaqpKAACALKSedW2tlPrl8YfOhq2h7N7ZuwuIHX+NsTmhKaDMVVz1c5QpX
# 5SzqPAaOCYUI1QVCQAYTiabamSo7r2839+Lpy8LfZK1LIwbulpKmhbwHuPGm1NI=
# SIG # End signature block
