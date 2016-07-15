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

    if($global:RunnerMode -eq "Runner")
    {
        $out = .\remote-scripts\bosh-cf-template-handler.ps1 ..\azure-quickstart-templates\bosh-setup\azuredeploy.json $parameters.environment runner
    }

    if($global:RunnerMode -eq "OnDemand" -and $global:OnDemandVersInfo -ne $null)
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

        $testResult_deploy_bosh = "PASS"
    }
    else
    {
        $testResult_deploy_bosh = "Failed"
        throw 'deploy resouces with error, please check.'
    }

    # connect to the devbox then deploy multi-vms cf
    $dep_ssh_info = $(Get-AzureRmResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs['sshDevBox'].Value.Split(' ')[1]
    LogMsg $dep_ssh_info
    $port = 22
    $sshKey = "cf_devbox_privatekey.ppk"
    $command = 'hostname'
    
    # ssh to devbox and deploy multi-vms cf
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "$command"

    $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh -v"
    LogMsg "Current bosh cli version: $out"
    if($global:RunnerMode -eq "Runner")
    {
        LogMsg "Runner mode, Update bosh cli to the latest"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo gem install bosh_cli --no-ri --no-rdoc"
        $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh -v"
        LogMsg "UPDATED bosh cli version: $out"
    }

    LogMsg "Install expect"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo apt-get install expect -y"
    $tmprunsh = @"
#!/bin/bash
/home/azureuser/deploy_cloudfoundry.sh example_manifests/multiple-vm-cf.yml && echo multi_vms_cf_deploy_ok || echo multi_vms_cf_deploy_fail
"@

    $wrappersh = @"
#!/usr/bin/expect
set timeout -1
spawn  /home/azureuser/tmprun.sh
expect "Enter a password to use in example_manifests/multiple-vm-cf.yml" { send "\r" }
expect "Type yes to continue" { send "yes\r" }
expect "Enter a password to use in example_manifests/multiple-vm-cf.yml"
"@
    LogMsg "generate test scripts"
    $wrappersh | Out-File .\wrapper.sh -Encoding utf8
    $tmprunsh | Out-File .\tmprun.sh -Encoding utf8
    .\tools\dos2unix.exe -q .\wrapper.sh
    .\tools\dos2unix.exe -q .\tmprun.sh
    LogMsg "upload test scripts"
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\wrapper.sh ${dep_ssh_info}:
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\tmprun.sh ${dep_ssh_info}:
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x wrapper.sh"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x tmprun.sh"

    $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./wrapper.sh"

    # autoDeployBosh always set to enabled in cf runner
<#    if($parameters.autoDeployBosh -eq "disabled")
    {
        LogMsg "generate test scripts"
        $pre | Out-File .\pre-action.sh -Encoding utf8
        .\tools\dos2unix.exe -q .\pre-action.sh
        LogMsg "upload test scripts"
        echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\pre-action.sh ${dep_ssh_info}:
        echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\remote-scripts\bosh-cf-perf-yaml-handler.py ${dep_ssh_info}:
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x *.sh"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x *.py"
        LogMsg "prepare test"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./pre-action.sh"
        $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./deploy_bosh.sh && echo bosh_deploy_ok || echo bosh_deploy_fail"
        if ($out -match 'bosh_deploy_ok')
        {
            LogMsg "deploy bosh successfully then start to deploy multi-vms cf"
            $testResult_deploy_bosh = "PASS"
            $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./deploy_cloudfoundry.sh example_manifests/multiple-vm-cf.yml && echo multi_vms_cf_deploy_ok || echo multi_vms_cf_deploy_fail"   
        }
        else
        {
            LogMsg "deploy bosh failed."
            $testResult_deploy_bosh = "Failed"
            throw 'deploy bosh failed, please check.'
        }
    } #>

    # upload deploy log to devbox
    $out | Out-File .\deploy_cloudfoundry.log -Encoding utf8
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\deploy_cloudfoundry.log ${dep_ssh_info}:

    # archive log and configs
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "tar -czf all.tgz deploy_cloudfoundry.log bosh.yml example_manifests/multiple-vm-cf.yml deploy_cloudfoundry.sh"
    $downloadto = "all-" + $isDeployed.GetValue(1) + ".tgz"
    LogMsg "download test archives as $downloadto"
    echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:all.tgz $downloadto

    if ($out -match "multi_vms_cf_deploy_ok")
    {
        $testResult_deploy_multi_vms_cf = "PASS"
        LogMsg "deploy multi vms cf successfully"
    }
    else
    {
        $testResult_deploy_multi_vms_cf = "Failed"
        LogMsg "deploy multi vms cf failed, please ssh to devbox and check details from deploy_cloudfoundry.log"
    }

    if ($testResult_deploy_bosh -eq "PASS" -and $testResult_deploy_multi_vms_cf -eq "PASS")
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
