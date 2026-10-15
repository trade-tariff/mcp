# Rails secret_key_base. OAuth refresh tokens are encrypted with a key
# derived from it, so it must be the same on every task and stay the same
# across deploys. The value lives in Terraform state, so it does not change
# unless this resource is replaced. Replacing it makes all refresh tokens
# invalid, and every user must connect again.
resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}
