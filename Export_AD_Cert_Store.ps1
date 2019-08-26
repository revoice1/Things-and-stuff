$DomainDN = $(Get-ADDomain).DistinguishedName
$CACerts = (Get-ADObject "CN=NTAuthCertificates,CN=Public Key Services,CN=Services,CN=Configuration,$($DomainDN)" -Properties cACertificate).cACertificate
foreach ($cacert in $CACerts) {
    $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $cert.Import($cacert)
    [System.Convert]::ToBase64String($Cert.RawData) | Out-File ".\ADCACertStore\$($Cert.thumbprint).cer"
}
