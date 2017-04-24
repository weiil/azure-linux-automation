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
	
	
	$azureDeployJsonFile =  Get-Content ..\azure-quickstart-templates\bosh-setup\azuredeploy.json -Raw | ConvertFrom-Json
	$vnetName = $azureDeployJsonFile.variables.virtualNetworkName
	$subnetName = $azureDeployJsonFile.variables.subnetNameForCloudFoundry
	$securityGroupName = $azureDeployJsonFile.variables.cfNetworkSecurityGroup
	$systemDomain = "$cf_ip.xip.io"
	$DirectorUUID = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh status --uuid"	
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

	$SharedNetworkResourceGroupName = "bosh-test-network"
	$new_cfip = (Get-AzureRmPublicIpAddress -ResourceGroupName $SharedNetworkResourceGroupName -Name devbox-cf).IpAddress
	Remove-Item *.yml
	$vnet = Get-AzureRmVirtualNetwork -ResourceGroupName $isDeployed[1] -Name $vnetName
	Add-AzureRmVirtualNetworkSubnetConfig -Name CloudFoundry2 -VirtualNetwork $vnet -AddressPrefix 10.0.40.0/24
	Add-AzureRmVirtualNetworkSubnetConfig -Name CloudFoundry3 -VirtualNetwork $vnet -AddressPrefix 10.0.41.0/24
	Set-AzureRmVirtualNetwork -VirtualNetwork $vnet	
	$cfScenario = 'multiple-nics-single-vm-cf'
	$yml_file = "$cfScenario.yml"
	LogMsg "Update $yml_file"
	echo y | .\tools\pscp -i .\ssh\$sshKey -q -P $port .\remote-scripts\cf-manifest-handle.py ${dep_ssh_info}:
	$out = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "python cf-manifest-handle.py example_manifests/single-vm-cf.yml $yml_file && echo yml_update_pass || echo yml_update_fail"
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
			[String]$vmInfo = echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "bosh ssh multiplenics_z1/0 hostname"
			if($vmInfo -match "multiplenics_z1/0\s+(\S+)\s+Cleaning")
			{
				$vmName = $Matches[1]
				$nics = Get-AzureRmNetworkInterface -ResourceGroupName $isDeployed[1] | where {$_.VirtualMachine.Id.EndsWith($vmName)}
				if($nics.Length -eq 3)
				{
					$testResult = "PASS"
                    LogMsg "Test PASS, remove deployment multiple-nics-cf"
                    echo y | .\tools\plink -i .\ssh\$sshKey -P $port $dep_ssh_info "echo yes | bosh delete deployment multiple-nics-cf"
				}
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
