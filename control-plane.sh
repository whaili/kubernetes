#!/usr/bin/env bash
set -euo pipefail

# ==========================
# Kubernetes minimal debug control-plane
#  Usage:
#    $0 start [component]  # component: etcd|apiserver|controller|scheduler|all
#    $0 stop [component]
# ==========================

ACTION=${1:-""}
COMPONENT=${2:-"all"}  # 默认全部

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd)
DEBUG_DIR=/tmp/k8s-debug
LOG_DIR=${DEBUG_DIR}/logs
mkdir -p "${DEBUG_DIR}" "${LOG_DIR}"

ETCD_PID_FILE=${DEBUG_DIR}/etcd.pid
ETCD_LOG=${LOG_DIR}/etcd.log
APISERVER_PID_FILE=${DEBUG_DIR}/apiserver.pid
APISERVER_LOG=${LOG_DIR}/apiserver.log
CONTROLLER_PID_FILE=${DEBUG_DIR}/controller-manager.pid
CONTROLLER_LOG=${LOG_DIR}/controller-manager.log
SCHEDULER_PID_FILE=${DEBUG_DIR}/scheduler.pid
SCHEDULER_LOG=${LOG_DIR}/scheduler.log

export KUBECONFIG=${DEBUG_DIR}/debug.kubeconfig

usage() {
    echo "用法: $0 {start|stop} [component]"
    echo "  component: etcd|apiserver|controller|scheduler|all (默认 all)"
    exit 1
}

# --------------------------
# 环境准备（生成证书和kubeconfig）
# --------------------------
prepare_env() {
    echo "===== 环境准备 ====="
    cd "${DEBUG_DIR}"

    [ -f ca.key ] || openssl genrsa -out ca.key 2048
    [ -f ca.crt ] || openssl req -x509 -new -nodes -key ca.key -subj "/CN=my-debug-ca" -days 10000 -out ca.crt

    [ -f server.conf ] || cat > server.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = kube-apiserver
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = localhost
IP.1 = 127.0.0.1
IP.2 = 10.96.0.1
EOF

    [ -f server.key ] || openssl genrsa -out server.key 2048
    [ -f server.csr ] || openssl req -new -key server.key -out server.csr -config server.conf
    [ -f server.crt ] || openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
        -out server.crt -days 10000 -extensions v3_req -extfile server.conf

    [ -f client.key ] || openssl genrsa -out client.key 2048
    [ -f client.crt ] || openssl req -new -key client.key -subj "/O=system:masters/CN=debug-admin" | \
        openssl x509 -req -days 10000 -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt

    [ -f sa.key ] || openssl genrsa -out sa.key 2048

    if [ ! -f debug.kubeconfig ]; then
        kubectl config set-cluster debug-cluster \
            --server=https://127.0.0.1:6443 \
            --certificate-authority=ca.crt \
            --embed-certs=true \
            --kubeconfig=${DEBUG_DIR}/debug.kubeconfig
        kubectl config set-credentials debug-admin \
            --client-certificate=client.crt \
            --client-key=client.key \
            --embed-certs=true \
            --kubeconfig=${DEBUG_DIR}/debug.kubeconfig
        kubectl config set-context debug-context \
            --cluster=debug-cluster \
            --user=debug-admin \
            --kubeconfig=${DEBUG_DIR}/debug.kubeconfig
        kubectl config use-context debug-context --kubeconfig=${DEBUG_DIR}/debug.kubeconfig
    fi
}

# --------------------------
# etcd
# --------------------------
start_etcd() {
    if pgrep -x etcd >/dev/null 2>&1; then
        echo "⚠️ etcd 已在运行"
        return
    fi
    echo "🚀 启动 etcd ..."
    nohup etcd \
        --data-dir=/tmp/etcd-data \
        --listen-client-urls=http://127.0.0.1:2379 \
        --advertise-client-urls=http://127.0.0.1:2379 \
        > "${ETCD_LOG}" 2>&1 &
    echo $! > "${ETCD_PID_FILE}"
    echo "✅ etcd PID=$(cat ${ETCD_PID_FILE}) 日志=${ETCD_LOG}"
}

stop_etcd() {
    if [ -f "${ETCD_PID_FILE}" ]; then
        kill -9 $(cat ${ETCD_PID_FILE}) || true
        rm -f "${ETCD_PID_FILE}"
        echo "🛑 etcd 已停止"
    else
        echo "⚠️ etcd 未运行"
    fi
}

