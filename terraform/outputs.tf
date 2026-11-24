output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.lab.name
}

output "aks_cluster_id" {
  value = azurerm_kubernetes_cluster.lab.id
}

output "acr_name" {
  value = azurerm_container_registry.lab.name
}

output "acr_login_server" {
  value = azurerm_container_registry.lab.login_server
}

output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id
}

output "tenant_id" {
  value = var.tenant_id
}

output "service_principal_client_id" {
  value = azuread_application.lab.client_id
}

output "service_principal_object_id" {
  value = azuread_service_principal.lab.object_id
}

output "service_principal_client_secret" {
  value     = azuread_application_password.lab.value
  sensitive = true
}