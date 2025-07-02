
-----

# Guide: Setting Up a Google Cloud HTTPS Load Balancer for a Windows IIS Server

This guide provides a complete walkthrough for configuring a Global External HTTPS Application Load Balancer on Google Cloud (GCP) to serve a website from a Windows Server running IIS. It includes steps for creating a Google-managed SSL certificate and enabling an automatic HTTP-to-HTTPS redirect.

## Assumptions

This guide assumes that you have already fully configured your Windows Server VM. This includes:

  * The Internet Information Services (IIS) role is installed.
  * Your website's files have been copied to the server (e.g., to `C:\inetpub\wwwroot\yoursite`).
  * An IIS site has been created and is pointing to your website's directory.
  * The IIS site has an **HTTPS binding on port 443** and is in a "Started" state.

The focus of this tutorial is on the Google Cloud networking infrastructure, not the initial IIS setup. If you need guidance on setting up a basic site in IIS, you can follow the official Microsoft tutorial: **[Scenario: Build a Static Website on IIS](https://learn.microsoft.com/en-us/iis/manage/creating-websites/scenario-build-a-static-website-on-iis)**.

-----

## Prerequisites

  * A Google Cloud project.
  * A running Windows Server Virtual Machine in GCP with IIS installed and the website configured.
  * A registered domain name.
  * Access to the Google Cloud Console or the `gcloud` command-line tool.

-----

## Step 1: Verify the Local IIS Server

Before configuring any cloud infrastructure, ensure the IIS server is correctly serving the website.

1.  Connect to your Windows VM. You can do this securely via the GCP Console using **RDP** or **IAP (Identity-Aware Proxy)**.

2.  Open PowerShell and test the local response using `curl.exe`. The `--resolve` flag forces the request to use the local machine's IP (127.0.0.1) while still sending the correct host header for your domain.

    ```powershell
    # Replace test-site.com with your actual domain
    curl.exe --insecure --resolve test-site.com:443:127.0.0.1 https://test-site.com/
    ```

3.  A successful test will return the HTML source code of your website.

-----

## Step 2: Create an Unmanaged Instance Group

The load balancer sends traffic to an instance group, not directly to a VM.

1.  In the Google Cloud Console, navigate to **Compute Engine \> Instance groups**.
2.  Click **Create instance group**.
3.  Select **New unmanaged instance group**.
4.  **Name** the group (e.g., `ig-unmanaged-server`).
5.  Select the **Region** and **Zone** where your Windows VM is located.
6.  Under **VM instances**, select your Windows server VM from the dropdown list.
7.  Click **Create**.

### A Note on Named Ports

You may see an option to add a "named port" to the instance group. This is an optional feature for abstraction, allowing you to give a port number (like `443`) a friendly name (like `https-port`). For this guide, we will skip this step as it's simpler and more direct to specify the port number `443` in the backend service configuration later.

### gcloud Commands

```bash
# Create the unmanaged instance group
gcloud compute instance-groups unmanaged create ig-unmanaged-server \
    --zone=YOUR_ZONE

# Add your VM to the group
gcloud compute instance-groups unmanaged add-instances ig-unmanaged-server \
    --zone=YOUR_ZONE \
    --instances=YOUR_VM_NAME
```

  * **`YOUR_ZONE`**: The zone where your VM is located (e.g., `us-east1-c`).
  * **`YOUR_VM_NAME`**: The name of your existing Windows VM (e.g., `server2`).

-----

## Step 3: Reserve a Global Static IP Address

A load balancer needs a permanent public IP address that won't change.

1.  Navigate to **VPC network \> IP addresses**.
2.  Click **Reserve external static address**.
3.  **Name** the IP address (e.g., `lb-ip-test-site`).
4.  Set the **Network Service Tier** to **Premium**.
5.  Set the **Type** to **Global**.
6.  Click **Reserve**. Note this IP address for your DNS records later.

### gcloud Command

```bash
gcloud compute addresses create lb-ip-test-site --global
```

-----

## Step 4: Create a Firewall Rule for Health Checks

Create a firewall rule to allow Google's health checkers and the load balancer itself to reach your VM.

1.  Navigate to **VPC network \> Firewall**.
2.  Click **Create Firewall Rule**.
3.  **Name:** `allow-lb-health-checks`
4.  **Direction:** `Ingress`
5.  **Targets:** `Specified target tags`.
6.  **Target tags:** Enter a tag that is on your Windows VM (e.g., `health-checks`). **Note:** Ensure this network tag is added to your VM instance.
7.  **Source IPv4 ranges:** Enter these two required ranges:
      * `130.211.0.0/22`
      * `35.191.0.0/16`
8.  **Protocols and ports:** Select **Specified protocols and ports**, check **TCP** and enter **`443`** (and `80` if needed).
9.  Click **Create**.

### gcloud Command

```bash
gcloud compute firewall-rules create allow-lb-health-checks \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:443,tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=health-checks
```

-----

## Step 5: Create the HTTPS Load Balancer

This involves configuring the three main components of the load balancer. Using the console is recommended as it automates creating multiple linked components.

1.  Navigate to **Network Services \> Load balancing** and click **Create load balancer**.
2.  Under **Type of load balancer**, choose **Application Load Balancer (HTTP/S)**.
3.  Under **Public facing or internal**, choose **Public facing (external)**.
4.  Under **Global or single region deployment**, choose **Global workloads**.
5.  Under **Load balancer generation**, choose **Global external Application Load Balancer** (the modern, recommended version).
6.  Click **Continue** and give the load balancer a **Name** (e.g., `lb-test-site-https`).

Now, proceed with the Frontend and Backend configuration.

### A. Frontend Configuration

  * **Protocol:** `HTTPS`
  * **IP address:** Select the static IP you reserved (e.g., `lb-ip-test-site`).
  * **Certificate:** To get a free, auto-renewing SSL certificate:
    1.  Click the **Certificate** dropdown and select **Create a new certificate**.
    2.  Give it a **Name** (e.g., `ssl-test-site`).
    3.  Select **Create Google-managed certificate**.
    4.  In the **Domains** field, enter your full domain name (e.g., `test-site.com`).
    5.  Click **Create**.
  * Check the box for ✅ **Enable HTTP to HTTPS redirect**. This is a best practice.

### B. Backend Configuration

  * **Backend type:** `Instance group`.
  * **Protocol:** `HTTPS`.
  * **Instance group:** Select the group created in Step 2.
  * **Port numbers:** `443`.
  * **Health Check:** To ensure the load balancer knows if your server is online:
    1.  Click the **Health Check** dropdown and select **Create a health check**.
    2.  Give it a **Name** (e.g., `hc-test-site-https`).
    3.  Set the **Protocol** to `HTTPS`.
    4.  Set the **Port** to `443`.
    5.  Click **Save**.

### gcloud Commands

Creating a load balancer with `gcloud` involves many steps. Here is a summary of the commands that the UI performs for you.

```bash
# 1. Create Health Check
gcloud compute health-checks create https hc-test-site-https --port 443

# 2. Create Backend Service
gcloud compute backend-services create bs-test-site-https \
    --protocol=HTTPS \
    --health-checks=hc-test-site-https \
    --global

# 3. Add Instance Group to Backend Service
gcloud compute backend-services add-backend bs-test-site-https \
    --instance-group=ig-unmanaged-server \
    --instance-group-zone=YOUR_ZONE \
    --global

# 4. Create Google-managed SSL certificate
gcloud compute ssl-certificates create ssl-test-site \
    --domains=test-site.com \
    --global

# 5. Create URL map for HTTPS traffic
gcloud compute url-maps create lb-test-site-https \
    --default-service bs-test-site-https

# 6. Create Target HTTPS Proxy
gcloud compute target-https-proxies create target-https-proxy-test-site \
    --url-map=lb-test-site-https \
    --ssl-certificates=ssl-test-site

# 7. Create HTTPS Forwarding Rule (Frontend)
gcloud compute forwarding-rules create https-forwarding-rule-test-site \
    --address=lb-ip-test-site \
    --target-https-proxy=target-https-proxy-test-site \
    --ports=443 \
    --global

# --- Commands for the HTTP to HTTPS Redirect ---

# 8. Create a URL map for the redirect
gcloud compute url-maps create lb-http-redirect-map \
    --default-url-redirect="https://test-site.com"

# 9. Create a Target HTTP Proxy for the redirect
gcloud compute target-http-proxies create http-redirect-proxy \
    --url-map=lb-http-redirect-map

# 10. Create the HTTP Forwarding Rule
gcloud compute forwarding-rules create http-forwarding-rule-test-site \
    --address=lb-ip-test-site \
    --target-http-proxy=http-redirect-proxy \
    --ports=80 \
    --global
```

-----

## Step 6: Update DNS Records

This is the final mandatory step to make your site live. This is done at your domain registrar, not in GCP.

1.  Go to your domain's DNS provider (e.g., GoDaddy, Namecheap, Cloud DNS).
2.  Create or update the **A record** for your domain (`test-site.com`).
3.  Set the value to the static IP address you reserved in Step 3.
4.  Save the changes.

-----

## Step 7: Important Note on Accessing the Site

### Why You Can't Access the Site Via IP Address

You will notice that you cannot access your website by visiting the load balancer's public IP address (e.g., `https://34.54.246.82`). This is expected behavior.

The Global Application Load Balancer is a sophisticated system that hosts many websites on shared infrastructure. It relies on a technology called **Server Name Indication (SNI)** to route traffic correctly.

  * When a browser connects to **`https://test-site.com`**, it sends the hostname `test-site.com` as part of the initial request. The load balancer sees this hostname, matches it to your SSL certificate, and directs traffic to your backend.
  * When a browser connects directly to the **IP address**, it does not send any hostname. The load balancer receives the request but has no idea which of the thousands of potential websites you want. Because it cannot match the request to a specific site, it drops the connection.

This is why **Step 6 (updating DNS) is mandatory**. The system is designed to work with domain names, not IP addresses.

-----

## Step 8: Verification

1.  **DNS Propagation:** Use a tool like [dnschecker.org](https://dnschecker.org/) to watch your new IP address propagate globally.

2.  **SSL Certificate Status:** Check the status of your certificate. It will change from `PROVISIONING` to `ACTIVE` once DNS is validated.

    ```bash
    gcloud compute ssl-certificates describe ssl-test-site --global --format="get(managed.status)"
    ```

3.  **Final Test:** Once DNS has propagated and the certificate is active, open a new incognito browser window and navigate to your domain: **`https://your-domain.com`**. Your site should load securely.
