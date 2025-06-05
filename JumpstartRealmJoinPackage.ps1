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
    while (-not $applicationName) {
        # we really need this, so we loop until we get it
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
    if ($repositoryName -inotlike "*macOS") { $repositoryName += " macOS" }
    if (-not $repositoryPath) {
        $repoPathDefault = ($repositoryName -ireplace '[-_ ]+', '-' -ireplace '[^a-z0-9-]').Trim('-').ToLowerInvariant()
        $repositoryPath = (Read-Host "Repository path (default: $repoPathDefault)").Trim()
        if (-not $repositoryPath) { $repositoryPath = $repoPathDefault }
    }
    if ($repositoryPath -inotlike "*macos") { $repositoryPath += "-macos" }
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
# MIIvTAYJKoZIhvcNAQcCoIIvPTCCLzkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCATC8Thhs4agIU0
# jb1Fq4WgqSUhEzHMGTjZhOVX6Lm/yqCCFDUwggWQMIIDeKADAgECAhAFmxtXno4h
# MuI5B72nd3VcMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0xMzA4MDExMjAwMDBaFw0z
# ODAxMTUxMjAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/z
# G6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZ
# anMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7s
# Wxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL
# 2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfb
# BHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3
# JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3c
# AORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqx
# YxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0
# viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aL
# T8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGjQjBAMA8GA1Ud
# EwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdDgQWBBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzANBgkqhkiG9w0BAQwFAAOCAgEAu2HZfalsvhfEkRvDoaIAjeNk
# aA9Wz3eucPn9mkqZucl4XAwMX+TmFClWCzZJXURj4K2clhhmGyMNPXnpbWvWVPjS
# PMFDQK4dUPVS/JA7u5iZaWvHwaeoaKQn3J35J64whbn2Z006Po9ZOSJTROvIXQPK
# 7VB6fWIhCoDIc2bRoAVgX+iltKevqPdtNZx8WorWojiZ83iL9E3SIAveBO6Mm0eB
# cg3AFDLvMFkuruBx8lbkapdvklBtlo1oepqyNhR6BvIkuQkRUNcIsbiJeoQjYUIp
# 5aPNoiBB19GcZNnqJqGLFNdMGbJQQXE9P01wI4YMStyB0swylIQNCAmXHE/A7msg
# dDDS4Dk0EIUhFQEI6FUy3nFJ2SgXUE3mvk3RdazQyvtBuEOlqtPDBURPLDab4vri
# RbgjU2wGb2dVf0a1TD9uKFp5JtKkqGKX0h7i7UqLvBv9R0oN32dmfrJbQdA75PQ7
# 9ARj6e/CVABRoIoqyc54zNXqhwQYs86vSYiv85KZtrPmYQ/ShQDnUBrkG5WdGaG5
# nLGbsQAe79APT0JsyQq87kP6OnGlyE0mpTX9iV28hWIdMtKgK1TtmlfB2/oQzxm3
# i0objwG2J5VT6LaJbVu8aNQj6ItRolb58KaAoNYes7wPD1N1KarqE3fk3oyBIa0H
# EEcRrYc9B9F1vM/zZn4wggawMIIEmKADAgECAhAIrUCyYNKcTJ9ezam9k67ZMA0G
# CSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0zNjA0MjgyMzU5NTla
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDVtC9C
# 0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0JAfhS0/TeEP0F9ce
# 2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJrQ5qZ8sU7H/Lvy0da
# E6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhFLqGfLOEYwhrMxe6T
# SXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+FLEikVoQ11vkunKoA
# FdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh3K3kGKDYwSNHR7Oh
# D26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJwZPt4bRc4G/rJvmM
# 1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQayg9Rc9hUZTO1i4F4z
# 8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbIYViY9XwCFjyDKK05
# huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchApQfDVxW0mdmgRQRNY
# mtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRroOBl8ZhzNeDhFMJlP
# /2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IBWTCCAVUwEgYDVR0T
# AQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHwYD
# VR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNV
# HR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAEDMAgGBmeBDAEEATAN
# BgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql+Eg08yy25nRm95Ry
# sQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFFUP2cvbaF4HZ+N3HL
# IvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1hmYFW9snjdufE5Btf
# Q/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3RywYFzzDaju4ImhvTnh
# OE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5UbdldAhQfQDN8A+KVssIh
# dXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw8MzK7/0pNVwfiThV
# 9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnPLqR0kq3bPKSchh/j
# wVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatEQOON8BUozu3xGFYH
# Ki8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bnKD+sEq6lLyJsQfmC
# XBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQjiWQ1tygVQK+pKHJ6l
# /aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbqyK+p/pQd52MbOoZW
# eE4wggfpMIIF0aADAgECAhAE0w/ewLw2E3KQ6RwmFyT5MA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwHhcNMjMxMTE2MDAwMDAwWhcNMjYxMTE1MjM1OTU5WjCB8TET
# MBEGCysGAQQBgjc8AgEDEwJERTEXMBUGCysGAQQBgjc8AgECEwZIZXNzZW4xIjAg
# BgsrBgEEAYI3PAIBARMRT2ZmZW5iYWNoIGFtIE1haW4xHTAbBgNVBA8MFFByaXZh
# dGUgT3JnYW5pemF0aW9uMRIwEAYDVQQFEwlIUkIgMTIzODExCzAJBgNVBAYTAkRF
# MQ8wDQYDVQQIEwZIZXNzZW4xGjAYBgNVBAcTEU9mZmVuYmFjaCBhbSBNYWluMRcw
# FQYDVQQKEw5nbHVlY2trYW5qYSBBRzEXMBUGA1UEAxMOZ2x1ZWNra2FuamEgQUcw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDOkzyWiAT0dzoCrdo4dTaE
# UjIJKcht/Gvb3OOJ/WpNQYJius0XbgOcyBu+7+yGANG0SKDbGxuy8gl6FDMkMKXS
# g4ukpw2GLeMNATJ+MBd5FL3MwTSyZS0SljlAbIdyo7ydBeCNrCqKsJoBLARTdxSu
# fsxRtgsEOM3AqkT51Z+oSb3fOpAvG3E6fj6ViQP2C37m3t9LvCzNJO6TQ94ylKFg
# WxOLmHlBnvBEK6wLsL3FRWl0avXTNvheH7XmY7vI9Othb469+V+FJVBbmD7SE0f5
# miAND4wpNGObz76r2TsHFcgTHah8EGKTJeo0+m3AM158ILT2cN35v8z7X4RbJ7L5
# k4eMFNoWKwPc72UPZKdlo0OQuutL5ehtFhopnB7WUUFCNV4+KQGYo9cKEeufGqV0
# xrIcdH409ejAuMleNZ4CLyU5LE5qVkYxLgdjDdCdxbk2ADSTOwQtpLJExnhf/jkc
# 9sRTys9i6NtpE+hb6xbAJ7p4vQt3iLMDQHy6l98HNJNlmY3Phvk0ViUIzRC7qgv7
# Fe+5bE6FkFc/J4rrx6AUTJek/WvkhbvJp39IvspHUxTYC34l9y8Dcnxk3XU2TASn
# JR6yKElD+OetRKE0rS9VcuL7kJrTY9det5Kv1hzoZj3zPqd5X+cqqV5hzE3aI3TP
# 1v0zICGYf5ayeA1zg9aCkQIDAQABo4ICAjCCAf4wHwYDVR0jBBgwFoAUaDfg67Y7
# +F8Rhvv+YXsIiGX0TkIwHQYDVR0OBBYEFOTb7LJoGHhU5+5fcQSNJKUzQX0kMD0G
# A1UdIAQ2MDQwMgYFZ4EMAQMwKTAnBggrBgEFBQcCARYbaHR0cDovL3d3dy5kaWdp
# Y2VydC5jb20vQ1BTMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzCBtQYDVR0fBIGtMIGqMFOgUaBPhk1odHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0Ex
# LmNybDBToFGgT4ZNaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1
# c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5jcmwwgZQGCCsG
# AQUFBwEBBIGHMIGEMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5j
# b20wXAYIKwYBBQUHMAKGUGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3J0
# MAkGA1UdEwQCMAAwDQYJKoZIhvcNAQELBQADggIBAMkcpd3bsp6QPtw6hZFySq8n
# 50F0KYvrGH0MnQipkz7lV5RvFjl/cBf5gRSrebMIV1rvQMttrFxC06Y3zTbU6t4E
# z1nDX76GZV7bmomreROITlH43UvsYacedTmiPp+SFDF5hjDz71XHaATzaSSL5puE
# GRrGCyEh2Y/tw823jtk7jDLZrjb74kbGIB21/uUkjOWkhNGN55rDa933sjJuoZx2
# /pVSSmHxo+Bvc3td67EY4ylZj4CsBHmr6afeGKtZFT/QtnilYq+5nARiCDVKSHP0
# svNpmOCDZJg+aaq+TBAtvu6ddAogZ4FHtpOFQ+NQZeO9jWNn/9bYDdBlwejQKPqZ
# 0p3oO+25FyYe8dxr1j82TyefL4mC486nVbSSk3XCu+LUKRmMkOh8cSKXyIP06RIz
# LWQSpS1zenI+DREJ6VJHI/pBhRZGr9i6gwOIVaKva2t/AnaCkI4ulJd8iq6/lI+z
# DvuLPjRqQOv2+Zf+1jbNV2I0BttmiFfXGDeAOCEaiF82lak6CcwkrGj3Hbt7YjuF
# Zd7qCJWHG4pVrpJhwEScp+1+kDLpWGlupiPJv4XDhKUEqJPQ2KGhMzE0JDd8V7Si
# 4gXvAoEZAPb1sjLcatDHYJX1acsAHEoYD2Um1Lx0pARy4LcHsTPrETz4EiiGg/iE
# qeoXQDjtJraR++BTJXQyMYIabTCCGmkCAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQg
# RzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0ExAhAE0w/ewLw2
# E3KQ6RwmFyT5MA0GCWCGSAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKA
# AKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEII0UyfeLhgQCdk8djW5BNvxF
# 9ntFdeCPV7qtIkbVOB7vMA0GCSqGSIb3DQEBAQUABIICABUVXWY5EZA4L3ywEva0
# xZYv1dahtBDimsZhyqpC/QnMCMicb+Ft3sYQhQshO9lz2gE7Y5J2Ku6LkO4uxg1k
# TKiSEHIz6v8or5e6pLqk3qvgeEFcDAfN36TPBJjvipE7wnLViaMfeNWiczqiQ0Nb
# 0EGs31T7sWoafq2LiTxDDcZYKDoAButwJnPfICVRVZwpsmiqD9O5cfZ0nKpmSLuz
# Zh8WYYCHFIevj6TmRx/qV4u0W9AITIaHGZnIEeOWfekb4ywaCzLCJL3p2FPTODBL
# Y8bC1Y7CAjqFZL6JYKpSM74WbFbmNwdiOeqr8oUzVLXBcvl3CEDKafXxB9/w+v6r
# ccTO1n2tz2ZxgQ8A3KmkfvHQudLyWpfnzDQJvFzVimvwTXiHi1GDn1mlaL4NYUip
# ASQS7QqYrBGMwcPgcigJE5PL0j/sPpmpSkmODkOQq197zQqHH1fh9YakcHbH/e6f
# fgCgT6g41JiYSFLlOTMZw+tL5LKSA3DdJ/c7mEiS2yySsmQPzJDZsQ3FTbM44ML1
# 3uIM4/aXafP38dgqhkAwdlMKewloOGIpsJMFWx/kqlfwrO9lg7I7iqTmTYwBGjKg
# afroilDQmFb9Q/hrpFg7yC7+m00RoOOFkAr42j1c1mFnxv7l9ggiMeC176j9DJkh
# EEcbJLgqNkzrJ3SOR27GqUnqoYIXOjCCFzYGCisGAQQBgjcDAwExghcmMIIXIgYJ
# KoZIhvcNAQcCoIIXEzCCFw8CAQMxDzANBglghkgBZQMEAgEFADB4BgsqhkiG9w0B
# CRABBKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAEINNWrwTr
# Kljh1M1lyw9j2wbnOAvR4S6TwvvQxkOlPEckAhEA9DCVneqMto6HWcH/jOtSRRgP
# MjAyNTA2MDUxNDM0MzJaoIITAzCCBrwwggSkoAMCAQICEAuuZrxaun+Vh8b56QTj
# MwQwDQYJKoZIhvcNAQELBQAwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYg
# U0hBMjU2IFRpbWVTdGFtcGluZyBDQTAeFw0yNDA5MjYwMDAwMDBaFw0zNTExMjUy
# MzU5NTlaMEIxCzAJBgNVBAYTAlVTMREwDwYDVQQKEwhEaWdpQ2VydDEgMB4GA1UE
# AxMXRGlnaUNlcnQgVGltZXN0YW1wIDIwMjQwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQC+anOf9pUhq5Ywultt5lmjtej9kR8YxIg7apnjpcH9CjAgQxK+
# CMR0Rne/i+utMeV5bUlYYSuuM4vQngvQepVHVzNLO9RDnEXvPghCaft0djvKKO+h
# Du6ObS7rJcXa/UKvNminKQPTv/1+kBPgHGlP28mgmoCw/xi6FG9+Un1h4eN6zh92
# 6SxMe6We2r1Z6VFZj75MU/HNmtsgtFjKfITLutLWUdAoWle+jYZ49+wxGE1/UXjW
# fISDmHuI5e/6+NfQrxGFSKx+rDdNMsePW6FLrphfYtk/FLihp/feun0eV+pIF496
# OVh4R1TvjQYpAztJpVIfdNsEvxHofBf1BWkadc+Up0Th8EifkEEWdX4rA/FE1Q0r
# qViTbLVZIqi6viEk3RIySho1XyHLIAOJfXG5PEppc3XYeBH7xa6VTZ3rOHNeiYnY
# +V4j1XbJ+Z9dI8ZhqcaDHOoj5KGg4YuiYx3eYm33aebsyF6eD9MF5IDbPgjvwmnA
# alNEeJPvIeoGJXaeBQjIK13SlnzODdLtuThALhGtyconcVuPI8AaiCaiJnfdzUcb
# 3dWnqUnjXkRFwLtsVAxFvGqsxUA2Jq/WTjbnNjIUzIs3ITVC6VBKAOlb2u29Vwgf
# ta8b2ypi6n2PzP0nVepsFk8nlcuWfyZLzBaZ0MucEdeBiXL+nUOGhCjl+QIDAQAB
# o4IBizCCAYcwDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/
# BAwwCgYIKwYBBQUHAwgwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcB
# MB8GA1UdIwQYMBaAFLoW2W1NhS9zKXaaL3WMaiCPnshvMB0GA1UdDgQWBBSfVywD
# dw4oFZBmpWNe7k+SH3agWzBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGltZVN0
# YW1waW5nQ0EuY3JsMIGQBggrBgEFBQcBAQSBgzCBgDAkBggrBgEFBQcwAYYYaHR0
# cDovL29jc3AuZGlnaWNlcnQuY29tMFgGCCsGAQUFBzAChkxodHRwOi8vY2FjZXJ0
# cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGlt
# ZVN0YW1waW5nQ0EuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQA9rR4fdplb4ziEEkfZ
# Q5H2EdubTggd0ShPz9Pce4FLJl6reNKLkZd5Y/vEIqFWKt4oKcKz7wZmXa5VgW9B
# 76k9NJxUl4JlKwyjUkKhk3aYx7D8vi2mpU1tKlY71AYXB8wTLrQeh83pXnWwwsxc
# 1Mt+FWqz57yFq6laICtKjPICYYf/qgxACHTvypGHrC8k1TqCeHk6u4I/VBQC9VK7
# iSpU5wlWjNlHlFFv/M93748YTeoXU/fFa9hWJQkuzG2+B7+bMDvmgF8VlJt1qQcl
# 7YFUMYgZU1WM6nyw23vT6QSgwX5Pq2m0xQ2V6FJHu8z4LXe/371k5QrN9FQBhLLI
# SZi2yemW0P8ZZfx4zvSWzVXpAb9k4Hpvpi6bUe8iK6WonUSV6yPlMwerwJZP/Gtb
# u3CKldMnn+LmmRTkTXpFIEB06nXZrDwhCGED+8RsWQSIXZpuG4WLFQOhtloDRWGo
# Cwwc6ZpPddOFkM2LlTbMcqFSzm4cd0boGhBq7vkqI1uHRz6Fq1IX7TaRQuR+0BGO
# zISkcqwXu7nMpFu3mgrlgbAW+BzikRVQ3K2YHcGkiKjA4gi4OA/kz1YCsdhIBHXq
# BzR0/Zd2QwQ/l4Gxftt/8wY3grcc/nS//TVkej9nmUYu83BDtccHHXKibMs/yXHh
# DXNkoPIdynhVAku7aRZOwqw6pDCCBq4wggSWoAMCAQICEAc2N7ckVHzYR6z9KGYq
# XlswDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGln
# aUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTIyMDMyMzAwMDAwMFoXDTM3MDMyMjIz
# NTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTsw
# OQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVT
# dGFtcGluZyBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMaGNQZJ
# s8E9cklRVcclA8TykTepl1Gh1tKD0Z5Mom2gsMyD+Vr2EaFEFUJfpIjzaPp985yJ
# C3+dH54PMx9QEwsmc5Zt+FeoAn39Q7SE2hHxc7Gz7iuAhIoiGN/r2j3EF3+rGSs+
# QtxnjupRPfDWVtTnKC3r07G1decfBmWNlCnT2exp39mQh0YAe9tEQYncfGpXevA3
# eZ9drMvohGS0UvJ2R/dhgxndX7RUCyFobjchu0CsX7LeSn3O9TkSZ+8OpWNs5KbF
# Hc02DVzV5huowWR0QKfAcsW6Th+xtVhNef7Xj3OTrCw54qVI1vCwMROpVymWJy71
# h6aPTnYVVSZwmCZ/oBpHIEPjQ2OAe3VuJyWQmDo4EbP29p7mO1vsgd4iFNmCKseS
# v6De4z6ic/rnH1pslPJSlRErWHRAKKtzQ87fSqEcazjFKfPKqpZzQmiftkaznTqj
# 1QPgv/CiPMpC3BhIfxQ0z9JMq++bPf4OuGQq+nUoJEHtQr8FnGZJUlD0UfM2SU2L
# INIsVzV5K6jzRWC8I41Y99xh3pP+OcD5sjClTNfpmEpYPtMDiP6zj9NeS3YSUZPJ
# jAw7W4oiqMEmCPkUEBIDfV8ju2TjY+Cm4T72wnSyPx4JduyrXUZ14mCjWAkBKAAO
# hFTuzuldyF4wEr1GnrXTdrnSDmuZDNIztM2xAgMBAAGjggFdMIIBWTASBgNVHRMB
# Af8ECDAGAQH/AgEAMB0GA1UdDgQWBBS6FtltTYUvcyl2mi91jGogj57IbzAfBgNV
# HSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYD
# VR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1Ud
# HwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRy
# dXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwH
# ATANBgkqhkiG9w0BAQsFAAOCAgEAfVmOwJO2b5ipRCIBfmbW2CFC4bAYLhBNE88w
# U86/GPvHUF3iSyn7cIoNqilp/GnBzx0H6T5gyNgL5Vxb122H+oQgJTQxZ822EpZv
# xFBMYh0MCIKoFr2pVs8Vc40BIiXOlWk/R3f7cnQU1/+rT4osequFzUNf7WC2qk+R
# Zp4snuCKrOX9jLxkJodskr2dfNBwCnzvqLx1T7pa96kQsl3p/yhUifDVinF2ZdrM
# 8HKjI/rAJ4JErpknG6skHibBt94q6/aesXmZgaNWhqsKRcnfxI2g55j7+6adcq/E
# x8HBanHZxhOACcS2n82HhyS7T6NJuXdmkfFynOlLAlKnN36TU6w7HQhJD5TNOXrd
# /yVjmScsPT9rp/Fmw0HNT7ZAmyEhQNC3EyTN3B14OuSereU0cZLXJmvkOHOrpgFP
# vT87eK1MrfvElXvtCl8zOYdBeHo46Zzh3SP9HSjTx/no8Zhf+yvYfvJGnXUsHics
# JttvFXseGYs2uJPU5vIXmVnKcPA3v5gA3yAWTyf7YGcWoWa63VXAOimGsJigK+2V
# Qbc61RWYMbRiCQ8KvYHZE/6/pNHzV9m8BPqC3jLfBInwAM1dwvnQI38AC+R2AibZ
# 8GV2QqYphwlHK+Z/GqSFD/yYlvZVVCsfgPrA8g4r5db7qS9EFUrnEw4d2zc4GqEr
# 9u3WfPwwggWNMIIEdaADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEB
# DAUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQg
# SUQgUm9vdCBDQTAeFw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJ
# BgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5k
# aWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPs
# wqclLskhPfKK2FnC4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLk
# X9YFPFIPUh/GnhWlfr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4TmdDtt
# ceItDBvuINXJIB1jKS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hI
# qGZXV59UWI4MK7dPpzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2
# scS1ahg4AxCN2NQ3pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm
# 2ToxRJozQL8I11pJpMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaH
# iZdpekjw4KISG2aadMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3r
# M9nF30sEAMx9HJXDj/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJ
# B+G9t+ZDpBi4pncB4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzTQRES
# W+UQUOsxxcpyFiIJ33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6Kxfgom
# mfXkaS+YHS312amyHeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0G
# A1UdDgQWBBTs1+OC0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLL
# gjEtUYunpyGd823IDzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQG
# CCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKG
# N2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcnQwRQYDVR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYGBFUd
# IAAwDQYJKoZIhvcNAQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72arKGH
# LOyFXqkauyL4hxppVCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFIDyE7Q
# Kt76LVbP+fT3rDB6mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajw
# vy8LpunyNDzs9wPHh6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQ
# Pfx2CWiEn2/K2yCNNWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFq
# I2si/xK4VC0nftg62fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQxggN2MIIDcgIB
# ATB3MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkG
# A1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3Rh
# bXBpbmcgQ0ECEAuuZrxaun+Vh8b56QTjMwQwDQYJYIZIAWUDBAIBBQCggdEwGgYJ
# KoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNTA2MDUx
# NDM0MzJaMCsGCyqGSIb3DQEJEAIMMRwwGjAYMBYEFNvThe5i29I+e+T2cUhQhyTV
# hltFMC8GCSqGSIb3DQEJBDEiBCD6FM96+7KCOXY7FRhQvmJKzB8GDkRE9vrRM3XN
# x+wWozA3BgsqhkiG9w0BCRACLzEoMCYwJDAiBCB2dp+o8mMvH0MLOiMwrtZWdf7X
# c9sF1mW5BZOYQ4+a2zANBgkqhkiG9w0BAQEFAASCAgAOnZ/S5YBoDZulryIbbgCM
# xrbuo9Q/iNmswMHV6GHuRmday+Pza5kjVNX7N8jA2m8M87bw5L9sLJ81SF4fRbBQ
# us83gbpO32Ud+97yMJ6aijtC99WonLYPH4ZmvOyK1Ry3WbJIfogrRoFaL4hCStbC
# wzexxN4Oe2TRrKeqXw9RwRCJowk2HzTX6LtDK1+Z+m+zmdcm90cOwl6ZuvjDcpft
# XqJuJ/Y92XeT/MyBdiSXAnU8yD9OCtMJdD80cnT7MFssKa0r5K6XFeVxrb2F+3Hb
# zgnqkTRGn+uv0yeCkfjtc0oc1iNW5tKw3FFZnPWURK5xwIf7amL7lo9flZRWH5dW
# W0tBi5rvAYRkInVbcV4TzS/Jhoi1YhC1Y1/pGCDlAPz1Ht+9L77VAJHuGVpTC9ED
# FdrPMMJwNgqgSi7x3vCDp0+qOaag0027O6jHBQhUTk/E9AxKflzzHI9mDUWI2XQ2
# FstrLdzFkXl2XbM6sYu07UOE/533LnuHP5+9ItzftNf8Dfg0EBNdK1N3CQEQPhWz
# kEZ3shqdQFcsr2qKibzeqyPyzOIBMudbe0Cp5WZbqeyjX+4JWuuS7GlQhzd6zxl7
# JDrtg0O0nUy95W2RQwD2kVBO9bKKwJ3cWXVwngO/3IxophEwNjrnD/wyUPIZT/Zh
# khCg82BCRHpRCALhMDGEkA==
# SIG # End signature block
