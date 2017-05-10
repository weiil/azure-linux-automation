import yaml
import sys
from shutil import move

def main():
    cf_yaml_path = sys.argv[1]
    cf_yaml_mod_path = cf_yaml_path + '.mod'

    # for CF
    with open(cf_yaml_path) as ff:
        cf = yaml.load(ff)
        networks = cf['networks']
        for network in networks:
            subnets = network.get('subnets')
            if subnets:
                for subnet in subnets:
                    subnet['dns'] = ['10.0.0.4']
        with open(cf_yaml_mod_path, 'w') as f:
            yaml.dump(cf, f)
    move(cf_yaml_path, cf_yaml_path + '.origin')
    move(cf_yaml_mod_path, cf_yaml_path)

if __name__ == '__main__':
    main()
