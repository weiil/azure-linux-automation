#!/usr/bin/env python3

import requests
import os
import sys

# download api
auth_uri = 'https://network.pivotal.io/api/v2/authentication'
elastic_runtime_releases_uri = 'https://network.pivotal.io/api/v2/products/elastic-runtime/releases'

# auth with token
def auth(token):
    headers = {'Authorization': 'Token {}'.format(token)}
    res = requests.get(auth_uri, headers=headers)
    if res.status_code == 200:
        print('token authenticated.')
    else:
        print('invalid token, authenticate failed.')
        sys.exit(41)

# get download api of elastic runtime
def get_download_api(version):
    res_releases = requests.get(elastic_runtime_releases_uri)
    releases = res_releases.json()['releases']
    r = filter(lambda x:x['version'] == version, releases)
    l_r = list(r)
    if len(l_r) == 0:
        print('not found elastic runtime v{}'.format(version))
        sys.exit('42')
    else:
        r = l_r[0]
        eula = r['_links']['eula_acceptance']['href']
        url=r['_links']['product_files']['href']
        res = requests.get(url)
        if res.status_code == 200:
            product_files = res.json()['product_files']
            p = filter(lambda y:y['name'] == 'PCF Elastic Runtime', product_files)
            l_p = list(p)
            if len(l_p) == 0:
                print('not found product file for pcf elastic runtime from uri:{}'.format(url))
                sys.exit(43)
            else:
                p = l_p[0]
                download_api = p['_links']['download']['href']
                return eula, download_api
        else:
            print('get product_files failed from uri:{}'.format(url))
            sys.exit(43)

# accept eula
def accept_eula(eula, api_token):
    headers = {'Authorization': 'Token {}'.format(api_token)}
    res = requests.post(eula, headers=headers)
    if res.status_code == 200:
        print('EULA accepted.')
    else:
        print('failed to accept EULA.')
        sys.exit(44)

# download release
def download(api_token, version):
    auth(api_token)
    eula, download_api = get_download_api(version)
    print('EULA: {}'.format(eula))
    print('Download API: {}'.format(download_api))
    accept_eula(eula, api_token)
    cmd = 'wget -O cf-{}.pivotal.tgz --header="Authorization: Token {}" {}'.format(version, api_token, download_api)
    print('downloading')    
    print(cmd)
    os.system(cmd)
    print('extracting releases to PWD')
    os.system('unzip cf-*.pivotal.tgz "*releases*"')


if __name__ == "__main__":
    elastic_runtime_version = sys.argv[1]
    token = sys.argv[2]
    download(token,elastic_runtime_version)
