variable "subscription_id" {
  description = "Azure subscription used for the lab."
  type        = string
}

variable "tenant_id" {
  description = "Microsoft Entra tenant containing the lab identities."
  type        = string
}

variable "student_name" {
  description = "Student name used in resource names: lowercase letters and numbers."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,20}$", var.student_name))
    error_message = "Use 2–20 lowercase letters or numbers."
  }
}

variable "location" {
  description = "Azure region for the lab; verify availability before deployment."
  type        = string
}

variable "node_vm_size" {
  description = "VM size for the lab's single AKS node."
  type        = string
  default     = "Standard_D4s_v4"
}

variable "sp_secret_end_date" {
  description = "Expiration of the temporary lab secret, in UTC RFC3339 format."
  type        = string
}