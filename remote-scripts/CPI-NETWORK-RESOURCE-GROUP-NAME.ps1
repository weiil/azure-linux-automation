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
	$vmName = $parameters.vmName + $timestr
    $jsonfile.parameters.vmName.value = $vmName
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

    $port = 22
    $global:sshKey = "cf_devbox_privatekey.ppk"
	$user = $parameters.adminUsername
	$publicIPResourceID = (Get-AzureRmVM -Name $vmName -ResourceGroupName $isDeployed[1] | Get-AzureRmNetworkInterface).IpConfigurations[0].PublicIpAddress.id
	$ip = (Get-AzureRmResource -ResourceId $publicIPResourceID).Properties.ipAddress

	$SharedNetworkResourceGroupName = "bosh-test-network"
	$new_cfip = (Get-AzureRmPublicIpAddress -ResourceGroupName $SharedNetworkResourceGroupName -Name devbox-cf).IpAddress

	RemoteCopy -uploadTo $ip -port $port -files $currentTestData.files -username $user -password $password -upload -usePrivateKey
	$out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "bosh -v" -usePrivateKey
    LogMsg "Current bosh cli version: $out"
    if($global:RunnerMode -eq "Runner")
    {
        LogMsg "Runner mode, Update bosh cli to the latest"
		RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "sudo gem install bosh_cli --no-ri --no-rdoc" -usePrivateKey
        $out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "bosh -v" -usePrivateKey
        LogMsg "UPDATED bosh cli version: $out"
    }

    if($global:RunnerMode -eq "OnDemand" -and $env:BoshCLIVersion -eq "latest")
    {
        LogMsg "OnDemand mode, but request to update bosh cli to the latest"
		RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "sudo gem install bosh_cli --no-ri --no-rdoc" -usePrivateKey
        $out = RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "bosh -v" -usePrivateKey
        LogMsg "UPDATED bosh cli version: $out"
    }
	
	LogMsg "Executing : $($currentTestData.testScript)"
	RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "python $($currentTestData.testScript) example_manifests/single-vm-cf.yml cpi-network-rg-single-vm-cf.yml $new_cfip" -runMaxAllowedTime 7200 -usePrivateKey
	RunLinuxCmd -username $user -password $password -ip $ip -port $port -command "mv Runtime.log $($currentTestData.testScript).log" -usePrivateKey
	RemoteCopy -download -downloadFrom $ip -files "/home/$user/deployCF.log, /home/$user/state.txt, /home/$user/Summary.log, /home/$user/$($currentTestData.testScript).log" -downloadTo $LogDir -port $port -username $user -password $password -usePrivateKey
	$testResult = Get-Content $LogDir\Summary.log
	$testStatus = Get-Content $LogDir\state.txt
	LogMsg "Test result : $testResult"

	if ($testStatus -eq "TestCompleted")
	{
		LogMsg "Test Completed"
	}
}
catch
{
    $info = $_.InvocationInfo
    "Line{0}, Col{1}, caught exception:{2}" -f $info.ScriptLineNumber,$info.OffsetInLine ,$_.Exception.Message
}
Finally
{
    # Dissociate shared PublicIPAddress for next job use
	$networkInterface = Get-AzureRmNetworkInterface -ResourceGroupName $isDeployed[1]  | where {$_.IpConfigurations[0].PublicIpAddress.Id -match $SharedNetworkResourceGroupName}
	if($networkInterface)
	{
		$networkInterface.IpConfigurations[0].PublicIpAddress = $null
		Set-AzureRmNetworkInterface -NetworkInterface $networkInterface
	}
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
