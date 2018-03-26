#!/bin/sh

# $1 = aritfactory admin password
# $2 = database username
# $3 = database password
# $4 = database url

echo "### Installing openjdk 1.8.0 ..." >&2
sudo yum install -y java-1.8.0-openjdk
echo "JAVA_HOME=\"$(find /usr/lib/jvm -type f -name java | sed -r 's|/[^/]+$||' | sed -r 's|/[^/]+$||')/\"" | sudo tee --append /etc/environment > /dev/null

echo "### Installing artifactory ..." >&2
wget https://bintray.com/jfrog/artifactory-rpms/rpm -O bintray-jfrog-artifactory-rpms.repo
sudo mv bintray-jfrog-artifactory-rpms.repo /etc/yum.repos.d/
sudo yum install -y jfrog-artifactory-oss

echo "### Creating artifactory app folder ..." >&2
sudo mkdir /opt/app
sudo ln -s /etc/opt/jfrog/artifactory/ /opt/app/artifactory

echo "### Installing JDBC driver for MySQL ..." >&2
sudo wget -nv --timeout=30 -O /opt/jfrog/artifactory/tomcat/lib/mysql-connector-java-5.1.24.jar http://repo.jfrog.org/artifactory/remote-repos/mysql/mysql-connector-java/5.1.24/mysql-connector-java-5.1.24.jar 2>&1

echo "### Configure JDBC driver ..." >&2
sudo tee -a /etc/opt/jfrog/artifactory/storage.properties << END
type=mysql
driver=com.mysql.jdbc.Driver
url=$4
username=$2
password=$3
END

echo "### Open firewall port 8081 and reload ..." >&2
sudo firewall-cmd --zone=public --add-port=8081/tcp --permanent
sudo firewall-cmd --reload

echo "### Starting artifactory as service ..." >&2
sudo service artifactory start

echo "### Waiting for artifactory to become available ..." >&2
until $(curl --output /dev/null --silent --head --fail http://localhost:8081); do
    printf '.'
    sleep 5
done

echo "### Changing default admin password ..." >&2
curl -sX POST -u admin:password -H "Content-type: application/json" -d '{ "userName" : "admin", "oldPassword" : "password", "newPassword1" : "$1", "newPassword2" : "$1" }' http://localhost:8081/artifactory/api/security/users/authorization/changePassword

