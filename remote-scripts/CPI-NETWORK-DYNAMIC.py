#!/usr/bin/python

from azuremodules import *
import random

def Update_cf_manifest(source_yml_file, destination_yml_file):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    network = filter(lambda j:j.get('name') == 'cf_private', out['networks'])
    network[0]['type'] = 'dynamic'
    network[0]['subnets'][0].pop('reserved')
    network[0]['subnets'][0].pop('static')
    network[0]['subnets'][0].pop('gateway')
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'dynamicnet_z1'
    out['jobs'][0]['networks'][0].pop('static_ips')
    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    Update_cf_manifest(source_manifest_name, destination_manifest_name)
    if DeployCF(destination_manifest_name):
        RunLog.info("Remove deployed CF %s and test resources" % cf_deployment_name)		
        Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
        ResultLog.info('PASS')
        UpdateState("TestCompleted")
    else:
        ResultLog.error('FAIL')
        UpdateState("TestCompleted")


#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-dynamic-network-single-vm-cf.yml'
cf_deployment_name = 'dynamic-network-cf'

RunTest()
