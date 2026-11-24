# M9 Technical Report
Jordan Naegle — IT3200

## Executive Summary

I used Terraform to deploy Azure Kubernetes Service (AKS), Azure Container
Registry (ACR), a Microsoft Entra application and service principal, and
scoped Azure role assignments.

I deployed NGINX into the `it3200-lab` namespace using the service principal.
Kubernetes successfully pulled the image from my ACR, and I accessed the
application through `kubectl port-forward`.

Testing demonstrated that successful authentication and credential retrieval
do not automatically grant Kubernetes resource permissions.

## Architecture Overview

The environment uses West US 3 and contains:

- Resource group: `rg-uvu-it3200-jordan`
- AKS cluster: `aks-uvu-it3200-jordan`
- One `Standard_D4s_v4` worker node
- Basic-tier ACR: `acruvuit3200jordandc2b96`
- Microsoft Entra application and service principal
- Kubernetes namespace: `it3200-lab`
- NGINX Deployment and ClusterIP Service

See [Architecture and Identity Design](architecture.md) for the diagram,
identity flows, permissions, and limitations.

The service principal accesses the Kubernetes API. The separate kubelet
managed identity pulls images from ACR.

## Terraform Infrastructure

Terraform manages the resource group, AKS cluster, registry, application
registration, service principal, temporary secret, and Azure role assignments.

AzureRM manages Azure resources and role assignments. AzureAD manages the
Entra application identity. Provider versions are recorded in
`terraform/.terraform.lock.hcl`.

Kubernetes manifests manage the namespace, Deployment, and Service.
The image was imported into ACR using Azure CLI.

I ran `terraform fmt`, `terraform validate`, and reviewed deployment plans
before applying changes. The final verification plan reported no changes.

Evidence: [Insert successful apply and final no-change screenshot references.]

## Identity and Access Management

The environment separates four identities:

1. Personal Entra user: provisions infrastructure and performs comparison tests.
2. Service principal: authenticates independently and deploys the workload.
3. AKS cluster managed identity: manages supporting Azure infrastructure.
4. Kubelet managed identity: retrieves container images from ACR.

The service principal uses a temporary client secret. Its value is marked
sensitive in Terraform outputs, but remains present in local Terraform state.
State, local variable files, credentials, and saved plans are excluded from Git.

I used separate Azure CLI configuration and kubeconfig locations for the
service-principal tests to avoid confusing identities.

## AKS and ACR Integration

The registry uses standard registry RBAC permissions, with its administrator
account disabled.

Terraform grants `AcrPull` to the AKS kubelet identity at the registry scope.
The kubelet needs pull access because nodes retrieve container images before
starting application containers. The Kubernetes deployment identity does not
perform that image pull.

`AcrPush` would unnecessarily allow nodes to publish images. Contributor
would grant unnecessary resource-management permissions.

For an ABAC-enabled registry, the corresponding repository permissions must
be evaluated instead of assuming `AcrPull` applies.

Evidence: [Insert kubelet role-assignment screenshot.]

## Service Principal Authentication Testing

The service principal successfully authenticated to Azure and retrieved AKS
user credentials using its Cluster User role.

The initial `kubelogin convert-kubeconfig -l spn` command returned
`--client-id is required`. Supplying the client ID and tenant ID explicitly
completed conversion. The secret remained in an environment variable.

Before Kubernetes Reader access was assigned, listing namespaces, Pods, and
nodes returned Forbidden.

After Terraform assigned AKS RBAC Reader, namespaces and Pods became readable.
Core node listing remained Forbidden.

After assigning AKS RBAC Writer at the `it3200-lab` namespace scope:

| Test | Result |
|---|---|
| Create Deployments in `it3200-lab` | Allowed |
| Create Services in `it3200-lab` | Allowed |
| Create Deployments in `default` | Denied |
| Delete namespaces | Denied |

These results verified both required access and permission boundaries.

Evidence: [Insert before/after authentication and authorization screenshots.]

## Personal Account Troubleshooting Comparison

My personal identity retrieved AKS credentials but initially could not list
namespaces, Pods, or nodes. Existing Azure provisioning permissions did not
automatically grant Kubernetes resource access.

Terraform assigned my personal identity AKS RBAC Reader. After propagation,
namespace and Pod listing succeeded.

A temporary custom role permitted namespace reads and writes. I used it to
create `it3200-lab`, then removed the custom role and assignment using Terraform.

My personal identity had Reader access; the service principal additionally
had namespace-scoped Writer access.

One authorization test was accidentally run in the personal terminal.
Repeating it in the service-principal terminal produced the expected results.
This demonstrated why identity verification is an important troubleshooting step.

## Kubernetes Application Deployment

I imported the official NGINX `stable-alpine` image into ACR as `lab/nginx:v1`.

The Deployment references this digest:

`sha256:8eb2b5540eae779603cc3db84b3986a15ecb5308b54303146eee9837c137b51a`

