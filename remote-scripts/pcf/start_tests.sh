#!/bin/bash
set -e
shopt -s expand_aliases
alias bosh='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'

test=$1
passwd=$2

# login
echo 'Login bosh director'
bosh login >/dev/null 2>&1 << EndOfessage
admin
${passwd}
EndOfessage

if [ $test = 'smoke' ]; then
    { bosh run errand smoke_tests --download-logs --logs-dir ~ && echo smoke_test_pass || echo smoke_test_fail; } | tee smoke-tests.log
else [ $test = 'acceptance' ]
    { bosh run errand acceptance_tests --download-logs --logs-dir ~ && echo cat_test_pass || echo cat_test_fail; } | tee acceptance-tests.log
fi