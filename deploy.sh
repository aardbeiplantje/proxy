#!/bin/bash 

export WORKSPACE=${WORKSPACE:-${BASH_SOURCE%/*}}
export APP_NAME=${APP_NAME:-proxy}
export STACK_NAME=${STACK_NAME:-$APP_NAME}
printf -v now "%(%s)T" -1
export CFG_PREFIX=$STACK_NAME-$now
export TC_HTB_RATE=${TC_HTB_RATE:-50Mbit}

cd $WORKSPACE || exit $?

echo "using: $APP_NAME / $STACK_NAME, rate=${TC_HTB_RATE}"

if [ -z "$DOCKER_REGISTRY" \
    -o -z "$DOCKER_REGISTRY_USER" \
    -o -z "$DOCKER_REGISTRY_PASS" ]; then
  if [ -n "$DOCKER_REGISTRY_USER" ]; then
    echo "no docker registry credentials; skipping push (use \`docker buildx bake local\`)"
    exit 0
  fi
fi

if [ -n "$DOCKER_REGISTRY" \
   -a -n "$DOCKER_REGISTRY_USER" \
   -a -n "$DOCKER_REGISTRY_PASS" ]; then
  export DOCKER_REGISTRY DOCKER_REGISTRY_USER DOCKER_REGISTRY_PASS
  printenv DOCKER_REGISTRY_PASS \
    | docker login \
        -u ${DOCKER_REGISTRY_USER?Need a DOCKER_REGISTRY_USER} \
        --password-stdin \
        ${DOCKER_REGISTRY?Need a DOCKER_REGISTRY}
fi

export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-${DOCKER_REGISTRY}/proxy}

echo "building images with buildx bake, using $DOCKER_REPOSITORY"
docker buildx bake -f docker-bake.hcl || exit $?

echo "stack deploy $STACK_NAME, using $DOCKER_REPOSITORY"
docker stack deploy \
  -c $WORKSPACE/proxy.yml \
  --with-registry-auth \
  --detach=false \
  $STACK_NAME
