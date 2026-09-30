#!/usr/bin/env bash
# Deploy script for the Data Ingestion Demo on OpenShift / RHOAI
#
# Prerequisites:
#   - Logged into OpenShift cluster with oc
#   - Spark operator installed via RHOAI
#   - Webhook namespace selector includes target namespace
#   - (Optional) Kueue configured with LocalQueue 'spark-lq'
#
# Usage:
#   ./deploy.sh setup        — Create PVCs, ConfigMaps, upload sample data
#   ./deploy.sh run           — Submit SparkApplication (single run)
#   ./deploy.sh run-kueue     — Submit with Kueue admission control
#   ./deploy.sh run-scheduled — Deploy ScheduledSparkApplication (cron)
#   ./deploy.sh status        — Check SparkApplication/workload status
#   ./deploy.sh logs [name]   — Tail driver logs
#   ./deploy.sh history       — Deploy Spark History Server
#   ./deploy.sh cleanup       — Delete all demo resources
set -euo pipefail

NAMESPACE="${NAMESPACE:-redhat-ods-applications}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"
DATA_DIR="${SCRIPT_DIR}/../sample-data"
SPARK_IMAGE="${SPARK_IMAGE:-quay.io/opendatahub/data-processing:Spark-v4.0.1}"

info() { echo "==> $*"; }
err()  { echo "ERROR: $*" >&2; exit 1; }

