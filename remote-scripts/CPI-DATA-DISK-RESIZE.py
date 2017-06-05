#!/usr/bin/env python

from azuremodules import *
import yaml
import random

def update_cf_manifest(source_yml_file, destination_yml_file, initial_size):
    RunLog.info("Update CF manifest file")
    out = load_manifest(source_yml_file)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    RunLog.info("Deployment Name: %s" % deployment_name)
    out['name'] = deployment_name
    out['jobs'][0]['persistent_disk'] = initial_size
    RunLog.info('initial size of data disk: %s' % initial_size)
    out['jobs'][0]['name'] = job_name
    for rp in out['resource_pools']:
        if rp['name'] == 'resource_postgres_z1':
            rp['cloud_properties']['instance_type'] = 'Standard_A2'
            rp['stemcell']['version'] = '3312.12'
    generate_manifest(destination_yml_file ,out)

def get_storage_access(rg_name, storage):
    return Run("az storage account keys list -n %s -g %s --query \'[0].value\' | tr -d '\"' | tr -d '\\n'" % (storage, rg_name))

def get_vm_name_by_cf_job_name(rg_name, job_name):
    return Run("az vm list -g %s --query \"[?tags.job==\'%s\'].name | [0]\" | tr -d '\"' | tr -d '\\n'" % (rg_name, job_name))

# todo: get managed data disk
def get_data_disk_info_by_vm_name(rg_name, vm_name):
    vhd_name = Run("az vm unmanaged-disk list -g %s -n %s --query \"[?name!='ephemeral-disk'].name | [0]\" | tr -d '\"' | tr -d '\\n'" % (rg_name, vm_name)) + '.vhd'
    vhd_uri = Run("az vm unmanaged-disk list -g %s -n %s --query \"[?name!='ephemeral-disk'].vhd.uri | [0]\" | tr -d '\"' | tr -d '\\n'" % (rg_name, vm_name))
    storage = vhd_uri.split('//')[1].split('.')[0]
    container = vhd_uri.split('/')[3]
    return (storage, container, vhd_name) 

def get_data_disk_size(rg_name, vm_name, managed):
    if not managed:
        storage, container, vhd = get_data_disk_info_by_vm_name(rg_name, vm_name)
        key = get_storage_access(rg_name, storage)
        content_length = Run("az storage blob show -c %s -n %s --query \"properties.contentLength\" --account-name %s --account-key %s | tr -d '\\n'" % (container, vhd, storage, key))
        # unit: GB
        return int(content_length) / 1024 / 1024 / 1024
    else:
        disk_size = Run("az vm unmanaged-disk list -n %s -g %s --query \"[?createOption=='attach'].diskSizeGb | [0]\" | tr -d '\"' | tr -d '\\n'" % (vm_name, rg_name))
        return int(disk_size)

def RunTest():
    UpdateState("TestStarted")
    RunLog.info('install azure-cli 2.0 and set azure subscription')
    InstallAzureCli()
    set_azure_subscription('settings')

    RunLog.info('update manifest')
    update_cf_manifest(source_manifest_name, destination_manifest_name, init_size)

    RunLog.info("upload stemcell v3312.12 for resize teseting")
    Run("bosh upload stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3312.12 --sha1 2cc0ecc75a2e29c4df1bea18e91c777688026fed --skip-if-exists")

    is_managed = Run("cat bosh.yml | grep \'use_managed_disks\' | awk {\'print $2\'} | tr -d '\\n'")
    if is_managed == 'true':
        is_managed = True
        RunLog.info("testing for managed disk")
    else:
        is_managed = False
        RunLog.info("testing for unmanaged disk")

    if DeployCF(destination_manifest_name):
        RunLog.info("inital deploy successfully")
        job_vm = get_vm_name_by_cf_job_name(resource_group_name, job_name)

        # define test size
        rd1 = random.randint(5,20)
        size1 = rd1 * 1024
        size1 += init_size
        rd2 = random.randint(4, rd1)
        size2 = rd2 * 1024
        size2 -= rd2

        RunLog.info("resizing(increase) data disk")
        with open(destination_manifest_name) as f:
            out1 = yaml.load(f)
            out1['jobs'][0]['persistent_disk'] = size1
            RunLog.info("change size from %s to %s" %(init_size, size1))
        with open(destination_manifest_name,'w') as f:
            yaml.dump(out1,f)
        if DeployCF(destination_manifest_name):
            RunLog.info('deploy successfully after increse size to %s' % size1)
            RunLog.info('verify:')
            cur_size1 = get_data_disk_size(resource_group_name, job_vm, is_managed)
            if cur_size1 == size1 / 1024:
                RunLog.info('pass, current size is %s' % cur_size1)
                RunLog.info('resizing(decrease) data disk')
                with open(destination_manifest_name) as f:
                    out2 = yaml.load(f)
                    out2['jobs'][0]['persistent_disk'] = size2
                    RunLog.info("change size from %s to %s" %(size1, size2))
                with open(destination_manifest_name, 'w') as f:
                    yaml.dump(out2, f)
                if DeployCF(destination_manifest_name):
                    RunLog.info('deploy successfully after decrease size to %s' % size2)
                    RunLog.info('verify:')
                    cur_size2 = get_data_disk_size(resource_group_name, job_vm, is_managed)
                    if cur_size2 == size2 / 1024:
                        RunLog.info('pass, current size is %s' % cur_size2)
                        ResultLog.info('PASS')
                        RunLog.info("remove deployment %s" % deployment_name)
                        Run("bosh -n delete deployment %s" % deployment_name)
                    else:                        
                        ResultLog.error('FAIL')        
                        RunLog.info('failed, current size is %s not equal to expected %s' % (cur_size2, size2))
                else:
                    ResultLog.error('FAIL')
                    RunLog.info('deploy failed after decrease size to %s' % size2)
            else:
                ResultLog.error('FAIL')
                RunLog.info('failed, current size is %s not equal to expected %s' % (cur_size1, size1))
        else:
            ResultLog.error('FAIL')
            RunLog.info('deploy failed after increse size to %s' % size1)
    else:
        ResultLog.error('FAIL')
        RunLog.info("inital deploy failed")
    
    UpdateState("TestCompleted")

if __name__ == '__main__':
    source_manifest_name = 'example_manifests/single-vm-cf.yml'
    destination_manifest_name = 'cpi-disk-resize-single-vm.yml'
    deployment_name = 'disk-resize'
    job_name = "cpi_verify_data_disk_resize_z1"
    settings = load_jsonfile('settings')
    resource_group_name = settings['RESOURCE_GROUP_NAME']
    init_size = 1024

    RunTest()
