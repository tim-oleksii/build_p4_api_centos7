#!/bin/bash

# docker 25.02 is incredible slow
# refer to this thread https://github.com/moby/moby/issues/45838
docker build --ulimit "nofile=1024:1048576"  -t build_p4_api_centos7 .