The manifests specify one replica, resource requests and limits, a readiness
probe, and a ClusterIP Service.

Verification showed:

- Deployment Ready: 1/1
- Pod Ready: 1/1, Running, with zero restarts at verification
- Events confirming a successful pull from my ACR
- Successful NGINX page access through localhost port 8080

The forwarding process later lost its connection. That ended the local
forwarding session; it did not, by itself, establish a workload failure.

Evidence: [Insert workload, image-pull events, and browser screenshots.]

## Permission and Security Analysis

Cluster User permits retrieving user kubeconfig. AKS RBAC Reader and Writer
authorize Kubernetes operations. These serve different purposes.

Deployment permissions are restricted to the application namespace.
Writer includes access to namespace Secrets, so the scope is security-sensitive.

The deployment identity did not receive Owner or Cluster Admin.
Local cluster accounts and ACR administrator credentials were disabled.

The registry requires authentication but uses a public network endpoint.
The single-node configuration is a temporary lab design, not a highly available
production architecture.

## Troubleshooting Findings

### Observed Environment Restrictions

The school identity could not create an Entra application:
`403 Authorization_RequestDenied`.

The school subscription also reported a six-vCPU regional quota and rejected
the requested quota increase. `Standard_D2s_v5` was unavailable in West US 3.

A resource-group name also already existed outside the project's Terraform
state. I did not import or delete that group.

I switched to my personal account, which had a different tenant and subscription.
I updated the variables, verified quota and SKU availability, and generated
a fresh plan. Deployment then succeeded.

### Scenario A — Authentication Succeeds, Kubernetes Access Fails

This was observed during the lab.

Possible cause: the identity authenticates successfully but lacks the relevant
Kubernetes data-plane role or has a role assigned at the wrong scope.

Investigation: verify the active identity, role assignments, cluster authorization
configuration, and `kubectl auth can-i` results.

Evidence: Azure login and credential retrieval succeeded while resource requests
returned Forbidden. Reader assignment subsequently enabled namespace and Pod reads.

Resolution: assign the required role through Terraform at the appropriate scope.

Prevention: document role purposes and test both allowed and denied operations
in deployment pipelines.

### Scenario B — ImagePullBackOff

This is a hypothetical investigation; my image pull succeeded.

Possible causes: missing pull permission, wrong kubelet identity, incorrect image
hostname or digest, missing image, network restrictions, or DNS failure.

Commands: `kubectl describe pod`, `kubectl get events`, ACR repository inspection,
and Azure role-assignment inspection.

Evidence: authentication errors suggest access problems; manifest-not-found errors
suggest an incorrect image reference; timeouts suggest connectivity problems.

Resolution: correct the specific cause, then retry the workload and verify a
successful Pulled event.

Prevention: manage registry permissions through Terraform, verify image existence,
pin image digests, and run deployment smoke tests.

### Scenario D — Excessive Permissions

This is a hypothetical design review.

Assigning Cluster Admin to every deployment identity would conceal missing
permission design and allow unnecessary cluster-wide operations.

Investigation: inspect role scopes and test operations inside and outside the
application namespace.

Evidence: an identity can perform administrative operations unrelated to its task.

Resolution: replace broad grants with namespace-scoped deployment permissions
and remove temporary access.

Prevention: review role assignments, separate environments and deployment identities,
and automate negative authorization tests.

## AI Assistance and Validation

I used ChatGPT for step-by-step guidance, Terraform configuration, permission
research, and troubleshooting.

Representative prompts included:
- “Review the assignment open in the browser and then walk me through
  accomplishing it step by step.”
- “Can we get away without increasing?”
- Pasted Terraform and Kubernetes errors requesting the next troubleshooting step.

I validated recommendations using provider documentation, Terraform validation
and plans, actual Azure deployment, authorization tests, Pod events, and browser access.

Some recommendations required correction, including the initial VM-size suggestion,
the need for a quota increase for the proposed two-node design, the deprecated
secret-expiration argument, and kubelogin's required client-ID argument.
This reinforced the need to verify AI-generated instructions.

## Conclusion and Lessons Learned

The lab demonstrated successful Terraform provisioning, Entra authentication,
scoped Kubernetes authorization, private-registry image pulls, and workload access.

The most important lesson was to distinguish identity authentication, Azure
management permissions, Kubernetes authorization, and kubelet registry access.

At larger scale, I would use reusable Terraform modules, separate environment
scopes, managed identities or federated CI/CD authentication, reviewed role
assignments, controlled image promotion, and automated security and deployment tests.

## Resource Cleanup

I reviewed and applied a Terraform destroy plan covering 11 lab resources.
The operation completed successfully.

Azure CLI returned `false` for both the lab resource group and the
AKS-managed node resource group. `terraform state list` returned no resources.

The deployment, registry, application identity, temporary credential, and
Terraform-managed role assignments were removed.