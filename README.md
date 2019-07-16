# Azure Backup Files and Folders (MARS agent) Demo
## Scenario
You have multiple windows servers you want to install and configure the mars agent on across multiple datacentres in different geograhical locations. For perfomance reasons you would like to maintain a vault as close as possible to each datacentre. You would like to automate the install and configuration of the agents as much as possible.

This demo has two components
1. A set of arm templates that can create multiple vaults in various regions to support data soverinty and latency requirements, including a shared log analytics workspace and a keyvault to store server passphrases in
2. A powerhell script which installs the mars agent, reads configuration from the shared keyvault tries to match the server name against the config and then proceeds to configure the mars agent against the specfied vault with the specified protection policy. Allowing users to control inital vault location and back policy from a central location. The idea is you could automate this script using 

## Automation identity
When automating this script consider using a service princpal / app registration with only the permissions it needs to 1. register the server in the vault, 2. get the backup vault pin 2. read and write to keyvault secrets. Service principals can use either certificates or shared secrets to authenticate. Certificate are the recommended approach but it does require getting the cerficate into the local machines certificate store.

## Idempotency

## Backup Reporting

[![Deploy to Azure](http://azuredeploy.net/deploybutton.png)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftimleyden%2Fmarsdemo%2Fmaster%2FdeployGlobal.json)