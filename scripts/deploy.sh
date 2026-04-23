#!/bin/bash

# GCP Load Balancer Deployment Script for Windows IIS
# This script automates the steps outlined in the README.md

set -e # Exit on error

# --- Variables ---
# You can customize these or pass them as environment variables
ZONE="${ZONE:-us-east1-c}"
VM_NAME="${VM_NAME:-server2}"
DOMAIN="${DOMAIN:-test-site.com}"
PROJECT_ID=$(gcloud config get-value project)

# Component Names
IP_NAME="lb-ip-${DOMAIN//./-}"
IG_NAME="ig-unmanaged-${DOMAIN//./-}"
HC_NAME="hc-https-${DOMAIN//./-}"
BS_NAME="bs-https-${DOMAIN//./-}"
SSL_CERT_NAME="ssl-cert-${DOMAIN//./-}"
URL_MAP_NAME="lb-url-map-${DOMAIN//./-}"
HTTPS_PROXY_NAME="https-proxy-${DOMAIN//./-}"
FW_RULE_HTTPS="https-forwarding-rule-${DOMAIN//./-}"

REDIRECT_MAP_NAME="http-redirect-map-${DOMAIN//./-}"
REDIRECT_PROXY_NAME="http-redirect-proxy-${DOMAIN//./-}"
FW_RULE_HTTP="http-forwarding-rule-${DOMAIN//./-}"
FIREWALL_NAME="allow-lb-health-checks"

echo "--------------------------------------------------------"
echo "Deploying GCP Load Balancer for: $DOMAIN"
echo "Project: $PROJECT_ID"
echo "Zone: $ZONE"
echo "VM: $VM_NAME"
echo "--------------------------------------------------------"

# 1. Create Unmanaged Instance Group
echo "Creating Unmanaged Instance Group..."
gcloud compute instance-groups unmanaged create "$IG_NAME" --zone="$ZONE"
gcloud compute instance-groups unmanaged add-instances "$IG_NAME" --zone="$ZONE" --instances="$VM_NAME"

# 2. Reserve Global Static IP
echo "Reserving Global Static IP..."
gcloud compute addresses create "$IP_NAME" --global

# 3. Create Firewall Rule for Health Checks
echo "Creating Firewall Rule..."
# We try to create it, if it exists we skip
gcloud compute firewall-rules create "$FIREWALL_NAME" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:443,tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=health-checks || echo "Firewall rule already exists or failed to create."

# Ensure the VM has the tag
echo "Adding network tag to VM..."
gcloud compute instances add-tags "$VM_NAME" --zone="$ZONE" --tags=health-checks

# 4. Create Health Check
echo "Creating HTTPS Health Check..."
gcloud compute health-checks create https "$HC_NAME" --port 443

# 5. Create Backend Service
echo "Creating Backend Service..."
gcloud compute backend-services create "$BS_NAME" \
    --protocol=HTTPS \
    --health-checks="$HC_NAME" \
    --global

# 6. Add Instance Group to Backend Service
echo "Adding Instance Group to Backend Service..."
gcloud compute backend-services add-backend "$BS_NAME" \
    --instance-group="$IG_NAME" \
    --instance-group-zone="$ZONE" \
    --global

# 7. Create Google-managed SSL Certificate
echo "Creating SSL Certificate..."
gcloud compute ssl-certificates create "$SSL_CERT_NAME" \
    --domains="$DOMAIN" \
    --global

# 8. Create URL Map
echo "Creating URL Map..."
gcloud compute url-maps create "$URL_MAP_NAME" \
    --default-service "$BS_NAME"

# 9. Create Target HTTPS Proxy
echo "Creating Target HTTPS Proxy..."
gcloud compute target-https-proxies create "$HTTPS_PROXY_NAME" \
    --url-map="$URL_MAP_NAME" \
    --ssl-certificates="$SSL_CERT_NAME"

# 10. Create HTTPS Forwarding Rule
echo "Creating HTTPS Forwarding Rule..."
gcloud compute forwarding-rules create "$FW_RULE_HTTPS" \
    --address="$IP_NAME" \
    --target-https-proxy="$HTTPS_PROXY_NAME" \
    --ports=443 \
    --global

# --- HTTP to HTTPS Redirect ---
echo "Setting up HTTP to HTTPS redirect..."

# 11. Create URL map for redirect
gcloud compute url-maps create "$REDIRECT_MAP_NAME" \
    --default-url-redirect="https://$DOMAIN"

# 12. Create Target HTTP Proxy for redirect
gcloud compute target-http-proxies create "$REDIRECT_PROXY_NAME" \
    --url-map="$REDIRECT_MAP_NAME"

# 13. Create HTTP Forwarding Rule
gcloud compute forwarding-rules create "$FW_RULE_HTTP" \
    --address="$IP_NAME" \
    --target-http-proxy="$REDIRECT_PROXY_NAME" \
    --ports=80 \
    --global

echo "--------------------------------------------------------"
echo "Deployment Complete!"
IP_ADDRESS=$(gcloud compute addresses describe "$IP_NAME" --global --format="get(address)")
echo "Static IP Address: $IP_ADDRESS"
echo "Next Steps:"
echo "1. Point your A record for $DOMAIN to $IP_ADDRESS"
echo "2. Wait for SSL certificate to provision (can take up to 60 mins)"
echo "--------------------------------------------------------"
