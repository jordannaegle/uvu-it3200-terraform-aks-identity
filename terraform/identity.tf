data "azuread_client_config" "current" {}

resource "azuread_application" "lab" {
  display_name     = "app-${local.name_prefix}"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "lab" {
  client_id = azuread_application.lab.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "lab" {
  application_id = azuread_application.lab.id
  display_name   = "temporary-lab-secret"
  end_date       = var.sp_secret_end_date
}