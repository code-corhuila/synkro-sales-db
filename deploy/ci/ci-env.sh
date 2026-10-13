#!/usr/bin/env bash
# CI-only connection defaults, shared by all disposable integration checks.
export CI_MONGO_CONTAINER="${CI_MONGO_CONTAINER:-synkro-mongo}"
export MONGODB_NETWORK="${MONGODB_NETWORK:-platform}"
export CI_ADMIN_PASSWORD="${CI_ADMIN_PASSWORD:-ci-admin-pw}"
export CI_SALES_APP_PASSWORD="${CI_SALES_APP_PASSWORD:-ci-sales-app-pw}"
ci_admin_uri() {
  CI_CONNECTION_HOST="$CI_MONGO_CONTAINER" CI_CONNECTION_USER=admin node deploy/ci/connection.js
}
export MONGODB_URI="${MONGODB_URI:-$(ci_admin_uri)}"
export MONGODB_DATABASE="${MONGODB_DATABASE:-sales}"
export MONGODB_OPTIONS="${MONGODB_OPTIONS:-replicaSet=rs0&authSource=admin&serverSelectionTimeoutMS=5000}"
require_disposable_database() {
  local label storage
  label=$(docker container inspect --format '{{index .Config.Labels "com.synkro.sales-db.disposable"}}' "$CI_MONGO_CONTAINER") || return
  storage=$(docker container inspect --format '{{range $path, $options := .HostConfig.Tmpfs}}{{if eq $path "/data/db"}}tmpfs{{end}}{{end}}' "$CI_MONGO_CONTAINER") || return
  [[ $label == true && $storage == tmpfs && $MONGODB_DATABASE == sales &&
    $MONGODB_URI == "$(ci_admin_uri)" &&
    $MONGODB_OPTIONS == 'replicaSet=rs0&authSource=admin&serverSelectionTimeoutMS=5000' ]] || {
    echo 'Refusing database checks: target must be the labelled tmpfs CI container with the CI connection' >&2
    return 1
  }
}
