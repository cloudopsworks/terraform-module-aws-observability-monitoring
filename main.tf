##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

resource "aws_cloudwatch_metric_alarm" "monitor" {
  for_each                              = local.groups_map
  alarm_name                            = each.value.monitor_name
  alarm_description                     = each.value.rendered_description
  comparison_operator                   = coalesce(try(each.value.monitor.comparison_operator, null), each.value.config.comparison_operator)
  evaluation_periods                    = coalesce(try(each.value.monitor.evaluation_periods, null), each.value.config.evaluation_periods)
  datapoints_to_alarm                   = coalesce(try(each.value.monitor.datapoints_to_alarm, null), each.value.config.datapoints_to_alarm)
  period                                = length(try(each.value.rendered_metric_query, {})) == 0 ? coalesce(try(each.value.monitor.period, null), try(each.value.config.period, null)) : null
  metric_name                           = try(each.value.config.metric_name, null)
  statistic                             = coalesce(try(each.value.monitor.statistic, null), try(each.value.config.statistic, null))
  namespace                             = try(each.value.config.namespace, null)
  threshold                             = coalesce(try(each.value.monitor.threshold, null), try(each.value.config.default_threshold, null))
  threshold_metric_id                   = try(each.value.config.threshold_metric_id, null)
  unit                                  = coalesce(try(each.value.monitor.unit, null), try(each.value.config.unit, null))
  treat_missing_data                    = coalesce(try(each.value.monitor.treat_missing_data, null), try(each.value.config.treat_missing_data, null), "missing")
  evaluate_low_sample_count_percentiles = try(each.value.config.evaluate_low_sample, null)
  actions_enabled                       = (length(local.alarm_actions) + length(local.ok_actions)) > 0
  alarm_actions                         = local.alarm_actions
  ok_actions                            = local.ok_actions
  dimensions                            = length(each.value.rendered_dimensions) > 0 ? each.value.rendered_dimensions : null

  dynamic "metric_query" {
    for_each = each.value.rendered_metric_query
    content {
      id          = metric_query.key
      account_id  = try(each.value.monitor.account_id, null)
      expression  = try(metric_query.value.expression, null)
      label       = try(metric_query.value.label, null)
      return_data = try(metric_query.value.return_data, null)
      period      = try(metric_query.value.metric, null) == null ? coalesce(try(each.value.monitor.period, null), try(metric_query.value.period, null)) : null

      dynamic "metric" {
        for_each = try(metric_query.value.metric, null) != null ? [metric_query.value.metric] : []
        content {
          metric_name = metric.value.metric_name
          namespace   = metric.value.namespace
          period      = coalesce(try(each.value.monitor.period, null), try(metric.value.period, null))
          stat        = coalesce(try(each.value.monitor.statistic, null), metric.value.statistic)
          unit        = coalesce(try(each.value.monitor.unit, null), try(metric.value.unit, null))
          dimensions  = length(try(metric.value.dimensions, {})) > 0 ? metric.value.dimensions : null
        }
      }
    }
  }

  tags = merge(local.all_tags, try(each.value.group.tags, {}), {
    "alarm-priority"       = tostring(each.value.monitor.priority)
    "observability-config" = each.value.config.name
    "service-name"         = each.value.group.service_name
    "service-key"          = each.value.service_key
  })

  lifecycle {
    precondition {
      condition     = length(local.unknown_catalog_placeholders) == 0
      error_message = "Unsupported observability-config.yaml placeholder(s): ${join(", ", tolist(local.unknown_catalog_placeholders))}."
    }
  }
}

data "aws_sns_topic" "sns" {
  for_each = {
    for target in local.alarm_targets : target.name => target
    if target.type == "sns"
  }
  name = each.value.name
}

data "aws_lambda_function" "lambda" {
  for_each = {
    for target in local.alarm_targets : target.name => target
    if target.type == "lambda"
  }
  function_name = each.value.name
}
