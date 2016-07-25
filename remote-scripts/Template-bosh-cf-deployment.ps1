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
	if($env:EnableCAT -eq $True)
	{
		LogMsg "CAT enabled"
		$SharedNetworkResourceGroupName = "bosh-share-network"
		$Domains = @{'AzureCloud'='mscfonline.info';'AzureChinaCloud'='mscfonline.site'}
		$Environment = $parameters.environment
		$DomainName = $Domains.$Environment
		$old_cfip = $(Get-AzureRmResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs['cloudFoundryIP'].Value
		$new_cfip = (Get-AzureRmPublicIpAddress -ResourceGroupName $SharedNetworkResourceGroupName -Name devbox-cf).IpAddress
		$testTasks = ("acceptance test","smoke test")
		#$Subtests = ("single-vm-cf","multiple-vm-cf")
		foreach ($SetupType in $currentTestData.SubtestValues.split(","))
		{
			LogMsg "Start to deploy $SetupType"
			if($DeployedMultipleVMCF)
			{
				LogMsg "Remove deployed multiple-cf-on-azure"
				echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "echo yes | bosh delete deployment multiple-cf-on-azure"			
			}
			if($DeployedSingleVMCF)
			{
				LogMsg "Remove deployed single-vm-cf-on-azure"
				echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "echo yes | bosh delete deployment single-vm-cf-on-azure"		
			}
			#update yml file
			LogMsg "Update file $SetupType.yml"
			echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i '/type: vip$/a\  cloud_properties:\n    resource_group_name: $SharedNetworkResourceGroupName' example_manifests/$SetupType.yml"
			echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/$old_cfip/$new_cfip/g' example_manifests/$SetupType.yml"
			echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/$new_cfip.xip.io/$DomainName/g' example_manifests/$SetupType.yml"
			$tmprunsh = @"
#!/bin/bash
{ /home/azureuser/deploy_cloudfoundry.sh example_manifests/$SetupType.yml && echo cf_deploy_ok || echo cf_deploy_fail; } | tee deploy-$SetupType.log
"@

			$wrappersh = @"
#!/usr/bin/expect
set timeout -1
spawn  /home/azureuser/tmprun.sh
expect "Enter a password to use in example_manifests/$SetupType.yml" { send "\r" }
expect "Type yes to continue" { send "yes\r" }
expect "Enter a password to use in example_manifests/$SetupType.yml"
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

			echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./wrapper.sh"
            echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:deploy-$SetupType.log $LogDir\deploy-$SetupType.log
			#$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./deploy_cloudfoundry.sh example_manifests/$SetupType.yml && echo cf_deploy_ok || echo cf_deploy_fail"
			$out = [String](Get-Content $LogDir\deploy-$SetupType.log)
			if($SetupType -eq 'multiple-vm-cf')
			{
				$DeployedMultipleVMCF = $True
			}
			if($SetupType -eq 'single-vm-cf')
			{
				$DeployedSingleVMCF = $True
			}
			if ($out -match "cf_deploy_ok")
			{					
				LogMsg "deploy $SetupType successfully, start to run test"
				foreach($testTask in $testTasks)
				{
					LogMsg "Testing $testTask on $SetupType"
					$metaData = "$testTask on $SetupType"
					if($testTask -eq 'acceptance test')
					{
						if($parameters.environment -eq 'AzureCloud')
						{
							$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "{ bosh run errand acceptance_tests --keep-alive --download-logs --logs-dir /tmp/ && echo cat_test_pass || echo cat_test_fail; } | tee $SetupType-AcceptanceTest.log"						
						}
						else
						{
							$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "{ bosh run errand acceptance_tests_internetless --keep-alive --download-logs --logs-dir /tmp && echo cat_test_pass || echo cat_test_fail; } | tee $SetupType-AcceptanceTest.log"
						}
						echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:$SetupType-AcceptanceTest.log $LogDir\$SetupType-AcceptanceTest.log
                        $out = [String](Get-Content $LogDir\$SetupType-AcceptanceTest.log)
						if($out -match "cat_test_pass")
						{
							LogMsg "****************************************************************"
							LogMsg "$testTask PASS on deployment $SetupType"
							LogMsg "****************************************************************"
							$testResult = "PASS"
						}
						else
						{
							LogMsg "****************************************************************"
							LogMsg "$testTask FAIL on deployment $SetupType"
							LogMsg "please check details from $LogDir\$SetupType-AcceptanceTest.log and $LogDir\$SetupType-AcceptanceTest.tgz"
							LogMsg "****************************************************************"
							$testResult = "FAIL"
						}
						
						$pattern = "Logs saved in '(\S+)'"
						if($out -match $pattern)
						{
							$Logfile = $Matches[1]
							echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:$Logfile $LogDir\$SetupType-AcceptanceTest.tgz
						}
					}
					else
					{
						echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "{ bosh run errand smoke_tests --keep-alive --download-logs --logs-dir /tmp/ && echo smoke_test_pass || echo smoke_test_fail; } | tee $SetupType-SmokeTest.log"						
                        echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:$SetupType-SmokeTest.log $LogDir\$SetupType-SmokeTest.log
                        $out = [String](Get-Content $LogDir\$SetupType-SmokeTest.log)
						if($out -match "smoke_test_pass")
						{
							LogMsg "****************************************************************"
							LogMsg "$testTask PASS on deployment $SetupType"
							LogMsg "****************************************************************"
							$testResult = "PASS"
						}
						else
						{
							LogMsg "****************************************************************"
							LogMsg "$testTask FAIL on deployment $SetupType"
							LogMsg "please check details from $LogDir\$SetupType-SmokeTest.log and $LogDir\$SetupType-SmokeTest.tgz"
							LogMsg "****************************************************************"
							$testResult = "FAIL"
						}						
						$pattern = "Logs saved in '(\S+)'"
						if($out -match $pattern)
						{
							$Logfile = $Matches[1]
							echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:$Logfile $LogDir\$SetupType-SmokeTest.tgz
						}
					}
					$resultArr += $testResult
					$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
				}
			}
			else
			{
				LogMsg "deploy $SetupType failed, please check details from $LogDir\deploy-$SetupType.log"
				$testResult = "FAIL"
				$resultArr += $testResult
				$resultSummary +=  CreateResultSummary -testResult $testResult -metaData "Deploy $SetupType" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
			}
		}
		# Dissociate shared PublicIPAddress for next job use
		$networkInterface = Get-AzureRmNetworkInterface -ResourceGroupName $isDeployed[1]  | where {$_.IpConfigurations[0].PublicIpAddress.Id -match $SharedNetworkResourceGroupName}
		if($networkInterface)
		{
			$networkInterface.IpConfigurations[0].PublicIpAddress = $null
			Set-AzureRmNetworkInterface -NetworkInterface $networkInterface
		}
	}
	else
	{
		$tmprunsh = @"
#!/bin/bash
/home/azureuser/deploy_cloudfoundry.sh example_manifests/multiple-vm-cf.yml | tee deploy_cloudfoundry.log
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

        # run deployment
		echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./wrapper.sh"

		# archive log and configs
		echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "tar -czf all.tgz deploy_cloudfoundry.log bosh.yml example_manifests/multiple-vm-cf.yml deploy_cloudfoundry.sh"
		$downloadto = "all-" + $isDeployed.GetValue(1) + ".tgz"
		LogMsg "download test archives as $downloadto"
		echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:all.tgz $downloadto

        $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "cat deploy_cloudfoundry.log | grep 'multiple-cf-on-azure' | grep 'Deployed' | grep 'bosh' | wc -l | tr -d '\n'"

		if ($out -match "1")
		{
			$testResult_deploy_multi_vms_cf = "PASS"
			LogMsg "deploy multi vms cf successfully"
		}
		else
		{
			$testResult_deploy_multi_vms_cf = "FAIL"
			LogMsg "deploy multi vms cf failed, please ssh to devbox and check details from deploy_cloudfoundry.log"
		}

		if ($testResult_deploy_bosh -eq "PASS" -and $testResult_deploy_multi_vms_cf -eq "PASS")
		{
			$testResult = "PASS"
		}
		else
		{
			$testResult = "FAIL"
		}
		$resultSummary += CreateResultSummary -testResult $testResult -metaData "" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
		$testStatus = "TestCompleted"
		LogMsg "Test result : $testResult"

		if ($testStatus -eq "TestCompleted")
		{
			LogMsg "Test Completed"
		}
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
		$resultArr += $testResult
		$resultSummary += CreateResultSummary -testResult $testResult -metaData "" -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
    }
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed[1] -ResourceGroups $isDeployed[1]

#Return the result and summery to the test suite script..
return $result, $resultSummary
