# Default provider charges API quota against each resource's target project.
provider "google-beta" {
  user_project_override = true
}

# Used exclusively for project creation/lookup and bootstrap Service Usage calls
# before quota override is available on a newly provisioned project.
provider "google-beta" {
  alias                 = "no_user_project_override"
  user_project_override = false
}
