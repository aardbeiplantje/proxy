#!/bin/bash 

export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export STACK_NAME=${STACK_NAME:-proxy}
export TC_HTB_RATE=${TC_HTB_RATE:-50Mbit}
export DOCKER_IMAGE=${DOCKER_IMAGE:-local/network/proxy:latest}

echo "using: $STACK_NAME, rate=${TC_HTB_RATE}"

echo "building images with buildx bake"
docker buildx bake -f docker-bake.hcl local || exit $?

echo "stack deploy $STACK_NAME, using $DOCKER_IMAGE"
docker stack deploy \
  -c $WORKSPACE/proxy.yml \
  --with-registry-auth \
  --detach=false \
  $STACK_NAME
