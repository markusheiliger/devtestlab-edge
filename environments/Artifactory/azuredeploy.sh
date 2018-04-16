#!/bin/bash

PARAM_ARTIFACTORY_ADMIN_PASSWORD=${1}
PARAM_DATABASE_ADMIN_USERNAME=${2}
PARAM_DATABASE_ADMIN_PASSWORD=${3}
PARAM_DATABASE_SERVER=${4}
PARAM_DATABASE_NAME=${5}
PARAM_STORAGE_ACCOUNT=${6}
PARAM_STORAGE_KEY=${7}
PARAM_ARTIFACTORY_LIC=${8}
PARAM_CUSTOMDOMAIN_NAME=${9}
PARAM_CUSTOMDOMAIN_SSLCRT=${10}
PARAM_CUSTOMDOMAIN_SSLKEY=${11}

LOCAL_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

echo "### Register Microsoft repository for Ubuntu ..."  >&2
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list

echo "### Register Azure CLI repository for Ubuntu ..."  >&2
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893

if [ -z "$PARAM_ARTIFACTORY_LIC" ]; then
    echo "### Register JFrog OSS repository for Ubuntu ..."  >&2
    echo "deb https://jfrog.bintray.com/artifactory-debs $(lsb_release -cs) main" | sudo tee -a /etc/apt/sources.list
    curl https://bintray.com/user/downloadSubjectPublicKey?username=jfrog | sudo apt-key add -
else
    echo "### Register JFrog PRO repository for Ubuntu ..."  >&2
    echo "deb https://jfrog.bintray.com/artifactory-pro-debs $(lsb_release -cs) main" | sudo tee -a /etc/apt/sources.list
    curl https://bintray.com/user/downloadSubjectPublicKey?username=jfrog | sudo apt-key add -
fi

echo "### Updating & upgrading repositories"
sudo apt-get update && sudo apt-get upgrade -y

echo "### Installing packages ..." >&2
sudo ACCEPT_EULA=Y apt-get install -y apt-transport-https azure-cli openjdk-8-jre cifs-utils mssql-tools unixodbc-dev libssl-dev libffi-dev python-dev build-essential

echo "### Setting JAVA_HOME ..." >&2
echo "JAVA_HOME=\"$(find /usr/lib/jvm -type f -name java | sed -r 's|/[^/]+$||' | sed -r 's|/[^/]+$||')/\"" | sudo tee --append /etc/environment > /dev/null

if [ -z "$PARAM_ARTIFACTORY_LIC" ]; then

    echo "### Installing artifactory OSS ..." >&2
    sudo apt-get install jfrog-artifactory-oss

else

    echo "### Installing artifactory PRO ..." >&2
    sudo apt-get install jfrog-artifactory-pro

    echo "### Installing nginx ..." >&2
    sudo apt-get install -y nginx

    # echo "### Fixing nginx httpd permissions ..." >&2
    # sudo setsebool httpd_can_network_connect on -P
fi


echo "### Creating artifactory app folder ..." >&2
sudo mkdir /opt/app
sudo ln -s /etc/opt/jfrog/artifactory/ /opt/app/artifactory

SQLCMD_HOME=/opt/mssql-tools/bin
ARTIFACTORY_HOME=/var/opt/jfrog/artifactory
ARTIFACTORY_USER=artifactory
ARTIFACTORY_PWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
ARTIFACTORY_JDBC_URL=https://download.microsoft.com/download/0/2/A/02AAE597-3865-456C-AE7F-613F99F850A8/sqljdbc_6.0.8112.200_enu.tar.gz

echo "### Enable unauthenticated artifactory system health check ..." >&2
sudo tee -a $ARTIFACTORY_HOME/etc/artifactory.system.properties << END
## Enable System Health Ping without authentication
artifactory.ping.allowUnauthenticated=true
END

echo "### Configure storage ..." >&2
sudo az storage share create --name filestore --account-name $PARAM_STORAGE_ACCOUNT --account-key $PARAM_STORAGE_KEY

sudo mkdir /mnt/filestore
echo "//$PARAM_STORAGE_ACCOUNT.file.core.windows.net/filestore /mnt/filestore cifs nofail,vers=3.0,username=$PARAM_STORAGE_ACCOUNT,password=$PARAM_STORAGE_KEY,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab
sudo mount --all
    
sudo cp $ARTIFACTORY_HOME/etc/binarystore.xml $ARTIFACTORY_HOME/etc/binarystore.bak
sudo tee $ARTIFACTORY_HOME/etc/binarystore.xml << END
<config version="1">   
    <chain template="file-system"/>
    <provider id="file-system" type="file-system">
        <fileStoreDir>/mnt/filestore</fileStoreDir>
    </provider>
</config>
END

echo "### Configure database ..." >&2
sudo wget -qO- $ARTIFACTORY_JDBC_URL | tar xvz -C $ARTIFACTORY_HOME/etc
sudo cp $ARTIFACTORY_HOME/etc/sqljdbc_*/enu/jre8/sqljdbc*.jar $ARTIFACTORY_HOME/tomcat/lib/

sudo tee $ARTIFACTORY_HOME/etc/db.properties << END
type=mssql
driver=com.microsoft.sqlserver.jdbc.SQLServerDriver
url=jdbc:sqlserver://$PARAM_DATABASE_SERVER.database.windows.net:1433;database=$PARAM_DATABASE_NAME;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;sendStringParametersAsUnicode=false;
username=$ARTIFACTORY_USER
password=$ARTIFACTORY_PWD
END

