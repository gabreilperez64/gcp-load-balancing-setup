provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Unmanaged Instance Group
resource "google_compute_instance_group" "web_server_group" {
  name      = "ig-unmanaged-${replace(var.domain_name, ".", "-")}"
  zone      = var.zone
  instances = ["projects/${var.project_id}/zones/${var.zone}/instances/${var.vm_name}"]
}

# 2. Global Static IP
resource "google_compute_global_address" "lb_ip" {
  name = "lb-ip-${replace(var.domain_name, ".", "-")}"
}

# 3. Firewall Rule
resource "google_compute_firewall" "allow_lb_health_checks" {
  name    = "allow-lb-health-checks"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["health-checks"]
}

# 4. Health Check
resource "google_compute_health_check" "https_health_check" {
  name = "hc-https-${replace(var.domain_name, ".", "-")}"

  https_health_check {
    port = 443
  }
}

# 5. Backend Service
resource "google_compute_backend_service" "backend_service" {
  name                  = "bs-https-${replace(var.domain_name, ".", "-")}"
  protocol              = "HTTPS"
  health_checks         = [google_compute_health_check.https_health_check.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_instance_group.web_server_group.id
  }
}

# 6. Google-managed SSL Certificate
resource "google_compute_managed_ssl_certificate" "ssl_cert" {
  name = "ssl-cert-${replace(var.domain_name, ".", "-")}"

  managed {
    domains = [var.domain_name]
  }
}

# 7. URL Map (Main HTTPS)
resource "google_compute_url_map" "https_url_map" {
  name            = "lb-url-map-${replace(var.domain_name, ".", "-")}"
  default_service = google_compute_backend_service.backend_service.id
}

# 8. Target HTTPS Proxy
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "https-proxy-${replace(var.domain_name, ".", "-")}"
  url_map          = google_compute_url_map.https_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_cert.id]
  ssl_policy       = google_compute_ssl_policy.modern_ssl_policy.id
}

# 8.1 SSL Policy (Security Hardening)
resource "google_compute_ssl_policy" "modern_ssl_policy" {
  name            = "modern-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# 9. HTTPS Forwarding Rule
resource "google_compute_global_forwarding_rule" "https_forwarding_rule" {
  name                  = "https-forwarding-rule-${replace(var.domain_name, ".", "-")}"
  ip_address            = google_compute_global_address.lb_ip.address
  target                = google_compute_target_https_proxy.https_proxy.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# --- HTTP to HTTPS Redirect ---

# 10. URL Map for Redirect
resource "google_compute_url_map" "https_redirect" {
  name = "http-redirect-map-${replace(var.domain_name, ".", "-")}"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# 11. Target HTTP Proxy for Redirect
resource "google_compute_target_http_proxy" "http_redirect_proxy" {
  name    = "http-redirect-proxy-${replace(var.domain_name, ".", "-")}"
  url_map = google_compute_url_map.https_redirect.id
}

# 12. HTTP Forwarding Rule
resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name                  = "http-forwarding-rule-${replace(var.domain_name, ".", "-")}"
  ip_address            = google_compute_global_address.lb_ip.address
  target                = google_compute_target_http_proxy.http_redirect_proxy.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
