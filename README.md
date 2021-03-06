# Azure Backup Files and Folders (MARS agent) Demo
## Scenario
You have multiple windows servers you want to install and configure the mars agent on across multiple datacentres in different geograhical locations. For perfomance reasons you would like to maintain a vault as close as possible to each datacentre. You would like to automate the install and configuration of the agents as much as possible.

This demo has serveral components
1. A set of arm templates that can create multiple vaults in various regions to support data soverinty and latency requirements, including a shared log analytics workspace and a keyvault to store server encryption passphrases in
2. A backup config file (backupConfig.json) which defines which server belongs to which vault as well as locations to be backed up. The config file has a default section and so where it makes sense you only have to define configuration once. e.g backup schedule. Not all config sections are currently used in installMars.ps1 and is there as a demostration of how it can be done not a finished implmentation.
3. A powerhell script which installs the mars agent, reads configuration from the shared keyvault tries to match the server name against the config and then proceeds to configure the mars agent against the specfied vault with the specified protection policy. Allowing users to control inital vault location and backup policy from a central location. The idea is you could automate this script using some form of orchestration such as Azure Runbooks or System Center Orchestrator or Remote Powershell 

## Automation identity
When automating this script consider using a service princpal / app registration with only the permissions it needs to 1. register the server in the vault, 2. get the backup vault pin 3. read and write to keyvault secrets. Service principals can use either certificates or shared secrets to authenticate. Certificates are the recommended approach but it does require getting the cerficate into the local machines certificate store. 

Consider seperating the keyvault used for config from the keyvault used for encrption passphrase , as the access policies on keyvault apply to all secrets, consequently if the install serviceprincipal was comprimised it may be able to read out the encryption passphrase of other servers. The backup config could be stored anywhere, I chose to use keyvault as i already had to interact with in to store passphrase

Running `Get-AzRecoveryServicesVault -Name $VaultName` without specifying resource group name requires read access to the vault resource group. otherwise this command will return null.

## Idempotency and fault handaling
At the moment the installMars.ps1 script does not handle being run more than once. If the script fails, Finsish installation and registration manually.

## Backup Reporting

## TODO
* Proxy and throttling config from the backupConfig.json
* Custom install paramaters e.g agent install location and scratch location

## Deploy

At the momemnt the subscription level deployments canont be done from the portal, instead use powershell instead