#!/usr/bin/python

from azuremodules import *
import random, string, time


def generate_random_storage_account(length):
    digits = "".join([random.choice(string.digits) for i in xrange(2)])
    lowercase = "".join([random.choice(string.ascii_lowercase) for i in xrange(length-2)] )
    return digits+'scpattern'+lowercase

def create_storage_account():
    data = load_jsonfile('settings')
    rg_name = data['RESOURCE_GROUP_NAME']
    rg_info = Run('az group show --name %s' % rg_name)
    data = json.loads(rg_info)
    location = data['location']

    storage_account_types = ['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS']
    storage_account_type = random.choice(storage_account_types)
    count = 0
    while count < 2:
        random_storage_account_name = generate_random_storage_account(random.randint(3, 15))
        RunLog.info("Check availability of storage account %s " % random_storage_account_name)
        storage_account_info = Run('az storage account check-name --name %s' % random_storage_account_name)
        storage_account = json.loads(storage_account_info)

        while storage_account['nameAvailable'] == 'false':
            random_storage_account_name = generate_random_storage_account(random.randint(3, 15))
            RunLog.info("Check availability of storage account %s " % random_storage_account_name)
            storage_account_info = Run('az storage account check-name --name %s' % random_storage_account_name)
            storage_account = json.loads(storage_account_info)
        
        RunLog.info("Storage account name %s is available" % random_storage_account_name)
        Run('az storage account create -l %s -n %s -g %s --sku %s' % (location, random_storage_account_name, rg_name, storage_account_type))

        RunLog.info('az storage account show-connection-string -g %s -n %s -o json' % (rg_name, random_storage_account_name))
        storage_account_connection_info = Run('az storage account show-connection-string -g %s -n %s -o json' % (rg_name, random_storage_account_name))
        storage_account_connection = json.loads(storage_account_connection_info)

        RunLog.info("ConnectionString %s" % (str(storage_account_connection['connectionString'])))
        RunLog.info("Create bosh container for %s" % random_storage_account_name)
        
        connect_string = '"'+ str(storage_account_connection['connectionString']) + '"'
        RunLog.info('az storage container create -n bosh --connection-string %s' % connect_string)
        Run('az storage container create -n bosh --connection-string %s' % connect_string)
        pattern_storage_account.append(random_storage_account_name)
        pattern_storage_account_connectionstring.append(connect_string)
        count = count + 1

    return pattern_storage_account, storage_account_type, pattern_storage_account_connectionstring

def generate_data_disk(pattern_storage_account, pattern_storage_account_connectionstring):
    i = 1
    while i<7:
        RunLog.info('Start copy blob cf_pattern_test%s.vhd' % i)
        Run('az storage blob copy start --source-uri https://ciwestusv2.blob.core.windows.net/cftest/cf_pattern_test.vhd --connection-string %s --destination-container bosh --destination-blob cf_pattern_test%s.vhd' % (pattern_storage_account_connectionstring[0], i))
        while True:
            blob_status_info = Run('az storage blob show -c bosh -n cf_pattern_test%s.vhd --connection-string %s -o json' % (i, pattern_storage_account_connectionstring[0]))
            blob_status = json.loads(blob_status_info)
            while str(blob_status['properties']['copy']['status']) != 'success':
                time.sleep(5)
                RunLog.info('blob copy is not success')
                blob_status_info = Run('az storage blob show -c bosh -n cf_pattern_test%s.vhd --connection-string %s -o json' % (i, pattern_storage_account_connectionstring[0]))
                blob_status = json.loads(blob_status_info)
            if str(blob_status['properties']['copy']['status']) == 'success':
                RunLog.info('blob copy is success')
                break
        i = i + 1


def Update_cf_manifest(source_yml_file, destination_yml_file, storage_account_type):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    out['resource_pools'] = remove_unnessary_resourcepools(out)
    out['releases'][0]['version'] = 'latest'
    out['resource_pools'][0]['stemcell']['version'] = 'latest'
    out['resource_pools'][0]['cloud_properties']['storage_account_name'] = '*scpattern*'
    out['resource_pools'][0]['cloud_properties']['storage_account_max_disk_number'] = 5
    
    meet_size=[]

    if(storage_account_type=='Premium_LRS'):
        RunLog.info("Storage account type is premium, choose an DS or GS VM size")
        premium_vm_sizes = GetPremiumVMSizes()
        
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

    out['resource_pools'][0]['cloud_properties']['storage_account_type'] = str(storage_account_type)
    out['name'] = cf_deployment_name
    out['jobs'][0]['name'] = 'pattern_storage_account_name'

    generate_manifest(destination_yml_file ,out)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    pattern_storage_account, storage_account_type, pattern_storage_account_connectionstring = create_storage_account()
    generate_data_disk(pattern_storage_account, pattern_storage_account_connectionstring)
    Update_cf_manifest(source_manifest_name, destination_manifest_name, storage_account_type)
    if DeployCF(destination_manifest_name):
        vm_name = Run('bosh vms --details | grep pattern_storage_account_name | awk \'{print $13}\'')
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

        if(os_sc==pattern_storage_account[1] and datadisk1_sc==pattern_storage_account[1] and datadisk2_sc==pattern_storage_account[1]):
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
destination_manifest_name = 'cpi-storage-account-pattern-cf.yml'
cf_deployment_name = 'storage-account-pattern-cf'
pattern_storage_account = []
pattern_storage_account_connectionstring = []
rg_name = ""
location = ""
RunTest()
