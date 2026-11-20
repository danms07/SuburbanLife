resource "google_firebase_web_app" "default" {
  provider = google-beta

  project         = local.project_id
  display_name    = var.web_app_display_name
  deletion_policy = var.deletion_policy

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["apikeys.googleapis.com"],
  ]
}

resource "google_firebase_android_app" "default" {
  provider = google-beta

  project         = local.project_id
  display_name    = var.android_app_display_name
  package_name    = var.android_package_name
  sha1_hashes     = local.normalized_android_sha1
  sha256_hashes   = local.normalized_android_sha256
  deletion_policy = var.deletion_policy

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["apikeys.googleapis.com"],
  ]
}

resource "google_firebase_apple_app" "default" {
  provider = google-beta

  project         = local.project_id
  display_name    = var.ios_app_display_name
  bundle_id       = var.ios_bundle_id
  team_id         = var.ios_team_id
  app_store_id    = var.ios_app_store_id
  deletion_policy = var.deletion_policy

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["apikeys.googleapis.com"],
  ]
}

resource "google_firebase_hosting_site" "default" {
  provider = google-beta

  project         = local.project_id
  site_id         = local.hosting_site_id
  app_id          = google_firebase_web_app.default.app_id
  deletion_policy = local.hosting_site_id == local.project_id ? local.singleton_deletion_policy : var.deletion_policy

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["firebasehosting.googleapis.com"],
  ]
}

# Read generated Web SDK config after default Hosting, RTDB, Firestore, and Storage exist.
data "google_firebase_web_app_config" "default" {
  provider = google-beta

  project    = local.project_id
  web_app_id = google_firebase_web_app.default.app_id

  depends_on = [
    google_firebase_hosting_site.default,
    google_firestore_database.default,
    google_firebase_database_instance.default,
    google_firebase_storage_default_bucket.default,
  ]
}