upload_data() {
    info "Uploading sample data to PVC nas-raw-data..."
    oc run data-uploader -n "${NAMESPACE}" \
        --image="${SPARK_IMAGE}" \
        --restart=Never \
        --overrides='{
          "spec": {
            "securityContext": {},
            "containers": [{
              "name": "data-uploader",
              "image": "'"${SPARK_IMAGE}"'",
              "command": ["sleep", "300"],
              "securityContext": {},
              "resources": {"requests": {"cpu": "100m", "memory": "256Mi"}},
              "volumeMounts": [{"name":"data","mountPath":"/mnt/data"}]
            }],
            "volumes": [{"name":"data","persistentVolumeClaim":{"claimName":"nas-raw-data"}}]
          }
        }'

    info "Waiting for uploader pod..."
    # If Kueue is managing the namespace, remove scheduling gates
    sleep 5
    oc patch pod data-uploader -n "${NAMESPACE}" --type='json' \
        -p='[{"op":"remove","path":"/spec/schedulingGates"}]' 2>/dev/null || true
    oc wait pod/data-uploader -n "${NAMESPACE}" --for=condition=Ready --timeout=120s

    info "Copying data files..."
    for f in "${DATA_DIR}"/*; do
        oc cp "${f}" "${NAMESPACE}/data-uploader:/mnt/data/$(basename "${f}")"
        info "  Uploaded $(basename "${f}")"
    done

    info "Verifying uploaded files..."
    oc exec -n "${NAMESPACE}" data-uploader -- ls -la /mnt/data/

    info "Cleaning up uploader pod..."
    oc delete pod data-uploader -n "${NAMESPACE}" --wait=false
}

cmd_setup() {
    info "Creating PVCs..."
    oc apply -f "${K8S_DIR}/input-pvc.yaml"
    oc apply -f "${K8S_DIR}/output-pvc.yaml"
    oc apply -f "${K8S_DIR}/event-logs-pvc.yaml"

    info "Creating ConfigMaps..."
    oc apply -f "${K8S_DIR}/schema-configmap.yaml"
    oc apply -f "${K8S_DIR}/app-configmap.yaml"

    upload_data

    info "Setup complete!"
    oc get pvc -n "${NAMESPACE}" -l app=data-ingestion-demo
    oc get configmap -n "${NAMESPACE}" -l app=data-ingestion-demo
}

cmd_run() {
    info "Submitting SparkApplication..."
    oc delete sparkapplication data-ingestion-batch -n "${NAMESPACE}" 2>/dev/null || true
    sleep 2
    oc apply -f "${K8S_DIR}/spark-data-ingestion.yaml"
    info "Submitted. Monitor with: ./deploy.sh status  or  ./deploy.sh logs"
}

cmd_run_kueue() {
    info "Submitting SparkApplication with Kueue admission..."
    oc delete sparkapplication data-ingestion-batch-kueue -n "${NAMESPACE}" 2>/dev/null || true
    sleep 2
    oc apply -f "${K8S_DIR}/spark-data-ingestion-kueue.yaml"
    info "Submitted with Kueue. Monitor with: ./deploy.sh status"
}

cmd_run_scheduled() {
    info "Deploying ScheduledSparkApplication..."
    oc apply -f "${K8S_DIR}/scheduled-data-ingestion.yaml"
    info "Scheduled job deployed."
    oc get scheduledsparkapplication -n "${NAMESPACE}" -l app=data-ingestion-demo
}

cmd_status() {
    info "SparkApplication status:"
    oc get sparkapplication -n "${NAMESPACE}" -l app=data-ingestion-demo 2>/dev/null || true
    echo ""
    info "ScheduledSparkApplication status:"
    oc get scheduledsparkapplication -n "${NAMESPACE}" -l app=data-ingestion-demo 2>/dev/null || true
    echo ""
    info "Pods:"
    oc get pods -n "${NAMESPACE}" -l sparkoperator.k8s.io/launched-by-spark-operator=true 2>/dev/null || true
    echo ""
    info "Kueue workloads:"
    oc get workloads -n "${NAMESPACE}" 2>/dev/null || true
}

cmd_logs() {
    local app=${1:-data-ingestion-batch}
    info "Tailing driver logs for ${app}..."
    local driver_pod
    driver_pod=$(oc get pods -n "${NAMESPACE}" -l "spark-role=driver,sparkoperator.k8s.io/app-name=${app}" -o name 2>/dev/null | head -1)
    if [[ -z "${driver_pod}" ]]; then
        err "No driver pod found for ${app}."
    fi
    oc logs -n "${NAMESPACE}" "${driver_pod}" -f
}

cmd_history() {
    info "Deploying Spark History Server..."
    oc apply -f "${K8S_DIR}/spark-history-server.yaml"
    oc rollout status deployment/spark-history-server -n "${NAMESPACE}" --timeout=120s || true
    local route
    route=$(oc get route spark-history-server -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)
    info "Spark History Server UI: https://${route}"
}

cmd_cleanup() {
    info "Cleaning up all demo resources..."
    oc delete sparkapplication -n "${NAMESPACE}" -l app=data-ingestion-demo 2>/dev/null || true
    oc delete scheduledsparkapplication -n "${NAMESPACE}" -l app=data-ingestion-demo 2>/dev/null || true
    oc delete deployment spark-history-server -n "${NAMESPACE}" 2>/dev/null || true
    oc delete service spark-history-server -n "${NAMESPACE}" 2>/dev/null || true
    oc delete route spark-history-server -n "${NAMESPACE}" 2>/dev/null || true
    oc delete configmap ingestion-schema ingestion-app-code -n "${NAMESPACE}" 2>/dev/null || true
    oc delete pvc nas-raw-data ingestion-output spark-event-logs -n "${NAMESPACE}" 2>/dev/null || true
    oc delete pod data-uploader -n "${NAMESPACE}" 2>/dev/null || true
    info "Cleanup complete!"
}

case "${1:-}" in
    setup)         cmd_setup ;;
    run)           cmd_run ;;
    run-kueue)     cmd_run_kueue ;;
    run-scheduled) cmd_run_scheduled ;;
    status)        cmd_status ;;
    logs)          cmd_logs "${2:-data-ingestion-batch}" ;;
    history)       cmd_history ;;
    cleanup)       cmd_cleanup ;;
    *)
        echo "Usage: $0 {setup|run|run-kueue|run-scheduled|status|logs|history|cleanup}"
        exit 1
        ;;
esac
