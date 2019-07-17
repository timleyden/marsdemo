#sample wrapper script that calls installMars.ps1
#check prereq
if ((get-module -ListAvailable az.resources, az.accounts, az.recoveryservices, az.keyvault).length -lt 4) {
    #ensure nuget
    install-packageprovider -Name "NuGet" -Force
    #set trusted 
    $repo = get-psrepository -name "PSGallery" 
    if ($repo.InstallationPolicy -ne "Trusted") {
        Set-PSRepository -name "PSGallery" -InstallationPolicy Trusted
    }
    #get modules from psgallery
    install-module az.resources, az.accounts, az.recoveryservices, az.keyvault
    #revert install policy
    Set-PSRepository -name "PSGallery" -InstallationPolicy $repo.InstallationPolicy
}
#setup variables
$keyVaultName = "kvtest"
#set serviceprincipal details
#these details can be found under the Enterprise application blade or using powershell in Azure AD
#secure secret used for demo purposes, recommend using cert
$servicePrincipalName = "your service principal id"
$tenantId = "your tenant id"
$appPassword = "appsecret"
$secureSecret = ConvertTo-SecureString -String $apppassword -AsPlainText -Force
.\InstallMARS.ps1  -KeyVaultName $keyVaultName -ServicePrincipalName $servicePrincipalName -Secret $secureSecret -Tenantid $tenantId -verbose



