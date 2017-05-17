#!/usr/bin/python

from azuremodules import *


def Update_cf_manifest(source_yml_file, destination_yml_file):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    network = filter(lambda j:j.get('name') == 'cf_public', out['networks'])
    network[0]['cloud_properties'] = {'resource_group_name':'bosh-test-network'}
    out['name'] = 'separate-network-cf'
    out['jobs'][0]['name'] = 'separatenetwork_z1'
    out['jobs'][0]['networks'][0]['default'] = ['gateway', 'dns']
    out['jobs'][0]['networks'][0].pop('static_ips')
    out['jobs'][0]['networks'].append({'name':'cf_public','static_ips': cf_ip})
    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    Update_cf_manifest(source_manifest_name, destination_manifest_name)
    if DeployCF(destination_manifest_name):
        ResultLog.info('PASS')
        UpdateState("TestCompleted")
    else:
        ResultLog.error('FAIL')
        UpdateState("TestCompleted")



source_manifest_name = sys.argv[1]
destination_manifest_name = sys.argv[2]
cf_ip = sys.argv[3]
InstallAzureCli()
RunTest()
