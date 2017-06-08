#!/usr/bin/python

from azuremodules import *
import random

def Update_cf_manifest(source_yml_file, destination_yml_file, load_balancer_name):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    out['resource_pools'] = remove_unnessary_resourcepools(out)
    out['releases'][0]['version'] = 'latest'
    out['resource_pools'][0]['stemcell']['version'] = 'latest'
    out['resource_pools'][0]['cloud_properties']['load_balancer'] = load_balancer_name
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'rplb_z1'
    out['jobs'][0]['networks'][0].pop('static_ips')
    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')
    data = load_jsonfile('settings')
    resource_group_name = data['RESOURCE_GROUP_NAME']

    RunLog.info('create temporary load balancer for test')
    Run('az network lb create -g %s -n %s' % (resource_group_name, lb_name))
    Update_cf_manifest(source_manifest_name, destination_manifest_name, lb_name)
    if DeployCF(destination_manifest_name):
        RunLog.info('Start to verify the security group')
        host_name = Run("bosh vms --details | grep rplb_z1 | awk '{print $13}'")
        lb_info = Run('az network lb show -g %s -n %s --query backendAddressPools[].backendIpConfigurations[].id' % (resource_group_name, lb_name))
        if host_name and (host_name.strip('\n') in lb_info):
            RunLog.info("Test PASS, Remove deployed CF %s and test resources" % cf_deployment_name)		
            Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
            Run('az network lb delete -g %s -n %s' % (resource_group_name, lb_name))
            ResultLog.info('PASS')
        else:
            RunLog.info("Test FAIL")
            ResultLog.info('FAIL')
    else:
        ResultLog.error('FAIL')
    UpdateState("TestCompleted")

#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-rp-lb-cf.yml'
cf_deployment_name = 'rp-lb-cf'
lb_name = 'test-lb-%s' % random.randint(1,100)

RunTest()
