if($args.Length -lt 3)
{
    Write-Host "template file path, azure environment and mode all must be given."
    Write-Host "mode allowed values ['runner' | 'ondemand']."
    Write-Host "when mode set to 'ondemand', param object for on-demand versions of bosh, bosh-azure-cpi, stemcell and bosh-init must be given."
    return
}

$file_path = $args[0]
$env = $args[1]
$mode = $args[2]
$d = $args[3]

if(-not (Test-Path $file_path))
{
    Write-Host "$file_path is not exist."
    return
}
else
{
    $dir_name = Split-Path $file_path
    $base_name = $(Get-Item $file_path).Name
    $new_file_path = Join-Path $dir_name $('new-'+$base_name)
}

if(Test-Path $new_file_path)
{
    Remove-Item -Path $new_file_path
}

$global_latest_bosh_release_url = "https://bosh.io/d/github.com/cloudfoundry/bosh"
$global_latest_bosh_azure_cpi_url = "https://bosh.io/d/github.com/cloudfoundry-incubator/bosh-azure-cpi-release"
$global_stemcell_url = "https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent"
$bosh_init_artifacts = "https://s3.amazonaws.com/bosh-init-artifacts/"

Function GetLatest([string]$url)
{
    try
    {
        $response = Invoke-WebRequest -Uri $url -Method Head
        if($url -match "stemcell")
        {
            $latest = $response.BaseResponse.ResponseUri.OriginalString
            if($latest -match "stemcell-(\d+.?\d+)")
            {
                return $Matches.1
            }
            else
            {
                Write-Host "Failed to catch version for $url"
                return $null
            }
        }
        else
        {
            $latest = $($($response.Headers.'Content-Disposition').Split() | Where-Object {$_.contains('filename')}).Split('=')[-1]
            if($latest -match "\d+.?\d+")
            {
                return $Matches.0
            }
            else
            {
                Write-Host "Failed to catch version for $url"
                return $null
            }
        }
    }
    catch
    {
        $ErrorMessage =  $_.Exception.Message
        Write-Host "EXCEPTION : $ErrorMessage" 
        Write-Host "Get latest version failed for $url"
    }
}

Function GetLatestBoshInit
{
    $out = Invoke-RestMethod -Uri $bosh_init_artifacts -Method Get
    $latest = $($out.ListBucketResult.Contents.Where({($_.Key -match 'linux-amd64') -and (-not $_.Key.contains('.md5'))}))[-1].Key
    if($latest -match "\d+.?\d+.?\d+")
    {
        return $Matches.0
    }
    else
    {
        Write-Host "Failed to catch version for bosh-init"
        return $null
    }
}

Function GetFileHash([string]$url)
{
    try
    {
        $outfile = $url.Split('?')[0].Split('/')[-1]
        Invoke-WebRequest -Uri $url -OutFile $outfile
        Sleep -Seconds 10
        $sha1 = $(Get-FileHash -Algorithm SHA1 -Path $outfile).Hash.ToLower()
        return $sha1
    }
    catch 
    {
        $ErrorMessage =  $_.Exception.Message
        Write-Host "EXCEPTION : $ErrorMessage" 
        Write-Host "Get file hash failed."
    }
    finally
    {
        Remove-Item $outfile -ErrorAction SilentlyContinue
    }
}

Function GetVersionFromOriginTemplate([psobject]$json_src, [string]$azureenv)
{
    $d_vers = @{}
    $json_out = $json_src
    $vars = $json_out.variables

    if($azureenv -eq "AzureCloud")
    {
        $env_flag = "environmentAzure"
    }
    if($azureenv -eq "AzureChinaCloud")
    {
        $env_flag = "environmentAzureChinaCloud"
    }

    if($vars.$env_flag.boshReleaseUrl -match "\d+.?\d+")
    {
        $d_vers['bosh'] = $Matches.0
    }

    if($vars.$env_flag.boshAzureCPIReleaseUrl -match "\d+.?\d+")
    {
        $d_vers['boshazurecpi'] = $Matches.0
    }
    
    if($vars.$env_flag.stemcellUrl -match "\d+.?\d+")
    {
        $d_vers['stemcell'] = $Matches.0
    }

    if($vars.$env_flag.boshInitUrl -match "\d+.?\d+.?\d+")
    {
        $d_vers['boshinit'] = $Matches.0
    }

    return $d_vers
}

