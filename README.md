# IT3200 M9 — AKS, Container Registry, and Identity Management

This project uses Terraform to provision an Entra-integrated AKS cluster,
Azure Container Registry, an application/service principal, and scoped Azure
role assignments.

A Kubernetes Deployment runs NGINX from the private registry in `it3200-lab`.

## Documentation

- [Architecture and identity design](docs/architecture.md)
- [Technical report and troubleshooting](docs/technical-report.md)
- [Evidence](docs/evidence/)

Additional screenshots may be stored in the repository root.

## Prerequisites

Install Terraform, Azure CLI, kubectl, Microsoft kubelogin, and Git.

Your chosen tenant/subscription must permit:

- Entra application, service-principal, and credential creation
- AKS and ACR deployment
- Azure role assignments and custom role definitions
- A supported node SKU with sufficient regional and VM-family CPU quota

This lab successfully deployed one `Standard_D4s_v4` node in `westus3`.
Availability and permissions must be checked for each subscription.

The configuration is for a temporary lab, not a highly available production cluster.
AKS Free tier does not eliminate worker-node, disk, registry, or networking charges.

## 1. Configure Terraform

Clone this repository and enter its `terraform` directory.

```powershell
az login
az account list --output table
az account set --subscription "<your-subscription-id>"

Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit the local `terraform.tfvars` with your subscription ID, tenant ID,
student name, permitted region, and a future UTC secret-expiration timestamp.

Use this command to generate an expiration seven days ahead:

```powershell
(Get-Date).ToUniversalTime().AddDays(7).ToString("yyyy-MM-ddTHH:mm:ssZ")
```

Local `.tfvars`, Terraform state, saved plans, and credentials must not be committed.
Commit `.terraform.lock.hcl` to record provider versions.

## 2. Deploy Azure Infrastructure

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan "-out=deploy.tfplan"
terraform apply "deploy.tfplan"
```

Review the plan before applying. Application-registration permissions and
resource availability are ultimately verified by Azure during deployment.

## 3. Bootstrap the Kubernetes Namespace

In the personal-account Terraform terminal, create a temporary file named
`temporary_namespace.tf` containing:

```hcl
resource "azurerm_role_definition" "namespace_provisioner" {
  name        = "namespace-provisioner-${local.name_prefix}"
  scope       = azurerm_resource_group.lab.id
  description = "Temporary namespace provisioning permission."

  permissions {
    actions = []

    data_actions = [
      "Microsoft.ContainerService/managedClusters/namespaces/read",
      "Microsoft.ContainerService/managedClusters/namespaces/write"
    ]
  }

  assignable_scopes = [azurerm_resource_group.lab.id]
}

resource "azurerm_role_assignment" "personal_namespace_provisioner" {
  scope              = azurerm_kubernetes_cluster.lab.id
  role_definition_id = azurerm_role_definition.namespace_provisioner.role_definition_resource_id
  principal_id       = data.azuread_client_config.current.object_id
}
```

Plan, review, and apply those two temporary resources.

Then obtain a dedicated personal kubeconfig:

```powershell
$labPersonalDirectory = Join-Path $env:TEMP ("it3200-personal-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $labPersonalDirectory | Out-Null
$env:KUBECONFIG = Join-Path $labPersonalDirectory "kubeconfig"

$labResourceGroup = terraform output -raw resource_group_name
$labClusterName = terraform output -raw aks_cluster_name

az aks get-credentials --resource-group $labResourceGroup --name $labClusterName --file "$env:KUBECONFIG"
kubelogin convert-kubeconfig -l azurecli
kubectl apply -f ..\k8\namespace.yaml
```

Allow time for role propagation if access is initially denied.

After namespace creation, delete only `temporary_namespace.tf`.
Review and apply a new Terraform plan that removes the temporary assignment
and custom role definition. The namespace remains.

The final configuration retains namespace-scoped Writer access for the
service principal.

## 4. Import the Application Image

Use the personal-account terminal:

```powershell
$labAcrName = terraform output -raw acr_name

az acr import --name $labAcrName --source docker.io/library/nginx:stable-alpine --image lab/nginx:v1

az acr repository show-tags --name $labAcrName --repository lab/nginx --detail --output table

terraform output -raw acr_login_server
```

Update the `image` field in `k8/deployment.yaml` to use your registry hostname
and the digest reported by your import:

`<registry-hostname>/lab/nginx@sha256:<digest>`

The committed manifest records the original lab deployment. Its registry
hostname and digest must be adjusted when reproducing in another environment.

## 5. Authenticate as the Service Principal

Open a separate PowerShell terminal in the `terraform` directory.

```powershell
$env:AZURE_CLIENT_ID = terraform output -raw service_principal_client_id
$env:AZURE_CLIENT_SECRET = terraform output -raw service_principal_client_secret
$env:AZURE_TENANT_ID = terraform output -raw tenant_id
$env:AAD_SERVICE_PRINCIPAL_CLIENT_SECRET = $env:AZURE_CLIENT_SECRET

$labResourceGroup = terraform output -raw resource_group_name
$labClusterName = terraform output -raw aks_cluster_name

$labTestDirectory = Join-Path $env:TEMP ("it3200-sp-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $labTestDirectory | Out-Null

$env:AZURE_CONFIG_DIR = Join-Path $labTestDirectory "azure"
$env:KUBECONFIG = Join-Path $labTestDirectory "kubeconfig"

az login --service-principal --username "$env:AZURE_CLIENT_ID" "--password=$env:AZURE_CLIENT_SECRET" --tenant "$env:AZURE_TENANT_ID" --output none

az aks get-credentials --resource-group $labResourceGroup --name $labClusterName --file "$env:KUBECONFIG"

kubelogin convert-kubeconfig -l spn --client-id "$env:AZURE_CLIENT_ID" --tenant-id "$env:AZURE_TENANT_ID"
```

Do not print the secret or include it in kubeconfig, screenshots, or documentation.

## 6. Verify Permissions and Deploy

In the service-principal terminal:

```powershell
kubectl auth can-i create deployments -n it3200-lab
kubectl auth can-i create services -n it3200-lab
kubectl auth can-i create deployments -n default
kubectl auth can-i delete namespaces
```

Expected: yes, yes, no, no.

```powershell
kubectl apply -f ..\k8\deployment.yaml
kubectl apply -f ..\k8\service.yaml

kubectl rollout status deployment/lab-nginx -n it3200-lab --timeout=180s
kubectl get deployments,pods,services -n it3200-lab
kubectl describe pods -l app=lab-nginx -n it3200-lab

kubectl port-forward service/lab-nginx 8080:80 -n it3200-lab
```

Open http://localhost:8080 while forwarding runs. Capture the running workload,
successful ACR pull events, and NGINX page.

The report documents the original staged tests before Reader and Writer
permissions were assigned. Reproducing the final configuration starts with
those final permissions already assigned.

## 7. Cleanup

After capturing evidence, use the personal-account Terraform terminal:

```powershell
terraform plan -destroy "-out=cleanup.tfplan"
terraform apply "cleanup.tfplan"
```

Review the destruction plan first. It must contain only this lab's resources.

Verify deletion of the cluster, registry, resource group, application,
service principal, and credentials. Check for remaining AKS-managed resources.

Close the service-principal test terminal after testing to discard its
process-local credential environment variables.