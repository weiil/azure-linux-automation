#!/bin/bash
set -e

# extract param.json 
my_subscription=`cat $1 | jq .subscriptionId | tr -d '"'`
my_tenant=`cat $1 | jq .tenantId | tr -d '"'`
my_client=`cat $1 | jq .clientId | tr -d '"'`
super_duper_secret=`cat $1 | jq .clientSecret | tr -d '"'`
public_key=`cat $1 | jq .sshKey | tr -d '"'`
private_key=`cat $1 | jq .sshPrivateKey | tr -d '"'`
my_resource_group=`cat $1 | jq .resourceGroup | tr -d '"'`
storage_account_bosh=`cat $1 | jq .boshStorage | tr -d '"'`
cloud_storage_type=`cat $1 | jq .cloudStorageType | tr -d '"'`
storage_account_type=`cat $1 | jq .storageAccountType | tr -d '"'`
storage_account_deployment=`cat $1 | jq .deploymentsStorageAccountName | tr -d '"'`
username=`cat $1 | jq .uaaUserName | tr -d '"'`
password=`cat $1 | jq .uaaPassword | tr -d '"'`
elastic_ver=`cat $1 | jq .elasticVersion | tr -d '"'`
token=`cat $1 | jq .netToken | tr -d '"'`

# input
opsmanurl=$2
$lb=$3

echo '----------------------------------------- Preparation -----------------------------------------'

echo '######################### install dependencies'
sudo apt-get update
sudo apt-get install -y python3-pip
pip3 install pyyaml

# install jq if need
sudo apt-get install -y jq

sudo apt-add-repository -y ppa:brightbox/ruby-ng
sudo apt-get update
sudo apt-get install -y ruby2.4
sudo apt-get install -y ruby2.4-dev
sudo gem install cf-uaac

wget -q -O - https://raw.githubusercontent.com/starkandwayne/homebrew-cf/master/public.key | sudo apt-key add -
echo "deb http://apt.starkandwayne.com stable main" | sudo tee /etc/apt/sources.list.d/starkandwayne.list
sudo apt-get update
sudo apt-get install -y om

which om
if [ $? -eq 0 ]
then
  echo 'om install successfully'
else
  echo 'preparation/om: failed'
  exit
fi

echo '######################### UAA access token'
which uaac
if [ $? -eq 0 ]
then
  echo 'uaac install successfully'
else
  echo 'preparation/uaac: failed'
  exit
fi

uaac target "$opsmanurl/uaa" --skip-ssl-validation

/usr/bin/expect <<\EOF
spawn uaac token owner get
expect "Client ID:*"
sleep 1
send "opsman\r"
sleep 1
expect "Client secret:*"
sleep 1
send "\r"
sleep 1
expect "User name:*"
sleep 1
send "azureuser\r"
sleep 1
expect "Password:*"
sleep 1
send "#EDCzaq1\r"
sleep 3
EOF

echo 
uaa_token=`uaac context | grep access_token | awk '{print $2}'`
echo "UAA access token:"
echo $uaa_token

echo '----------------------------------------- Director -----------------------------------------'
echo '######################### azure config'
# there is a bug in om, call api directly in here
# TODO:
# managed disk and storage accounts, standard_lrs and premium_lrs
curl "$opsmanurl/api/v0/staged/director/properties" \
    -k \
    -X PUT \
    -H "Authorization: Bearer $uaa_token" \
    -H "Content-Type: application/json" \
    -d '{
          "iaas_configuration": {
            "subscription_id": "'"$my_subscription"'",
            "tenant_id": "'"$my_tenant"'",
            "client_id": "'"$my_client"'",
            "client_secret": "'"$super_duper_secret"'",
            "resource_group_name": "'"$my_resource_group"'",
            "bosh_storage_account_name": "'"$storage_account_bosh"'",
            "default_security_group": "pcf-nsg",
            "ssh_public_key": "'"$public_key"'",
            "ssh_private_key": "'"$private_key"'",
            "cloud_storage_type": "'"$cloud_storage_type"'",
            "storage_account_type": "'"$storage_account_type"'",
            "environment": "AzureCloud"
          }
        }'

