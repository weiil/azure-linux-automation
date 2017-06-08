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
    out['resource_pools'][0]['cloud_properties']['assign_dynamic_public_ip'] = True
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'dynamicvip_z1'
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
        RunLog.info('Start to verify Public IP of VM')
        host_name = Run("bosh vms --details | grep dynamicvip_z1 | awk '{print $13}'")
        publicIP_info = Run('az network public-ip list -g %s --query "[?contains(to_string(ipConfiguration.id),\'%s\')]"' % (resource_group_name, host_name.strip('\n')))
        if publicIP_info:
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
destination_manifest_name = 'cpi-dynamic-vip-cf.yml'
cf_deployment_name = 'dynamic-vip-cf'

RunTest()
