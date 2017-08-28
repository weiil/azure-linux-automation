#!/usr/bin/env python3

import requests
import sys
import time
import os
import pexpect
import subprocess
import json
from pprint import pprint

# params
with open(sys.argv[1]) as f:
    params = json.loads(f.read())
    opsman = params['opsmanURL']
    admin_user = params['adminUser']
    admin_pwd = params['adminPwd']
    decryption_passphrase = params['decryptionPass']
    pivotal_net_token = params['pivotalNetToken']
    lb_ip = params['lb_ip']

class CredentialManager(object):
    def __init__(self):
        pass

class OpsMan(object):
    def __init__(self, baseUrl):
        self.is_uaa_setup = False
        self.base = baseUrl
        self._uaa_token = None

    def setup_uaa(self):
        print("set uaa")
        url = "{}/api/v0/setup".format(self.base)
        data = '{ "setup": {\n' + '    "decryption_passphrase": "' + decryption_passphrase + '",\n' + '    "decryption_passphrase_confirmation": "' + decryption_passphrase + '",\n' + '    "eula_accepted": "true",\n' + '    "identity_provider": "internal",\n' + '    "admin_user_name":  "' + admin_user + '",\n' + '    "admin_password": "' + admin_pwd + '",\n' + '    "admin_password_confirmation": "' + admin_pwd + '",\n' + '    "no_proxy": "127.0.0.1"\n  } }'
        headers = {
            "Content-Type": "application/json",
        }
        res = requests.post(url, headers=headers, data=data, verify=False)
        if res.status_code == 200:
            self.is_uaa_setup = True
            print('setup uaa successfully.')
            print('wait a moment for opsman initial.')
            time.sleep(40) 
        else:
            raise Exception('setup uaa failed and http code:{}'.format(res.status_code))

    def fetch_uaa_token(self):
        print("get uaa authorization token")
        if not self.is_uaa_setup:
            self.setup_uaa()
        if not self._uaa_token:
            rtn = os.system('which uaac')
            if rtn == 0:
                print('check uaac is installed')
            else:
                os.system("sudo gem install cf-uaac")
            uaa = opsman + "/uaa"
            os.system("uaac target {} --skip-ssl-validation".format(uaa))
            cmd = "uaac token owner get"
            child = pexpect.spawn(cmd)
            index = child.expect(["Client ID:(?i)", pexpect.EOF, pexpect.TIMEOUT])
            if index == 0:
                child.sendline("opsman")
                index = child.expect(["Client secret:(?i)", pexpect.EOF, pexpect.TIMEOUT])
                if index == 0:
                    child.sendline("")
                    index = child.expect(["User name:(?i)", pexpect.EOF, pexpect.TIMEOUT])
                    if index == 0 :
                        child.sendline(admin_user)
                        index = child.expect(["Password:(?i)", pexpect.EOF, pexpect.TIMEOUT])
                        if index == 0:
                            child.sendline(admin_pwd)
                            index = child.expect(["Successfully fetched", "error response"])
                            if index == 0:
                                print('successfully fetch token')
                                p = subprocess.run('uaac context', shell=True, stdout=subprocess.PIPE)
                                token = p.stdout.decode('utf8')
                                for k,v in enumerate(token.split()):
                                    if v == 'access_token:':
                                        self._uaa_token = token.split()[k+1]
                            elif index == 1:
                                print('failed to fetch token')
                                child.close(force=True)
                            else:
                                print('pexpect: result not match.')
                                child.close(force=True)
                        else:
                            print('pexpect: #4 not match.')
                            child.close(force=True)
                    else:
                        print("pexpect: #3 not match.")
                        child.close(force=True)
                else:
                    print("pexpect #2 not match.")
                    child.close(force=True)
            else:
                print('pexcept: #1 not match.')
                child.close(force=True)

    @property
    def uaa_token(self):
        self.fetch_uaa_token()
        return self._uaa_token
        
    @property
    def requests_headers(self):
        return {
            'Authorization': 'Bearer {}'.format(self.uaa_token),
            'Content-Type': 'application/json',
        } 

    def set_pivotal_net_token(self):
        print('set pivotal network token')
        url = "{}/api/v0/settings/pivotal_network_settings".format(self.base)
        data = '{{ "pivotal_network_settings": {{ "api_token": "{}" }}}}'.format(self.pivotal_net_token)
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

    def check_download(self, downloadId):
        url = "{}/api/v0/pivotal_network/downloads/{}".format(self.base, downloadId)
        requests.get(url, headers=self.requests_headers, verify=False)


    def download_elastic(self, prod_name='cf', prod_ver):
        pass

    def add_elastic(self, prod_name='cf', prod_ver):
        pass
    
    def get_elastic_guid(self):
        url = "{}/api/v0/staged/products".format(self.base)
        res = requests.get(url, headers=self.requests_headers)
        f = filter(lambda x:x['type'] == 'cf', res.json())
        return next(f)['guid']

    def stage_elastic(self):
        print('STAGE ELASTIC')
        cf_guid = self.get_elastic_guid()
        base_url = "{}/api/v0/staged/products/{}/".format(self.base, cf_guid)

        # assign network
        print('Assign Network')
        url = base_url + "/networks_and_azs"
        data = '{\n          "networks_and_azs": {\n            "singleton_availability_zone": {\n              "name": "null"\n            },\n            "other_availability_zones": [\n              { "name": "null" }\n            ],\n            "network": {\n              "name": "default"\n            }\n          }\n        }'
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        # domains
        print('Domains')
        url = base_url + '/properties'
        print('set system domain')
        data = '{{\n          "properties": {{\n            ".cloud_controller.system_domain": {{"value": "system.{}.xip.io" }}\n          }}\n        }}'.format(self.lb_ip)
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        print('set apps domain')
        data = '{{\n          "properties": {{\n            ".cloud_controller.system_domain": {{"value": "app.{}.xip.io" }}\n          }}\n        }}'.format(self.lb_ip)
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        # networking
        print("Networking")
        print('generate RSA certificate')
        url = "{}/api/v0/certificates/generate".format(self.opsman)
        data = '{{ "domains": ["*.{}.xip.io"] }}'.format(self.lb_ip)
        res = requests.post(url, headers=self.requests_headers, data=data, verify=False)
        cert = res.json()['certificate']
        key = res.json()['key']

        url = base_url + '/properties'
        print('networking')
        data = '{{\n          "properties": {{\n            ".properties.networking_point_of_entry": {{\n              "value": "external_ssl"\n            }},\n            ".properties.networking_point_of_entry.external_ssl.ssl_rsa_certificate": {{\n              "value": {"cert_pem": "{}", "private_key_pem": "{}"}}\n            }}\n          }}\n        }}'.format(cert, key)
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        # application security groups
        print("Application Security Groups")
        url = base_url + '/properties'
        data = '{\n          "properties": {\n            ".properties.security_acknowledgement": {"value": "X" }\n          }\n        }'
        requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        # uaa
        print("UAA")
        print('generate RSA certificate')
        url = "{}/api/v0/certificates/generate".format(self.opsman)
        data = '{{ "domains": ["*.{}.xip.io"] }}'.format(self.lb_ip)
        res = requests.post(url, headers=self.requests_headers, data=data, verify=False)
        cert = res.json()['certificate']
        key = res.json()['key']

        url = base_url + '/properties'
        print('uaa database')
        data = '{\n          "properties": {\n            ".properties.uaa_database": {\n              "value": "internal_mysql"\n            }\n          }\n        }'
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        print('uaa service provider credential')
        data = '{{\n          "properties": {{\n            ".uaa.service_provider_key_credentials": {{\n              "value": {"cert_pem": "{}", "private_key_pem": "{}"}}\n            }}\n          }}\n        }}'.format(cert, key)
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        # internal mysql
        print("Internal MySQL")
        url = base_url + '/properties'
        print('email address')
        data = '{\n          "properties": {\n            ".mysql_monitor.recipient_email": {\n              "value": "axbycz@microsoft.com"\n            }\n          }\n        }'
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        # errands
        print('Errands')
        url = base_url + '/errands'
        print('enable smoke tests only')
        data = '{"errands":[{"name":"smoke-tests","post_deploy":true},{"name":"push-apps-manager","post_deploy":false},{"name":"notifications","post_deploy":false},{"name":"notifications-ui","post_deploy":false},{"name":"push-pivotal-account","post_deploy":false},{"name":"autoscaling","post_deploy":false},{"name":"autoscaling-register-broker","post_deploy":false},{"name":"nfsbrokerpush","post_deploy":false}]}'
        res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
        if res.status_code == 200:
            print('=> successfully')
        else:
            print('=> failed')

        # resources
        print('Resource Config')
        # get jobs firstly
        url = base_url + '/jobs'
        res = requests.get(url, headers=self.requests_headers, verify=False)
        jobs = res.json()['jobs']
        target_jobs = [job for job in jobs if job['name'] not in ['backup-prepare', 'ccdb', 'uaadb', 'ha_proxy', 'tcp_router']]
        # config each job. instance automatic:1, internet connected: false, router: lb: pcf-lb
        for job in target_jobs:
            guid_job = job['guid']
            url = base_url + '/jobs/{}/resource_config'.format(guid_job)
            if job['name'] == 'router':
                data = '{\n          "instances": 1,\n          "instance_type": {\n            "id": "automatic"\n          },\n          "persistent_disk": {\n            "size_mb": "automatic"\n          },\n          "internet_connected": false,\n          "elb_names": ["pcf-lb"]\n        }'
            else:
                data = '{\n          "instances": 1,\n          "instance_type": {\n            "id": "automatic"\n          },\n          "persistent_disk": {\n            "size_mb": "automatic"\n          },\n          "internet_connected": false\n        }'
            res = requests.put(url, headers=self.requests_headers, data=data, verify=False)
            if res.status_code != 200:
                print("config error: {} - {}".format(guid_job, res.text))
        print("=> done")

    def get_elastic_manifest(self):
        print('DOWNLOAD MANIFEST OF PCF')
        cf_guid = self.get_elastic_guid()
        url = "{}/api/v0/staged/products/{}/manifest".format(self.opsman, cf_guid)
        res = requests.get(url, headers=self.requests_headers, verify=False)
        if res.status_code == 200:
            print('=> successfully')
            with open('pcf-on-azure.yml','w') as f:
                yaml.dump(res.json['manifest'], f, default_flow_style=False)
        else:
            print("=> failed")

    def get_cloud_config(self):
        print('DOWNLOAD CLOUD-CONFIG')
        url = "{}/api/v0/staged/cloud_config".format(self.opsman)
        res = requests.get(url, headers=self.requests_headers, verify=False)
        if res.status_code == 200:
            print('=> successfully')
            with open('pcf-cloud-config.yml','w') as f:
                yaml.dump(res.json['cloud_config'], f, default_flow_style=False)
        else:
            print("=> failed")


    def fetch_director_properties(token):
        properties = None
        print('fetch director properties')
        url = "{}/api/v0/staged/director/properties".format(opsman)
        headers = {"Authorization": "Bearer {}".format(token)}
        res = requests.get(url, headers=headers, verify=False)
        if res.status_code == 200:
            properties = res.json()
            properties['iaas_configuration']['ssh_private_key'] = ""
        else:
            print('fetch director properties failed')
        return properties

    def update_direcotr_iaas(token):
        print('update director iaas properties')
        url = "{}/api/v0/staged/director/properties".format(opsman)
        headers = {
            'Authorization': 'Bearer {}'.format(token),
            'Content-Type': 'application/json',
        }

        data_iaas = '{{\n                "iaas_configuration": {{\n                  "subscription_id": "{subscription_id}",\n                  "tenant_id": "{tenant_id}",\n                  "client_id": "{client_id}",\n                  "client_secret": "{client_secret}",\n                  "resource_group_name": "{resource_group_name}",\n                  "bosh_storage_account_name": "{bosh_storage_account_name}",\n                  "default_security_group": "pcf-nsg",\n                  "ssh_public_key": "{ssh_public_key}",\n                  "ssh_private_key": "{ssh_private_key}",\n                  "cloud_storage_type": "managed_disks",\n                  "storage_account_type": "Premium_LRS",\n                  "environment": "AzureCloud"\n                }}\n        }}'.format_map(params)

        data_director = '{\n                "director_configuration": {\n                  "ntp_servers_string": "time-c.nist.gov",\n                  "metrics_ip": "1.2.3.4",\n                  "resurrector_enabled": true,\n                  "max_threads": 1,\n                  "database_type": "internal",\n                  "blobstore_type": "local"\n                }\n        }'

        data_security_syslog = '{\n                "security_configuration": {\n                  "trusted_certificates": "",\n                  "generate_vm_passwords": true\n                },\n                "syslog_configuration": {\n                  "enabled": false\n                }\n        }'


        print(data_iaas)
        print(data_director)
        print(data_security_syslog)

        res = requests.put(url, headers=headers, data=data_iaas, verify=False)
        if res.status_code == 200:
            print('update iaas part successfully')
        else:
            print('update iaas part failed and http code: {}'.format(res.status_code))

        res = requests.put(url, headers=headers, data=data_director, verify=False)
        if res.status_code == 200:
            print('update director part successfully')
        else:
            print('update director part failed and http code: {}'.format(res.status_code))
        
        res = requests.put(url, headers=headers, data=data_security_syslog, verify=False)
        if res.status_code == 200:
            print('update security and syslog part successfully')
        else:
            print('update security and syslog part failed and http code: {}'.format(res.status_code))

    def update_director_networks(token):
        pass

    def assign_director_networks(token):
        print("assign networks for director")
        url = "{}/api/v0/staged/director/network_and_az".format(opsman)
        headers = {
            'Authorization': 'Bearer {}'.format(token),
            'Content-Type': 'application/json',
        }
        data = '{\n          "network_and_az": {\n             "network": {\n               "name": "default"\n             }\n          }\n        }'
        res = requests.put(url, headers=headers, data=data, verify=False)
        if res.status_code == 200:
            print("assign successfully")
        else:
            print('assign failed')

    def fetch_director_manifest(token):
        print("fetch manifest for director")
        url = "{}/api/v0/staged/director/manifest".format(opsman)
        headers = {
            'Authorization': 'Bearer {}'.format(token),
            'Content-Type': 'application/json',
        }
        res = requests.get(url, headers=headers, verify=False)
        if res.status_code == 200:
            print('fetch successfully')
        else:
            print('fetch failed')

    def fetch_cloud_config(token):
        print("fetch cloud config")
        url = "{}/api/v0/staged/director/cloud_config".format(opsman)
        headers = {
            'Authorization': 'Bearer {}'.format(token),
            'Content-Type': 'application/json',
        }
        res = requests.get(url, headers=headers, verify=False)

    def stage_bosh(token):
        update_direcotr_iaas(token)
        update_director_networks(token)
        
    def stage_pcf():
        pass

    def gen_manifest_bosh():
        pass

    def gen_manifest_pcf():
        pass


class Pcf(object):
    def __init__(self, opsmanurl, adminuser, adminpwd, pivtoken, lbip):
        self.opsman = opsmanurl
        self.adminuser = adminuser
        self.adminpwd = adminpwd
        self.uaa_setup = False
        self.uaa_token = None
        self.pivotal_net_token = pivtoken
        self.requests_headers = None
        self.lb_ip = lbip


if __name__ == "__main__":
    pass
