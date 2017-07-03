#!/bin/bash
set -e
shopt -s expand_aliases
alias bosh='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

export BOSH_INIT_LOG_LEVEL="Debug"
export BOSH_INIT_LOG_PATH="./run.log"

bosh-init deploy ~/bosh-for-pcf.yml

bosh -n --ca-cert root_ca_certificate target 10.0.0.10