#!/usr/bin/python

from azuremodules import *
import random

def move_vnet_resource(vnet_name, source_resource_group, destination_resource_group):
    RunLog.info("Move VNET %s from %s to %s" % (vnet_name, source_resource_group, destination_resource_group))
    vnet_info = Run('az resource show -g %s --resource-type Microsoft.Network/virtualNetworks -n %s' % (source_resource_group, vnet_name))
    data = json.loads(vnet_info)
    vnet_id = data['id']
    Run('az resource move --destination-group %s --ids %s' % (destination_resource_group, vnet_id))

def Update_cf_manifest(source_yml_file, destination_yml_file, resource_group_name):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    network = filter(lambda j:j.get('name') == 'cf_private', out['networks'])
    network[0]['subnets'][0]['cloud_properties']['resource_group_name'] = resource_group_name
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'separatevnet_z1'
    out['jobs'][0]['networks'][0].pop('static_ips')
    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    data = load_jsonfile('settings')
    old_rg_name = data['RESOURCE_GROUP_NAME']
    vnet_name = data['VNET_NAME']
    rg_info = Run('az group show --name %s' % old_rg_name)
    rgdata = json.loads(rg_info)
    location = rgdata['location']
    Run('az group create --name %s --location %s' % (temp_resource_group_name, location))
    move_vnet_resource(vnet_name, old_rg_name, temp_resource_group_name)
    Update_cf_manifest(source_manifest_name, destination_manifest_name, temp_resource_group_name)
    if DeployCF(destination_manifest_name):
        RunLog.info("Remove deployed CF %s and test resources" % cf_deployment_name)		
        Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
        move_vnet_resource(vnet_name, temp_resource_group_name, old_rg_name)
        Run('az group delete --name %s -y' % temp_resource_group_name)
        ResultLog.info('PASS')
        UpdateState("TestCompleted")
    else:
        ResultLog.error('FAIL')
        UpdateState("TestCompleted")


#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-separate-vnet-single-vm-cf.yml'
cf_deployment_name = 'separate-vnet-cf'
temp_resource_group_name = 'vnetrg-%s' % random.randint(1,100)

RunTest()
