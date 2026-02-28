# Security Context module — determines allowed IP and security configurations
# Uses checkip.amazonaws.com to get the current public IP

# Fetch current public IP
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  # The response includes a newline, so we trim it and add /32 for a single IP
  my_ip_cidr = "${chomp(data.http.my_ip.response_body)}/32"
}

output "allowed_cidr" {
  description = "CIDR of the current machine's public IP (for ALB ingress restrictions)"
  value       = local.my_ip_cidr
}

output "allowed_ip" {
  description = "Current machine's public IP (without CIDR notation)"
  value       = chomp(data.http.my_ip.response_body)
}
