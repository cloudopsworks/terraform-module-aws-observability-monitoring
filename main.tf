##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  slo_in = try(var.settings.service_level_objectives, [])
  slo_operational = flatten([
    for slo in local.slo_in : [
      for operation in slo.service_level_indicator.operations : {
        name        = format("%s %s op", try(slo.name, slo.service_level_indicator.name), replace(operation, "/[\\/\\$\\%\\^]/", "-"))
        description = try(slo.description, "SLO Setting for ${try(slo.name, slo.service_level_indicator.name)} - ${operation}")
        sli = {
          comparisson_operator = try(slo.service_level_indicator.comparisson, "LessThan")
          metric_threshold     = try(slo.service_level_indicator.threshold, null)
          sli_metric = {
            key_attributes = {
              Environment = slo.service_level_indicator.environment
              Name        = slo.service_level_indicator.name
              Type        = slo.service_level_indicator.type
            }
            metric_type    = try(slo.service_level_indicator.metric_type, "LATENCY")
            operation_name = operation
            period_seconds = try(slo.service_level_indicator.period_seconds, 60)
            statistic      = try(slo.service_level_indicator.statistic, "p99")
          }
        }
        goal = {
          attainment_goal = try(slo.goal.attainment, 99.9)
          interval = {
            rolling_interval = {
              duration      = try(slo.goal.duration, 7)
              duration_unit = try(slo.goal.duration_unit, "DAY")
            }
          }
        }
        tags = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "operational"
  ])

  slo_all = concat(local.slo_operational, [])
}

resource "awscc_applicationsignals_service_level_objective" "slo" {
  for_each = {
    for slo in local.slo_all : slo.name => slo
  }
  name                     = each.value.name
  description              = each.value.description
  sli                      = try(each.value.sli, null)
  goal                     = try(each.value.goal, null)
  request_based_sli        = try(each.value.request_based_sli, null)
  burn_rate_configurations = try(each.value.burn_rate_configurations, null)
  exclusion_windows        = try(each.value.exclusion_windows, null)
  tags = toset([
    for k, v in merge(local.all_tags, each.value.tags) : {
      key   = k
      value = v
    }
  ])
}