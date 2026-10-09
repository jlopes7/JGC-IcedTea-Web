[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$CertFilename = 'JGC-CodeSigning.cer'
)

try {
    if (-not (Test-Path -LiteralPath $CertFilename -PathType Leaf)) {
        throw "Required certificate file is missing: $CertFilename"
    }

    $certificatePath = (Resolve-Path -LiteralPath $CertFilename -ErrorAction Stop).ProviderPath

    $stores = @(
        'Cert:\LocalMachine\Root'
        'Cert:\LocalMachine\TrustedPublisher'
    )

    foreach ($store in $stores) {
        Write-Host "Importing certificate into $store..." -ForegroundColor Yellow

        $certificate = Import-Certificate -FilePath $certificatePath -CertStoreLocation $store -ErrorAction Stop

        Write-Host "Imported: $($certificate.Thumbprint)" -ForegroundColor Green
    }

    Write-Host 'Certificate import completed successfully.' -ForegroundColor Green
}
catch {
    Write-Error `
        -Message "Certificate import failed: $($_.Exception.Message)" `
        -ErrorAction Continue

    exit 1
}

exit 0
