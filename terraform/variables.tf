variable "create_project" {
  type        = bool
  description = "When true, Terraform creates a new GCP project. Set to false to configure an existing GCP project."
  default     = true
}

variable "project_id" {
  type        = string
  description = "Globally unique GCP/Firebase project ID (6-30 lowercase letters, digits, or hyphens)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "project_name" {
  type        = string
  description = "Human-readable GCP/Firebase project display name (used when create_project = true)."
  default     = "Suburban Life"

  validation {
    condition     = length(trimspace(var.project_name)) >= 4 && length(var.project_name) <= 30
    error_message = "project_name must be between 4 and 30 characters to satisfy GCP project naming limits."
  }
}

variable "org_id" {
  type        = string
  description = "Numeric Google Cloud Organization ID under which a new project is created (mutually exclusive with folder_id)."
  default     = null

  validation {
    condition     = var.org_id == null || can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be null or a numeric Google Cloud Organization ID."
  }
}

variable "folder_id" {
  type        = string
  description = "Numeric Google Cloud Folder ID under which a new project is created (mutually exclusive with org_id)."
  default     = null

  validation {
    condition     = var.folder_id == null || can(regex("^[0-9]+$", var.folder_id))
    error_message = "folder_id must be null or a numeric Google Cloud Folder ID."
  }
}

variable "billing_account" {
  type        = string
  description = "Cloud Billing Account ID (e.g., 012345-6789AB-CDEF01). Required for Blaze plan services (Gen 2 Cloud Functions, Cloud Scheduler, Artifact Registry, Identity Platform, Vertex AI)."
  default     = null

  validation {
    condition     = var.billing_account == null || can(regex("^[0-9A-Za-z-]+$", var.billing_account))
    error_message = "billing_account must be null or an alphanumeric Billing Account ID (with hyphens)."
  }
}

variable "auto_create_network" {
  type        = bool
  description = "Whether GCP creates the default VPC network during project creation."
  default     = true
}

variable "project_labels" {
  type        = map(string)
  description = "Additional GCP labels applied to the created project (firebase = \"enabled\" is always merged)."
  default     = {}
}

variable "deletion_policy" {
  type        = string
  description = "Deletion protection policy applied to mutable resources (PREVENT for production safety, ABANDON, or DELETE)."
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "ABANDON", "DELETE"], var.deletion_policy)
    error_message = "deletion_policy must be one of PREVENT, ABANDON, or DELETE."
  }
}

variable "firestore_location" {
  type        = string
  description = "Cloud Firestore (default) database location (e.g., nam5, eur3, us-central1)."
  default     = "nam5"

  validation {
    condition     = length(trimspace(var.firestore_location)) > 0
    error_message = "firestore_location must not be empty."
  }
}

variable "firestore_delete_protection_enabled" {
  type        = bool
  description = "Enable Firestore database-level delete protection."
  default     = true
}

variable "firestore_point_in_time_recovery_enabled" {
  type        = bool
  description = "Enable Firestore Point-in-Time Recovery (PITR) backups."
  default     = true
}

variable "rtdb_region" {
  type        = string
  description = "Firebase Realtime Database region (e.g., us-central1, europe-west1, asia-southeast1)."
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9-]+$", var.rtdb_region))
    error_message = "rtdb_region must be a valid Firebase RTDB region identifier (e.g., us-central1)."
  }
}

variable "rtdb_instance_id" {
  type        = string
  description = "Optional custom default RTDB instance ID. Defaults to <project_id>-default-rtdb."
  default     = null

  validation {
    condition     = var.rtdb_instance_id == null || can(regex("^[a-z][a-z0-9-]{2,62}$", var.rtdb_instance_id))
    error_message = "rtdb_instance_id must be null or a valid lowercase Firebase RTDB instance identifier."
  }
}

variable "storage_location" {
  type        = string
  description = "Location for the default Firebase Cloud Storage bucket (e.g., US, EU, US-CENTRAL1)."
  default     = "US"

  validation {
    condition     = length(trimspace(var.storage_location)) > 0
    error_message = "storage_location must not be empty."
  }
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the Firebase Web App."
  default     = "Suburban Life Web"
}

variable "android_app_display_name" {
  type        = string
  description = "Display name for the Firebase Android App."
  default     = "Suburban Life Android"
}

