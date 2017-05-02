<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

try
{

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

    $isDeployed = CreateAllRGDeploymentsWithTempParameters -templateName $currentTestData.setupType -location $location -TemplateFile ..\azure-quickstart-templates\bosh-setup\azuredeploy.json  -TemplateParameterFile .\azuredeploy.parameters.json

    if ($isDeployed[0] -eq $True)
    {		
        $testResult_deploy_bosh = "PASS"
    }
    else
    {
        $testResult_deploy_bosh = "Failed"
        throw 'deploy resouces with error, please check.'
    }
	
    # connect to the devbox then deploy cf
    $rg_info_outputs = $(Get-AzureRmResourceGroupDeployment -ResourceGroupName $isDeployed[1]).outputs
	$cf_ip = $($rg_info_outputs.values | Where-Object {$_.value -match '^\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}$'}).value
    $dep_ssh_info = $($rg_info_outputs.values | Where-Object {$_.value -match 'ssh' -and $_.value -match 'devbox'}).value.Split('')[1]
    LogMsg $dep_ssh_info
    $port = 22
    $sshKey = "cf_devbox_privatekey.ppk"
    $command = 'hostname'
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

    if($global:RunnerMode -eq "OnDemand" -and $env:BoshCLIVersion -eq "latest")
    {
        LogMsg "OnDemand mode, but request to update bosh cli to the latest"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo gem install bosh_cli --no-ri --no-rdoc"
        $out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh -v"
        LogMsg "UPDATED bosh cli version: $out"
    }

    LogMsg "Install expect"
    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo apt-get install expect -y"

	$cfScenario = 'deploy-for-enterprise-single-vm-cf'
	$yml_file = "$cfScenario.yml"
	$id = [guid]::NewGuid().ToString()
    $id = $id.Replace('-','').Substring(0,7)
	$new_storage_account = "storage" + $id

	# get the RG location
	$new_storage_loc = $location
	$availability_set = "as-" + $id
	$str_params = "$new_storage_account,$new_storage_loc,$availability_set"
	LogMsg "Update $yml_file"
	echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\remote-scripts\cf-manifest-handle.py ${dep_ssh_info}:
	$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "python cf-manifest-handle.py example_manifests/single-vm-cf.yml $yml_file `'$str_params`' && echo yml_update_pass || echo yml_update_fail"

	if($out -match 'yml_update_pass')
	{
		$tmprunsh = @"
#!/bin/bash
{ /home/azureuser/deploy_cloudfoundry.sh $yml_file && echo cf_deploy_ok || echo cf_deploy_fail; } | tee deploy-$cfScenario.log
"@

		$wrappersh = @"
#!/usr/bin/expect
set timeout -1
spawn  /home/azureuser/tmprun.sh
expect "Enter a password(note: password should not contain special characters: @,' and so on) to use in $yml_file" { send "\r" }
expect "Type yes to continue" { send "yes\r" }
expect "Enter a password(note: password should not contain special characters: @,' and so on) to use in $yml_file"
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
		LogMsg "Start to deploy $cfScenario"
		echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./wrapper.sh"
		echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port ${dep_ssh_info}:deploy-$cfScenario.log $LogDir\deploy-$cfScenario.log
		#$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./deploy_cloudfoundry.sh example_manifests/$cfScenario.yml && echo cf_deploy_ok || echo cf_deploy_fail"
		$out = [String](Get-Content $LogDir\deploy-$cfScenario.log)

		if ($out -match "cf_deploy_ok")
		{
			$testResult = "FAIL"
			LogMsg "deploy $cfScenario successfully, start to verify the scenario feature"

			# verification about bosh deployment
			LogMsg "Check VMs of bosh deployment on devbox"
			[String]$vms_info = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh vms deploy-cf-for-enterprise"
			LogMsg "$vms_info"
			$vms_running_count = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh vms deploy-cf-for-enterprise | grep -i running | wc -l"
			$postgres_z1_running_count = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh vms deploy-cf-for-enterprise | grep -i postgres_z1 | grep -i running | wc -l"
			$mytestjob_z1_running_count = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh vms deploy-cf-for-enterprise | grep -i mytestjob_z1 | grep -i running | wc -l"
			if($vms_running_count -eq 3)
			{
				if($postgres_z1_running_count -eq 2)
				{
					if($mytestjob_z1_running_count -eq 1)
					{
						$testResult_bosh_deployment_vms = "PASS"
						LogMsg "[PASS][deployment] Expect 1 mytestjob vm instance in deployment is running and actually $mytestjob_z1_running_count instance(s)."					
					}
					else 
					{
						$testResult_bosh_deployment_vms = "FAIL"
						LogMsg "Expect 1 mytestjob vm instance in deployment is running but actually $mytestjob_z1_running_count instance(s)."					
					}
				}
				else
				{
					$testResult_bosh_deployment_vms = "FAIL"
					LogMsg "Expect 2 postgres vm instances in deployment are running but actually $postgres_z1_running_count instance(s)."
				}
			}
			else 
			{
				$testResult_bosh_deployment_vms = "FAIL"
				LogMsg "Expect 3 vm instances in deployment are running but actually $vms_running_count instance(s)."
			}

			$original_storage = $($(Get-AzureRmVM -ResourceGroupName $isDeployed[1] -Name $jsonfile.parameters.vmName.value).StorageProfile.OsDisk.Vhd.Uri).Split('.')[0].Split('/')[-1]
			$postgres_z1_using_orginal_storage = $true

			# verification about availability set
			# 1. check the availability set is created
			$my_set = Find-AzureRmResource -ResourceType Microsoft.Compute/availabilitySets -ResourceNameContains "$availability_set" -ResourceGroupName $isDeployed[1]
			if($my_set -eq $null)
			{
				$testResult_availability_set = "FAIL"
				LogMsg "Expect the avaiability set ${availability_set} is created automatically but actually no."
			}
			else
			{
				# 2. check there are 2 instance are putted in set
				$my_set = Get-AzureRmAvailabilitySet -ResourceGroupName $isDeployed[1] -Name $availability_set
				$VMs = $my_set.VirtualMachinesReferences
				if($VMs.count -eq 2)
				{
					$check = 0
					foreach($vm in $VMs)
					{
						$resource_id = $vm.id
						$resource_name = $(Get-AzureRmResource -ResourceId $resource_id).ResourceName
						$instance = Get-AzureRmVM -Status -ResourceGroupName $isDeployed[1] -Name $resource_name
						$osdisk_vhd_uri = $(Get-AzureRmVM -Name $resource_name -ResourceGroupName $isDeployed[1]).StorageProfile.OsDisk.Vhd.Uri
						if($($instance.Statuses | Where-Object {$_.DisplayStatus -contains 'vm running'}).count -eq 1)
						{
							$check += 1
						}
						$match_storage = "https://${original_storage}.blob.core"
						if($osdisk_vhd_uri.Contains($match_storage))
						{
							$postgres_z1_using_orginal_storage = $postgres_z1_using_orginal_storage -and $true
						}
						else 
						{
							$postgres_z1_using_orginal_storage = $postgres_z1_using_orginal_storage -and $false
						}
					}
					if($check -eq 2)
					{
						$testResult_availability_set = "PASS" 
						LogMsg "[PASS][availability set] Expect 2 instances are running and actually $check vm instance(s) running."
					}
					else 
					{	
						$testResult_availability_set = "FAIL" 
						LogMsg "Expect 2 instances are running but actually $check vm instance(s) running."
					}
				}
				else 
				{
					$testResult_availability_set = "FAIL"
					LogMsg "Expect 2 instances are associate with the availability set but actually have $($VMs.count) vm instance(s)."
				}
			}

			# verification about multiple storage account
			# 1. verify the new storage account is created
			$storage = Get-AzureRmResource -ResourceName $new_storage_account -ResourceGroupName $isDeployed[1]
			if($storage -eq $null)
			{
				$testResult_multiple_storage_account = "FAIL"
				LogMsg "Expect the storage account $new_storage_account is created automatically but actually no."
			}
			else 
			{
				# verify if it's premium storage
				if($storage.sku.name -eq "Premium_LRS" -and $storage.sku.tier -eq "Premium")
				{
					# verify the seconde job is using the new account
					$mytestjob_resource = Find-AzureRmResource -ResourceNameContains $new_storage_account -ResourceType microsoft.compute/virtualMachines -ResourceGroupNameContains $isDeployed[1]
					$mytestjob_vm_resource_id = $mytestjob_resource.ResourceId
					$mytestjob_vm_resource = Get-AzureRmResource -ResourceId $mytestjob_vm_resource_id
					$osdisk_uri = $mytestjob_vm_resource.Properties.StorageProfile.OsDisk.Vhd.Uri
					$match = "https://${new_storage_account}.blob.core"
					if($osdisk_uri.Contains($match))
					{
						# verfiy the postgres_z1 instances using the original stroage account
						if($postgres_z1_using_orginal_storage)
						{
							$testResult_multiple_storage_account = "PASS"
							LogMsg "[PASS][storage account] Expect postgres_z1 instances use the original storage and actually yes."
						}
						else 
						{
							$testResult_multiple_storage_account = "FAIL"
							LogMsg "Expect postgres_z1 instances use the original storage but actually no."
						}
					}
					else 
					{
						$testResult_multiple_storage_account = "FAIL"
						LogMsg "Expect the vm instance of mytestjob_z1 use the storage account ${new_storage_account} but actually no."	
					}
				}
				else 
				{
					$testResult_multiple_storage_account = "FAIL"
					LogMsg "Expect the storage is premium storage but actually no."	
				}
			}


			if($testResult_bosh_deployment_vms -eq "PASS" -and $testResult_availability_set -eq "PASS" -and $testResult_multiple_storage_account -eq "PASS")
			{
				$testResult = "PASS"
				LogMsg "Test PASS, remove deployment deploy-cf-for-enterprise"
				echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh -n delete deployment deploy-cf-for-enterprise"
			}
			else
			{
				$testResult = "FAIL"
				LogMsg "test failed. please check the error messages."
			}
		}
		else
		{
			$testResult = "FAIL"
			LogMsg "deploy $cfScenario failed, please check details from $LogDir\deploy-$cfScenario.log"
		}
	}
	else
	{
		$testResult = "FAIL"
		LogMsg "cf manifest update fail,skip to deploy cf"		
	}	
}
catch
{
    $info = $_.InvocationInfo
    "Line{0}, Col{1}, caught exception:{2}" -f $info.ScriptLineNumber,$info.OffsetInLine ,$_.Exception.Message
}
Finally
{
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
