#!/usr/bin/env python3
import sys
import yaml

bosh = sys.argv[1]
with open(bosh) as f:
    bosh = yaml.load(f.read())

with open('root_ca_certificate', 'w') as f:
    f.write(bosh['jobs'][0]['properties']['hm']['director_account']['ca_cert'])
    print('write key to root_ca_certificate')

with open('uaa_admin_password', 'w') as f:
    users = bosh['jobs'][0]['properties']['uaa']['scim']['users']
    for u in users:
        if u['name'] == 'admin':
            f.write(u['password'])
            break
    print('write password to uaa_admin_password')



