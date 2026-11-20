locals {
  auth_authorized_domains = distinct(concat(
    [
      "localhost",
      "${local.project_id}.firebaseapp.com",
      "${local.project_id}.web.app",
      "${local.hosting_site_id}.firebaseapp.com",
      "${local.hosting_site_id}.web.app",
    ],
    var.custom_domains,
    var.auth_extra_authorized_domains,
  ))
}

# Configure Firebase Authentication (Identity Platform) with Email/Password sign-in
# matching LoginScreen/SignupScreen and strict authorized OAuth/redirect domains.
resource "google_identity_platform_config" "default" {
  provider = google-beta

  project                    = local.project_id
  autodelete_anonymous_users = true
  authorized_domains         = local.auth_authorized_domains
  deletion_policy            = local.singleton_deletion_policy

  sign_in {
    allow_duplicate_emails = var.auth_allow_duplicate_emails

    email {
      enabled           = true
      password_required = true
    }

    anonymous {
      enabled = false
    }

    phone_number {
      enabled = false
    }
  }

  depends_on = [
    google_firebase_project.default,
    google_project_service.services["identitytoolkit.googleapis.com"],
    google_project_service.services["securetoken.googleapis.com"],
  ]
}
