<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

try
{
    $templateName = $currentTestData.testName
    $parameters = $currentTestData.parameters
    $location = $xmlConfig.config.Azure.General.Location

    if(Test-Path .\azuredeploy.parameters.json)
    {
        Remove-Item .\azuredeploy.parameters.json
    }

    # update template parameter file 
    LogMsg 'update template parameter file '
    $jsonfile =  Get-Content ..\azure-quickstart-templates\bosh-setup\azuredeploy.parameters.json -Raw | ConvertFrom-Json
    $curtime = Get-Date
    $timestr = "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Hour + "-" + $curtime.Minute + "-" + $curtime.Second
    $jsonfile.parameters.vmName.value = $parameters.vmName + $timestr
    $jsonfile.parameters.adminUsername.value = $parameters.adminUsername
    $jsonfile.parameters.sshKeyData.value = $parameters.sshKeyData
    $jsonfile.parameters.environment.value = $parameters.environment
    $jsonfile.parameters.tenantID.value = $parameters.tenantID
    $jsonfile.parameters.clientID.value = $parameters.clientID
    $jsonfile.parameters.clientSecret.value = $parameters.clientSecret
    $jsonfile.parameters.autoDeployBosh.value = $parameters.autoDeployBosh
    
    # save template parameter file
    $jsonfile | ConvertTo-Json | Out-File .\azuredeploy.parameters.json
    if(Test-Path .\azuredeploy.parameters.json)
    {
        LogMsg "successful save azuredeploy.parameters.json"
    }
    else
    {
        LogMsg "fail to save azuredeploy.parameters.json"
    }


    $isDeployed = CreateAllRGDeploymentsWithTempParameters -templateName $templateName -location $location -TemplateFile ..\azure-quickstart-templates\bosh-setup\azuredeploy.json  -TemplateParameterFile .\azuredeploy.parameters.json

    if ($isDeployed[0] -eq $True)
    {

        $testResult_deploy = "PASS"
    }
    else
    {
        $testResult_deploy = "Failed"
    }

    # connect to the devbox
    $subscription_id = $AzureSetup.SubscriptionID
    $storage = $($(Get-AzureResourceGroup -Name $isDeployed[1]).Resources | Where-Object {$_.ResourceType -eq 'Microsoft.Storage/storageAccounts'}).Name
    $rgname = $isDeployed[1]
    $tenantid = $jsonfile.parameters.tenantID.value
    $clientid = $jsonfile.parameters.clientID.value
    $clientsecret = $jsonfile.parameters.clientSecret.value
    $sshpublickey = $jsonfile.parameters.sshKeyData.value
    $dep_ssh_info = $(Get-AzureResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs['sshDevBox'].Value.Split(' ')[1]
    $port = 22
    $sshKey = "cf_devbox_privatekey.ppk"
    
    
    try
    {
        # prepare test
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo apt-get install git -y"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "git clone https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release.git"
        # install npm
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo apt-get install npm -y"
        # install azure-cli
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo npm install azure-cli -g"
        # create a soft link for nodejs
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo ln -s /usr/bin/nodejs /usr/local/bin/node"
    }
    catch 
    {
        $ErrorMessage =  $_.Exception.Message
        Write-Host "$ErrorMessage"
    }
   
    # generate the life cycle test script
    $src = @"
#!/usr/bin/env bash

export BOSH_AZURE_SUBSCRIPTION_ID=$subscription_id
export BOSH_AZURE_STORAGE_ACCOUNT_NAME=$storage
export BOSH_AZURE_RESOURCE_GROUP_NAME=$rgname
export BOSH_AZURE_TENANT_ID=$tenantid
export BOSH_AZURE_CLIENT_ID=$clientid
export BOSH_AZURE_CLIENT_SECRET=$clientsecret
export BOSH_AZURE_VNET_NAME='boshvnet-crp'
export BOSH_AZURE_SUBNET_NAME='Bosh'
export BOSH_AZURE_SSH_PUBLIC_KEY='$sshpublickey'
export BOSH_AZURE_DEFAULT_SECURITY_GROUP='nsg-bosh'
export BOSH_AZURE_ENVIRONMENT='AzureCloud'

azure login --service-principal -u `${BOSH_AZURE_CLIENT_ID} -p `${BOSH_AZURE_CLIENT_SECRET} --tenant `${BOSH_AZURE_TENANT_ID}
azure config mode arm
AZURE_STORAGE_ACCESS_KEY=`$(azure storage account keys list `${BOSH_AZURE_STORAGE_ACCOUNT_NAME} -g `${BOSH_AZURE_RESOURCE_GROUP_NAME} --json | jq '.key1' -r)

export BOSH_AZURE_STEMCELL_ID="bosh-stemcell-00000000-0000-0000-0000-0AZURECPICI0"
export AZURE_STORAGE_ACCOUNT=`${BOSH_AZURE_STORAGE_ACCOUNT_NAME}
export AZURE_STORAGE_ACCESS_KEY

azure storage blob show stemcell `${BOSH_AZURE_STEMCELL_ID}.vhd
if [ `$? -eq 1 ]; then
    echo 'download stemcell'
    wget -q -O `${PWD}/stemcell.tgz https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3169
    echo 'upload stemcell to storage'
    sudo tar -xf `${PWD}/stemcell.tgz -C /mnt/
    sudo tar -xf /mnt/image -C /mnt/
    azure storage blob upload -q --blobtype PAGE /mnt/root.vhd stemcell `${BOSH_AZURE_STEMCELL_ID}.vhd
fi

cd bosh-azure-cpi-release/src/bosh_azure_cpi

sudo gem install bundler --no-ri --no-rdoc
sudo ln -s /usr/local/bin/bundle /usr/bin/bundle
bundle install
bundle exec rspec spec/integration | tee execution.log
"@

    $src | Out-File .\run-lifecycletest.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\run-lifecycletest.sh
    
    # uploading script to devbox
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\run-lifecycletest.sh ${dep_ssh_info}:

    # kickoff test
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x run-lifecycletest.sh"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./run-lifecycletest.sh &> lifecycletest.log"
    $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "cat lifecycletest.log"

    if ($out -match "failure")
    {
        $testResult_life_cycle_test = "Failed"
        LogMsg "life cycle test failed, please ssh to devbox check details from lifecycletest.log"
    }
    else
    {
        $testResult_life_cycle_test = "PASS"
        LogMsg "life cycle test successfully"
    }

    if ($testResult_deploy -eq "PASS" -and $testResult_life_cycle_test -eq "PASS")
    {
        $testResult = "PASS"
    }
    else
    {
        $testResult = "Failed"
    }


    $testStatus = "TestCompleted"
    LogMsg "Test result : $testResult"

    if ($testStatus -eq "TestCompleted")
    {
        LogMsg "Test Completed"
    }
}
catch
{
    $ErrorMessage =  $_.Exception.Message
    LogMsg "EXCEPTION : $ErrorMessage"   
}
Finally
{
    $metaData = ""
    if (!$testResult)
    {
        $testResult = "Aborted"
    }
    $resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed[1] -ResourceGroups $isDeployed[1]

#Return the result and summery to the test suite script..
return $result
