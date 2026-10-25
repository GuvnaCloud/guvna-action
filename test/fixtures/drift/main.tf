# Test fixture for the action's end-to-end test. CI applies this, then edits
# the file outside Terraform so the next refresh-only plan reports drift.
# Uses only the local filesystem: no cloud account or credentials.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
}

resource "local_file" "managed" {
  filename        = "${path.module}/managed.txt"
  content         = "managed by terraform\n"
  file_permission = "0600"
}