echo '######################### director config'
om \
 --target $opsmanurl \
 --username $username \
 --password $password \
 -k \
 configure-bosh \
   --director-configuration '{
     "ntp_servers_string": "time-c.nist.gov"
   }'

echo '######################### create network'
om \
 --target $opsmanurl \
 --username $username \
 --password $password \
 -k \
 configure-bosh \
   --networks-configuration '{
  "networks": [
    {
      "name": "default",
      "subnets": [
        {
          "iaas_identifier": "pcf-net/pcf",
          "cidr": "10.0.0.0/20",
          "reserved_ip_ranges": "10.0.0.1-10.0.0.9",
          "dns": "168.63.129.16",
          "gateway": "10.0.0.1"
        }
      ]
    }
  ]
}' 

echo '######################### assign network'
om \
 --target $opsmanurl \
 --username $username \
 --password $password \
 -k \
 configure-bosh \
   --network-assignment '{
  "network": "default"
}'

echo '######################### fetch manifest'
om \
 --target $opsmanurl \
 --username $username \
 --password $password \
 -k \
 curl \
   --path "/api/v0/staged/director/manifest" > bosh-for-pcf.json

./json2yaml.py bosh-for-pcf.json

echo '######################### fetch cloud-config'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
curl \
 --path "/api/v0/staged/cloud_config" > pcf-cloud-config.json

./json2yaml.py pcf-cloud-config.json


echo '----------------------------------------- Elastic -----------------------------------------'
echo '######################### download'
python3 download_releases.py elastic $elastic_ver $token

echo '######################### upload'
cf_file_name=`ls *.pivotal`
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
upload-product \
 --product $cf_file_name
#### (about 24 minutes)

echo '############################# stage'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
stage-product \
 --product-name cf \
 --product-version $elastic_ver

echo '######################### get properties'
cf_guid=`om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
curl \
 --path /api/v0/staged/products | jq '.[] | select(.type == "cf") | .guid' | tr -d '"'`

om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
curl \
 --path /api/v0/staged/products/$cf_guid/properties

echo '######################### configure'
echo '<Domains>'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
configure-product \
 --product-name cf \
 --product-properties '{
        ".cloud_controller.system_domain": {
          "value": "'"system.${lb}.xip.io"'"
        },
        ".cloud_controller.apps_domain": {
          "value": "'"app.${lb}.xip.io"'"
        }
      }'

echo '<Networking>'
echo '---> generate RSA certificate'
rsa=`om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
curl \
 --request POST \
 --path /api/v0/certificates/generate \
 --data '{"domains": ["'"*.$lb.xip.io"'"]}'`
cert=`echo $rsa | jq .certificate | tr -d '"'`
key=`echo $rsa | jq .key | tr -d '"'`

echo '---> external ssl'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
configure-product \
 --product-name cf \
 --product-properties '{
        ".ha_proxy.skip_cert_verify": {
          "value": true
        },
        ".properties.networking_point_of_entry": {
          "value": "external_ssl"
        },
        ".properties.networking_point_of_entry.external_ssl.ssl_rsa_certificate": {
          "value": {
            "cert_pem": "'"$cert"'",
            "private_key_pem": "'"$key"'"
          }
        }
      }'

echo '<Application Security Groups>'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
configure-product \
 --product-name cf \
 --product-properties '{
        ".properties.security_acknowledgement": {
          "value": "X"
        }
      }'

echo '<UAA>'
echo '---> generate RSA certificate'
rsa1=`om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
curl \
 --request POST \
 --path /api/v0/certificates/generate \
 --data '{"domains": ["'"*.$lb.xip.io"'"]}'`
cert1=`echo $rsa1 | jq .certificate | tr -d '"'`
key1=`echo $rsa1 | jq .key | tr -d '"'`

