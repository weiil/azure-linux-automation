if($args.Length -ne 2)
{
    Write-Host "template file path and azure environment all must be given."
    return
}

$file_path = $args[0]
$env = $args[1]

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
        }
        else
        {
            $latest = $($($response.Headers.'Content-Disposition').Split() | Where-Object {$_.contains('filename')}).Split('=')[-1]
        }
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
        $outfile = $url.Split('/')[-1]
        Invoke-WebRequest -Uri $url -OutFile $outfile
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

Function UpdateDeployTemplateJsonForRunner([psobject]$json_src, [string]$azureenv)
{
    $latest_bosh_release = GetLatest $global_latest_bosh_release_url
    $latest_bosh_release_sha1 = GetFileHash $global_latest_bosh_release_url
    $latest_bosh_azure_cpi_release = GetLatest $global_latest_bosh_azure_cpi_url
    $latest_bosh_azure_cpi_release_sha1 = GetFileHash $global_latest_bosh_azure_cpi_url
    $latest_stemcell = GetLatest $global_stemcell_url
    $latest_stemcell_sha1 = GetFileHash $global_stemcell_url
    $latest_bosh_init = GetLatestBoshInit

    Write-Host "-Latest Bosh Release: $latest_bosh_release"
    Write-Host " --SHA1: $latest_bosh_release_sha1"
    Write-Host "-Latest Bosh Azure CPI Release: $latest_bosh_azure_cpi_release"
    Write-Host " --SHA1: $latest_bosh_azure_cpi_release_sha1"
    Write-Host "-Latest Stemcell: $latest_stemcell"
    Write-Host " --SHA1: $latest_stemcell_sha1"
    Write-Host "-Latest Bosh Init: $latest_bosh_init"

    $json_out = $json_src
    $vars = $json_out.variables

    if($azureenv -eq "AzureCloud")
    {
        Write-Host "Update vars for AzureCloud"
        $vars.environmentAzureCloud.boshReleaseUrl = $global_latest_bosh_release_url
        $vars.environmentAzureCloud.boshReleaseSha1 = $latest_bosh_release_sha1
        $vars.environmentAzureCloud.boshAzureCPIReleaseUrl = $global_latest_bosh_azure_cpi_url
        $vars.environmentAzureCloud.boshAzureCPIReleaseSha1 = $latest_bosh_azure_cpi_release_sha1
        $vars.environmentAzureCloud.stemcellUrl = $global_stemcell_url
        $vars.environmentAzureCloud.stemcellSha1 = $latest_stemcell_sha1
        if($vars.environmentAzureCloud.boshInitUrl -match "\d+.?\d+.?\d+")
        {
            $vars.environmentAzureCloud.boshInitUrl = $vars.environmentAzureCloud.boshInitUrl.Replace($Matches.0,$latest_bosh_init)
        }
    }

    if($azureenv -eq "AzureChinaCloud")
    {
        Write-Host "Update vars for AzureChinaCloud"
        if($vars.environmentAzureChinaCloud.boshReleaseUrl -match "\d+.?\d+")
        {
            $vars.environmentAzureChinaCloud.boshReleaseUrl = $vars.environmentAzureChinaCloud.boshReleaseUrl.Replace($Matches.0,$latest_bosh_release)
        }
        $vars.environmentAzureChinaCloud.boshReleaseSha1 = $latest_bosh_release_sha1
        if($vars.environmentAzureChinaCloud.boshAzureCPIReleaseUrl -match "\d+.?\d+")
        {
            $vars.environmentAzureChinaCloud.boshAzureCPIReleaseUrl = $vars.environmentAzureChinaCloud.boshAzureCPIReleaseUrl.Replace($Matches.0,$latest_bosh_azure_cpi_release)
        }
        $vars.environmentAzureChinaCloud.boshAzureCPIReleaseSha1 = $latest_bosh_azure_cpi_release_sha1
        if($vars.environmentAzureChinaCloud.stemcellUrl -match "\d+.?\d+")
        {
            $vars.environmentAzureChinaCloud.stemcellUrl = $vars.environmentAzureChinaCloud.stemcellUrl.Replace($Matches.0,$latest_stemcell)
        }
        $vars.environmentAzureChinaCloud.stemcellSha1 = $latest_stemcell_sha1
        if($vars.environmentAzureChinaCloud.boshInitUrl -match "\d+.?\d+.?\d+")
        {
            $vars.environmentAzureChinaCloud.boshInitUrl = $vars.environmentAzureChinaCloud.boshInitUrl.Replace($Matches.0,$latest_bosh_init)
        }
    }

    return $json_out
}

$json_template = Get-Content $file_path -Raw | ConvertFrom-Json
$update_json_template = UpdateDeployTemplateJsonForRunner $json_template $env
$($update_json_template | ConvertTo-Json -Depth 10).Replace("\u0027","'") | Out-File $new_file_path

Move-Item $file_path $($file_path+'.bak')
Move-Item $new_file_path $new_file_path.Replace('new-','')

Write-Host 'DONE'