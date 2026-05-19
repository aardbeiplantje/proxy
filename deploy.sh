#!/bin/bash 

export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-proxy}
export STACK_NAME=${STACK_NAME:-$APP_NAME}
printf -v now "%(%s)T" -1
export CFG_PREFIX=$STACK_NAME-$now
export TC_HTB_RATE=${TC_HTB_RATE:-50Mbit}
ipv6_prefix=${APP_IPV6_PREFIX?Need APP_IPV6_PREFIX}
export IPV6=${IPV6?Need IPV6}

cd $WORKSPACE || exit $?

echo "building multiarch images with buildx"
buildx_name=${BUILDX_NAME:-builder}
docker buildx use $buildx_name || \
docker buildx create \
    --use \
    --network host \
    --name $buildx_name \
    --platform linux/amd64,linux/arm64,linux/aarch64 \
    --driver docker-container \
    --driver-opt image=moby/buildkit:master \
    --driver-opt network=host

echo "checking for docker registry auth"
if [   -z "$DOCKER_REGISTRY" \
    -o -z "$DOCKER_REGISTRY_USER" \
    -o -z "$DOCKER_REGISTRY_PASS" ]; then
    echo "no docker registry login info, using local registry"
    export DOCKER_REGISTRY=local
    export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-${DOCKER_REGISTRY}/proxy}
else
    echo "using docker registry login info"
    export DOCKER_REGISTRY
    export DOCKER_REGISTRY_USER
    export DOCKER_REGISTRY_PASS
    printenv DOCKER_REGISTRY_PASS \
        |docker login \
            -u ${DOCKER_REGISTRY_USER?Need a DOCKER_REGISTRY_USER} \
            --password-stdin \
            ${DOCKER_REGISTRY?Need a DOCKER_REGISTRY}
    export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-${DOCKER_REGISTRY}/proxy}
fi

echo "building images with buildx bake, using $DOCKER_REPOSITORY"
docker buildx bake -f docker-bake.hcl || exit $?

echo "running sysctl for proxy_ndp and add $IPV6 as neighbour"
APP_IF_NAME=${APP_IF_NAME:-eno1}
sudo sh -x -c "ip -6 neigh add proxy $IPV6 dev $APP_IF_NAME; \
    sysctl net.ipv6.conf.default.proxy_ndp=1; \
    sysctl net.ipv6.conf.all.proxy_ndp=1; \
    ip6tables -D DOCKER -s ::/0 -d $IPV6 -p tcp --dport 8080 -j ACCEPT; \
    ip6tables -I DOCKER -s ::/0 -d $IPV6 -p tcp --dport 8080 -j ACCEPT"

echo "creating network $nw_name with prefix $ipv6_prefix"
if_name=${BRIDGE_IF_NAME:-dmz-${STACK_NAME}0}
nw_name=dmz-$STACK_NAME
docker stack rm $STACK_NAME
sleep 3
docker network rm $nw_name || true
sleep 3
docker network create \
    $nw_name \
    --ipv6 \
    --ipv4 \
    --attachable \
    --scope=swarm \
    --subnet=$ipv6_prefix \
    --driver=bridge \
    -o com.docker.network.bridge.name=$if_name \
    -o com.docker.network.container_iface_prefix=dmz \
    -o com.docker.network.bridge.gateway_mode_ipv6=routed \
    -o com.docker.network.bridge.enable_icc=true \
    -o com.docker.network.bridge.enable_ip_masquerade=false \
    -o com.docker.network.bridge.enable_ip6_masquerade=false \
    -o com.docker.network.enable_ipv6=true \
    -o com.docker.network.bridge.inhibit_ipv4=true \
    -o com.docker.network.driver.mtu=1500 \
    --ipam-driver default \
    || exit $?

echo "stack deploy $STACK_NAME, using $DOCKER_REPOSITORY"
docker stack deploy \
    -c $WORKSPACE/proxy.yml \
    --with-registry-auth \
    --detach=false \
    $STACK_NAME
