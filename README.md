# Kubernetes Namespace Cleaner

Automatically marks and deletes Kubernetes namespaces if their owner no longer exists in Azure Entra ID.

```mermaid
%% Namespace Cleaner Workflow (Bash Version)
flowchart TD
    A[CronJob Trigger] --> B[Load Config]
    B --> C{Mode?}
    C -->|Dry Run| D[Log Actions Only]
    C -->|Test Mode| E[Use Mock Users/Domains]
    C -->|Production| F[Authenticate with Azure]

    D & E & F --> G[Phase 1: New Namespaces]
    G --> H[Get namespaces with kubeflow label]
    H --> I[Loop Through Namespaces]
    I --> J{Valid Domain?}
    J -->|No| K[Log "Invalid Domain"]
    J -->|Yes| L{User Exists?}
    L -->|No| M[Label for Deletion]
    L -->|Yes| N[Skip]

    G --> O[Phase 2: Expired Labels]
    O --> P[Get namespaces with delete-at label]
    P --> Q[Loop Through Namespaces]
    Q --> R{Grace Period Expired?}
    R -->|Yes| S{User Still Missing?}
    S -->|Yes| T[Delete Namespace]
    S -->|No| U[Remove Label]
    R -->|No| V{User Restored?}
    V -->|Yes| U

    classDef green fill:#d6f0dd,stroke:#28a745;
    classDef orange fill:#fce8d2,stroke:#fd7e14;
    class A,D,E,T,U green
    class M,V orange
```

---

## Features

- Labels namespaces for deletion after a grace period (`GRACE_PERIOD`).
- Validates user domains against an allowlist (`ALLOWED_DOMAINS`).
- **Local Testing Mode**: Simulate checks without Azure integration.
- **Dry Run Mode**: Preview actions without modifying the cluster.

## Prerequisites

- `kubectl` configured with cluster access.
- Azure service principal credentials (for production/dry-run modes).

## Installation

1. **Update Configurations**:
   - Edit `configmap.yaml` to set `ALLOWED_DOMAINS` and `GRACE_PERIOD`.
   - Populate `secret.yaml` with valid Azure credentials.

2. **Apply Resources**:
   ```bash
   kubectl apply -f configmap.yaml
   kubectl apply -f secret.yaml
   kubectl apply -f cronjob.yaml
   ```

## Testing Modes

### Local Testing (No Azure Checks)
Simulates user/domain validation using test data:
```bash
# Set test parameters
export TEST_MODE="true"
export TEST_USERS="user1@test.example,user2@company.com"  # Mock existing users
export TEST_ALLOWED_DOMAINS="test.example,company.com"    # Optional domain override
export GRACE_PERIOD="1d"                                   # Test grace period

# Run script (ensure kubectl points to a test cluster)
./namespace-cleaner.sh
```

### Dry Run (Azure Checks, No Cluster Changes)
Performs real Azure checks but only logs actions:
```bash
export DRY_RUN="true"
./namespace-cleaner.sh
```

## Production Deployment
The CronJob runs daily at midnight (UTC). To modify the schedule, edit `cronjob.yaml`:
```yaml
spec:
  schedule: "0 0 * * *"  # Cron schedule format
```

**Requirements**:
- Valid Azure credentials in `secret.yaml`.
- Ensure `ALLOWED_DOMAINS` in `configmap.yaml` matches your organization's domains.

## Limitations vs. a Go Implementation
1. **Performance**: Bash scripts process namespaces sequentially. For large clusters (>1000 namespaces), a Go binary would be faster.
2. **Error Handling**: Limited retry logic for transient Azure/k8s API errors.
3. **Dependencies**: Relies on `az` CLI, `jq`, and `bc` utilities. A Go binary could embed these checks.
4. **State Management**: Uses Kubernetes labels for tracking deletion states. A Go implementation could use a database for auditability.
5. **Testing Complexity**: Mocking Azure users requires manual environment variable setup.

## Troubleshooting
- **Azure Login Failures**: Verify `secret.yaml` credentials and Azure permissions.
- **Invalid Labels/Annotations**: Ensure namespaces have the `app.kubernetes.io/part-of=kubeflow-profile` label and `owner` annotation.
- **Permission Issues**: The CronJob's service account needs RBAC access to list/update/delete namespaces.
