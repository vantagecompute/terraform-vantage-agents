terraform {
  # terraform_data needs 1.4. No providers are required: the module works over
  # SSH with provisioners only.
  required_version = ">= 1.4"
}
