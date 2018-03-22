#!/bin/sh

# $1 = Service Principal Client Id
# $2 = Service Principal Client Secret
# $3 = Tenant Id
# $4 = Cluster Name
# $5 = Cluster RG Name
# $6 = Cluster Owner

echo "### Provisioning as $(whoami)" >&2

export DEBIAN_FRONTEND=noninteractive

echo "### Registering additional package repositories ..." >&2
AZ_REPO=$(lsb_release -cs)

echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
     sudo tee /etc/apt/sources.list.d/azure-cli.list

sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893
sudo apt-get update

echo "### Installing packages ..." >&2
sudo apt-get install -y apt-transport-https
sudo apt-get install -y azure-cli
sudo apt-get update

echo "### Using service principal $1 to login Azure CLI ..." >&2
sudo az login --service-principal -u "$1" -p "$2" --tenant "$3" 

echo "### Installing kubectl using Azure CLI ..." >&2
sudo az aks install-cli 

echo "### Getting credentials for kubectl ..." >&2
sudo az aks get-credentials -g "$5" -n "$4" -a 

echo "### Installing helm ..." >&2
sudo rm -f azuredeploy.operations.helm.sh
sudo curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > azuredeploy.operations.helm.sh
sudo chmod 700 azuredeploy.operations.helm.sh
sudo sh azuredeploy.operations.helm.sh

echo "### Initializing helm ..." >&2
sudo helm init

echo "### Creating startup script to prepare kubectl config ..." >&2
sudo tee -a /etc/profile.d/copy-kubectl-config.sh << END
ME="\$(whoami)"
if [ ! -d "/home/\$ME/.kube" ]; then
    sudo cp -R /root/.kube /home/\$ME/
fi
if [ ! -d "/home/\$ME/.helm" ]; then
    helm init --client-only
fi
ps cax | grep kubectl > /dev/null
if [ \$? -eq 0 ]; then
  echo "Already serving on 127.0.0.1:8001"
else
  kubectl proxy &
fi
END

echo "### Enable execution on startup script ..." >&2
sudo chmod +x /etc/profile.d/copy-kubectl-config.sh

echo "### Fetching information to peer networks ..." >&2
CLUSTERLOCATION=$(az resource show -g $5 -n $4 --resource-type "Microsoft.ContainerService/ManagedClusters" --query location --output tsv)
CLUSTERRGNAME="MC_$5_$4_$CLUSTERLOCATION"
CLUSTERVNETID=$(az resource list -g $CLUSTERRGNAME --resource-type "Microsoft.Network/virtualNetworks" --query '[0].id' --output tsv)
CLUSTERVNETNAME=$(az resource list -g $CLUSTERRGNAME --resource-type "Microsoft.Network/virtualNetworks" --query '[0].name' --output tsv)
OPERATIONSVNETID=$(az resource list -g $5 --resource-type "Microsoft.Network/virtualNetworks" --query '[0].id' --output tsv)
OPERATIONSVNETNAME=$(az resource list -g $5 --resource-type "Microsoft.Network/virtualNetworks" --query '[0].name' --output tsv)

echo "### Peer cluster and operations vnet ..." >&2
az network vnet peering create --name LinkClusterToOperations --resource-group $CLUSTERRGNAME --vnet-name $CLUSTERVNETNAME --remote-vnet-id $OPERATIONSVNETID
az network vnet peering create --name LinkOperationsToCluster --resource-group $5 --vnet-name $OPERATIONSVNETNAME --remote-vnet-id $CLUSTERVNETID --allow-vnet-access

