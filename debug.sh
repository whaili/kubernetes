#!/usr/bin/env bash
#
etcd --data-dir=/tmp/etcd --listen-client-urls=http://127.0.0.1:2379 \
     --advertise-client-urls=http://127.0.0.1:2379

