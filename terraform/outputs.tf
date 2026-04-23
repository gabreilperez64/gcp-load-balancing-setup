output "load_balancer_ip" {
  description = "The static IP address of the load balancer."
  value       = google_compute_global_address.lb_ip.address
}

output "ssl_certificate_status" {
  description = "The status of the Google-managed SSL certificate."
  value       = google_compute_managed_ssl_certificate.ssl_cert.managed[0].status
}
