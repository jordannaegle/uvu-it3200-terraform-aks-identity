# Architecture and Identity Design

This lab deploys an Entra-integrated AKS cluster and an authenticated
Azure Container Registry in West US 3 using Terraform.

## Architecture Diagram

```mermaid
flowchart TD
    Personal["Personal Microsoft Entra user"]
    SP["Lab service principal"]
    Entra["Microsoft Entra ID<br/>Authenticates identities"]
    Auth["Azure RBAC for Kubernetes authorization"]
    AKS["AKS: aks-uvu-it3200-jordan<br/>One Standard_D4s_v4 node"]
    Workload["Namespace: it3200-lab<br/>NGINX Deployment and ClusterIP Service"]
    ClusterMI["AKS cluster managed identity"]
    KubeletMI["AKS kubelet managed identity"]
    ACR["Private image in Azure Container Registry<br/>lab/nginx:v1"]
    Browser["Local browser"]

    Personal -->|"Signs in"| Entra
    SP -->|"Client ID and temporary secret"| Entra
    Entra -->|"Authenticated identity"| Auth
    Auth -->|"Authorizes Kubernetes operations"| AKS
    AKS -->|"Runs"| Workload

    AKS --- ClusterMI
    ClusterMI -->|"Manages supporting Azure infrastructure"| Infrastructure["Azure networking and related resources"]

    AKS --- KubeletMI
    KubeletMI -->|"AcrPull scoped to this registry"| ACR
    ACR -->|"Container image"| Workload

    SP -->|"kubectl port-forward through the Kubernetes API"| Workload
    Browser -->|"localhost:8080"| Forward["Local port-forward process"]
    Forward -->|"Forwards traffic"| Workload
```

## Identity and Permission Assignments

| Identity | Permission | Scope | Purpose |
|---|---|---|---|
| Service principal | Azure Kubernetes Service Cluster User Role | AKS cluster | Retrieve user kubeconfig |
| Service principal | Azure Kubernetes Service RBAC Reader | AKS cluster | Read supported Kubernetes resources |
| Service principal | Azure Kubernetes Service RBAC Writer | `it3200-lab` namespace | Deploy and manage the lab workload |
| Personal user | Azure Kubernetes Service RBAC Reader | AKS cluster | Inspect Kubernetes resources for comparison and troubleshooting |
| Kubelet managed identity | AcrPull | ACR registry | Pull the application image |

The personal account also used its existing Azure permissions to provision
resources and assign roles. These Azure management permissions are separate
from Kubernetes resource authorization.

The AKS cluster managed identity manages supporting Azure infrastructure.
It is distinct from the kubelet identity used for registry image pulls.

## Temporary Namespace Permission

A custom role temporarily granted the personal user namespace read/write
permissions at the lab cluster scope. It was used to create `it3200-lab`.

After namespace creation, the temporary role assignment and custom role
definition were removed through Terraform.

## Security Decisions

- AKS uses Microsoft Entra authentication and Azure RBAC authorization.
- Local AKS accounts are disabled.
- The ACR administrator account is disabled.
- Deployment access is restricted to `it3200-lab`.
- The service principal cannot deploy in `default` or delete namespaces.
- Reader access does not grant core node reads or access to Secrets.
- Namespace Writer includes access to Secrets within its namespace.
- The service principal secret has a short, explicitly configured expiration.
- Terraform state, local variables, credentials, and saved plans are excluded
  from Git.
- The Deployment references an image digest to identify the exact image.
- ACR uses an authenticated public endpoint; no private endpoint was configured.

## Lab Limitations

The cluster has one node and is not highly available. It was successfully
deployed for this lab, despite the ambiguity encountered in published
system-pool sizing guidance.

AKS uses the Free control-plane tier. Worker nodes, disks, networking,
and the registry can still generate charges.

The application uses a ClusterIP Service and local port forwarding.
No public application load balancer was created.