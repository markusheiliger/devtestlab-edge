# Azure DevTest Lab - EDGE <img src="https://mseng.visualstudio.com/_apis/public/build/definitions/7bfebc51-9907-4838-b87b-d6d0f62f72fa/5869/badge" style="display:block;align:right;"/>

This repository contains DevTest Lab artifact and environment definitions in an **experimental** state.  

You can create a preconfigured lab hooked up with this repository with the "Deploy to Azure" button below.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmarkusheiliger%2Fdevtestlab-edge%2Fmaster%2Ffactory%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

## Artifacts

* [Windows - Minikube](https://github.com/markusheiliger/devtestlab-edge/blob/master/artifacts/windows-minikube/README.md)

## Environments

* [ACS - DCOS/Swarm](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/ACS-DCOSSwarm/README.md)
* [ACS - Kubernetes](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/ACS-Kubernetes/README.md)
* [AKS - Kubernetes](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/AKS/README.md)
* [HPCPack 2016](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/HPCPack-2016/README.md)
* [ServiceFabric - LabCluster](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/ServiceFabric-LabCluster/README.md)
* [SonarQube - Linux](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/SonarQube-Linux/README.md)
* [SharePoint 2013 - Farm](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/SP2013-Farm/README.md)
* [VSTS - BuildRig](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/VSTS-BuildRig/README.md)
* [WebApp - Windows](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/WebApp-Windows/README.md)

For a more "playground" like environment experience please use the following environment definition: 

* [Playground](https://github.com/markusheiliger/devtestlab-edge/blob/master/environments/Playground/README.md)

## Registration

To register this repository directly in your Azure DevTest Lab instance - please follow these steps:
1) Goto your DevTest Lab instance and click on "Configuration and policies"<img src="https://github.com/markusheiliger/devtestlab-edge/raw/master/images/dtl-ConfigurationAndPolicies.PNG" width="500" style="display:block;"/>

2) Select "Repositories" on the left side's menu and click "Add" on the top menu<img src="https://github.com/markusheiliger/devtestlab-edge/raw/master/images/dtl-RepositoriesAdd.PNG" width="500" style="display:block;"/>

3) Fill the "Add Repository" form fields ([GitHub - Creating a personal access token](https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/))<img src="https://github.com/markusheiliger/devtestlab-edge/raw/master/images/dtl-AddRepository.PNG" width="500" style="display:block;"/>

---

*Copyright (c) 2017 Markus Heiliger - [MIT License](https://github.com/markusheiliger/devtestlab-edge/blob/master/LICENSE)*


