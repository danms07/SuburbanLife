resource "google_project" "default" {
  count    = var.create_project ? 1 : 0
  provider = google-beta.no_user_project_override

  project_id          = var.project_id
  name                = var.project_name
  org_id              = var.org_id
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  auto_create_network = var.auto_create_network
  deletion_policy     = var.deletion_policy

  # Ensures the project appears cleanly inside the Firebase Console project list.
  labels = merge(var.project_labels, {
    firebase = "enabled"
  })
}

data "google_project" "existing" {
  count    = var.create_project ? 0 : 1
  provider = google-beta.no_user_project_override

  project_id = var.project_id
}

locals {
  project_id     = var.create_project ? google_project.default[0].project_id : data.google_project.existing[0].project_id
  project_number = var.create_project ? google_project.default[0].number : data.google_project.existing[0].number

  hosting_site_id  = coalesce(var.hosting_site_id, local.project_id)
  rtdb_instance_id = coalesce(var.rtdb_instance_id, "${local.project_id}-default-rtdb")

  # Firebase project, Identity Platform config, default RTDB, and default Hosting site
  # cannot be deleted independently via API once initialized, so DELETE falls back to ABANDON.
  singleton_deletion_policy = var.deletion_policy == "DELETE" ? "ABANDON" : var.deletion_policy

  normalized_android_sha1 = [for h in var.android_sha1_hashes : lower(replace(h, ":", ""))]
  normalized_android_sha256 = [for h in var.android_sha256_hashes : lower(replace(h, ":", ""))]
}

check "org_or_folder_mutually_exclusive" {
  assert {
    condition     = !(var.org_id != null && var.folder_id != null)
    error_message = "Set at most one of org_id or folder_id; GCP projects cannot belong to both simultaneously."
  }
}

check "wif_requires_docs_publisher_sa" {
  assert {
    condition     = var.github_repository == null || var.create_docs_publisher_service_account
    error_message = "github_repository is set for Workload Identity Federation, which requires create_docs_publisher_service_account = true."
  }
}

check "app_check_enforced_mobile_prereqs" {
  assert {
    condition = !(
      var.app_check_enforcement_mode == "ENFORCED" &&
      (length(var.android_sha256_hashes) == 0 || var.ios_team_id == null || trimspace(var.ios_team_id) == "")
    )
    error_message = "app_check_enforcement_mode is ENFORCED without both android_sha256_hashes and ios_team_id; mobile clients will fail requests unless Play Integrity and App Attest are registered."
  }
}
