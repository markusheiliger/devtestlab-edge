#!/bin/sh

# $1 = new aritfactory admin password

sudo yum install -y java-1.8.0-openjdk
echo "JAVA_HOME=\"$(find /usr/lib/jvm -type f -name java | sed -r 's|/[^/]+$||' | sed -r 's|/[^/]+$||')/\"" | sudo tee --append /etc/environment > /dev/null

wget https://bintray.com/jfrog/artifactory-rpms/rpm -O bintray-jfrog-artifactory-rpms.repo
sudo mv bintray-jfrog-artifactory-rpms.repo /etc/yum.repos.d/
sudo yum install -y jfrog-artifactory-oss

sudo mkdir /opt/app
sudo ln -s /etc/opt/jfrog/artifactory/ /opt/app/artifactory

sudo service artifactory start

sudo firewall-cmd  --zone=public --add-port=8081/tcp --permanent
sudo firewall-cmd --reload

curl -sX POST -u admin:password -H "Content-type: application/json" -d '{ "userName" : "admin", "oldPassword" : "password", "newPassword1" : "$1", "newPassword2" : "$1" }' http://localhost:8081/artifactory/api/security/users/authorization/changePassword > /dev/null
