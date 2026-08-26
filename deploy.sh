#!/bin/bash 

export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-proxy}
export STACK_NAME=${STACK_NAME:-proxy}
export TC_HTB_RATE=${TC_HTB_RATE:-50Mbit}
export DOCKER_IMAGE=${DOCKER_IMAGE:-local/network/proxy:latest}
export IPV6_SUBNET=${IPV6_SUBNET?Need IPV6_SUBNET (e.g. 2a02:a03f:8789:e700:c::/120)}
export IPV6_GATEWAY=${IPV6_GATEWAY?Need IPV6_GATEWAY (e.g. 2a02:a03f:8789:e700:c::1)}

cd $WORKSPACE || exit $?

echo "using: $APP_NAME, rate=${TC_HTB_RATE}"

echo "building images with buildx bake"
docker buildx bake -f docker-bake.hcl local || exit $?

echo "starting with docker compose"
APP_NAME=$APP_NAME TC_HTB_RATE=$TC_HTB_RATE DOCKER_IMAGE=$DOCKER_IMAGE IPV6_SUBNET=$IPV6_SUBNET IPV6_GATEWAY=$IPV6_GATEWAY docker compose up -d
