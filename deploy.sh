#!/bin/bash 

export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-proxy}
export STACK_NAME=${STACK_NAME:-$APP_NAME}
printf -v now "%(%s)T" -1
export CFG_PREFIX=$STACK_NAME-$now
export TC_HTB_RATE=${TC_HTB_RATE:-50Mbit}

cd $WORKSPACE || exit $?

echo "building multiarch images with buildx"
buildx_name=${BUILDX_NAME:-builder}
docker buildx use $buildx_name || \
docker buildx create \
    --use \
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

echo "stack deploy $STACK_NAME, using $DOCKER_REPOSITORY"
docker stack deploy \
    -c $WORKSPACE/proxy.yml \
    --with-registry-auth \
    --detach=false \
    $STACK_NAME
