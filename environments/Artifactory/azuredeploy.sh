#!/bin/sh

# $1 = aritfactory admin password
# $2 = database username
# $3 = database password
# $4 = database server
# $5 = database name

echo "### Installing openjdk 1.8.0 ..." 2>&1
sudo yum install -y java-1.8.0-openjdk
echo "JAVA_HOME=\"$(find /usr/lib/jvm -type f -name java | sed -r 's|/[^/]+$||' | sed -r 's|/[^/]+$||')/\"" | sudo tee --append /etc/environment > /dev/null

echo "### Installing artifactory ..." 2>&1
wget https://bintray.com/jfrog/artifactory-rpms/rpm -O bintray-jfrog-artifactory-rpms.repo
sudo mv bintray-jfrog-artifactory-rpms.repo /etc/yum.repos.d/
sudo yum install -y jfrog-artifactory-oss

echo "### Creating artifactory app folder ..." 2>&1
sudo mkdir /opt/app
sudo ln -s /etc/opt/jfrog/artifactory/ /opt/app/artifactory

echo "### Installing JDBC driver for MySQL ..." 2>&1
sudo wget -nv --timeout=30 -O /opt/jfrog/artifactory/tomcat/lib/mysql-connector-java-5.1.24.jar http://repo.jfrog.org/artifactory/remote-repos/mysql/mysql-connector-java/5.1.24/mysql-connector-java-5.1.24.jar 2>&1

echo "### Configure JDBC driver ..." 2>&1
sudo tee -a /etc/opt/jfrog/artifactory/storage.properties << END
type=mysql
driver=com.mysql.jdbc.Driver
url=mysql://$4.mysql.database.azure.com/$5?characterEncoding=UTF-8&elideSetAutoCommits=true
username=$2
password=$3
END

echo "### Starting artifactory as service ..." 2>&1
sudo service artifactory start
sleep 30

echo "### Waiting for artifactory to become available ..." 2>&1
while $(curl -s http://localhost:8081/artifactory | grep -q "Starting Up"); do
    printf '.'
    sleep 5
done

echo "### Changing default admin password ..." 2>&1
sudo curl -sX POST -u admin:password -H "Content-type: application/json" -d '{ "userName" : "admin", "oldPassword" : "password", "newPassword1" : "$1", "newPassword2" : "$1" }' http://localhost:8081/artifactory/api/security/users/authorization/changePassword

echo "### Open firewall port 8081 and reload ..." 2>&1
sudo firewall-cmd --zone=public --add-port=8081/tcp --permanent
sudo firewall-cmd --reload
