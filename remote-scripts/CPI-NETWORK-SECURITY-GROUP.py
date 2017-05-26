#!/usr/bin/python

from azuremodules import *
import random

def create_security_group(resource_group_name, security_group_name):
    rg_info = Run('az group show --name %s' % resource_group_name)
    data = json.loads(rg_info)
    location = data['location']
    RunLog.info("Remove security group %s regardless of whether it exists" % security_group_name)
    Run('az network nsg delete -g %s -n %s' % (resource_group_name, security_group_name))

    Run('az network nsg create -g %s -l %s -n %s' % (resource_group_name, location, security_group_name))
    Run("az network nsg rule create -g %s --nsg-name %s --access Allow --protocol Tcp --direction Inbound --priority 201 --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --name 'cf-https' --destination-port-range 443" % (resource_group_name, security_group_name))
    Run("az network nsg rule create -g %s --nsg-name %s --access Allow --protocol Tcp --direction Inbound --priority 202 --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --name 'cf-log' --destination-port-range 4443" % (resource_group_name, security_group_name))


def Update_cf_manifest(source_yml_file, destination_yml_file, security_group_name):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    network = filter(lambda j:j.get('name') == 'cf_private', out['networks'])
    network[0]['subnets'][0]['cloud_properties']['security_group'] = security_group_name
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'separatensg_z1'

    resource_pool = filter(lambda j:j.get('name') == 'resource_postgres_z1', out['resource_pools'])
    resource_pool[0]['cloud_properties'].pop('security_group')

    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')
    data = load_jsonfile('settings')
    resource_group_name = data['RESOURCE_GROUP_NAME']

    RunLog.info('create temporary security group for test')
    create_security_group(resource_group_name, security_group_name)
    Update_cf_manifest(source_manifest_name, destination_manifest_name, security_group_name)
    if DeployCF(destination_manifest_name):
        ResultLog.info('PASS')
        RunLog.info("Test PASS, remove deployed CF %s" % cf_deployment_name)
        Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
        RunLog.info("Remove temporary security group %s" % security_group_name)
        Run('az network nsg delete -g %s -n %s' % (resource_group_name, security_group_name))
        UpdateState("TestCompleted")
    else:
        ResultLog.error('FAIL')
        UpdateState("TestCompleted")

#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-separate-nsg-single-vm-cf.yml'
cf_deployment_name = 'separate-nsg-cf'
security_group_name = 'test-nsg-%s' % random.randint(1,100)

RunTest()
