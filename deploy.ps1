$subscriptionid = "<yoursubid>"

$deployArtifacts = $true
$params = new-object hashtable
$environment = "PROD"
$prefix = "DEMO"
$rgName = "$prefix-BACKUP-$environment-SHARED"
$artifactStorageName = "$($prefix.ToLower())backupartifact$($environment.ToLower())"
$location = "centralus"
$params = new-object hashtable
if((Get-AzSubscription -errorAction SilentlyContinue) -eq $null){
    login-azaccount
}
Select-AzSubscription $subscriptionid
$resourceGroup = Get-AzResourceGroup $rgName -errorAction SilentlyContinue
if(-not $resourceGroup){
    $resourceGroup =  New-AzResourceGroup -Name $rgName -Location $location
}
#child templates need to be in a accessbile location, create storage account and copy templates
if($deployArtifacts){
    New-AzResourceGroupDeployment -Name "$prefix-BACKUP-$environment-ARTIFACTS-DEPLOYMENT" -ResourceGroupName $resourceGroup.ResourceGroupName -Mode Incremental -TemplateFile .\artifactstorage.json -TemplateParameterObject @{"StorageAccountName"=$artifactStorageName}
      $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup.ResourceGroupName -Name $artifactStorageName
      get-childitem *.json | Set-AzStorageBlobContent -Context $storageAccount.Context -Container "azuretemplates" -Force
    
}else{
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup.ResourceGroupName -Name $artifactStorageName 
}

#generate sas token
$StartTime = Get-Date
$EndTime = $startTime.AddHours(2.0)   
$artifactStorageSAStoken = New-AzStorageAccountSASToken -Context $storageAccount.Context -Permission "rl" -StartTime $StartTime -ExpiryTime $EndTime -Service Blob -ResourceType Service,Container,Object
$params.Add("containerSasToken",$artifactStorageSAStoken)
$params.Add("TemplateStorageUri",$storageAccount.PrimaryEndpoints.Blob + "azuretemplates/")
$params.Add("DeploymentPrefix",$prefix)
$params.Add("Environment",$environment)
#start global deployment
New-AzDeployment -Location $location -Name "$($Prefix)Backup$($enviornment)Deployment" -TemplateFile .\deployGlobal.json -TemplateParameterObject $params