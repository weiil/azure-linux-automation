# import test libs
Import-Module .\TestLibs\AzureWinUtils.psm1 -Force -Scope Global
Import-Module .\TestLibs\RDFELibs.psm1 -Force -Scope Global
Import-Module .\TestLibs\ARMLibrary.psm1 -Force -Scope Global

$testDir = "testresults" + "\" + 'pcf'
mkdir $testDir -ErrorAction SilentlyContinue | out-null
$logFile = $testDir + "\" + 'pcf-testing-on-azure.log'
Set-Variable -Name logfile -Value $logFile -Scope Global

Write-Host "------------------------------------------------------------------ Runner for PCF on Azure ------------------------------------------------------------------"

# load parameters
$sp_config = ($env:ServicePrincipalConfig).ToString().trim()
$sp = Get-Content "..\CI\Cloud\ServicePrincipalConfig\$sp_config" -Raw | ConvertFrom-Json

$subscriptionId = $sp.SubscriptionId.Trim()
$tenantId = $sp.TenantId.Trim()
$clientId = $sp.ApplicationId.Trim()
$clientSecret = $sp.ClientSecret.Trim()
$azureEnv = $sp.Environment.Trim()
$opsmanVersion = $env:OpsManVersion.Trim()
$director_passwd = $env:DirectorPassword.Trim()
$elasticRuntimeVersion = $env:ElasticRuntimeRelease.Trim()
$location = $env:Location.Trim()
$pivotalDownloadAPIToken = $env:Token.Trim()
$passwd = $env:DevCliVMPassword.Trim()


Write-Host "  1. Login Azure with Service Principle"
$securePasswd = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($clientId,$securePasswd)
Login-AzureRmAccount -Credential $cred -ServicePrincipal -TenantId $tenantId -EnvironmentName $azureEnv
Write-Host ""

Write-Host "  2. Create a VM as devbox"
# Variables for common values
$curtime = Get-Date
$postfix = '' + "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
$resourceGroup = "ICA-RG-PCF-DEV$postfix"
$resourceGroup_PCF = "ICA-RG-PCF$postfix"
$boshStorage = "mybosh" + [guid]::NewGuid().guid.split('-')[0]
$vmName = "DEV-CLI-PCF$postfix"

$userName = "azureuser"
Set-Variable -Name password -Value $passwd -Scope Global

# Definer user name and blank password
$securePassword = ConvertTo-SecureString $passwd -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)

# Create a resource group
New-AzureRmResourceGroup -Name $resourceGroup -Location $location

# Create a storage account
$storageName = "general" + $curtime.Month + $curtime.Day + $curtime.Hour + $curtime.Minute + $curtime.Second
$storageType = "Standard_LRS"
$storageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $storageName -Type $storageType -Location $location

# Create a subnet configuration
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name mySubnet -AddressPrefix 192.168.1.0/24

# Create a virtual network
$vnet = New-AzureRmVirtualNetwork -ResourceGroupName $resourceGroup -Location $location `
  -Name MYvNET -AddressPrefix 192.168.0.0/16 -Subnet $subnetConfig

# Create a public IP address and specify a DNS name
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $resourceGroup -Location $location `
  -Name "mypublicdns$(Get-Random)" -AllocationMethod Static -IdleTimeoutInMinutes 4

# Create an inbound network security group rule for port 22
$nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig -Name myNetworkSecurityGroupRuleSSH  -Protocol Tcp `
  -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 22 -Access Allow

# Create a network security group
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroup -Location $location `
  -Name myNetworkSecurityGroup -SecurityRules $nsgRuleSSH

# Create a virtual network card and associate with public IP address and NSG
$nic = New-AzureRmNetworkInterface -Name myNic -ResourceGroupName $resourceGroup -Location $location `
  -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id

# Create a virtual machine configuration
$vmConfig = New-AzureRmVMConfig -VMName $vmName -VMSize Standard_D1 | `
Set-AzureRmVMOperatingSystem -Linux -ComputerName $vmName -Credential $cred   | `
Set-AzureRmVMSourceImage -PublisherName Canonical -Offer UbuntuServer -Skus 14.04.2-LTS -Version latest | `
Add-AzureRmVMNetworkInterface -Id $nic.Id
$OSDiskName = $vmName + "OSDisk"
$OSDiskUri = $StorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/" + $OSDiskName + ".vhd"
Set-AzureRmVMOSDisk -VM $vmConfig -Name $OSDiskName -VhdUri $OSDiskUri -CreateOption FromImage

# Create a virtual machine
New-AzureRmVM -ResourceGroupName $resourceGroup -Location $location -VM $vmConfig

