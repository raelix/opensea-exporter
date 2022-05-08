terraform {
  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "3.6.0"
    }
  }
}

variable "password" {
  description = "The keycloack admin password"
  sensitive = true
}

variable "user" {
  description = "The keycloack admin username"
  default = "user"
}

variable "url" {
  description = "The keycloack URL (e.g. http://raelix-cluster.duckdns.org)"
  default = "http://raelix-cluster.duckdns.org"
}

variable "grafana_url" {
  description = "The Grafana URL (e.g. http://raelix-cluster.duckdns.org/grafana)"
  default = "http://raelix-cluster.duckdns.org/grafana"
}

variable "realm" {
  default = "master"
  description = "The keycloack Realm to interact with (default: master)"
}

# configure keycloak provider
provider "keycloak" {
  client_id                = "admin-cli"
  username                 = var.user
  password                 = var.password
  url                      = var.url
  tls_insecure_skip_verify = true
}

locals {
  realm_id = var.realm
  groups   = ["grafana-dev", "grafana-admin"]
  user_groups = {
    user-dev   = ["grafana-dev"]
    user-admin = ["grafana-admin"]
  }
}

# create groups
resource "keycloak_group" "groups" {
  for_each = toset(local.groups)
  realm_id = local.realm_id
  name     = each.key
}
# create users
resource "keycloak_user" "users" {
  for_each       = local.user_groups
  realm_id       = local.realm_id
  username       = each.key
  enabled        = true
  email          = "${each.key}@domain.com"
  email_verified = true
  first_name     = each.key
  last_name      = each.key
  initial_password {
    value = each.key
  }
}
# configure use groups membership
resource "keycloak_user_groups" "user_groups" {
  for_each  = local.user_groups
  realm_id  = local.realm_id
  user_id   = keycloak_user.users[each.key].id
  group_ids = [for g in each.value : keycloak_group.groups[g].id]
}
# create groups openid client scope
resource "keycloak_openid_client_scope" "groups" {
  realm_id               = local.realm_id
  name                   = "groups"
  include_in_token_scope = true
  gui_order              = 1
}
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id        = local.realm_id
  client_scope_id = keycloak_openid_client_scope.groups.id
  name            = "groups"
  claim_name      = "groups"
  full_path       = false
}

resource "keycloak_openid_client" "grafana" {
  realm_id              = local.realm_id
  client_id             = "grafana"
  name                  = "grafana"
  enabled               = true
  access_type           = "CONFIDENTIAL"
  client_secret         = "grafana-client-secret"
  standard_flow_enabled = true
  valid_redirect_uris   = [
    format("%s/login/generic_oauth", var.grafana_url)
  ]
}

resource "keycloak_openid_client_default_scopes" "grafana" {
  realm_id  = local.realm_id
  client_id = keycloak_openid_client.grafana.id
  default_scopes = [
    "profile",
    "email",
    keycloak_openid_client_scope.groups.name,
  ]
}
