#!/usr/bin/env python3
import sys 
import os.path
import json
import yaml
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('json_file', nargs='?', type=argparse.FileType('r'), default=sys.stdin)
json_file = parser.parse_args().json_file
filename = os.path.splitext(json_file.name)[0]
yaml_file = filename + ".yml"
json_body = json.loads(json_file.read())
with open(yaml_file, 'w') as f:

    if filename == "bosh-for-pcf":
        key = "manifest"
        releases = json_body[key]['releases']
        # cpi
        for r in releases:
            if r['name'] == 'bosh-azure-cpi':
                r['url'] = "https://bosh.io/d/github.com/cloudfoundry-incubator/bosh-azure-cpi-release?v=REPLACE_WITH_YOUR_CPI_URL"
                r['sha1'] = "REPLACE_WITH_YOUR_CPI_SHA1"
                break
        # powerdns
        json_body[key]['jobs'][0]['templates'].append({"name": "powerdns", "release": "bosh"})
        json_body[key]['jobs'][0]['properties']['postgres']['listen_address'] = "10.0.0.10"
        json_body[key]['jobs'][0]['properties']['postgres']['host'] = "10.0.0.10"
        postgres = json_body[key]['jobs'][0]['properties']['postgres']
        json_body[key]['jobs'][0]['properties']['dns'] = {"address": "10.0.0.10", "db": postgres}
        json_body[key]['jobs'][0]['properties']['director']['address'] = "127.0.0.1"
        json_body[key]['jobs'][0]['properties']['director']['db'] = postgres
        json_body[key]['jobs'][0]['properties']['uaadb']['address'] = "10.0.0.10"
        json_body[key]['jobs'][0]['properties']['registry']['db'] = postgres

        # private key
        json_body[key]['cloud_provider']['ssh_tunnel']['private_key'] = "~/bosh"

    elif filename == "pcf-cloud-config":
        key = "cloud_config"
        network = json_body[key]['networks'][0]
        subnet = network['subnets'][0]
        # powerdns
        subnet['dns'] = ["10.0.0.10"]
        subnet['reserved'] = ["10.0.0.2-10.0.0.10", "10.0.0.51-10.0.15.254"]
        subnet['static'] = ['10.0.0.15', '10.0.0.16', '10.0.0.17', '10.0.0.18', '10.0.0.19', '10.0.0.20', '10.0.0.24', '10.0.0.25', '10.0.0.28']
    elif filename == "pcf-on-azure":
        key = "manifest"
    else:
        raise Exception('incorrect json file you input to the script')

    yaml.dump(json_body[key], f, default_flow_style=False)