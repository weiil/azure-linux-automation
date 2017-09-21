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

# deploy
echo 'Update cloud-config for PCF on Azure'
bosh -n update cloud-config ./pcf-cloud-config.yml
echo 'Start deployments'
bosh deployment ./pcf-on-azure.yml
bosh -n deploy
echo '---END---'
