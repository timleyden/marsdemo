#uploads backupConfig.json from local storage to keyvault
$keyVaultName = "kvtest"
$config = Get-Content .\backupConfig.json -Raw
$configSecret = ConvertTo-SecureString -String $config -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $keyVaultName -SecretValue $configSecret -ContentType "application/json" -Name "backupConfig"