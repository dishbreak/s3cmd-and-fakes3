#!/bin/bash
set -e

docker build -t fakeds3cmd .
docker run -it --network='s3cmdandfakes3_s3cmd-network' fakeds3cmd /bin/sh