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

    if($global:PerfMode -eq "OnDemand" -and $global:OnDemandVersInfo -ne $null)
    {
        $out = .\remote-scripts\bosh-cf-template-handler.ps1 ..\azure-quickstart-templates\bosh-setup\azuredeploy.json $parameters.environment ondemand $global:OnDemandVersInfo
    }

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

    # perf test params
    $BOSH_AZURE_INSTANCE_TYPE = $parameters.boshInstanceType
    $BOSH_AZURE_DISK_SIZE = $parameters.boshDiskSize
    $BOSH_AZURE_COMPILE_INSTANCE_TYPE = $parameters.compilationInstanceType
    $BOSH_AZURE_COMPILE_DISK_SIZE = $parameters.compilationDiskSize
    $BOSH_AZURE_CF_RP_SMALL = $parameters.cfSmallInstanceType
    $BOSH_AZURE_CF_RP_MEDIUM = $parameters.cfMediumInstanceType
    $BOSH_AZURE_CF_RP_LARGE = $parameters.cfLargeInstanceType

    $bosh_instance_require_premium = $False
    $compile_instance_require_premium = $False
    $cf_rp_small_require_premium = $False
    $cf_rp_medium_require_premium = $False
    $cf_rp_large_require_premium = $False

    if(($BOSH_AZURE_INSTANCE_TYPE -match '_ds') -or ($BOSH_AZURE_INSTANCE_TYPE -match '_gs'))
    {
        $bosh_instance_require_premium = $True
    }

    if(($BOSH_AZURE_COMPILE_INSTANCE_TYPE -match '_ds') -or ($BOSH_AZURE_COMPILE_INSTANCE_TYPE -match '_gs'))
    {
        $compile_instance_require_premium = $True
    }

    if(($BOSH_AZURE_CF_RP_SMALL -match '_ds') -or ($BOSH_AZURE_CF_RP_SMALL -match '_gs'))
    {
        $cf_rp_small_require_premium = $True
    }

    if(($BOSH_AZURE_CF_RP_MEDIUM -match '_ds') -or ($BOSH_AZURE_CF_RP_MEDIUM -match '_gs'))
    {
        $cf_rp_medium_require_premium = $True
    }

    if(($BOSH_AZURE_CF_RP_LARGE -match '_ds') -or ($BOSH_AZURE_CF_RP_LARGE -match '_gs'))
    {
        $cf_rp_large_require_premium = $True
    }

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

        $testResult_deploy_devbox = "PASS"
    }
    else
    {
        $testResult_deploy_devbox = "Failed"
    }

    # connect to the devbox then deploy multi-vms cf
    $dep_ssh_info = $(Get-AzureRmResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs['sshDevBox'].Value.Split(' ')[1]
    LogMsg $dep_ssh_info
    $storage = $(Find-AzureRmResource -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceGroupNameContains $isDeployed[1]).ResourceName
    LogMsg "$storage"
    $port = 22
    $sshKey = "cf_devbox_privatekey.ppk"
    $command = 'hostname'
    # set the default storage firstly
    $BOSH_AZURE_VM_STORAGE_ACCOUNT = $storage
    $BOSH_AZURE_COMPILE_VM_STORAGE_ACCOUNT = $storage
    $BOSH_AZURE_CF_RP_SMALL_STORAGE_ACCOUNT = $storage
    $BOSH_AZURE_CF_RP_MEDIUM_STORAGE_ACCOUNT = $storage
    $BOSH_AZURE_CF_RP_LARGE_STORAGE_ACCOUNT = $storage

    # prepare the required storage and override if needed
    if ($bosh_instance_require_premium -or $compile_instance_require_premium -or $cf_rp_small_require_premium -or $cf_rp_medium_require_premium -or $cf_rp_large_require_premium)
    {
        $curtime1 = Get-Date
        $timestr1 = "" + $curtime.Month + $curtime.Day + $curtime.Hour + $curtime.Minute + $curtime.Second
        $premiumstorage = "cfpremstor" + $timestr1
        LogMsg "creating premium storage: $premiumstorage for rg $($isDeployed.GetValue(1))"
        $location = $location.Replace('"','')
        New-AzureRmStorageAccount -ResourceGroupName $isDeployed[1] -Name $premiumstorage -SkuName Premium_LRS -Location $location -Kind Storage
        if($? -eq $True)
        {
            LogMsg "created storage successfully"
            LogMsg "createing containers: 'bosh' and 'stemcell'"
            ####
            $ctx = $(Get-AzureRmStorageAccount -ResourceGroupName $isDeployed[1] -Name $premiumstorage).Context
            New-AzureStorageContainer -Context $ctx -Name 'bosh'
            if($? -eq $True)
            {
                LogMsg "created container 'bosh' successfully"
            }
            else 
            {
                LogMsg "created container 'bosh' failed"    
            }
            New-AzureStorageContainer -Context $ctx -Name 'stemcell'
            if($? -eq $True)
            {
                LogMsg "created container 'stemcell' successfully"
            }
            else 
            {
                LogMsg "created container 'stemcell' failed"    
            }
        }
        else 
        {
            LogMsg "created storage failed"
        }
    }

    if($bosh_instance_require_premium)
    {
        $BOSH_AZURE_VM_STORAGE_ACCOUNT = $premiumstorage
    }

    if($compile_instance_require_premium)
    {
        $BOSH_AZURE_COMPILE_VM_STORAGE_ACCOUNT = $premiumstorage
    }

    if($cf_rp_small_require_premium)
    {
        $BOSH_AZURE_CF_RP_SMALL_STORAGE_ACCOUNT = $premiumstorage
    }

    if($cf_rp_medium_require_premium)
    {
        $BOSH_AZURE_CF_RP_MEDIUM_STORAGE_ACCOUNT = $premiumstorage
    }

    if($cf_rp_large_require_premium)
    {
        $BOSH_AZURE_CF_RP_LARGE_STORAGE_ACCOUNT = $premiumstorage
    }

    LogMsg "bosh instance storage: $BOSH_AZURE_VM_STORAGE_ACCOUNT"
    LogMsg "compilation instance storage: $BOSH_AZURE_COMPILE_VM_STORAGE_ACCOUNT"
    LogMsg "resource_pool_small_z1 storage: $BOSH_AZURE_CF_RP_SMALL_STORAGE_ACCOUNT"
    LogMsg "resource_pool_medium_z1 storage: $BOSH_AZURE_CF_RP_MEDIUM_STORAGE_ACCOUNT"
    LogMsg "resource_pool_large_z1 storage: $BOSH_AZURE_CF_RP_LARGE_STORAGE_ACCOUNT"
    
    $pre = @"
#!/usr/bin/env bash

export BOSH_AZURE_INSTANCE_TYPE='${BOSH_AZURE_INSTANCE_TYPE}'
export BOSH_AZURE_VM_STORAGE_ACCOUNT='${BOSH_AZURE_VM_STORAGE_ACCOUNT}'
export BOSH_AZURE_COMPILE_INSTANCE_TYPE='${BOSH_AZURE_COMPILE_INSTANCE_TYPE}'
export BOSH_AZURE_COMPILE_VM_STORAGE_ACCOUNT='${BOSH_AZURE_COMPILE_VM_STORAGE_ACCOUNT}'
export BOSH_AZURE_DISK_SIZE='${BOSH_AZURE_DISK_SIZE}'
export BOSH_AZURE_COMPILE_DISK_SIZE='${BOSH_AZURE_COMPILE_DISK_SIZE}'
export BOSH_AZURE_CF_RP_SMALL='${BOSH_AZURE_CF_RP_SMALL}'
export BOSH_AZURE_CF_RP_MEDIUM='${BOSH_AZURE_CF_RP_MEDIUM}'
export BOSH_AZURE_CF_RP_LARGE='${BOSH_AZURE_CF_RP_LARGE}'
export BOSH_AZURE_CF_RP_SMALL_STORAGE_ACCOUNT='${BOSH_AZURE_CF_RP_SMALL_STORAGE_ACCOUNT}'
export BOSH_AZURE_CF_RP_MEDIUM_STORAGE_ACCOUNT='${BOSH_AZURE_CF_RP_MEDIUM_STORAGE_ACCOUNT}'
export BOSH_AZURE_CF_RP_LARGE_STORAGE_ACCOUNT='${BOSH_AZURE_CF_RP_LARGE_STORAGE_ACCOUNT}'

python bosh-cf-perf-yaml-handler.py bosh.yml
python bosh-cf-perf-yaml-handler.py example_manifests/multiple-vm-cf.yml
"@

    $deployboshwithretry = @"
#!/usr/bin/env bash

deploy_bosh_result=1
retry=1
while [ `${retry} -lt 4 ]; do
    echo 'deploy bosh retry#'`${retry}
    { time ./deploy_bosh.sh; } &> deploy_bosh_test_`${retry}.log
    if [ `$? -eq 0 ]; then
        echo 'deploy_bosh_ok'
        deploy_bosh_result=0
        mv deploy_bosh_test_`${retry}.log deploy_bosh_test.log
        break
    else
        let retry=retry+1
    fi
done

rm -rf DEPLOY_BOSH_PASS
if [ `$deploy_bosh_result -eq 0 ]; then
    touch DEPLOY_BOSH_PASS
