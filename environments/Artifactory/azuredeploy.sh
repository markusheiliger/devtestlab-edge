#!/bin/sh

# $1 = aritfactory admin password
# $2 = database username
# $3 = database password
# $4 = database server
# $5 = database name
# $6 = file storage account
# $7 = file storage key

echo "Import the Microsoft repository key and create repository info ..."  2>&1
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc"  | sudo tee /etc/yum.repos.d/azure-cli.repo
sudo curl -s https://packages.microsoft.com/config/rhel/7/prod.repo > /etc/yum.repos.d/msprod.repo

echo "### Installing packages ..." 2>&1
sudo ACCEPT_EULA=Y yum install -y java-1.8.0-openjdk samba-client samba-common cifs-utils azure-cli mssql-tools unixODBC-devel

echo "### Login Azure CLI ..." 2>&1
sudo az login --msi

echo "### Preparing openjdk 1.8.0 - set JAVA_HOME ..." 2>&1
echo "JAVA_HOME=\"$(find /usr/lib/jvm -type f -name java | sed -r 's|/[^/]+$||' | sed -r 's|/[^/]+$||')/\"" | sudo tee --append /etc/environment > /dev/null

echo "### Installing artifactory ..." 2>&1
wget https://bintray.com/jfrog/artifactory-rpms/rpm -O bintray-jfrog-artifactory-rpms.repo
sudo mv bintray-jfrog-artifactory-rpms.repo /etc/yum.repos.d/
sudo yum install -y jfrog-artifactory-oss

echo "### Creating artifactory app folder ..." 2>&1
sudo mkdir /opt/app
sudo ln -s /etc/opt/jfrog/artifactory/ /opt/app/artifactory

SQLCMD_HOME=/opt/mssql-tools/bin
ARTIFACTORY_HOME=/var/opt/jfrog/artifactory
ARTIFACTORY_USER=artifactory
ARTIFACTORY_PWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
ARTIFACTORY_JDBC_URL=https://download.microsoft.com/download/0/2/A/02AAE597-3865-456C-AE7F-613F99F850A8/sqljdbc_6.0.8112.200_enu.tar.gz
#ARTIFACTORY_JDBC_URL=https://download.microsoft.com/download/F/0/F/F0FF3F95-D42A-46AF-B0F9-8887987A2C4B/sqljdbc_4.2.8112.200_enu.tar.gz

echo "### Configure storage ..." 2>&1
sudo az storage share create --name filestore --connection-string "DefaultEndpointsProtocol=https;AccountName=$6;AccountKey=$7;EndpointSuffix=core.windows.net"

sudo mkdir /mnt/filestore
echo "//$6.file.core.windows.net/filestore /mnt/filestore cifs nofail,vers=3.0,username=$6,password=$7,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab
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

echo "### Configure database ..." 2>&1
sudo wget -qO- $ARTIFACTORY_JDBC_URL | tar xvz -C $ARTIFACTORY_HOME/etc
sudo cp $ARTIFACTORY_HOME/etc/sqljdbc_*/enu/jre8/sqljdbc*.jar $ARTIFACTORY_HOME/tomcat/lib/

sudo tee $ARTIFACTORY_HOME/etc/db.properties << END
type=mssql
driver=com.microsoft.sqlserver.jdbc.SQLServerDriver
url=jdbc:sqlserver://$4.database.windows.net:1433;database=$5;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;sendStringParametersAsUnicode=false;
username=$ARTIFACTORY_USER
password=$ARTIFACTORY_PWD
END

echo "### Grant database access ..." 2>&1
$SQLCMD_HOME/sqlcmd -S tcp:$4.database.windows.net,1433 -d master -U $2 -P $3 -Q "CREATE LOGIN $ARTIFACTORY_USER WITH PASSWORD='$ARTIFACTORY_PWD';"
$SQLCMD_HOME/sqlcmd -S tcp:$4.database.windows.net,1433 -d $5 -U $2 -P $3     -Q "CREATE USER $ARTIFACTORY_USER FROM LOGIN $ARTIFACTORY_USER; exec sp_addrolemember 'db_owner', '$5';"

echo "### Starting artifactory as service ..." 2>&1
sudo service artifactory start
sleep 30

echo "### Waiting for artifactory to become available ..." 2>&1
while $(curl -s http://localhost:8081/artifactory | grep -q "Starting Up"); do
    printf '.'
    sleep 5
done

echo "### Changing default admin password ..." 2>&1
sudo curl -sX POST -u admin:password -H "Content-type: application/json" -d "{ \"userName\" : \"admin\", \"oldPassword\" : \"password\", \"newPassword1\" : \"$1\", \"newPassword2\" : \"$1\" }" http://localhost:8081/artifactory/api/security/users/authorization/changePassword

echo "### Open firewall port 8081 and reload ..." 2>&1
sudo firewall-cmd --zone=public --add-port=8081/tcp --permanent
sudo firewall-cmd --reload

