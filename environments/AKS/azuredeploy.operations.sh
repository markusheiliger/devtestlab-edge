#!/bin/sh

# $1 = Service Principal Client Id
# $2 = Service Principal Client Secret
# $3 = Tenant Id
# $4 = Cluster Name
# $5 = Cluster RG Name

AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
     sudo tee /etc/apt/sources.list.d/azure-cli.list

sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893
sudo apt-get install apt-transport-https
sudo apt-get update && sudo apt-get install azure-cli

sudo az login --service-principal -u $1 -p $2 -t $3

sudo az aks install-cli
sudo az aks get-credentials --resource-group $5 --name $4