echo "### Grant database access ..." >&2
$SQLCMD_HOME/sqlcmd -S tcp:$PARAM_DATABASE_SERVER.database.windows.net,1433 -d master -U $PARAM_DATABASE_ADMIN_USERNAME -P $PARAM_DATABASE_ADMIN_PASSWORD -Q "CREATE LOGIN $ARTIFACTORY_USER WITH PASSWORD='$ARTIFACTORY_PWD';"
$SQLCMD_HOME/sqlcmd -S tcp:$PARAM_DATABASE_SERVER.database.windows.net,1433 -d $PARAM_DATABASE_NAME -U $PARAM_DATABASE_ADMIN_USERNAME -P $PARAM_DATABASE_ADMIN_PASSWORD     -Q "CREATE USER $ARTIFACTORY_USER FROM LOGIN $ARTIFACTORY_USER; exec sp_addrolemember 'db_owner', '$PARAM_DATABASE_NAME';"

echo "### Starting artifactory as service ..." >&2
sudo service artifactory start

echo "### Waiting for artifactory to become available ..." >&2
while [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/artifactory/api/system/ping)" -ne "200" ]; do
    echo "--- Sleeping for 5 seconds ..." >&2
    sleep 5
done

if [ ! -z "$PARAM_ARTIFACTORY_LIC" ]; then

    echo "### Updating artifactory license key ..." >&2
    sudo curl -X POST -u admin:password -H "Content-type: application/json" -d "{ \"licenseKey\": \"$PARAM_ARTIFACTORY_LIC\" }" http://localhost:8081/artifactory/api/system/license

    if [ -z "$PARAM_CUSTOMDOMAIN_NAME" ]; then

        VM_NAME=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/name?api-version=2017-08-01&format=text")
        VM_LOCATION=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2017-08-01&format=text")

        PARAM_CUSTOMDOMAIN_NAME="$VM_NAME.$VM_LOCATION.cloudapp.azure.com"
    fi

    PARAM_CUSTOMDOMAIN_SSLKEY_FILE=/etc/nginx/ssl/$PARAM_CUSTOMDOMAIN_NAME.key
    PARAM_CUSTOMDOMAIN_SSLCRT_FILE=/etc/nginx/ssl/$PARAM_CUSTOMDOMAIN_NAME.crt    
    
    echo "### Creating cert files ..." >&2
    sudo mkdir /etc/nginx/ssl
    #if [ "$PARAM_CUSTOMDOMAIN_NAME" == *.cloudapp.azure.com ]; then
    if [[ $PARAM_CUSTOMDOMAIN_NAME =~ \.cloudapp\.azure\.com$ ]]; then
        echo "--- Self signed certificate ..." >&2
        sudo openssl req -subj "/CN=$PARAM_CUSTOMDOMAIN_NAME/O=unknown/C=US" -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout $PARAM_CUSTOMDOMAIN_SSLKEY_FILE -out $PARAM_CUSTOMDOMAIN_SSLCRT_FILE
    else
        echo $PARAM_CUSTOMDOMAIN_SSLKEY | base64 --decode | sudo tee $PARAM_CUSTOMDOMAIN_SSLKEY_FILE
        echo $PARAM_CUSTOMDOMAIN_SSLCRT | base64 --decode | sudo tee $PARAM_CUSTOMDOMAIN_SSLCRT_FILE
    fi

    echo "### Creating site configuration ..." >&2
    sudo curl -sX POST -u admin:password -H "Content-type: application/json" -d "{\"key\":\"nginx\",\"artifactoryAppContext\":\"artifactory\",\"publicAppContext\":\"\",\"serverName\":\"$PARAM_CUSTOMDOMAIN_NAME\",\"artifactoryServerName\":\"localhost\",\"artifactoryPort\":8081,\"dockerReverseProxyMethod\":\"REPOPATHPREFIX\",\"useHttps\":true,\"useHttp\":false,\"httpsPort\":443,\"httpPort\":80,\"upStreamName\":\"artifactory\",\"webServerType\":\"NGINX\",\"sslKey\":\"/etc/nginx/ssl/$PARAM_CUSTOMDOMAIN_NAME.key\",\"sslCertificate\":\"/etc/nginx/ssl/$PARAM_CUSTOMDOMAIN_NAME.crt\"}" http://localhost:8081/artifactory/api/system/configuration/webServer
    sudo curl -sX GET  -u admin:password http://localhost:8081/artifactory/api/system/configuration/reverseProxy/nginx | sudo tee /etc/nginx/sites-available/$PARAM_CUSTOMDOMAIN_NAME.conf

    echo "### Enabling site configuration ..." >&2
    sudo ln -s /etc/nginx/sites-available/$PARAM_CUSTOMDOMAIN_NAME.conf /etc/nginx/sites-enabled/$PARAM_CUSTOMDOMAIN_NAME.conf

    echo "### Disabling SSL settings in global nginx configuration ..."
    sudo sed -i 's/ssl_/# ssl_/g' /etc/nginx/nginx.conf

    echo "### Starting nginx as service ..." >&2
    sudo service nginx restart
else
    echo "### No license key available - skip nginx installation ..." >&2
fi

echo "### Changing default admin password ..." >&2
sudo curl -sX POST -u admin:password -H "Content-type: application/json" -d "{ \"userName\" : \"admin\", \"oldPassword\" : \"password\", \"newPassword1\" : \"$PARAM_ARTIFACTORY_ADMIN_PASSWORD\", \"newPassword2\" : \"$PARAM_ARTIFACTORY_ADMIN_PASSWORD\" }" http://localhost:8081/artifactory/api/security/users/authorization/changePassword