echo '---> internal_mysql and service provider credentials'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
configure-product \
 --product-name cf \
 --product-properties '{
        ".properties.uaa_database": {
          "value": "internal_mysql"
        },
        ".uaa.service_provider_key_credentials": {
          "value": {
            "cert_pem": "'"$cert1"'",
            "private_key_pem": "'"$key1"'"
          }
        }
      }'

echo '<Internal MySQL>'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
configure-product \
 --product-name cf \
 --product-properties '{
        ".mysql_monitor.recipient_email": {
          "value": "v-lii@microsoft.com"
        }
      }'

echo '<Errands>'
echo '---> list current errands'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
errands \
 --product-name cf 

echo '---> set errands'
errands=("push-apps-manager" "notifications" "notifications-ui" "push-pivotal-account" "autoscaling" "autoscaling-register-broker" "nfsbrokerpush")
for errand in ${errands[*]}
do
  echo "disable $errand"
  om \
  --target $opsmanurl \
  --username $username \
  --password $password \
  -k \
  set-errand-state \
   --product-name cf \
   --errand-name $errand \
   --post-deploy-state disabled
done

echo '<Resource Config>'
om \
--target $opsmanurl \
--username $username \
--password $password \
-k \
configure-product \
 --product-name cf \
 --product-resources '{
  "consul_server": {
    "instances": 1,
    "internet_connected": false
  },
  "nats": {
    "instances": 1,
    "internet_connected": false
  },
  "etcd_tls_server": {
    "instances": 1,
    "internet_connected": false
  },
  "nfs_server": {
    "instances": 1,
    "internet_connected": false
  },
  "mysql_proxy": {
    "instances": 1,
    "internet_connected": false
  },
  "mysql": {
    "instances": 1,
    "internet_connected": false
  },
  "diego_database": {
    "instances": 1,
    "internet_connected": false
  },
  "uaa": {
    "instances": 1,
    "internet_connected": false
  },
  "cloud_controller": {
    "instances": 1,
    "internet_connected": false
  },
  "router": {
    "instances": 1,
    "internet_connected": false,
    "elb_names": ["pcf-lb"]
  },
  "mysql_monitor": {
    "instances": 1,
    "internet_connected": false
  },
  "clock_global": {
    "instances": 1,
    "internet_connected": false
  },
  "cloud_controller_worker": {
    "instances": 1,
    "internet_connected": false
  },
  "diego_brain": {
    "instances": 1,
    "internet_connected": false
  },
  "diego_cell": {
    "instances": 1,
    "internet_connected": false
  },
  "loggregator_trafficcontroller": {
    "instances": 1,
    "internet_connected": false
  },
  "syslog_adapter": {
    "instances": 1,
    "internet_connected": false
  },
  "syslog_scheduler": {
    "instances": 1,
    "internet_connected": false
  },
  "doppler": {
    "instances": 1,
    "internet_connected": false
  },
  "smoke-tests": {
    "internet_connected": false
  }
}'

echo '<Stemcell>'
check=`curl "$opsmanurl/products/$cf_guid/stemcells/edit" \
    -k \
    -X GET \
    -H "Authorization: Bearer $uaa_token" | grep 'Go to Pivotal Network and download Stemcell'`

if [ "$check" == "" ]
then
  echo 'stemcell is ready'
else
  echo $check
  stemcell_ver=echo $check | awk 'NF=NF-1{print $NF}'
  echo 'stemcell is not ready, will download it automatically'
  python3 download_releases.py stemcell $stemcell_ver $token
  echo 'upload stemcell'
  stemcell_file_name=`ls bosh-stemcell*.tgz`
  om \
  --target $opsmanurl \
  --username $username \
  --password $password \
  -k \
      upload-stemcell \
      --stemcell $stemcell_file_name
fi

echo '############################# fetch manifest'
om \
 --target $opsmanurl \
 --username $username \
 --password $password \
 -k \
 curl \
   --path "/api/v0/staged/products/$cf_guid/manifest" > pcf-on-azure.json

./json2yaml.py pcf-on-azure.json
