#!/usr/bin/env bash
# Feed scripts through stdin and credentials through Docker's inherited environment.
ci_mongosh() (
  set -o pipefail
  local user="$1"
  local LIQUIBASE_COMMAND_URL
  LIQUIBASE_COMMAND_URL=$(CI_CONNECTION_USER="$user" CI_CONNECTION_HOST=localhost node deploy/ci/connection.js)
  export LIQUIBASE_COMMAND_URL
  LIQUIBASE_COMMAND_URL+='/sales?authSource=admin'
  { printf '%s\n' 'db = connect(process.env.LIQUIBASE_COMMAND_URL);'; cat; } |
    docker exec -i -e LIQUIBASE_COMMAND_URL -e PHASE -e DRIFT "$CI_MONGO_CONTAINER" \
      mongosh --nodb --quiet --file /dev/stdin 2>&1 | node deploy/ci/redact-output.js
)
