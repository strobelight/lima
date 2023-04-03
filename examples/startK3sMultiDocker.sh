#!/bin/bash

INSTANCE_NAME=k3smulti
YAML=~/src/lima/examples/docker-k3s-multiarch.yaml

# start lima from desired yaml file
limactl start --name $INSTANCE_NAME --tty=false $YAML

# copy kubeconfig
mkdir -p ~/.lima/$INSTANCE_NAME/copied-from-guest
limactl shell $INSTANCE_NAME sudo cat /etc/rancher/k3s/k3s.yaml > ~/.lima/$INSTANCE_NAME/copied-from-guest/kubeconfig.yaml

# merge kube config with current one
MY_CONFIG=~/.kube/config
GUEST_CONFIG=/tmp/k3s$$
NEW_CONFIG=/tmp/new$$
limactl shell $INSTANCE_NAME sudo kubectl config view --flatten > $GUEST_CONFIG
sed -i "s/default/$INSTANCE_NAME/g" $GUEST_CONFIG
KUBECONFIG=$MY_CONFIG kubectl config set-context default
KUBECONFIG=$MY_CONFIG kubectl config use-context default
KUBECONFIG=$MY_CONFIG kubectl config delete-user $INSTANCE_NAME
KUBECONFIG=$MY_CONFIG kubectl config delete-context $INSTANCE_NAME
KUBECONFIG=$MY_CONFIG kubectl config delete-cluster $INSTANCE_NAME
KUBECONFIG=$MY_CONFIG:$GUEST_CONFIG kubectl config view --merge --flatten > $NEW_CONFIG
TS=$(stat --format "%y" $MY_CONFIG | sed 's/\..*//;s/ /_/g;s/://g')
mv $MY_CONFIG ${MY_CONFIG}_${TS}
mv $NEW_CONFIG $MY_CONFIG
kubectl config use-context $INSTANCE_NAME
rm -f $GUEST_CONFIG $NEW_CONFIG

# set docker context
docker context create lima-$INSTANCE_NAME --docker "host=unix://${HOME}/.lima/$INSTANCE_NAME/sock/docker.sock"
docker context use lima-$INSTANCE_NAME

# set up registry
mkdir -p ~/Docker-Storage
docker run -d --restart=always -p "127.0.0.1:5001:5000" -v ~/Docker-Storage:/var/lib/registry --name registry registry
