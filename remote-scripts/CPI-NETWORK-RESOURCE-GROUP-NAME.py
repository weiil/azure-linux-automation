#!/usr/bin/python

from azuremodules import *
import random

def create_publicIP_resource(resource_group_name):
    data = load_jsonfile('settings')
    old_rg_name = data['RESOURCE_GROUP_NAME']
    rg_info = Run('az group show --name %s' % old_rg_name)
    data = json.loads(rg_info)
    location = data['location']
    RunLog.info("Remove resource group %s regardless of whether it exists" % resource_group_name)
    Run('az group delete --name %s -y' % resource_group_name)
	
    Run('az group create --name %s --location %s' % (resource_group_name, location))
    Run('az network public-ip create --resource-group %s --allocation-method Static --name publicIP' % resource_group_name)
    network_info = Run('az network public-ip show --resource-group %s --name publicIP' % resource_group_name)
    data = json.loads(network_info)
    publicIPAddress = data['ipAddress']
    return str(publicIPAddress)


def Update_cf_manifest(source_yml_file, destination_yml_file, publicIP):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    out['resource_pools'] = remove_unnessary_resourcepools(out)
    out['releases'][0]['version'] = 'latest'
    out['resource_pools'][0]['stemcell']['version'] = 'latest'
    network = filter(lambda j:j.get('name') == 'cf_public', out['networks'])
    network[0]['cloud_properties'] = {'resource_group_name':temp_resource_group_name}
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'separatenetwork_z1'
    out['jobs'][0]['networks'][0]['default'] = ['gateway', 'dns']
    out['jobs'][0]['networks'][0].pop('static_ips')
    out['jobs'][0]['networks'].append({'name':'cf_public','static_ips': publicIP})
    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    RunLog.info('create temporary resource group which contains publicIPAddress resource')
    publicIP = create_publicIP_resource(temp_resource_group_name)
    Update_cf_manifest(source_manifest_name, destination_manifest_name, publicIP)
    if DeployCF(destination_manifest_name):
        RunLog.info('Start to verify the publicIP resource')
        host_name = Run("bosh vms --details | grep separatenetwork_z1 | awk '{print $13}'")
        publicIP_info = Run('az network public-ip show -g %s -n publicIP --query ipConfiguration.id' % temp_resource_group_name)
        if host_name and (host_name.strip('\n') in publicIP_info):
            RunLog.info("Test PASS, Remove deployed CF %s and test resources" % cf_deployment_name)		
            Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
            Run('az group delete --name %s -y' % temp_resource_group_name)
            ResultLog.info('PASS')
        else:
            RunLog.info("Test FAIL")
            ResultLog.info('FAIL')
    else:
        ResultLog.error('FAIL')
    UpdateState("TestCompleted")

#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-separate-network-cf.yml'
cf_deployment_name = 'separate-network-cf'
temp_resource_group_name = 'testrg-%s' % random.randint(1,100)

RunTest()
