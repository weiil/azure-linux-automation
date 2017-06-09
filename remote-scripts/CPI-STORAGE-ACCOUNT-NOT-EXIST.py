#!/usr/bin/python

from azuremodules import *
import random, string


def generate_random_storage_account(length):
    return ''.join(random.choice(string.ascii_lowercase + string.digits) for i in range(length))

        
def Update_cf_manifest(source_yml_file, destination_yml_file, random_storage_account_name):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    out['resource_pools'] = remove_unnessary_resourcepools(out)
    out['releases'][0]['version'] = 'latest'
    out['resource_pools'][0]['stemcell']['version'] = 'latest'
    out['resource_pools'][0]['cloud_properties']['storage_account_name'] = str(random_storage_account_name)
    storage_account_types = ['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS']
    storage_account_type = random.choice(storage_account_types)
    if(storage_account_type=='Premium_LRS'):
        RunLog.info("Storage account type is premium, choose an DS or GS VM size")
        premium_vm_sizes = GetPremiumVMSizes()
        meet_size=[]
        
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
        index = -1
        while index < retry_maxcount-1:
            index = index + 1
            count = sizes[index]['maxDataDiskCount']
            size = sizes[index]['name']
            needed_core = sizes[index]['numberOfCores']

            if size in premium_vm_sizes and count >= 2 and needed_core <= left_core_count:
                RunLog.info("Get meet requirement size %s " % size)
                RunLog.info("Add it into meet_size array")
                meet_size.append(size)
                
        if(len(meet_size)!=0):
            out['resource_pools'][0]['cloud_properties']['instance_type'] = str(random.choice(meet_size))
        else:
            storage_account_types.pop(-1)
            storage_account_type = random.choice(storage_account_types)

    out['resource_pools'][0]['cloud_properties']['storage_account_type'] = str(storage_account_type)
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'random_storage_account_name'

    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    random_storage_account_name = generate_random_storage_account(random.randint(3,12))
    Update_cf_manifest(source_manifest_name, destination_manifest_name, random_storage_account_name)
    if DeployCF(destination_manifest_name):
        vm_name = Run('bosh vms --details | grep random_storage_account_name | awk \'{print $13}\'')
        vm_name = vm_name.strip() 

        data = load_jsonfile('settings')
        rg_name = data['RESOURCE_GROUP_NAME']
        vm_info = Run('az vm show -g %s -n %s --output json' % (rg_name, vm_name))
        vm = json.loads(vm_info)

        os_url = vm['storageProfile']['osDisk']['vhd']['uri']
        datadisk1_url = vm['storageProfile']['dataDisks'][0]['vhd']['uri']
        datadisk2_url = vm['storageProfile']['dataDisks'][1]['vhd']['uri']

        RunLog.info("VM OS uri %s" % os_url)
        RunLog.info("VM data disk 0 uri %s" % datadisk1_url)
        RunLog.info("VM data disk 1 uri %s" % datadisk2_url)
        
        os_sc = os_url.split('/')[2].split('.')[0]
        datadisk1_sc = datadisk1_url.split('/')[2].split('.')[0]
        datadisk2_sc = datadisk2_url.split('/')[2].split('.')[0]
        RunLog.info("VM OS storage account %s" % os_sc)
        RunLog.info("VM data disk 0 storage account %s" % datadisk1_sc)
        RunLog.info("VM data disk 1 storage account %s" % datadisk2_sc)

        if(os_sc==random_storage_account_name and datadisk1_sc==random_storage_account_name and datadisk2_sc==random_storage_account_name):
            ResultLog.info('PASS')
            RunLog.info("Remove deployed CF %s" % cf_deployment_name)		
            Run("echo yes | bosh delete deployment %s" % cf_deployment_name)
        else:
            ResultLog.error('FAIL')
        UpdateState("TestCompleted")
    else:
        ResultLog.error('FAIL')
        UpdateState("TestCompleted")

#set variable
source_manifest_name = 'example_manifests/single-vm-cf.yml'
destination_manifest_name = 'cpi-storage-account-not-exist-cf.yml'
cf_deployment_name = 'storage-account-not-exist-cf'

RunTest()
