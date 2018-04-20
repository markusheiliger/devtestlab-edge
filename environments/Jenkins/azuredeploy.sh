#!/bin/bash

# register azure cli package repo
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893

# register jenkins package repo
wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'

# udpate and upgrade packages
sudo apt-get update && sudo apt-get upgrade -y

# install jenkins & nginx
sudo apt-get install -y jenkins nginx

VM_NAME=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/name?api-version=2017-08-01&format=text")
VM_LOCATION=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2017-08-01&format=text")
VM_FQN="$VM_NAME.$VM_LOCATION.cloudapp.azure.com"

SSLKEY_FILE=/etc/nginx/ssl/$VM_FQN.key
SSLCRT_FILE=/etc/nginx/ssl/$VM_FQN.crt

# create self signed certifcate for SSL support
sudo mkdir /etc/nginx/ssl
sudo openssl req -subj "/CN=$VM_FQN/O=unknown/C=US" -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout $SSLKEY_FILE -out $SSLCRT_FILE

# remove nginx default configuration
sudo rm /etc/nginx/sites-available/default
sudo rm /etc/nginx/sites-enabled/default

# create jenkins nginx configuration
sudo tee /etc/nginx/sites-available/$VM_FQN.conf << END
upstream jenkins {
    server 127.0.0.1:8080 fail_timeout=0;
}

server {
    listen 80;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443;
    server_name $VM_FQN;

    ssl on;
    ssl_certificate /etc/nginx/ssl/$VM_FQN.crt;
    ssl_certificate_key /etc/nginx/ssl/$VM_FQN.key;

    location / {
        proxy_set_header        Host \$host;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;
        proxy_redirect          http://$VM_FQN https://$VM_FQN;
        proxy_pass              http://jenkins;

        # Required for new HTTP-based CLI
        proxy_http_version 1.1;
        proxy_request_buffering off;
        proxy_buffering off; # Required for HTTP-based CLI to work over SSL

        # workaround for https://issues.jenkins-ci.org/browse/JENKINS-45651
        add_header 'X-SSH-Endpoint' '$VM_FQN:50022' always;
    }
}
END

# enable jenkins configuration in nginx and restart
sudo ln -s /etc/nginx/sites-available/$VM_FQN.conf /etc/nginx/sites-enabled/$VM_FQN.conf
sudo service nginx restart