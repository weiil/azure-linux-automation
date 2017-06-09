#!/usr/bin/python

from azuremodules import *
import random


def Update_cf_manifest(source_yml_file, destination_yml_file):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    out['resource_pools'] = remove_unnessary_resourcepools(out)
    out['releases'][0]['version'] = 'latest'
    out['resource_pools'][0]['stemcell']['version'] = 'latest'
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'detachdatadisk_z1'
    out['jobs'][0]['networks'][0].pop('static_ips')
    generate_manifest(destination_yml_file ,out)

def Remove_datadisk_section(source_yml_file, destination_yml_file):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['resource_pools'][0]['cloud_properties']['ephemeral_disk'] = {'use_root_disk': True}
    out['jobs'][0].pop('persistent_disk')
    generate_manifest(destination_yml_file ,out)

def Get_data_disk_number(resource_group_name):
    host_name = Run("bosh vms --details | grep detachdatadisk_z1 | awk '{print $13}'")
    datadisk_info = Run('az vm show -g %s -n %s --query "storageProfile.dataDisks[]"' % (resource_group_name, host_name.strip('\n')))
    disks = json.loads(datadisk_info)
    return len(disks)
	
	
def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')
    data = load_jsonfile('settings')
    resource_group_name = data['RESOURCE_GROUP_NAME']

    Update_cf_manifest(source_manifest_name, destination_manifest_name)
    if DeployCF(destination_manifest_name):
        RunLog.info('Start to verify the number of data disk')
        numberOfdatadisk = Get_data_disk_number(resource_group_name)
        RunLog.info('The initial number of data disk is : %s' % numberOfdatadisk)
        if numberOfdatadisk > 0:
            RunLog.info("Remove configuration that related to data disk from CF manifest then redeploy CF" )
            Remove_datadisk_section(destination_manifest_name, destination_manifest_name)
            if DeployCF(destination_manifest_name):			
                datadisks = Get_data_disk_number(resource_group_name)
                RunLog.info('After redeploy CF, the number of data disk is : %s' % datadisks)
                if datadisks == 0:
                    RunLog.info('The data disks have been detached successfully')
                    Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
                    ResultLog.info('PASS')
                else:
                    RunLog.info('The data disks failed to been detached')
                    ResultLog.info('FAIL')
                    
            else:
                ResultLog.info('FAIL')
        else:
            RunLog.info("Test FAIL, the initial number of data disk is 0, can't do the test")
            ResultLog.info('FAIL')
    else:
        ResultLog.error('FAIL')
    UpdateState("TestCompleted")

#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-detach-data-disk-cf.yml'
cf_deployment_name = 'detach-data-disk-cf'

RunTest()
