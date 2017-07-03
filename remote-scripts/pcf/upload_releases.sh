#!/bin/bash
set -e
shopt -s expand_aliases
alias bosh='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

elastic_runtime_ver=$1
download_token=$2

# download releases
sudo apt-get install -y python3-pip
pip3 install requests
echo "Elastic Runtime: $elastic_runtime_ver"
python3 download_releases.py $elastic_runtime_ver $download_token

# upload releases
for f in releases/*.tgz
do
  echo uploading $f
  bosh -n upload release $f --skip-if-exists
  
done

# generate version files for stemcell and releases
# stemcell.txt
# releases.txt
python3 get_stemcell_version.py 

bosh releases | grep -v 'Commit Hash' | grep '|' | tr -d '|' | awk {'print $1,$2'} > releases.txt

