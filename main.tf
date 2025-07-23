##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {

}

resource "awscc_applicationsignals_service_level_objective" "slo" {
  for_each = {
    for slo in try(var.settings.service_level_objectives, []) : slo.name => slo if try(slo.enabled, true)
  }
  name                     = format("%s-%s", each.value.name, local.system_name)
  description              = try(each.value.description, "SLO Setting for ${each.value.name}")
  sli                      = try(each.value.sli, {})
  goal                     = try(each.value.goal, {})
  request_based_sli        = try(each.value.request_based_sli, {})
  burn_rate_configurations = try(each.value.burn_rate_configurations, [])
  exclusion_windows        = try(each.value.exclusion_windows, [])
  tags = toset([
    for k, v in local.all_tags : {
      key   = k
      value = v
    }
  ])
}