variable "android_package_name" {
  type        = string
  description = "Android applicationId matching android/app/build.gradle.kts."
  default     = "com.example.suburban_life"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$", var.android_package_name))
    error_message = "android_package_name must be a valid reverse-domain Android applicationId."
  }
}

variable "android_sha1_hashes" {
  type        = list(string)
  description = "SHA-1 signing certificate fingerprints (40 hex chars) for the Android App."
  default     = []

  validation {
    condition     = alltrue([for h in var.android_sha1_hashes : can(regex("^[0-9A-Fa-f]{40}$", replace(h, ":", "")))])
    error_message = "Each entry in android_sha1_hashes must be a valid 40-character hexadecimal SHA-1 fingerprint."
  }
}

variable "android_sha256_hashes" {
  type        = list(string)
  description = "SHA-256 signing certificate fingerprints (64 hex chars) required by Android Play Integrity App Check."
  default     = []

  validation {
    condition     = alltrue([for h in var.android_sha256_hashes : can(regex("^[0-9A-Fa-f]{64}$", replace(h, ":", "")))])
    error_message = "Each entry in android_sha256_hashes must be a valid 64-character hexadecimal SHA-256 fingerprint."
  }
}

variable "ios_app_display_name" {
  type        = string
  description = "Display name for the Firebase Apple/iOS App."
  default     = "Suburban Life iOS"
}

variable "ios_bundle_id" {
  type        = string
  description = "Apple bundle identifier matching ios/Runner.xcodeproj/project.pbxproj."
  default     = "com.example.suburbanLife"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*(\\.[a-zA-Z0-9-]+)+$", var.ios_bundle_id))
    error_message = "ios_bundle_id must be a valid Apple bundle identifier."
  }
}

variable "ios_team_id" {
  type        = string
  description = "10-character Apple Developer Team ID (required to register Apple App Attest in App Check)."
  default     = null

  validation {
    condition     = var.ios_team_id == null || can(regex("^[A-Z0-9]{10}$", var.ios_team_id))
    error_message = "ios_team_id must be null or a 10-character uppercase alphanumeric Apple Developer Team ID."
  }
}

variable "ios_app_store_id" {
  type        = string
  description = "Optional numeric Apple App Store ID for the iOS App."
  default     = null

  validation {
    condition     = var.ios_app_store_id == null || can(regex("^[0-9]+$", var.ios_app_store_id))
    error_message = "ios_app_store_id must be null or numeric."
  }
}

variable "hosting_site_id" {
  type        = string
  description = "Optional Firebase Hosting site ID. Defaults to var.project_id."
  default     = null

  validation {
    condition     = var.hosting_site_id == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.hosting_site_id))
    error_message = "hosting_site_id must be null or a valid lowercase DNS label."
  }
}

variable "custom_domains" {
  type        = list(string)
  description = "Optional production custom web hostnames (e.g., portal.example.com) added to Auth authorized domains, strict Storage CORS, and reCAPTCHA Enterprise allow-lists."
  default     = []

  validation {
    condition = alltrue([
      for d in var.custom_domains :
      can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", d)) && !strcontains(d, "*")
    ])
    error_message = "Each custom_domains entry must be a bare hostname without protocol, port, path, or wildcards."
  }
}

variable "auth_allow_duplicate_emails" {
  type        = bool
  description = "Whether Firebase Authentication permits multiple accounts with the same email address."
  default     = false
}

variable "auth_extra_authorized_domains" {
  type        = list(string)
  description = "Additional hostnames authorized for Firebase Authentication redirects."
  default     = []
}

variable "app_check_enforcement_mode" {
  type        = string
  description = "App Check enforcement mode across Firestore, Storage, RTDB, and Identity Toolkit (UNENFORCED collects metrics safely; switch to ENFORCED after configuring client tokens/keys)."
  default     = "UNENFORCED"

  validation {
    condition     = contains(["UNENFORCED", "ENFORCED"], var.app_check_enforcement_mode)
    error_message = "app_check_enforcement_mode must be UNENFORCED or ENFORCED."
  }
}

