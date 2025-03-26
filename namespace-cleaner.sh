#!/bin/bash

# Modified configuration loading
CONFIG_FILE="./cleaner-config.env"

# Load configuration from cluster or local file
if [ "$TEST_MODE" = "true" ]; then
  echo "TEST_MODE: Loading config from ConfigMap"
  kubectl get configmap namespace-cleaner-config -o jsonpath='{.data.config\.env}' > $CONFIG_FILE
  source $CONFIG_FILE
else
  # Production config (original path)
  source /etc/cleaner-config/config.env
fi

# Testing mode setup
if [ "$TEST_MODE" = "true" ]; then
  echo "Running in TEST_MODE - using ConfigMap test users"
  TEST_USERS=$(kubectl get configmap namespace-cleaner-test-users -o jsonpath='{.data.users}' | tr ',' '\n')
else
  # Production Azure login
  az login --service-principal \
    -u $AZURE_CLIENT_ID \
    -p $AZURE_CLIENT_SECRET \
    --tenant $AZURE_TENANT_ID
fi

# User existence check
user_exists() {
  local user="$1"

  if [ "$TEST_MODE" = "true" ]; then
    # Check against ConfigMap test users
    grep -qFx "$user" <<< "$TEST_USERS"
    return $?
  else
    # Production Azure check
    az ad user show --id "$user" >/dev/null 2>&1
    return $?
  fi
}

# Domain validation
valid_domain() {
  local email="$1"
  local domain=$(echo "$email" | cut -d@ -f2)
  [[ ",${ALLOWED_DOMAINS}," =~ ",${domain}," ]]
}

# Dry-run wrapper
kubectl_dryrun() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY RUN] Would execute: kubectl $@"
  else
    kubectl "$@"
  fi
}

# Grace period calculation
grace_days=$(echo $GRACE_PERIOD | grep -oE '[0-9]+')
delete_date=$(date -d "+${grace_days} days" -u +%Y-%m-%d)

# Phase 1: Process new namespaces
kubectl get ns -l app.kubernetes.io/part-of=kubeflow-profile,!\namespace-cleaner/delete-at \
  -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | while read ns; do

  owner_email=$(kubectl get ns $ns -o jsonpath='{.metadata.annotations.owner}')

  if ! valid_domain "$owner_email"; then
    echo "Invalid domain in $ns: $owner_email"
    continue
  fi

  if ! user_exists "$owner_email"; then
    echo "Marking $ns for deletion on $delete_date"
    kubectl_dryrun label ns $ns namespace-cleaner/delete-at=$delete_date
  fi
done

# Phase 2: Check existing markers
kubectl get ns -l namespace-cleaner/delete-at \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.namespace-cleaner/delete-at}{"\n"}{end}' \
  | while read line; do

  ns=$(echo "$line" | cut -f1)
  owner_email=$(kubectl get ns $ns -o jsonpath='{.metadata.annotations.owner}')

  today=$(date -u +%Y-%m-%d)
  delete_day=$(echo $delete_date | cut -d'T' -f1)

  echo "Processing namespace: $ns (delete date: $delete_day)"
  if [[ "$today" > "$delete_day" ]]; then
    echo "Namespace $ns is past deletion date ($delete_day)"
    if ! user_exists "$owner_email"; then
      echo "Deleting expired namespace: $ns"
      kubectl_dryrun delete ns $ns
    else
      echo "User restored, removing deletion marker from $ns"
      kubectl_dryrun label ns $ns namespace-cleaner/delete-at-
    fi
  else
    echo "Namespace $ns not expired yet (delete date: $delete_day)"
    if user_exists "$owner_email"; then
      echo "User restored, removing deletion marker from $ns"
      kubectl_dryrun label ns $ns namespace-cleaner/delete-at-
    fi
  fi
done
