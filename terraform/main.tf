locals {
  name_prefix = "uvu-it3200-${var.student_name}"

  # Stable suffix to reduce globally unique registry-name collisions.
  acr_suffix = substr(
    sha256("${var.subscription_id}-${var.student_name}"),
    0,
    6
  )

  tags = {
    course      = "IT3200"
    assignment  = "M9"
    environment = "lab"
    student     = var.student_name
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.name_prefix}"
  location = var.location

  tags = local.tags
}

resource "azurerm_container_registry" "lab" {
  name                = "acruvuit3200${var.student_name}${local.acr_suffix}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location

  sku                  = "Basic"
  admin_enabled        = false
  role_assignment_mode = "LegacyRegistryPermissions"

  tags = local.tags
}

resource "azurerm_kubernetes_cluster" "lab" {
  name                = "aks-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  dns_prefix          = "aks-${local.name_prefix}"

  sku_tier                          = "Free"
  role_based_access_control_enabled = true
  local_account_disabled            = true

  default_node_pool {
    name                 = "system"
    node_count           = 1
    vm_size              = var.node_vm_size
    auto_scaling_enabled = false
    os_disk_type         = "Managed"
    os_disk_size_gb      = 64
    os_sku               = "Ubuntu"
    max_pods             = 30
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 30
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = var.tenant_id
    azure_rbac_enabled = true
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  tags = local.tags
}