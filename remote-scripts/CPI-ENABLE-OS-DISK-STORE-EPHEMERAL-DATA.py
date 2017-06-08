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
    out['resource_pools'][0]['cloud_properties']['ephemeral_disk'] = {'use_root_disk': True}
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'userootdisk_z1'
    out['jobs'][0]['networks'][0].pop('static_ips')
    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')
    data = load_jsonfile('settings')
    resource_group_name = data['RESOURCE_GROUP_NAME']

    Update_cf_manifest(source_manifest_name, destination_manifest_name)
    if DeployCF(destination_manifest_name):
        RunLog.info('Start to verify the size of os disk')
        host_name = Run("bosh vms --details | grep userootdisk_z1 | awk '{print $13}'")
        datadisk_info = Run('az vm show -g %s -n %s --query "storageProfile.dataDisks[]"' % (resource_group_name, host_name.strip('\n')))
        osdisk_info = Run('az vm show -g %s -n %s --query "storageProfile.osDisk"' % (resource_group_name, host_name.strip('\n')))
        osdisk_info = json.loads(osdisk_info)
        osdisk_size = osdisk_info['diskSizeGb']
        RunLog.info('Actually the size of os disk is : %s Gb, expected value is 30 Gb' % osdisk_size)
        if not ('ephemeral-disk' in datadisk_info) and (osdisk_size == 30):
            RunLog.info("Test PASS, Remove deployed CF %s and test resources" % cf_deployment_name)		
            Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
            ResultLog.info('PASS')
        else:
            RunLog.info("Test FAIL")
            ResultLog.info('FAIL')
    else:
        ResultLog.error('FAIL')
    UpdateState("TestCompleted")

#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-use-root-disk-cf.yml'
cf_deployment_name = 'use-root-disk-cf'

RunTest()
