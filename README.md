# Namespace Cleaner Controller

A Kubernetes controller written in Go that automatically audits and cleans up Kubeflow namespaces associated with Statcan.gc.ca user accounts. The controller periodically checks if the account associated with a namespace still exists in Entra ID using the Microsoft Graph API. If the account is missing, it marks the namespace for deletion and, after a defined grace period, deletes the namespace to maintain a clean cluster.

## Features

- **Account Verification:**  
  Validates if the user associated with a namespace (using the `user-email` label) exists in Entra ID.

- **Grace Period:**  
  Implements a safety window (e.g., 48 hours) before namespace deletion to avoid accidental removal.

- **Automated Cleanup:**  
  Automatically marks and deletes namespaces based on user account status.

- **Logging & Auditing:**  
  Logs key actions (marking, deletion) for easier troubleshooting and auditability.

## Architecture

The controller uses the [controller-runtime](https://github.com/kubernetes-sigs/controller-runtime) framework to build a reconciliation loop that:

1. **Fetches** all namespaces that have a `user-email` label.
2. **Validates** each account against Entra ID via the Microsoft Graph API.
3. **Marks** namespaces for deletion if the account does not exist, by annotating them with a timestamp.
4. **Deletes** namespaces if the grace period has elapsed since the deletion candidate was marked.

## Prerequisites

- Go 1.18+
- Access to a Kubernetes cluster
- `kubectl` installed and configured
- Azure AD credentials (Tenant ID, Client ID, Client Secret) with permissions to query user information via Microsoft Graph API

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/bryanpaget/namespace-cleaner.git
cd namespace-cleaner
