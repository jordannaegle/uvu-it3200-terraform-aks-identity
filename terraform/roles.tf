resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = azurerm_container_registry.lab.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id

  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "sp_cluster_user" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azuread_service_principal.lab.object_id

  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "sp_kubernetes_reader" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = azuread_service_principal.lab.object_id

  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "personal_kubernetes_reader" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = data.azuread_client_config.current.object_id
}





resource "azurerm_role_assignment" "sp_lab_writer" {
  scope                = "${azurerm_kubernetes_cluster.lab.id}/namespaces/it3200-lab"
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = azuread_service_principal.lab.object_id

  skip_service_principal_aad_check = true
}