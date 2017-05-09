import yaml
import sys

def main():
    bosh_yaml_path = sys.argv[0]
    cf_yaml_path = sys.argv[1]

    # for BOSH
    with open(bosh_yaml_path, 'w') as f:
        out = yaml.load(f)
        out['jobs'][0]['properties']['postgres']['listen_address'] = '10.0.0.4'
        out['jobs'][0]['properties']['postgres']['host'] = '10.0.0.4'
        yaml.dump(out, f)

    # for CF
    with open(cf_yaml_path, 'w') as ff:
        out = yaml.load(ff)
        networks = out['networks']
        for network in networks:
            subnets = network.get('subnets')
            if subnets:
                for subnet in subnets:
                    subnet['dns'] = ['10.0.0.4']
        yaml.dump(out, f)

if __name__ == '__main__':
    main()