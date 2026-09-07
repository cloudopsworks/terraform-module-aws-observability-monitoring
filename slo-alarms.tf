##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  slo_alarm_map = {
    for slo in local.slo_all : slo.name => {
      alarm = {
        priority                 = coalesce(try(slo.alarm.priority, null), 1)
        threshold                = coalesce(try(slo.alarm.threshold, null), 1)
        datapoints_to_alarm      = coalesce(try(slo.alarm.datapoints_to_alarm, null), 1)
        period                   = coalesce(try(slo.alarm.period, null), 60)
        look_back_window_minutes = coalesce(try(slo.alarm.look_back_window_minutes, null), 60)
      }
      alarm_name = format(
        "[P%s] [SLO] [%s] [%s] [%s] %s - %s - %s",
        coalesce(try(slo.alarm.priority, null), 1),
        lower(var.org.organization_unit),
        lower(var.org.environment_name),
        try(local.slo_service_inventory[coalesce(try(slo.source_service_key, null), format("custom:%s", slo.name))].service_name, slo.name),
        slo.name,
        split(":", coalesce(try(slo.source_service_key, null), format("custom:%s", slo.name)))[0],
        lower(var.org.environment_type)
      )
      name         = slo.name
      service_key  = coalesce(try(slo.source_service_key, null), format("custom:%s", slo.name))
      service_name = try(local.slo_service_inventory[coalesce(try(slo.source_service_key, null), format("custom:%s", slo.name))].service_name, slo.name)
      slo_key      = slo.slo_key
      tags         = try(slo.tags, {})
    }
    if try(slo.alarm.enabled, false)
  }

  slo_alarm_names_by_service = {
    for service_key in toset([for alarm in values(local.slo_alarm_map) : alarm.service_key]) : service_key => {
      for slo_name, alarm in aws_cloudwatch_metric_alarm.slo : local.slo_alarm_map[slo_name].slo_key => alarm.alarm_name
      if local.slo_alarm_map[slo_name].service_key == service_key
    }
  }

  slo_alarm_arns_by_service = {
    for service_key in toset([for alarm in values(local.slo_alarm_map) : alarm.service_key]) : service_key => {
      for slo_name, alarm in aws_cloudwatch_metric_alarm.slo : local.slo_alarm_map[slo_name].slo_key => alarm.arn
      if local.slo_alarm_map[slo_name].service_key == service_key
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "slo" {
  for_each = local.slo_alarm_map

  alarm_name          = each.value.alarm_name
  alarm_description   = format("Application Signals burn rate alarm for SLO %s.", each.value.name)
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = each.value.alarm.datapoints_to_alarm
  datapoints_to_alarm = each.value.alarm.datapoints_to_alarm
  period              = each.value.alarm.period
  metric_name         = "BurnRate"
  namespace           = "AWS/ApplicationSignals"
  statistic           = "Maximum"
  threshold           = each.value.alarm.threshold
  treat_missing_data  = "missing"
  actions_enabled     = (length(local.alarm_actions) + length(local.ok_actions)) > 0
  alarm_actions       = local.alarm_actions
  ok_actions          = local.ok_actions

  dimensions = {
    SloName               = awscc_applicationsignals_service_level_objective.slo[each.key].name
    BurnRateWindowMinutes = tostring(each.value.alarm.look_back_window_minutes)
  }

  tags = merge(
    local.all_tags,
    each.value.tags,
    {
      "alarm-kind"     = "slo-burn-rate"
      "alarm-priority" = tostring(each.value.alarm.priority)
      "service-key"    = each.value.service_key
      "service-name"   = each.value.service_name
      "slo-name"       = each.value.name
    }
  )

  lifecycle {
    precondition {
      condition     = each.value.alarm.datapoints_to_alarm >= 1
      error_message = "SLO alarm datapoints_to_alarm must be at least 1."
    }

    precondition {
      condition     = each.value.alarm.period >= 60 && each.value.alarm.period % 60 == 0
      error_message = "SLO alarm period must be 60 seconds or a multiple of 60 seconds."
    }

    precondition {
      condition     = each.value.alarm.look_back_window_minutes >= 1 && each.value.alarm.look_back_window_minutes <= 10080
      error_message = "SLO alarm look_back_window_minutes must be between 1 and 10080."
    }
  }
}
