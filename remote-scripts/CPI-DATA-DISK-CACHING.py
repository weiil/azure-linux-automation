#!/usr/bin/env python

from azuremodules import *
import random

def update_cf_manifest(source_yml_file, destination_yml_file, disk_caching):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    RunLog.info("Deployment Name: %s" % deployment_name)
    out['name'] = deployment_name
    RunLog.info('Add disk pools. Name: %s, Caching: %s' % (disk_pool_name, disk_caching))
    new_disk_pool = {
        'name': disk_pool_name,
        'disk_size': 1024,
        'cloud_properties': {
            'caching': disk_caching
        }
    }
    out['disk_pools'] = [new_disk_pool]
    RunLog.info('Use the disk pool')
    out['jobs'][0]['persistent_disk_pool'] = disk_pool_name
    out['jobs'][0]['name'] = job_name
    del out['jobs'][0]['persistent_disk']
    generate_manifest(destination_yml_file ,out)

def get_vm_name_by_cf_job_name(rg_name, job_name):
    return Run("az vm list -g %s --query \"[?tags.job==\'%s\'].name | [0]\" | tr -d '\"' | tr -d '\\n'" % (rg_name, job_name))

def get_data_disk_caching(rg_name, vm_name):
    return Run("az vm unmanaged-disk list -g %s -n %s --query \"[?name!='ephemeral-disk'].caching | [0]\" | tr -d '\"' | tr -d '\\n'" % (rg_name, vm_name))

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    # random choice caching option
    #disk_caching_options = ['None', 'ReadOnly', 'ReadWrite']
    disk_caching_options = ['None', 'ReadOnly']
    disk_caching = random.choice(disk_caching_options)

    RunLog.info('update manifest')
    update_cf_manifest(source_manifest_name, destination_manifest_name, disk_caching)

    if DeployCF(destination_manifest_name):
        RunLog.info("deploy successfully")
        job_vm = get_vm_name_by_cf_job_name(resource_group_name, job_name)
        caching = get_data_disk_caching(resource_group_name, job_vm)
        RunLog.info("verify data disk caching.")
        if caching == disk_caching:
            ResultLog.info('PASS')
            RunLog.info("remove deployment %s" % deployment_name)	
            Run("bosh -n delete deployment %s" % deployment_name)
        else:
            ResultLog.error('FAIL')
        RunLog.info("expected cacing is %s, actual caching is %s" % (disk_caching, caching))
    else:
        ResultLog.error('FAIL')
        RunLog.info("deploy failed")
    
    UpdateState("TestCompleted")

if __name__ == '__main__':
    source_manifest_name = 'example_manifests/single-vm-cf.yml'
    destination_manifest_name = 'cpi-disk-pools-caching-single-vm.yml'
    deployment_name = 'disk-pools-caching'
    disk_pool_name = "default"
    job_name = "cpi_verify_data_disk_caching_z1"
    settings = load_jsonfile('settings')
    resource_group_name = settings['RESOURCE_GROUP_NAME']

    RunTest()
