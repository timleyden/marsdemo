#Requires -Modules az.resources,az.accounts,az.recoveryservices,az.keyvault 
param(
    [parameter(Mandatory = $true)]
    [String]
    $KeyVaultName,    
    [SecureString]
    $Secret,
    [String]
    $ServicePrincipalName,
    [String]
    $Tenantid
)
function CheckPropertyAndSetDefault($object, $propertyname, $defaultobject) {
    if ($object.$propertyname -eq $null) {
        add-member -InputObject $object -Name $propertyname -Value  $defaultobject.$propertyname -MemberType NoteProperty       
    }
}
if ($ServicePrincipalName) {
   
    $pscredential = New-Object System.Management.Automation.PSCredential($ServicePrincipalName, $secret)
    Login-AzAccount -ServicePrincipal  -Credential $pscredential -Tenant $Tenantid
}
#region variables
$temppath = "$($env:Temp)\MARS\"
$MarsAURL = "https://aka.ms/Azurebackup_Agent"
$computerName = $env:COMPUTERNAME
#endregion
#region load config from keyvault
$backupconfigSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "BackupConfig"
if ($backupconfigSecret -eq $null) {
    write-error "unable to load backup config"
    return
}
Write-Verbose "succesfull retrieved backup config from vault"
$backupconfig = ConvertFrom-Json $backupconfigSecret.SecretValueText
$serverconfig = $backupconfig.servers | ? serverName -eq $computerName
$defaultconfig = $backupconfig.servers | ? serverName -eq "default"
if ($serverconfig -eq $null) {
    Write-Error "Server not found in config store, using defaults. Servername: $($computerName)"
    $serverconfig = $defaultconfig
}
else {
    write-verbose "found server in config file"
}
CheckPropertyAndSetDefault $serverconfig "targetVault" $defaultconfig
CheckPropertyAndSetDefault $serverconfig "bakcupVolumes" $defaultconfig
CheckPropertyAndSetDefault $serverConfig "backupSchedule" $defaultconfig
CheckPropertyAndSetDefault $serverconfig "retentionPolicy" $defaultconfig
CheckPropertyAndSetDefault $serverconfig "excludeFolders" $defaultconfig
$VaultName = $serverconfig.targetVault
#endregion