variable "app_check_token_ttl" {
  type        = string
  description = "Duration string for exchanged App Check tokens (between 30m/1800s and 7d/604800s)."
  default     = "3600s"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]{1,9})?s$", var.app_check_token_ttl)) && tonumber(trimsuffix(var.app_check_token_ttl, "s")) >= 1800 && tonumber(trimsuffix(var.app_check_token_ttl, "s")) <= 604800
    error_message = "app_check_token_ttl must be formatted in seconds ending with 's' between 1800s and 604800s."
  }
}

variable "recaptcha_display_name" {
  type        = string
  description = "Display name for the reCAPTCHA Enterprise Web site key used by Firebase App Check."
  default     = "Suburban Life Web App Check"
}

variable "recaptcha_extra_allowed_domains" {
  type        = list(string)
  description = "Additional bare domains permitted on the reCAPTCHA Enterprise key (for example, localhost if testing against a cloud project without the emulator)."
  default     = []

  validation {
    condition = alltrue([
      for d in var.recaptcha_extra_allowed_domains :
      !strcontains(d, "*") && !strcontains(d, "://") && !strcontains(d, "/")
    ])
    error_message = "recaptcha_extra_allowed_domains entries must be bare hostnames without schemes, paths, or wildcards."
  }
}

variable "enable_storage_bucket_config_provisioner" {
  type        = bool
  description = "When true, runs gcloud storage buckets update after bucket creation to apply ../storage_lifecycle.json and non-wildcard Web CORS rules."
  default     = false
}

variable "enable_rtdb_rules_provisioner" {
  type        = bool
  description = "When true, runs firebase deploy --only database after RTDB creation to deploy ../database.rules.json."
  default     = false
}

variable "extra_cors_origins" {
  type        = list(string)
  description = "Additional explicit HTTPS (or local dev http://localhost:<port>) origins added to strict Storage CORS alongside Hosting and custom_domains."
  default     = []

  validation {
    condition = alltrue([
      for o in var.extra_cors_origins :
      can(regex("^https?://[^\\s*]+$", o))
    ])
    error_message = "extra_cors_origins must contain explicit http(s):// origins without wildcards."
  }
}

variable "functions_service_account_id" {
  type        = string
  description = "Account ID for the dedicated least-privilege Cloud Functions Gen 2 runtime service account."
  default     = "suburban-life-functions"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.functions_service_account_id))
    error_message = "functions_service_account_id must be 6-30 lowercase alphanumeric characters or hyphens."
  }
}

variable "grant_default_compute_sa_permissions" {
  type        = bool
  description = "Optional compatibility fallback: enables compute.googleapis.com and grants the Gen 2 runtime roles to the default Compute Engine service account. Keep false if deploying functions explicitly with the dedicated runtime service account."
  default     = false
}

variable "create_docs_publisher_service_account" {
  type        = bool
  description = "Create a least-privilege service account (Firestore + default Storage bucket access) for scripts/build_and_publish_docs.js."
  default     = true
}

variable "docs_publisher_service_account_id" {
  type        = string
  description = "Account ID for the documentation publishing automation service account."
  default     = "suburban-life-docs-publisher"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.docs_publisher_service_account_id))
    error_message = "docs_publisher_service_account_id must be 6-30 lowercase alphanumeric characters or hyphens."
  }
}

variable "github_repository" {
  type        = string
  description = "Optional GitHub repository slug (owner/repo) to configure keyless OIDC Workload Identity Federation for the docs publisher service account."
  default     = null

  validation {
    condition     = var.github_repository == null || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be null or formatted as owner/repo."
  }
}

variable "github_branch" {
  type        = string
  description = "Git branch permitted by the Workload Identity Provider attribute condition."
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.github_branch))
    error_message = "github_branch must be a valid Git branch name."
  }
}

variable "github_wif_pool_id" {
  type        = string
  description = "Workload Identity Pool ID for keyless GitHub Actions authentication."
  default     = "github-actions-pool"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.github_wif_pool_id)) && !startswith(var.github_wif_pool_id, "gcp-")
    error_message = "github_wif_pool_id must be 4-32 lowercase characters/digits/hyphens and not start with gcp-."
  }
}

variable "github_wif_provider_id" {
  type        = string
  description = "Workload Identity Pool Provider ID for GitHub Actions OIDC."
  default     = "github-actions-oidc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.github_wif_provider_id)) && !startswith(var.github_wif_provider_id, "gcp-")
    error_message = "github_wif_provider_id must be 4-32 lowercase characters/digits/hyphens and not start with gcp-."
  }
}