$interface = Get-AzureRmNetworkInterface -ResourceGroupName $resourceGroup
$publicIPName = $(Get-AzureRmResource -ResourceId $interface.IpConfigurations[0].PublicIpAddress.Id).Name
$publicIP = $(Get-AzureRmPublicIpAddress -Name $publicIPName -ResourceGroupName $resourceGroup).IpAddress

Write-Host "        Dev VM is created"
Write-Host "          RG: $resourceGroup"
Write-Host "          VM: $vmName"
Write-Host "          SSH: ${userName}@$publicIP"
Write-Host ""

Write-Host "  3. Install azure cli on dev VM"
$port = 22
$out = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -"
$out = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "sudo apt-get install -y nodejs"
$out = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "sudo npm install -g azure-cli"
$out = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "azure -v"
Write-Host "        azure-cli $out was installed"
Write-Host ""

Write-Host "  4. Prepare to deploy PCF on Azure"
RemoteCopy -uploadTo $publicIP -port $port -files '.\remote-scripts\pcf\prepare-pcf-infrastructure-on-azure.sh' -username $userName -password $passwd -upload
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "chmod a+x prepare-pcf-infrastructure-on-azure.sh"
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh-keygen -t rsa -f opsman -C ubuntu -N ''"
$sshKey = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "cat opsman.pub"

@{tenantId=$tenantId;clientId=$clientId;clientSecret=$clientSecret;sshKey=$sshKey;resourceGroup=$resourceGroup_PCF;location=$location;boshStorage=$boshStorage;opsmanVersion=$opsmanVersion} | ConvertTo-Json | Out-File params.json
RemoteCopy -uploadTo $publicIP -port $port -files '.\params.json' -username $userName -password $passwd -upload
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "./prepare-pcf-infrastructure-on-azure.sh params.json"
# get ops man FQDN
$opsmanfqdn = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "azure group deployment list $resourceGroup_PCF | grep -i fqdn | awk {'print `$4'} | tr -d '\n'"
Write-Host "        Infrastructure of PCF on Azure is created"
Write-Host "          RG: $resourceGroup_PCF"
Write-Host "          OPS MAN VM: pcf-ops-man"
Write-Host "          OPS MAN DNS: $opsmanfqdn"
Write-Host ""

Write-Host "  5. Configure manifest of BOSH"
# upload manifests and scripts to dev vm
$filepath = "..\CI\Cloud\CF\bosh-for-pcf.yml"
(Get-Content $filepath | Out-String).Replace('REPLACE_WITH_YOUR_STORAGE',$boshStorage) | Set-Content $filepath
(Get-Content $filepath | Out-String).Replace('REPLACE_WITH_YOUR_SUBSCRIPTION_ID',$subscriptionId) | Set-Content $filepath
(Get-Content $filepath | Out-String).Replace('REPLACE_WITH_YOUR_TENANT_ID',$tenantId) | Set-Content $filepath
(Get-Content $filepath | Out-String).Replace('REPLACE_WITH_YOUR_CLIENT_ID',$clientId) | Set-Content $filepath
(Get-Content $filepath | Out-String).Replace('REPLACE_WITH_YOUR_CLIENT_SECRET',$clientSecret) | Set-Content $filepath
(Get-Content $filepath | Out-String).Replace('REPLACE_WITH_YOUR_RESOURCE_GROUP',$resourceGroup_PCF) | Set-Content $filepath
(Get-Content $filepath | Out-String).Replace('REPLACE_WITH_YOUR_SSH_PUBLIC_KEY',$sshKey) | Set-Content $filepath
# upload bosh manifest to dev vm
RemoteCopy -uploadTo $publicIP -port $port -files $filepath -username $userName -password $passwd -upload

# upload deploy_bosh_for_pcf.sh to dev vm
RemoteCopy -uploadTo $publicIP -port $port -files '.\remote-scripts\pcf\deploy_bosh_for_pcf.sh' -username $userName -password $passwd -upload
RemoteCopy -uploadTo $publicIP -port $port -files '..\CI\Cloud\CF\root_ca_certificate' -username $userName -password $passwd -upload
# upload pcf manifest to dev vm
RemoteCopy -uploadTo $publicIP -port $port -files '..\CI\Cloud\CF\pcf-on-azure.yml' -username $userName -password $passwd -upload
# upload cloud-config for PCF on azure
RemoteCopy -uploadTo $publicIP -port $port -files '..\CI\Cloud\CF\pcf-cloud-config.yml' -username $userName -password $passwd -upload
Write-Host ""

