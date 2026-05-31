#!/bin/bash 

export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-proxy}
export STACK_NAME=${STACK_NAME:-$APP_NAME}
printf -v now "%(%s)T" -1
export CFG_PREFIX=$STACK_NAME-$now
export TC_HTB_RATE=${TC_HTB_RATE:-50Mbit}
export DOCKER_IMAGE=${DOCKER_IMAGE:-proxy:latest}

cd $WORKSPACE || exit $?

echo "using: $APP_NAME / $STACK_NAME, rate=${TC_HTB_RATE}"

echo "building images with buildx bake"
docker buildx bake -f docker-bake.hcl local || exit $?

echo "stack deploy $STACK_NAME, using $DOCKER_IMAGE"
docker stack deploy \
  -c $WORKSPACE/proxy.yml \
  --with-registry-auth \
  --detach=false \
  $STACK_NAME