fi
"@

    $deploycfonce = @"
#!/usr/bin/env bash

if [ -e DEPLOY_BOSH_PASS ]; then
    ./wrapper.sh
else 
    echo 'terminate deploy cf since deploy_bosh_failed.'
fi

rm -rf DEPLOY_CF_PASS
if [ -e deploy_cf_test.log ];then
    catch=``cat deploy_cf_test.log | grep 'multiple-cf-on-azure' | grep 'Deployed' | grep 'bosh' | wc -l``
    if [ `$catch -eq 1 ]; then
        touch DEPLOY_CF_PASS
        echo 'deploy_cf_ok'
    fi
fi
"@

    $tmprunsh = @"
#!/bin/bash
{ time ./deploy_cloudfoundry.sh example_manifests/multiple-vm-cf.yml; } | tee deploy_cf_test.log
"@

    $wrappersh = @"
#!/usr/bin/expect
set timeout -1
spawn  /home/azureuser/tmprun.sh
expect "Enter a password to use in example_manifests/multiple-vm-cf.yml" { send "\r" }
expect "Type yes to continue" { send "yes\r" }
expect "Enter a password to use in example_manifests/multiple-vm-cf.yml"
"@

    $post = @"
#!/usr/bin/env bash
if [ -e DEPLOY_BOSH_PASS ]; then
    python bosh-cf-perf-log-analyser.py bosh
fi

if [ -e DEPLOY_CF_PASS ]; then
    python bosh-cf-perf-log-analyser.py cf
fi

tar -czf all.tgz deploy_bosh_test*.log deploy_cf_test.log bosh.yml example_manifests/multiple-vm-cf.yml deploy_cloudfoundry.sh
"@

    # ssh to devbox 
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "$command"

    LogMsg "Install expect"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo apt-get install expect -y"

    LogMsg "generate test scripts"
    $pre | Out-File .\pre-action.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\pre-action.sh
    
    $deployboshwithretry | Out-File .\deployboshwithretry.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\deployboshwithretry.sh
    $deploycfonce | Out-File .\deploycfonce.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\deploycfonce.sh
    $tmprunsh | Out-File .\tmprun.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\tmprun.sh
    $wrappersh | Out-File .\wrapper.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\wrapper.sh

    $post | Out-File .\post-action.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\post-action.sh
    LogMsg "upload test scripts"
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\pre-action.sh ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\deployboshwithretry.sh ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\deploycfonce.sh ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\tmprun.sh ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\wrapper.sh ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\post-action.sh ${dep_ssh_info}:

    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\remote-scripts\bosh-cf-perf-yaml-handler.py ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\remote-scripts\bosh-cf-perf-log-analyser.py ${dep_ssh_info}:
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x *.sh"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x *.py"

    # update bosh.yml and example_manifests\multiple-vm-cf.yml
    LogMsg "update yaml config files in devbox"
    $out1 = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./pre-action.sh"
    if ($out1 -match 'update yaml config for bosh successfully' -and $out1 -match 'update yaml config for cf successfully')
    {
        $testResult_update_yaml = "PASS"
        LogMsg "update yaml files successfully."
        # deploy bosh and cf
        LogMsg "start to deploy bosh then cf"
        $out2 = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./deployboshwithretry.sh"
        if ($out2 -match "deploy_bosh_ok")
        {
            $testResult_deploy_bosh = "PASS"
            LogMsg "deploy bosh successfully"

            # deploy cf 
            $outx = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./deploycfonce.sh"
            if ($outx -match "deploy_cf_ok")
            {
                $testResult_deploy_multi_vms_cf = "PASS"
                LogMsg "deploy multi vms cf successfully"
            }
            else
            {
                $testResult_deploy_multi_vms_cf = "Failed"
                LogMsg "deploy multi vms cf failed, please ssh to devbox and check details from deploy_cf_test.log"
            }
        }
        else
        {
            $testResult_deploy_bosh = "Failed"
            LogMsg "deploy bosh failed, please ssh to devbox and check details from deploy_bosh_test.log"
        }  
    }
    else 
    {
        $testResult_update_yaml = "Failed"
        LogMsg "update yaml files failed, abort test"
    }
    
    LogMsg "analys result from deploy logs"
    $out3 = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./post-action.sh"
    LogMsg "-----------------------START STATISTIC-----------------------"
    foreach($i in $out3){ LogMsg $i }
    LogMsg "-----------------------END STATISTIC-----------------------"

    $downloadto = "all-" + $isDeployed.GetValue(1) + ".tgz"
    LogMsg "download test archives as $downloadto"
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:all.tgz $downloadto

    if ($testResult_deploy_devbox -eq "PASS" -and $testResult_update_yaml -eq "PASS" -and $testResult_deploy_bosh -eq "PASS" -and $testResult_deploy_multi_vms_cf -eq "PASS")
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
