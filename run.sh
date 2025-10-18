#!/bin/bash
set -e

PORT_ARG=""
TOKEN_ARG=""

if [ -n "$1" ]; then
  PORT=$1
  PORT_ARG="--device=${PORT}:${PORT} -e PORT=${PORT}"
fi

if [ -n "$2" ]; then
  TOKEN=$2
  TOKEN_ARG="-e TOKEN=${TOKEN}"
fi

docker run --rm -it \
  --privileged \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v docker-storage:/var/lib/docker \
  $PORT_ARG \
  $TOKEN_ARG \
  $URL_ARG \
  $FIRMWARE_ARG \
  esp-wrapper