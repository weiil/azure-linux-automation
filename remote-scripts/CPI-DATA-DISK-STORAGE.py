#!/usr/bin/env python

from azuremodules import *
import random

def update_cf_manifest(source_yml_file, destination_yml_file, storage_type):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    RunLog.info("Deployment Name: %s" % deployment_name)
    out['name'] = deployment_name
    RunLog.info('Add disk pools. Name: %s, Storage account type: %s' % (disk_pool_name, storage_type))
    new_disk_pool = {
        'name': disk_pool_name,
        'disk_size': 11264,
        'cloud_properties': {
            'storage_account_type': storage_type
        }
    }
    out['disk_pools'] = [new_disk_pool]
    RunLog.info('Use the disk pool')
    out['jobs'][0]['persistent_disk_pool'] = disk_pool_name
    out['jobs'][0]['name'] = job_name
    del out['jobs'][0]['persistent_disk']
    for rp in out['resource_pools']:
        if rp['name'] == 'resource_postgres_z1':
            rp['cloud_properties']['instance_type'] = 'Standard_DS1'
    generate_manifest(destination_yml_file ,out)

def get_vm_name_by_cf_job_name(rg_name, job_name):
    return Run("az vm list -g %s --query \"[?tags.job==\'%s\'].name | [0]\" | tr -d '\"' | tr -d '\\n'" % (rg_name, job_name))

def get_storage_account_type(rg_name, vm_name):
    return Run("az vm unmanaged-disk list -g %s -n %s --query \"[?createOption=='attach'].managedDisk.storageAccountType | [0]\" | tr -d '\"' | tr -d '\\n'" % (rg_name, vm_name))

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    # random choice storage account type
    storage_types = ['Standard_LRS', 'Premium_LRS']
    storage_type = random.choice(storage_types)

    RunLog.info('update manifest')
    update_cf_manifest(source_manifest_name, destination_manifest_name, storage_type)

    if DeployCF(destination_manifest_name):
        RunLog.info("deploy successfully")
        job_vm = get_vm_name_by_cf_job_name(resource_group_name, job_name)
        actual_stor_type = get_storage_account_type(resource_group_name, job_vm)
        RunLog.info("verify disk pool storage account type.")
        if actual_stor_type == storage_type:
            ResultLog.info('PASS')
            RunLog.info("remove deployment %s" % deployment_name)	
            Run("bosh -n delete deployment %s" % deployment_name)
        else:
            ResultLog.error('FAIL')
        RunLog.info("expected storage account type is %s, actual is %s" % (storage_type, actual_stor_type))
    else:
        ResultLog.error('FAIL')
        RunLog.info("deploy failed")
    
    UpdateState("TestCompleted")

if __name__ == '__main__':
    source_manifest_name = 'example_manifests/single-vm-cf.yml'
    destination_manifest_name = 'cpi-disk-pools-storage-single-vm.yml'
    deployment_name = 'disk-pools-storage'
    disk_pool_name = "default"
    job_name = "cpi_verify_disk_pools_storage_z1"
    settings = load_jsonfile('settings')
    resource_group_name = settings['RESOURCE_GROUP_NAME']

    RunTest()
