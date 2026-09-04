locals {
  local_vars  = yamldecode(file("./inputs.yaml"))
  spoke_vars  = yamldecode(file(find_in_parent_folders("spoke-inputs.yaml")))
  region_vars = yamldecode(file(find_in_parent_folders("region-inputs.yaml")))
  env_vars    = yamldecode(file(find_in_parent_folders("env-inputs.yaml")))
  global_vars = yamldecode(file(find_in_parent_folders("global-inputs.yaml")))

  local_tags  = jsondecode(file("./local-tags.json"))
  spoke_tags  = jsondecode(file(find_in_parent_folders("spoke-tags.json")))
  region_tags = jsondecode(file(find_in_parent_folders("region-tags.json")))
  env_tags    = jsondecode(file(find_in_parent_folders("env-tags.json")))
  global_tags = jsondecode(file(find_in_parent_folders("global-tags.json")))

  tags = merge(
    local.global_tags,
    local.env_tags,
    local.region_tags,
    local.spoke_tags,
    local.local_tags
  )
}

include "root" {
  path = find_in_parent_folders("{{ .RootFileName }}")
}

# awscc is plugin-framework based: assume_role is a nested attribute assigned with "=", not
# a block as in the aws provider. Copying the aws block verbatim fails to parse.
generate "provider_awscc" {
  path      = "provider-awscc.g.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "awscc" {
  region = "${include.root.locals.region}"
  assume_role = {
    role_arn     = "${include.root.locals.sts_role_arn}"
    session_name = "terragrunt"
  }
}
EOF
}

terraform {
  source = "{{ .sourceUrl }}"
}

inputs = {
  is_hub     = {{ .is_hub }}
  org        = local.env_vars.org
  spoke_def  = local.spoke_vars.spoke
  {{- range .requiredVariables }}
  {{- if ne .Name "org" }}
  {{ .Name }} = local.local_vars.{{ .Name }}
  {{- end }}
  {{- end }}
  {{- range .optionalVariables }}
  {{- if not (eq .Name "extra_tags" "is_hub" "spoke_def" "org") }}
  {{- if eq .Name "monitor_groups" }}
  {{ .Name }} = try(local.local_vars.{{ .Name }}, local.local_vars.groups, {{ .DefaultValue }})
  {{- else if eq .Name "slo_settings" }}
  {{ .Name }} = try(local.local_vars.{{ .Name }}, local.local_vars.slos, {{ .DefaultValue }})
  {{- else if eq .Name "dashboard_settings" }}
  {{ .Name }} = try(local.local_vars.{{ .Name }}, local.local_vars.dashboards, {{ .DefaultValue }})
  {{- else }}
  {{ .Name }} = try(local.local_vars.{{ .Name }}, {{ .DefaultValue }})
  {{- end }}
  {{- end }}
  {{- end }}
  extra_tags = local.tags
}
