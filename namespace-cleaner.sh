#!/bin/sh
set -eu

# Environment defaults
TEST_MODE=${TEST_MODE:-false}
DRY_RUN=${DRY_RUN:-false}
CONFIG_FILE="./cleaner-config.env"

# Dependency checks
check_dependencies() {
  for cmd in kubectl date cut tr grep; do
    if ! command -v $cmd >/dev/null; then
      echo "Error: Missing required command '$cmd'"
      exit 1
    fi
  done

  if [ "$TEST_MODE" = "false" ] && ! command -v az >/dev/null; then
    echo "Error: Azure CLI (az) required in production mode"
    exit 1
  fi
}

check_dependencies

# Configuration loading
load_config() {
  if [ "$TEST_MODE" = "true" ]; then
    echo "TEST MODE: Loading test configuration"

    # Test config validation
    if ! kubectl get configmap namespace-cleaner-config >/dev/null; then
      echo "Error: Missing test ConfigMap namespace-cleaner-config"
      exit 1
    fi

    kubectl get configmap namespace-cleaner-config -o jsonpath='{.data.config\.env}' > "$CONFIG_FILE"
    . "$CONFIG_FILE"

    # Test users validation
    if ! kubectl get configmap namespace-cleaner-test-users >/dev/null; then
      echo "Error: Missing test ConfigMap namespace-cleaner-test-users"
      exit 1
    fi
    TEST_USERS=$(kubectl get configmap namespace-cleaner-test-users -o jsonpath='{.data.users}' | tr ',' '\n')

  else
    echo "PRODUCTION MODE: Using cluster configuration"

    # Production config validation
    if [ ! -f "/etc/cleaner-config/config.env" ]; then
      echo "Error: Missing production config at /etc/cleaner-config/config.env"
      exit 1
    fi
    . /etc/cleaner-config/config.env

    # Azure authentication
    if ! az login --service-principal \
      -u "$AZURE_CLIENT_ID" \
      -p "$AZURE_CLIENT_SECRET" \
      --tenant "$AZURE_TENANT_ID" >/dev/null; then
      echo "Error: Azure authentication failed"
      exit 1
    fi
  fi

  # Validate loaded configuration
  if [ -z "${ALLOWED_DOMAINS:-}" ]; then
    echo "Error: ALLOWED_DOMAINS not configured"
    exit 1
  fi
}

load_config

# Core functions
user_exists() {
  local user="$1"

  if [ "$TEST_MODE" = "true" ]; then
    echo "$TEST_USERS" | grep -qFx "$user"
  else
    az ad user show --id "$user" >/dev/null 2>&1
  fi
}

valid_domain() {
  local email="$1"
  local domain=$(echo "$email" | cut -d@ -f2)

  case ",${ALLOWED_DOMAINS}," in
    *",${domain},"*) return 0 ;;
    *) return 1 ;;
  esac
}

kubectl_dryrun() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY RUN] Would execute: kubectl $@"
  else
    kubectl "$@"
  fi
}

# Date calculations using epoch seconds for portability
get_grace_period() {
  grace_days=$(echo "$GRACE_PERIOD" | grep -oE '^[0-9]+')
  if [ -z "$grace_days" ]; then
    echo "Invalid GRACE_PERIOD format: $GRACE_PERIOD"
    exit 1
  fi

  grace_seconds=$((grace_days * 86400))
  current_epoch=$(date +%s)
  date -u -d "@$((current_epoch + grace_seconds))" "+%Y-%m-%d"
}

# Main processing
process_namespaces() {
  # Phase 1: New namespaces
  delete_date=$(get_grace_period)

  kubectl get ns -l 'app.kubernetes.io/part-of=kubeflow-profile,!namespace-cleaner/delete-at' \
    -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | while read ns; do

    owner_email=$(kubectl get ns "$ns" -o jsonpath='{.metadata.annotations.owner}')

    if valid_domain "$owner_email"; then
      if ! user_exists "$owner_email"; then
        echo "Marking $ns for deletion on $delete_date"
        kubectl_dryrun label ns "$ns" "namespace-cleaner/delete-at=$delete_date"
      fi
    else
      echo "Invalid domain in $ns: $owner_email"
    fi
  done

  # Phase 2: Expired namespaces
  today=$(date -u +%Y-%m-%d)

  kubectl get ns -l 'namespace-cleaner/delete-at' \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.namespace-cleaner/delete-at}{"\n"}{end}' \
    | while read line; do

    ns=$(echo "$line" | cut -f1)
    label_date=$(echo "$line" | cut -f2 | cut -d'T' -f1)

    if [ "$today" \> "$label_date" ]; then
      owner_email=$(kubectl get ns "$ns" -o jsonpath='{.metadata.annotations.owner}')

      if ! user_exists "$owner_email"; then
        echo "Deleting expired namespace: $ns"
        kubectl_dryrun delete ns "$ns"
      else
        echo "User restored, removing label from $ns"
        kubectl_dryrun label ns "$ns" 'namespace-cleaner/delete-at-'
      fi
    fi
  done
}

process_namespaces
