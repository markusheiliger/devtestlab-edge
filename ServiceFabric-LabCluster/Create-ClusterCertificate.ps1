param(
    [Parameter(Mandatory=$true)]
    [string] $CertificateName,
     
    [Parameter(Mandatory=$true)]
    [string] $Password,   
    
    [Parameter(Mandatory=$false)]
    [string] $DnsName = $($CertificateName + ".ServiceFabric.lab")
)

$securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
$certificatePath = Join-Path $env:TEMP $($CertificateName + ".pfx")
$certificateInfo = [System.IO.Path]::ChangeExtension($certificatePath, ".txt")
Write-Host "Creating new self signed certificate at $certificatePath"

# Remove certificate file and info if exists
Remove-Item -Path $certificatePath -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path $certificateInfo -Force -ErrorAction SilentlyContinue | Out-Null

# Changes to PSPKI version 3.5.2 New-SelfSignedCertificate replaced by New-SelfSignedCertificateEx
$PspkiVersion = (Get-Module PSPKI).Version

if($PSPKIVersion.Major -ieq 3 -And $PspkiVersion.Minor -ieq 2 -And $PspkiVersion.Build -ieq 5) {
    New-SelfsignedCertificateEx -Subject "CN=$DnsName" -EKU "Server Authentication", "Client authentication" -KeyUsage "KeyEncipherment, DigitalSignature" -Path $certificatePath -Password $securePassword -Exportable
} else {
    New-SelfSignedCertificate -CertStoreLocation Cert:\CurrentUser\My -DnsName $DnsName | Export-PfxCertificate -FilePath $certificatePath -Password $securePassword | Out-Null
}

$cert = new-object System.Security.Cryptography.X509Certificates.X509Certificate2 $certificatePath, $Password
$bytes = [System.IO.File]::ReadAllBytes($certificatePath)

"Certificate Thumbprint: $($cert.Thumbprint)" | Out-File -FilePath $certificateInfo -Append
"Certificate Password:   $Password" | Out-File -FilePath $certificateInfo -Append
"================================================================" | Out-File -FilePath $certificateInfo -Append
$([System.Convert]::ToBase64String($bytes)) | Out-File -FilePath $certificateInfo -Append

notepad $certificateInfo