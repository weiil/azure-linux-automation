#!/bin/bash
set -e
shopt -s expand_aliases
alias bosh='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

lb_ip=$1
director_passwd=$2
elastic_runtime_ver=$3
download_token=$4

# target
echo 'Target bosh director'
bosh -n --ca-cert root_ca_certificate target 10.0.0.10
# login
echo 'Login bosh director'
bosh login >/dev/null 2>&1 << EndOfessage
admin
${director_passwd}
EndOfessage

# upload releases
echo 'Upload releases'
./upload_releases.sh $elastic_runtime_ver $download_token

# upload stemcell
echo 'Upload stemcell'
stemcell_ver=`cat stemcell.txt`
bosh -n upload stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=${stemcell_ver} --skip-if-exists

# update director uuid
echo 'Update director id in manifest'
sed -i -e "s/REPLACE_WITH_DIRECTOR_UUID/$(bosh status --uuid)/" ./pcf-on-azure.yml

# update releases
echo 'Update releases information in manifest'
sed -i -e "s/REPLACE_WITH_PUSH_APPS_MANAGER_VERSION/$(cat releases.txt | grep 'push-apps-manager-release' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_BINARY_BP_VERSION/$(cat releases.txt | grep 'binary-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_CAPI_VERSION/$(cat releases.txt | grep 'capi' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_CF_AUTOSCALING_VERSION/$(cat releases.txt | grep 'cf-autoscaling' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_CF_MYSQL_VERSION/$(cat releases.txt | grep 'cf-mysql' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_CF_NETWORKING_VERSION/$(cat releases.txt | grep 'cf-networking' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_CF_VERSION/$(cat releases.txt | grep 'cf ' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_CFLINUXFS2_VERSION/$(cat releases.txt | grep 'cflinuxfs2' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_CONSUL_VERSION/$(cat releases.txt | grep 'consul' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_DIEGO_VERSION/$(cat releases.txt | grep 'diego' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_DOTNET_BP_VERSION/$(cat releases.txt | grep 'dotnet-core-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_ETCD_VERSION/$(cat releases.txt | grep 'etcd' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_GARDEN_RUNC_VERSION/$(cat releases.txt | grep 'garden-runc' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_GO_BP_VERSION/$(cat releases.txt | grep 'go-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_JAVA_BP_VERSION/$(cat releases.txt | grep 'java-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_LOGGREGATOR_VERSION/$(cat releases.txt | grep 'loggregator' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_MYSQL_BACKUP_VERSION/$(cat releases.txt | grep 'mysql-backup' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_MYSQL_MONITORING_VERSION/$(cat releases.txt | grep 'mysql-monitoring' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_NATS_VERSION/$(cat releases.txt | grep 'nats' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_NFS_VOLUME_VERSION/$(cat releases.txt | grep 'nfs-volume' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_NODEJS_BP_VERSION/$(cat releases.txt | grep 'nodejs-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_NOTIFICATIONS_VERSION/$(cat releases.txt | grep 'notifications ' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_NOTIFICATIONS_UI_VERSION/$(cat releases.txt | grep 'notifications-ui' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_PHP_BP_VERSION/$(cat releases.txt | grep 'php-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_PIVOTAL_ACCOUNT_VERSION/$(cat releases.txt | grep 'pivotal-account' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_POSTGRES_VERSION/$(cat releases.txt | grep 'postgres' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_PYTHON_BP_VERSION/$(cat releases.txt | grep 'python-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_ROUTING_VERSION/$(cat releases.txt | grep 'routing' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_RUBY_BP_VERSION/$(cat releases.txt | grep 'ruby-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_SERVICE_BACKUP_VERSION/$(cat releases.txt | grep 'service-backup' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_STATICFILE_BP_VERSION/$(cat releases.txt | grep 'staticfile-offline-buildpack' | cut -d ' ' -f2)/" ./pcf-on-azure.yml
sed -i -e "s/REPLACE_WITH_UAA_VERSION/$(cat releases.txt | grep 'uaa' | cut -d ' ' -f2)/" ./pcf-on-azure.yml

# update stemcell
echo 'Update stemcell information'
sed -i -e "s/REPLACE_WITH_STEMCELL_VERSION/$(cat stemcell.txt)/" ./pcf-on-azure.yml

# update load balancer ip address
echo 'Update load balancer ip address in manifest'
sed -i -e "s/REPLACE_WITH_LB_IP/${lb_ip}/g" ./pcf-on-azure.yml

# deploy
echo 'Update cloud-config for PCF on Azure'
bosh -n update cloud-config ./pcf-cloud-config.yml
echo 'Start deployments'
bosh deployment ./pcf-on-azure.yml
bosh -n deploy
echo '---END---'
