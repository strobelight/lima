#!/bin/bash

INSTANCE_NAME=k3smulti
YAML=./docker-k3s-multiarch.yaml

# start lima from desired yaml file
# check for disks and create them first with limactl disk create blah --size blah
DISK_NAME=docker
DISK_PRESENT=$(limactl disk ls 2>/dev/null| grep $DISK_NAME)
if [ -z "$DISK_PRESENT" ]; then
    limactl disk create $DISK_NAME --size 10G
fi
limactl start --name $INSTANCE_NAME --tty=false $YAML

echo "Performing above steps ..."
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

echo "Setting up a local registry"
# set up registry
DOCKER_STORAGE=$HOME/Docker-Storage
mkdir -p $DOCKER_STORAGE
cat <<EOF > ${DOCKER_STORAGE}/registry_config.yml
version: 0.1
log:
  fields:
    service: registry
storage:
  delete:
    enabled: true
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
    Access-Control-Allow-Origin: ['*']
    Access-Control-Allow-Methods: ['HEAD', 'GET', 'OPTIONS', 'DELETE']
    Access-Control-Allow-Headers: ['Authorization', 'Accept', 'Cache-Control']
    Access-Control-Max-Age: [1728000]
    Access-Control-Expose-Headers: ['Docker-Content-Digest']
EOF
docker run -d --restart=always -p "127.0.0.1:5000:5000" \
    -v ${DOCKER_STORAGE}:/var/lib/registry \
    -v ${DOCKER_STORAGE}/registry_config.yml:/etc/docker/registry/config.yml \
    --name registry registry

docker run -d --restart=always -p "8080:80" -e DELETE_IMAGES=true -e REGISTRY_TITLE="Localhost Registry" -e REGISTRY_URL="http://localhost:5000" -e SINGLE_REGISTRY=true --name registry-ui joxit/docker-registry-ui:latest

cat <<EOF

Local registry available at http://localhost:8080

After delete, run
   docker exec registry registry garbage-collect /etc/docker/registry/config.yml

EOF
