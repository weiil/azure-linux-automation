#!/bin/bash

# install jq 
sudo apt-get install -y jq

# global 
export TENANT_ID = `cat $1 | jq .tenantId | tr -d '"'`
export CLIENT_ID = `cat $1 | jq .clientId | tr -d '"'`
export CLIENT_SECRET = `cat $1 | jq .clientSecret | tr -d '"'`
export PUBLIC_KEY = `cat $1 | jq .sshKey | tr -d '"'`
export RESOURCE_GROUP=`cat $1 | jq .resourceGroup | tr -d '"'`
export LOCATION=`cat $1 | jq .location | tr -d '"'`
export STORAGE_NAME=`cat $1 | jq .boshStorage | tr -d '"'`
export OPSMAN_VER=`cat $1 | jq .opsmanVersion | tr -d '"'`

# login
echo 'Login'
azure config mode arm
azure login --username $CLIENT_ID --password $CLIENT_SECRET --service-principal --tenant $TENANT_ID --environment AzureCloud

# create resource group for PCF
echo 'Create resource group:'
azure group create $RESOURCE_GROUP $LOCATION

# create storage account
echo 'Create BOSH storage account'
azure provider register Microsoft.Storage
azure storage account create -l $LOCATION -g $RESOURCE_GROUP --sku-name LRS --kind Storage $STORAGE_NAME

# get connection string of storage account
export CONNECTION_STRING=`azure storage account connectionstring show $STORAGE_NAME --resource-group $RESOURCE_GROUP | grep -i data | awk {'print $3'}`

# create containers
echo 'Create containers for BOSH storage account'
azure storage container create opsman-image --connection-string "'$CONNECTION_STRING'"
azure storage container create vhds --connection-string "'$CONNECTION_STRING'"
azure storage container create opsmanager --connection-string "'$CONNECTION_STRING'"
azure storage container create bosh --connection-string "'$CONNECTION_STRING'"
azure storage container create stemcell --permission blob --connection-string "'$CONNECTION_STRING'"
azure storage table create stemcells --connection-string "'$CONNECTION_STRING'"

# copy image
echo 'Copy image of opsman'
image_url="https://opsmanager${LOCATION}.blob.core.windows.net/images/ops-manager-${OPSMAN_VER}.vhd"
export OPS_MAN_IMAGE_URL="$image_url"
azure storage blob copy start $OPS_MAN_IMAGE_URL opsmanager --dest-connection-string $CONNECTION_STRING --dest-container opsman-image --dest-blob image.vhd

# check copy progressing
echo 'Checking copy progressing'
copy_status=`azure storage blob copy show opsman-image image.vhd --connection-string $CONNECTION_STRING --json | jq .copy.status`
while [ $copy_status != '"success"' ]
do
echo 'check after 2 seconds'
sleep 2
copy_status=`azure storage blob copy show opsman-image image.vhd --connection-string $CONNECTION_STRING --json | jq .copy.status`
done


# clone arm tempaltes of pcf on azure 
echo 'Install git'
apt-get install -y git
echo 'Clone arm template'
git clone https://github.com/pivotal-cf/pcf-azure-arm-templates.git
cd pcf-azure-arm-templates/
# chagne parameters
echo 'Change deploy parameters'
sed -i "s/YOUR-STORAGE-ACCOUNT-NAME/${STORAGE_NAME}/g;s/YOUR-RSA-PUBLIC-KEY/${PUBLIC_KEY}/g;s/YOUR-TENANT-ID/${TENANT_ID}/g;s/YOUR-CLIENT-ID/${CLIENT_ID}/g;s/OPS-MAN-LOCATION/${LOCATION}/g" azure-deploy-parameters.json
# start the deployment
echo 'Start to deploy'
output=`azure group deployment create -f azure-deploy.json -e azure-deploy-parameters.json -v $RESOURCE_GROUP cfdeploy`

opsman_fqdn=`echo $output | grep 'opsMan-FQDN' | awk {'print $4'}`
storage_prefix=`echo $output | grep 'extra Storage Account Prefix' | awk {'print $7'}`
result=`echo $output | grep 'group deployment create command OK' | wc -l | tr -d '\n'`
if [ $result -eq 1 ]; then
    echo 'deployment is success'
else 
    echo 'deployment is fail'
fi

# save connection strings for storages, create bosh and stemcell containers for each storage
echo 'Create bosh and stemcell containers for each storage'
for i in {1,2,3,4,5}
do
connection_string=`azure storage account connectionstring show $storage_prefix$i --resource-group $RESOURCE_GROUP | grep data | awk {'print $3'}`
azure storage container create bosh --connection-string "'$connection_string'"
azure storage container create stemcell --connection-string "'$connection_string'"
done

# create network security group and rules
echo 'Create NSG'
azure network nsg create $RESOURCE_GROUP pcf-nsg $LOCATION
azure network nsg rule create $RESOURCE_GROUP pcf-nsg internet-to-lb --protocol Tcp --priority 100 --destination-port-range '*'

echo 'End'