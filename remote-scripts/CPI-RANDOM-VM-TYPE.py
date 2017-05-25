#!/usr/bin/python

from azuremodules import *
import random

def get_current_location():
    data = load_jsonfile('settings')
    rg_name = data['RESOURCE_GROUP_NAME']
    rg_info = Run('az group show --name %s' % rg_name)
    data = json.loads(rg_info)
    location = data['location']
    RunLog.info("Get all available VM size in this location %s " % location)
    sizes_info = Run('az vm list-sizes --location %s' % location)
    sizes = json.loads(sizes_info)

    core_usage_info = Run('az vm list-usage -l %s' % location)
    core_usage = json.loads(core_usage_info)

    coreindex = 0
    while core_usage[coreindex]['name']['localizedValue']!='Total Regional Cores':
            coreindex = coreindex + 1
            
    currentcount = core_usage[coreindex]['currentValue']
    limit = core_usage[coreindex]['limit']
    RunLog.info("Total current core count %s " % currentcount)
    RunLog.info("Limit core count %s " % limit)
    left_core_count = int(limit) - int(currentcount)
    RunLog.info("Left core count %s " % left_core_count)

    retry_maxcount = len(sizes)
    try_count = 0
    while try_count <= retry_maxcount:
        index = random.randint(1,len(sizes))
        count = sizes[index]['maxDataDiskCount']
        size = sizes[index]['name']
        needed_core = sizes[index]['numberOfCores']
        if count >= 2 and needed_core*3 <= left_core_count:
            RunLog.info("Get meet requirement size %s " % size)
            break
        else:
            try_count = try_count + 1
            continue 

    if try_count > retry_maxcount:
        RunLog.info("Didn't get meet requirement size")
        return 0
    else:
        return size 
        
def Update_cf_manifest(source_yml_file, destination_yml_file, size):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    resource_pool = filter(lambda j:j.get('name') == 'resource_postgres_z1', out['resource_pools'])
    resource_pool[0]['cloud_properties'] = {'instance_type':str(size)}
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'random_instance_type'
    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    size = get_current_location()
    if size == 0:
        ResultLog.error('Core is not enough')
        ResultLog.error('FAIL')
        UpdateState("TestCompleted")
    else:
        Update_cf_manifest(source_manifest_name, destination_manifest_name, size)
        if DeployCF(destination_manifest_name):
            ResultLog.info('PASS')
            RunLog.info("Remove deployed CF %s" % cf_deployment_name)		
            Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
            UpdateState("TestCompleted")
        else:
            ResultLog.error('FAIL')
            UpdateState("TestCompleted")

#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-random-vm-type-single-cf.yml'
cf_deployment_name = 'random-vm-type-cf'

RunTest()
