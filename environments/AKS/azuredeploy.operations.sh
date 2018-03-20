#!/bin/sh

# $1 = Service Principal Client Id
# $2 = Service Principal Client Secret
# $3 = Tenant Id
# $4 = Cluster Name
# $5 = Cluster RG Name
# $6 = Cluster Owner

echo "### Provisioning as $(whoami)"

AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
     sudo tee /etc/apt/sources.list.d/azure-cli.list

echo "### Registering Azure package repo and installing Azure CLI"
sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893

sudo apt-get install -y apt-transport-https
sudo apt-get update -y

sudo apt-get install -y azure-cli
sudo apt-get update -y

echo "### Using service principal $1 to login Azure CLI ..."
sudo az login --service-principal -u $1 -p $2 -t $3 

echo "### Installing kubectl using Azure CLI ..."
sudo az aks install-cli 

echo "### Getting credentials for kubectl ..."
sudo az aks get-credentials -g $5 -n $4 -a 

echo "### Installing helm ..."
sudo curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash

echo "### Initializing helm"
sudo helm init

echo "### Creating startup script to prepare kubectl config ..."
sudo tee -a /etc/profile.d/copy-kubectl-config.sh << END
ME="\$(whoami)"
if [ ! -d "~/.kube" ]; then
    sudo cp -R /root/.kube /home/\$ME/
    helm init --client-only
fi
END

echo "### Enable execution on startup script ..."
sudo chmod +x /etc/profile.d/copy-kubectl-config.sh
