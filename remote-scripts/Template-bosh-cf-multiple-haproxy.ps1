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

	$cfScenario = 'multiple-haproxy-single-vm-cf'
	$yml_file = "$cfScenario.yml"
	$id = [guid]::NewGuid().ToString()
    $id = $id.Replace('-','').Substring(0,7)
	$availability_set = "as-" + $id
    $load_balancer = "lb-" + $id
    $str_params = "${availability_set},${load_balancer}"
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
        # install nodejs
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "curl -sL https://deb.nodesource.com/setup_7.x | sudo -E bash -"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo apt-get install -y nodejs"
        # install azure-cli via npm
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sudo npm install -g azure-cli"
        
        # azure login with sp
        $tenant = $parameters.tenantID
        $app_id = $parameters.clientID
        $client_secret = $parameters.clientSecret
        $azure_env = $parameters.environment
        $cmd_azure_login = "azure login --service-principal --tenant $tenant -u $app_id -p $client_secret -e $azure_env"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "echo `'#!/usr/bin/env bash`' >> create_lb_entry.sh"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "echo $cmd_azure_login >> create_lb_entry.sh"
        
        # download the script about create lb
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "wget https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/advanced/deploy-multiple-haproxy/create-load-balancer.sh"
        
        # get cf public ip name
        $cf_ip_name = $(Get-AzureRmPublicIpAddress -ResourceGroupName $isDeployed[1] | Where-Object {$_.Name.Contains('-cf')}).Name
        # replace the vars in script
        $RG_name = $isDeployed[1]
        $loc = $location.replace(' ','')
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/REPLACE-ME-WITH-YOUR-RESOURCE-GROUP-NAME/$RG_name/g' create-load-balancer.sh"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/REPLACE-ME-WITH-THE-LOCATION-OF-YOUR-RESOURCE-GROUP/$loc/g' create-load-balancer.sh"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/REPLACE-ME-WITH-THE-PUBLIC-IP-NAME-OF-CLOUDFOUNDRY/$cf_ip_name/g' create-load-balancer.sh"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "sed -i 's/haproxylb/$load_balancer/g' create-load-balancer.sh"

        # append the script content to create_lb_entry.sh
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "cat create-load-balancer.sh >> create_lb_entry.sh"
        # create load balancer 
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "chmod a+x create_lb_entry.sh"
        echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "./create_lb_entry.sh | tee create-load-balancer.log"

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
			[String]$vms_info = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh vms multiple-haproxy"
			LogMsg "$vms_info"
			$vms_running_count = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh vms multiple-haproxy | grep -i running | wc -l"
			$postgres_z1_running_count = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh vms multiple-haproxy | grep -i postgres_z1 | grep -i running | wc -l"
			if($vms_running_count -eq 2)
			{
				if($postgres_z1_running_count -eq 2)
				{
					$testResult_bosh_deployment_vms = "PASS"
                    LogMsg "[PASS][deployment] Expect 2 postgres vm instances in deployment are running and actually $postgres_z1_running_count instance(s) running."
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
				LogMsg "Expect 2 vm instances in deployment are running but actually $vms_running_count instance(s)."
			}

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
                $vm_id_list = @()
				if($VMs.count -eq 2)
				{
					$check = 0
					foreach($vm in $VMs)
					{
						$resource_id = $vm.id
                        $vm_id_list += $resource_id
						$resource_name = $(Get-AzureRmResource -ResourceId $resource_id).ResourceName
						$instance = Get-AzureRmVM -Status -ResourceGroupName $isDeployed[1] -Name $resource_name
						if($($instance.Statuses | Where-Object {$_.DisplayStatus -contains 'vm running'}).count -eq 1)
						{
							$check += 1
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

			# verification about azure load balancer
			# 1. verify the load balancer is created
            # 2. verify the load balancer's backendpool associates with the availability set 
            # 3. verify the load balancer's frontend binding the cf public ip
            $lb = Get-AzureRmLoadBalancer -ResourceGroupName $isDeployed[1] -Name $load_balancer -ErrorAction Ignore
			if($lb -eq $null)
			{
				$testResult_load_balancer = "FAIL"
				LogMsg "Expect the load balancer $load_balancer is created automatically but actually no."
			}
			else 
			{
                $backend_ip_config = $(Get-AzureRmLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb).BackendIpConfigurations
                if($backend_ip_config.count -eq 2)
                {
                    $check_vm_in_lb_binding = 0
                    foreach($config in $backend_ip_config)
                    {
                        $config_id = $config.id
                        $config_id -match "networkInterfaces/(\w.*)/ipConfigurations/ipconfig0"
                        $network_interface_id = $Matches[1]
                        $network_interface = Get-AzureRmNetworkInterface -Name $network_interface_id -ResourceGroupName $isDeployed[1]
                        $vm_id = $network_interface.VirtualMachine.id
                        if($vm_id -in $vm_id_list)
                        {
                            $check_vm_in_lb_binding += 1
                        }
                    }
                    if($check_vm_in_lb_binding -eq 2 -and $vm_id_list.count -eq 2)
                    {
                        $testResult_load_balancer = 'PASS'
                        LogMsg "[PASS][load balancer] Expect the associated network interfaces are belong to VMs in availability set and actually yes."
                    }
                    else
                    {
                        $testResult_load_balancer = 'FAIL'
                        LogMsg "Expect the associated network interfaces are belong to VMs in availability set but actually no."
                    }
                }
                else 
                {
                    $testResult_load_balancer = 'FAIL'
                    LogMsg "Expect 2 backend ip configs in $lb.BackendAddressPools[0].Name but actually no."   
                }
			}

			if($testResult_bosh_deployment_vms -eq "PASS" -and $testResult_availability_set -eq "PASS" -and $testResult_load_balancer -eq "PASS")
			{
				$testResult = "PASS"
				LogMsg "Test PASS, remove deployment deploy-cf-for-enterprise"
				echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh -n delete deployment multiple-haproxy"
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
