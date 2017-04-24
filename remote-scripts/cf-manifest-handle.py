import sys
import yaml
import os.path
from pprint import pprint

file_name = sys.argv[1]
manifest_file_name = sys.argv[2]

print '>>>>>> Load manifest:', file_name
with open(file_name) as f:
    out = yaml.load(f)

print '>>>>>> Remove unnessary releases'
releases = out['releases']
print ' >> before'
pprint(releases)
print ' >> after'
out['releases'] = filter(lambda r:r.get('name') == 'cf', releases)
pprint(out['releases'])
print ' >> done'


print '>>>>>> Remove unnessary jobs'
print ' >> before'
pprint([j.get('name') for j in out['jobs']])
print ' >> after'
out['jobs'] = filter(lambda j:j.get('name') == out['jobs'][0]['name'], out['jobs'])
pprint([j.get('name') for j in out['jobs']])
print ' >> done'

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

print ' >> done'




print '>>>>>> generate manifest:' 
with open(manifest_file_name,'w') as f:
    yaml.dump(out,f) 

print '>>>>>> FINISH'

