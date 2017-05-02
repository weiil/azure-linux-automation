import sys
import yaml
from copy import deepcopy
from pprint import pprint

file_name = sys.argv[1]
manifest_file_name = sys.argv[2]


def load_manifest(file_name):
    print '>>>>>> Load manifest'
    with open(file_name) as f:
        out = yaml.load(f)
    return out

def remove_unnessary_jobs(obj_manifest):
    print '>>>>>> Remove unnessary jobs'    
    jobs = obj_manifest['jobs']
    for k, v in enumerate(jobs):
        if v['name'] == 'postgres_z1':
            return [v]

def remove_unnessary_releases(obj_manifest):
    print '>>>>>> Remove unnessary releases'
    releases = obj_manifest['releases']
    for k, v in enumerate(releases):
        if v['name'] == 'cf':
            return [v]

def update_manifest(out):
    print '>>>>>> Update manifest'
    if(manifest_file_name == 'managed-disk-single-vm-cf.yml'):
        out['name'] = 'managed-disk-cf'
        out['jobs'][0]['name'] = 'manageddisk_z1'
        out['jobs'][0]['networks'][0]['static_ips'] = ['10.0.16.6']

    if(manifest_file_name == 'separate-network-single-vm-cf.yml'):
        cf_ip = sys.argv[3]
        network = filter(lambda j:j.get('name') == 'cf_public', out['networks'])
        network[0]['cloud_properties'] = {'resource_group_name':'bosh-test-network'}
        out['name'] = 'separate-network-cf'
        out['jobs'][0]['name'] = 'separatenetwork_z1'
        out['jobs'][0]['networks'][0]['default'] = ['gateway', 'dns']
        out['jobs'][0]['networks'][0].pop('static_ips')
        out['jobs'][0]['networks'].append({'name':'cf_public','static_ips': cf_ip})

    if(manifest_file_name == 'multiple-nics-single-vm-cf.yml'):
        out['name'] = 'multiple-nics-cf'
        out['jobs'][0]['name'] = 'multiplenics_z1'
        out['jobs'][0]['networks'][0]['default'] = ['gateway', 'dns']
        out['jobs'][0]['networks'][0]['static_ips'] = ['10.0.16.8']
        out['jobs'][0]['networks'].append({'name':'cf_private2'})
        out['jobs'][0]['networks'].append({'name':'cf_private3'})
        
        resource = filter(lambda j:j.get('name') == 'resource_postgres_z1', out['resource_pools'])
        resource[0]['cloud_properties']['instance_type'] = 'Standard_D3'
        private_network = filter(lambda j:j.get('name') == 'cf_private', out['networks'])
        vnet = private_network[0]['subnets'][0]['cloud_properties']['virtual_network_name']
        private_network2 =  {'name': 'cf_private2',
    'subnets': [{'cloud_properties': {'subnet_name': 'CloudFoundry2',
                                        'virtual_network_name': vnet},
                'dns': ['168.63.129.16', '8.8.8.8'],
                'gateway': '10.0.40.1',
                'range': '10.0.40.0/24',
                'reserved': ['10.0.40.2 - 10.0.40.3'],
                'static': ['10.0.40.4 - 10.0.40.100']}],
    'type': 'manual'}
        private_network3 =  {'name': 'cf_private3',
    'subnets': [{'cloud_properties': {'subnet_name': 'CloudFoundry3',
                                        'virtual_network_name': vnet},
                'dns': ['168.63.129.16', '8.8.8.8'],
                'range': '10.0.41.0/24',}],
    'type': 'dynamic'}
        out['networks'].append(private_network2)
        out['networks'].append(private_network3)

    if (manifest_file_name == 'deploy-for-enterprise-single-vm-cf.yml'):
        out['name'] = 'deploy-cf-for-enterprise'
        test_job_name  = 'mytestjob_z1'
        params = sys.argv[3]
        print params
        test_storage_name, test_storage_location, as_name = params.split(',')

        # modification for resource pools
        for pool in out['resource_pools']:
            # configure availability set
            if pool['name'] == 'resource_postgres_z1':
                pool['cloud_properties']['availability_set'] = as_name
            # configure multiple storage account
            elif pool['name'] == 'resource_z1':
                pool['cloud_properties']['instance_type'] = 'Standard_DS1'
                pool['cloud_properties']['storage_account_name'] = test_storage_name
                pool['cloud_properties']['storage_account_type'] = 'Premium_LRS'
                pool['cloud_properties']['storage_account_location'] = test_storage_location
            else:
                continue

        # add a job for multiple storage account testing
        # copy a job
        new_job = deepcopy(out['jobs'][0])
        # rename the job
        new_job['name'] = test_job_name
        # change the static ip
        new_job['networks'][0]['static_ips'][0] = '10.0.16.7'
        # change to the new resource pool
        new_job['resource_pool'] = 'resource_z1'
        # aapend the new job to jobs
        out['jobs'].append(new_job)

        # configure the corresponding job for availability set
        out['jobs'][0]['instances'] = 2
        out['jobs'][0]['networks'][0]['static_ips'][0] = '10.0.16.9'
        out['jobs'][0]['networks'][0]['static_ips'].append('10.0.16.19')

    
    if (manifest_file_name == 'multiple-haproxy-single-vm-cf.yml'):
        out['name'] = 'multiple-haproxy'
        params = sys.argv[3]
        as_name, lb_name = params.split(',')

        # modification for resource pools
        for pool in out['resource_pools']:
            # configure availability set
            if pool['name'] == 'resource_postgres_z1':
                pool['cloud_properties']['availability_set'] = as_name
                pool['cloud_properties']['load_balancer'] = lb_name
                pool['cloud_properties']['instance_type'] = "Standard_D1"
            else:
                continue

        # update job postgres_z1
        out['jobs'][0]['instances'] = 2
        out['jobs'][0]['networks'][0]['static_ips'].append('10.0.16.15')

    return out


def generate_manifest(obj_manifest):
    print '>>>>>> generate manifest:' 
    with open(manifest_file_name,'w') as f:
        yaml.dump(obj_manifest,f)
    print '>>>>>> finished'


if __name__ == "__main__":
    out = load_manifest(file_name)
    out['jobs'] = remove_unnessary_jobs(out)
    out['releases'] = remove_unnessary_releases(out)
    final = update_manifest(out)
    pprint(final['jobs'])
    pprint(final['resource_pools'])
    generate_manifest(final)