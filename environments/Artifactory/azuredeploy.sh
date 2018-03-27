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

echo "### Installing packages ..." 2>&1
sudo yum install -y java-1.8.0-openjdk samba-client samba-common cifs-utils azure-cli mysql

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

ARTIFACTORY_HOME=/var/opt/jfrog/artifactory
ARTIFACTORY_USER=artifactory
ARTIFACTORY_PWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

echo "### Configure storage ..." 2>&1
sudo az storage container create --name artifactory --connection-string "DefaultEndpointsProtocol=https;AccountName=$6;AccountKey=$7;EndpointSuffix=core.windows.net"
sudo tee $ARTIFACTORY_HOME/etc/binarystore.xml << END
<config version="1">
    <chain template="azure-blob-storage"/>
    <provider id="azure-blob-storage" type="azure-blob-storage">
        <accountName>$6</accountName>
        <accountKey>$7</accountKey>
        <endpoint>https://$6.blob.core.windows.net/</endpoint>
        <containerName>artifactory</containerName>
    </provider>
</config>
END

#echo "### Prepare MySQL SSL support ..." 2>&1
#sudo curl https://www.digicert.com/CACerts/BaltimoreCyberTrustRoot.crt.pem --output $ARTIFACTORY_HOME/etc/BaltimoreCyberTrustRoot.pem

#mysql  --ssl-ca=$ARTIFACTORY_HOME/etc/BaltimoreCyberTrustRoot.pem -h "$4.mysql.database.azure.com" -u "$2@$4" -p$3 -D $5 \
#        -e "GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP,ALTER,INDEX on artifactory.* TO 'artifactory'@'$ARTIFACTORY_PWD' IDENTIFIED BY '$';"

#echo "### Installing JDBC driver for MySQL ..." 2>&1
#sudo wget -nv --timeout=30 -O /opt/jfrog/artifactory/tomcat/lib/mysql-connector-java-5.1.24.jar http://repo.jfrog.org/artifactory/remote-repos/mysql/mysql-connector-java/5.1.24/mysql-connector-java-5.1.24.jar 2>&1

#echo "### Configure JDBC driver ..." 2>&1
#sudo tee $ARTIFACTORY_HOME/etc/storage.properties << END
#type=mysql
#driver=com.mysql.jdbc.Driver
#url=mysql://$4.mysql.database.azure.com/$5?characterEncoding=UTF-8&elideSetAutoCommits=true
#username=$ARTIFACTORY_USER
#password=$ARTIFACTORY_PWD
#END

#echo "### Mounting file share ..." 2>&1
#sudo az login --msi
#sudo az storage share create --name files --connection-string "DefaultEndpointsProtocol=https;AccountName=$6;AccountKey=$7;EndpointSuffix=core.windows.net"
#sudo mkdir /mnt/AzureFileShare
#echo "//$6.file.core.windows.net/files /mnt/AzureFileShare cifs nofail,vers=3.0,username=$6,password=$7,dir_mode=0777,file_mode=0777,serverino" | sudo tee -a /etc/fstab
#sudo mount --all

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

