#!/bin/bash
set -e
shopt -s expand_aliases
alias bosh='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

# fetch credentials
./credentials.py bosh-for-pcf.yml

# target
echo 'Target bosh director'
bosh -n --ca-cert root_ca_certificate target 10.0.0.10
# login
echo 'Login bosh director'
director_passwd=`cat uaa_admin_password`
bosh login >/dev/null 2>&1 << EndOfessage
admin
${director_passwd}
EndOfessage

# specify uuid in pcf manifest
sed -i "s/director_uuid: ignore/director_uuid: $(bosh status --uuid)/g" pcf-on-azure.yml

# upload releases
echo 'Upload releases'
ertfilename=`ls *.pivotal`
mv $ertfilename $ertfilename".tgz"
unzip "$ertfilename.tgz" "*releases*"
for f in releases/*.tgz
do
  echo uploading $f
  bosh -n upload release $f --skip-if-exists
done
mv $ertfilename".tgz" $ertfilename
rm -rf releases/
echo 'done'

# upload stemcells
echo 'upload stemcells'
stemcellfilename=`ls bosh-stemcell-*-azure-hyperv*go_agent.tgz`
bosh upload stemcell $stemcellfilename --skip-if-exists
echo 'done'

# deploy
echo 'Update cloud-config for PCF on Azure'
bosh -n update cloud-config ./pcf-cloud-config.yml
echo 'Start deployments'
bosh deployment ./pcf-on-azure.yml
bosh -n deploy
echo '---END---'