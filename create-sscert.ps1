$ErrorActionPreference = 'Stop'

$certificateDirectory = Join-Path $PWD 'CodeSigning'
New-Item -ItemType Directory -Path $certificateDirectory -Force | Out-Null

$certificateParameters = @{
    Type              = 'CodeSigningCert'
    Subject           = 'CN=JGonzalez Software OU'
    FriendlyName      = 'JGC Windows Code Signing'
    CertStoreLocation = 'Cert:\CurrentUser\My'
    KeyAlgorithm      = 'RSA'
    KeyLength         = 3072
    HashAlgorithm     = 'SHA256'
    KeyUsage          = 'DigitalSignature'
    KeyExportPolicy   = 'Exportable'
    NotAfter          = (Get-Date).AddYears(3)
}

$certificate = New-SelfSignedCertificate @certificateParameters

$publicCertificate = Join-Path $certificateDirectory 'JGC-CodeSigning.cer'

Export-Certificate -Cert $certificate -FilePath $publicCertificate | Out-Null

Write-Host "Certificate thumbprint: $($certificate.Thumbprint)"
Write-Host "Public certificate:     $publicCertificate"

exit $LASTEXITCODE
