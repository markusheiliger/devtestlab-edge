# Service Fabric Cluster (Windows/Linux) Environment

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmarkusheiliger%2Fdevtestlab-edge%2Fmaster%2Fenvironments%2FServiceFabric-LabCluster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

This environment template supports to operation modes:

* **Windows** - This mode allows you to deploy a secure 5 node, Single Node Type Service Fabric Cluster running Windows Server 2016 Datacenter on a Standard_D2 Size VMSS with Azure Diagnostics turned on.
* **Linux** - This mode allows you to deploy a secure 5 node, Single Node Type Service fabric Cluster running Ubuntu 16.04 on Standard_D2 Size VMs with Windows Azure diagnostics turned on.

To create the required certificate information for a Service Fabric Secure Cluster please use the following Powershell script [link](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/ServiceFabric-LabCluster/Create-ClusterCertificate.ps1).