#!/bin/bash

# Load configuration
source /etc/cleaner-config/config.env

# Azure login
az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID

# Function to check user existence
user_exists() {
    az ad user show --id "$1" >/dev/null 2>&1
    return $?
}

# Function to validate domain
valid_domain() {
    local domain=$(echo "$1" | cut -d@ -f2)
    [[ ",${ALLOWED_DOMAINS}," =~ ",${domain}," ]]
}

# Convert grace period days to date
grace_days=$(echo $GRACE_PERIOD | grep -oE '[0-9]+')
delete_date=$(date -d "+${grace_days} days" -u +%Y-%m-%dT00:00:00Z)

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
        kubectl label ns $ns namespace-cleaner/delete-at=$delete_date
    fi
done

# Phase 2: Check existing markers
kubectl get ns -l namespace-cleaner/delete-at \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.namespace-cleaner/delete-at}{"\n"}{end}' \
    | while read line; do

    ns=$(echo "$line" | cut -f1)
    delete_date=$(echo "$line" | cut -f2)
    owner_email=$(kubectl get ns $ns -o jsonpath='{.metadata.annotations.owner}')

    today=$(date -u +%Y-%m-%d)
    delete_day=$(echo $delete_date | cut -d'T' -f1)

    if [[ "$today" > "$delete_day" ]]; then
        if ! user_exists "$owner_email"; then
            echo "Deleting expired namespace: $ns"
            kubectl delete ns $ns
        else
            echo "User restored, removing deletion marker from $ns"
            kubectl label ns $ns namespace-cleaner/delete-at-
        fi
    else
        if user_exists "$owner_email"; then
            echo "User restored, removing deletion marker from $ns"
            kubectl label ns $ns namespace-cleaner/delete-at-
        fi
    fi
done