Function UpdateDeployTemplateJson([psobject]$json_src, [string]$azureenv, [string]$mode, [psobject]$dictvers)
{
    $json_out = $json_src
    $vars = $json_out.variables
    $d_origin_vers = GetVersionFromOriginTemplate $json_src $azureenv

    if($azureenv -eq "AzureCloud")
    {
        $env_flag = "environmentAzure"
    }
    if($azureenv -eq "AzureChinaCloud")
    {
        $env_flag = "environmentAzureChinaCloud"
    }

    if($mode -eq "runner")
    {
        Write-Host "Update azuredeploy.json with latest version"
        $bosh_v = GetLatest $global_latest_bosh_release_url
        $bosh_azure_cpi_v = GetLatest $global_latest_bosh_azure_cpi_url
        $stemcell_v = GetLatest $global_stemcell_url
        $bosh_init_v = GetLatestBoshInit
        $log_flag = "Latest"
    }

    if($mode -eq "ondemand")
    {
        Write-Host "Update azuredeploy.json with demand version"
        if($dictvers -ne $null)
        {
            $bosh_v = $dictvers.bosh
            $bosh_azure_cpi_v = $dictvers.boshazurecpi
            $stemcell_v = $dictvers.stemcell
            $bosh_init_v = $dictvers.boshinit

            if($dictvers.bosh -eq "KEEP_ORIGIN")
            {
                $bosh_v = $d_origin_vers['bosh']
            }
            
            if($dictvers.boshazurecpi -eq "KEEP_ORIGIN")
            {
                $bosh_azure_cpi_v = $d_origin_vers['boshazurecpi']
            }
            
            if($dictvers.stemcell -eq "KEEP_ORIGIN")
            {
                $stemcell_v = $d_origin_vers['stemcell']
            }
            
            if($dictvers.boshinit -eq "KEEP_ORIGIN")
            {
                $bosh_init_v = $d_origin_vers['boshinit']
            }
            
            $log_flag = "Demand"
        }
    }

    $bosh_release_url = $global_latest_bosh_release_url + "?v=" + $bosh_v
    $bosh_azure_cpi_url = $global_latest_bosh_azure_cpi_url + "?v=" + $bosh_azure_cpi_v
    $stemcell_url = $global_stemcell_url + "?v=" + $stemcell_v
    $bosh_release_sha1 = $vars.$env_flag.boshReleaseSha1
    $bosh_azure_cpi_sha1 = $vars.$env_flag.boshAzureCPIReleaseSha1
    $stemcell_sha1 = $vars.$env_flag.stemcellSha1

    # get sha1 just when need to
    if($bosh_v -ne $d_origin_vers['bosh'])
    {
        $bosh_release_sha1 = GetFileHash $bosh_release_url
    }
    if($bosh_azure_cpi_v -ne $d_origin_vers['boshazurecpi'])
    {
        $bosh_azure_cpi_sha1 = GetFileHash $bosh_azure_cpi_url
    }
    if($stemcell_v -ne $d_origin_vers['stemcell'])
    {
        $stemcell_sha1 = GetFileHash $stemcell_url
    }

    Write-Host "-$log_flag Bosh Release: $bosh_v"
    #Write-Host " --URL: $bosh_release_url"
    Write-Host " --SHA1: $bosh_release_sha1"
    Write-Host "-$log_flag Bosh Azure CPI Release: $bosh_azure_cpi_v"
    #Write-Host " --URL: $bosh_azure_cpi_url"
    Write-Host " --SHA1: $bosh_azure_cpi_sha1"
    Write-Host "-$log_flag Stemcell: $stemcell_v"
    #Write-Host " --URL: $stemcell_url"
    Write-Host " --SHA1: $stemcell_sha1"
    Write-Host "-$log_flag Bosh Init: $bosh_init_v"

    Write-Host "Update vars for $azureenv"

    $vars.$env_flag.boshReleaseUrl = $vars.$env_flag.boshReleaseUrl.Replace($d_origin_vers['bosh'],$bosh_v)
    $vars.$env_flag.boshReleaseSha1 = $bosh_release_sha1
    $vars.$env_flag.boshAzureCPIReleaseUrl = $vars.$env_flag.boshAzureCPIReleaseUrl.Replace($d_origin_vers['boshazurecpi'],$bosh_azure_cpi_v)
    $vars.$env_flag.boshAzureCPIReleaseSha1 = $bosh_azure_cpi_sha1        
    $vars.$env_flag.stemcellUrl = $vars.$env_flag.stemcellUrl.Replace($d_origin_vers['stemcell'],$stemcell_v)        
    $vars.$env_flag.stemcellSha1 = $stemcell_sha1
    $vars.$env_flag.boshInitUrl = $vars.$env_flag.boshInitUrl.Replace($d_origin_vers['boshinit'],$bosh_init_v)
        
    return $json_out
}

$json_template = Get-Content $file_path -Raw | ConvertFrom-Json
$update_json_template = UpdateDeployTemplateJson $json_template $env $mode $d
$($update_json_template | ConvertTo-Json -Depth 10).Replace("\u0027","'") | Out-File $new_file_path

Move-Item $file_path $($file_path+'.bak')
Move-Item $new_file_path $new_file_path.Replace('new-','')

Write-Host 'DONE'