# --------------------------
# kube-apiserver
# --------------------------
start_apiserver() {
    prepare_env
    APISERVER_BIN="${ROOT_DIR}/_output/local/go/bin/kube-apiserver"
    if [ ! -f "${APISERVER_BIN}" ]; then
        echo "❌ 找不到 kube-apiserver，请先 make DBG=1 WHAT=cmd/kube-apiserver"
        exit 1
    fi
    if pgrep -x kube-apiserver >/dev/null 2>&1; then
        echo "⚠️ kube-apiserver 已在运行"
        return
    fi
    echo "🚀 启动 kube-apiserver ..."
    nohup "${APISERVER_BIN}" \
        --etcd-servers=http://127.0.0.1:2379 \
        --service-cluster-ip-range=10.96.0.0/16 \
        --bind-address=127.0.0.1 \
        --secure-port=6443 \
        --tls-cert-file=${DEBUG_DIR}/server.crt \
        --tls-private-key-file=${DEBUG_DIR}/server.key \
        --client-ca-file=${DEBUG_DIR}/ca.crt \
        --authorization-mode=AlwaysAllow \
        --service-account-key-file=${DEBUG_DIR}/sa.key \
        --service-account-signing-key-file=${DEBUG_DIR}/sa.key \
        --service-account-issuer=https://kubernetes.default.svc \
        --allow-privileged=true -v=4 \
        > "${APISERVER_LOG}" 2>&1 &
    echo $! > "${APISERVER_PID_FILE}"
    echo "✅ kube-apiserver PID=$(cat ${APISERVER_PID_FILE}) 日志=${APISERVER_LOG}"
}

stop_apiserver() {
    if [ -f "${APISERVER_PID_FILE}" ]; then
        kill -9 $(cat ${APISERVER_PID_FILE}) || true
        rm -f "${APISERVER_PID_FILE}"
        echo "🛑 kube-apiserver 已停止"
    else
        echo "⚠️ kube-apiserver 未运行"
    fi
}

# --------------------------
# kube-controller-manager
# --------------------------
start_controller() {
    CONTROLLER_BIN="${ROOT_DIR}/_output/local/go/bin/kube-controller-manager"
    if [ ! -f "${CONTROLLER_BIN}" ]; then
        echo "❌ 找不到 kube-controller-manager，请先 make DBG=1 WHAT=cmd/kube-controller-manager"
        exit 1
    fi
    if pgrep -x kube-controller-manager >/dev/null 2>&1; then
        echo "⚠️ kube-controller-manager 已在运行"
        return
    fi
    echo "🚀 启动 kube-controller-manager ..."
    nohup "${CONTROLLER_BIN}" \
        --kubeconfig=${KUBECONFIG} \
        --service-account-private-key-file=${DEBUG_DIR}/sa.key \
        --root-ca-file=${DEBUG_DIR}/ca.crt \
        -v=4 \
        > "${CONTROLLER_LOG}" 2>&1 &
    echo $! > "${CONTROLLER_PID_FILE}"
    echo "✅ kube-controller-manager PID=$(cat ${CONTROLLER_PID_FILE}) 日志=${CONTROLLER_LOG}"
}

stop_controller() {
    if [ -f "${CONTROLLER_PID_FILE}" ]; then
        kill -9 $(cat ${CONTROLLER_PID_FILE}) || true
        rm -f "${CONTROLLER_PID_FILE}"
        echo "🛑 kube-controller-manager 已停止"
    else
        echo "⚠️ kube-controller-manager 未运行"
    fi
}

# --------------------------
# kube-scheduler ✅ 新增部分
# --------------------------
start_scheduler() {
    SCHED_BIN="${ROOT_DIR}/_output/local/go/bin/kube-scheduler"
    if [ ! -f "${SCHED_BIN}" ]; then
        echo "❌ 找不到 kube-scheduler，请先 make DBG=1 WHAT=cmd/kube-scheduler"
        exit 1
    fi
    if pgrep -x kube-scheduler >/dev/null 2>&1; then
        echo "⚠️ kube-scheduler 已在运行"
        return
    fi
    echo "🚀 启动 kube-scheduler ..."
    nohup "${SCHED_BIN}" \
        --kubeconfig=${KUBECONFIG} \
        -v=4 \
        > "${SCHEDULER_LOG}" 2>&1 &
    echo $! > "${SCHEDULER_PID_FILE}"
    echo "✅ kube-scheduler PID=$(cat ${SCHEDULER_PID_FILE}) 日志=${SCHEDULER_LOG}"
}

stop_scheduler() {
    if [ -f "${SCHEDULER_PID_FILE}" ]; then
        kill -9 $(cat ${SCHEDULER_PID_FILE}) || true
        rm -f "${SCHEDULER_PID_FILE}"
        echo "🛑 kube-scheduler 已停止"
    else
        echo "⚠️ kube-scheduler 未运行"
    fi
}

# --------------------------
# Dispatcher
# --------------------------
case "${ACTION}" in
    start)
        case "${COMPONENT}" in
            etcd) start_etcd ;;
            apiserver) start_apiserver ;;
            controller) start_controller ;;
            scheduler) start_scheduler ;;
            all)
                start_etcd
                sleep 1
                start_apiserver
                sleep 2
                start_controller
                start_scheduler
                ;;
            *) usage ;;
        esac
        ;;
    stop)
        case "${COMPONENT}" in
            etcd) stop_etcd ;;
            apiserver) stop_apiserver ;;
            controller) stop_controller ;;
            scheduler) stop_scheduler ;;
            all)
                stop_scheduler
                stop_controller
                stop_apiserver
                stop_etcd
                ;;
            *) usage ;;
        esac
        ;;
    *)
        usage ;;
esac