Write-Host "  6. Deploy BOSH director"
# get pcf-lb-ip address
$lb_ip = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "azure network public-ip show $resourceGroup_PCF pcf-lb-ip --json | jq .ipAddress | tr -d '`"'"
# upload bosh manifest from dev vm to opsman vm
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -o StrictHostKeyChecking=no -i opsman bosh-for-pcf.yml ubuntu@${opsmanfqdn}:/home/ubuntu/bosh-for-pcf.yml"
# upload private key for BOSH to opsman vm
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman opsman ubuntu@${opsmanfqdn}:/home/ubuntu/bosh"
# upload deploy bosh script to opsman vm
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman deploy_bosh_for_pcf.sh ubuntu@${opsmanfqdn}:/home/ubuntu/deploy_bosh_for_pcf.sh"
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman root_ca_certificate ubuntu@${opsmanfqdn}:/home/ubuntu/root_ca_certificate"
# start the deployment of BOSH
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh -o StrictHostKeyChecking=no -i opsman ubuntu@${opsmanfqdn} 'chmod a+x deploy_bosh_for_pcf.sh'"
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh -i opsman ubuntu@${opsmanfqdn} './deploy_bosh_for_pcf.sh 2&> deploy-BOSH.log'" -runMaxAllowedTime 3600
$director_info = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh -o StrictHostKeyChecking=no -i opsman ubuntu@${opsmanfqdn} 'bosh status'"

Write-Host "        BOSH director is deployed"
Write-Host ""

Write-Host "  7. Deploy PCF on Azure"
# get storage prefix
$prefix = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "azure group deployment list $resourceGroup_PCF | grep -i 'storage account prefix' | awk {'print `$7'}"
# update cloud-config then upload to opsman vm
$prefix = $prefix.Substring(1)
$prefix = '*' + $prefix + '*'
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "sed -i 's/REPLACE_WITH_YOUR_STORAGE/$prefix/g' pcf-cloud-config.yml"
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman pcf-cloud-config.yml ubuntu@${opsmanfqdn}:/home/ubuntu/pcf-cloud-config.yml"
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman pcf-on-azure.yml ubuntu@${opsmanfqdn}:/home/ubuntu/pcf-on-azure.yml"

# upload script for download releases
RemoteCopy -uploadTo $publicIP -port $port -files '.\remote-scripts\pcf\download_releases.py' -username $userName -password $passwd -upload
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman download_releases.py ubuntu@${opsmanfqdn}:/home/ubuntu/download_releases.py"

# upload script for upload releases
RemoteCopy -uploadTo $publicIP -port $port -files '.\remote-scripts\pcf\upload_releases.sh' -username $userName -password $passwd -upload
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman upload_releases.sh ubuntu@${opsmanfqdn}:/home/ubuntu/upload_releases.sh"

# upload scropt for get stemcell-version information for a elastic runtime release
RemoteCopy -uploadTo $publicIP -port $port -files '.\remote-scripts\pcf\get_stemcell_version.py' -username $userName -password $passwd -upload
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman get_stemcell_version.py ubuntu@${opsmanfqdn}:/home/ubuntu/get_stemcell_version.py"

# upload deploy_pcf_on_azure.sh
RemoteCopy -uploadTo $publicIP -port $port -files '.\remote-scripts\pcf\deploy_pcf_on_azure.sh' -username $userName -password $passwd -upload
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "scp -i opsman deploy_pcf_on_azure.sh ubuntu@${opsmanfqdn}:/home/ubuntu/deploy_pcf_on_azure.sh"

# update manifest of pcf according to elastic runtime version and start the PCF deployment
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh -i opsman ubuntu@${opsmanfqdn} 'chmod a+x deploy_pcf_on_azure.sh'"
RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh -i opsman ubuntu@${opsmanfqdn} 'chmod a+x upload_releases.sh'"

RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh -i opsman ubuntu@${opsmanfqdn} './deploy_pcf_on_azure.sh $lb_ip $director_passwd $elasticRuntimeVersion $pivotalDownloadAPIToken 2&> deploy-PCF.log'" -runMaxAllowedTime 7200
$chk = RunLinuxCmd -username $userName -password $passwd -ip $publicIP -port $port -command "ssh -i opsman ubuntu@${opsmanfqdn} 'cat deploy-PCF.log | grep Deployed | grep p-bosh | grep pcf-on-azure | wc -l'"
if($chk -eq 1)
{
    Write-Host "        PCF is deployed successfully"
}
else
{
    Write-Host "        PCF is deployed failed"
}

Write-Host ""

## TODO: CAT