#region install client
#check if installed
$packages = get-package -Name "Microsoft Azure Recovery Services Agent" -errorAction SilentlyContinue
if ($packages.count -eq 0) {
    #download
    $WC = New-Object System.Net.WebClient
    New-Item $temppath -ItemType Directory -Force
    $WC.DownloadFile($MarsAURL, "$($temppath)MARSAgentInstaller.EXE")
    #install silent, requires elevatged permissions
    invoke-expression "$($temppath)MARSAgentInstaller.EXE /q"
    #give some time for installer to complete as we were getting weird powershell module issues
    Start-Sleep -Seconds 60
}
else {
    write-warning "MARS agent already installed"
}
#endregion
#region register agent with vault
#get vault creds
Write-Verbose "Setting Vault context $($VaultName)"
$Vault = Get-AzRecoveryServicesVault -Name $VaultName
if ($Vault -eq $null) {
    Write-Error "Unable to find vault using specified vault name $($vaultname) using the credentials provided"
}
else {
    Set-AzRecoveryServicesASRVaultContext -vault $Vault 
    #generate certificate for 
    $dt = $(Get-Date).ToString("M-d-yyyy")
    $cert = New-SelfSignedCertificate -CertStoreLocation Cert:\CurrentUser\My -FriendlyName  $($vault.Name + $subscriptionid + '-' + $dt + '-vaultcredentials') -subject "Windows Azure Tools" -KeyExportPolicy Exportable -NotAfter $(Get-Date).AddHours(48) -NotBefore $(Get-Date).AddHours(-24) -KeyProtection None -KeyUsage None -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2") -Provider "Microsoft Enhanced Cryptographic Provider v1.0"
    $bytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
    $cert2 = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes, "", [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
    $certficate = [convert]::ToBase64String($cert2.RawData)
    $certficate2 = [convert]::ToBase64String($cert2.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx))
    $CredsFilename = Get-AzRecoveryServicesVaultSettingsFile -Backup -Vault $Vault -Path $temppath  -Certificate $certficate 
    $cert | remove-item
    [xml]$xml = get-content $CredsFilename.FilePath
    $xml.RSBackupVaultAADCreds.ManagementCert = $certficate2
    Copy-Item $CredsFilename.FilePath -Destination ($CredsFilename.FilePath + "bak")
    $xml.Save($CredsFilename.FilePath)
    #register agent in vault
    Import-Module -Name 'C:\Program Files\Microsoft Azure Recovery Services Agent\bin\Modules\MSOnlineBackup'
    $policy = Get-OBPolicy -ErrorAction SilentlyContinue
    if ($policy -ne $null) {
        Write-Error "Policy already exists on server"
    }
    else {
        Start-OBRegistration -VaultCredentials $CredsFilename.FilePath -Confirm:$false
        #endregion
        #region configure agent
        #configure Netwrok settings
        Set-OBMachineSetting -NoProxy 
        Set-OBMachineSetting -NoThrottle

        #setPassphrase
        $passphrasetext = [System.Web.Security.Membership]::GeneratePassword(25, 5)
        $PassPhrase = ConvertTo-SecureString -String $passphrasetext -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $computerName -SecretValue $passphrase
        #looks like pin only required if your changing an existing pin which we are not doing in this case
        #$pinResult = Invoke-AzResourceAction -Action "backupSecurityPin" -ResourceId $vault.ID -ApiVersion "2017-07-01" -Force
        #start-sleep -Seconds 5
        Set-OBMachineSetting -EncryptionPassPhrase $PassPhrase #-SecurityPin $pinResult.securityPIN
        #set backup schedule
        $NewPolicy = New-OBPolicy
        #convert to enum
        $daysofweek = $serverconfig.backupSchedule.DaysOfTheWeek | foreach-object { [system.dayofweek]$_ }
        $Schedule = New-OBSchedule -DaysOfWeek $daysofweek -TimesOfDay $serverconfig.backupSchedule.TimesOfDay
        #set retentionpolicy
        $RetentionPolicy = New-OBRetentionPolicy  -RetentionDays $serverconfig.retentionPolicy.daily `
            -RetentionWeeks $serverconfig.retentionPolicy.weekly  -RetentionWeeklyPolicy -WeekDaysOfWeek $serverconfig.retentionPolicy.weeklyDay `
            -RetentionMonths $serverconfig.retentionPolicy.monthly -RetentionMonthlyPolicy -MonthWeeksOfMonth $serverconfig.retentionPolicy.monthlyWeek -MonthDaysOfWeek $serverconfig.retentionPolicy.weeklyDay `
            -RetentionYears $serverconfig.retentionPolicy.yearly -RetentionYearlyPolicy -YearMonthsOfYear $serverconfig.retentionPolicy.yearlyMonth -YearWeeksOfMonth $serverconfig.retentionPolicy.monthlyWeek -YearDaysOfWeek $serverconfig.retentionPolicy.weeklyDay 
        Set-OBRetentionPolicy -Policy $NewPolicy -RetentionPolicy $RetentionPolicy
        #set backup volumes and folder exclusoins
        $validBackupVolumes = @()
        $serverconfig.backupVolumes | foreach-object {
            if ((Test-Path $_)) {
                $validBackupVolumes += $_
            }
            else {
                Write-Warning "backup volume $($_) not found on the local machine, skipping..."
            }
        }

        $validExludeFolders = @()
        $serverconfig.excludeFolders | foreach-object {
            if ((Test-Path $_)) {
                $validExludeFolders += $_
            }
            else {
                Write-Warning "exclude folder $($_) not found on the local machine, skipping..."
            }
        }
        $Inclusions = New-OBFileSpec -FileSpec $validBackupVolumes
        $Exclusions = New-OBFileSpec -FileSpec $validExludeFolders -Exclude
        Add-OBFileSpec -Policy $NewPolicy -FileSpec $Inclusions
        Add-OBFileSpec -Policy $NewPolicy -FileSpec $Exclusions
        $NewPolicy.backupSchedule = $Schedule
        $NewPolicy.RetentionPolicy = $RetentionPolicy
        Set-OBPolicy -Policy $NewPolicy -Confirm:$false
    }
    #endregion
}