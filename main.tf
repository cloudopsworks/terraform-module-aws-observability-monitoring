##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  configs    = yamldecode(file("${path.module}/observability-config.yaml"))
  config_map = { for conf in local.configs : conf.name => conf }
  groups = [
    for group in var.monitor_groups : {
      monitor_name = format("[P%s][%s][%s][%s] %s %s",
        group.priority,
        lower(var.org.organization_unit),
        lower(var.org.environment_name),
        lower(var.org.environment_type),
        group.name,
        group.service_name,
      )
      group  = group
      config = local.config_map[group.target_name]
    }
  ]
  groups_map = {
    for group in local.groups : group.group.target_name => group
  }
  sns_actions    = [for item in data.aws_sns_topic.sns : item.arn]
  lambda_actions = [for item in data.aws_lambda_function.lambda : item.arn]
  alarm_actions  = concat(local.sns_actions, local.lambda_actions)
  ok_actions     = concat(local.sns_actions, local.lambda_actions)
}

resource "aws_cloudwatch_metric_alarm" "monitor" {
  for_each                              = local.groups_map
  alarm_name                            = each.value.monitor_name
  alarm_description                     = templatestring(each.value.config.description, each.value.group)
  comparison_operator                   = each.value.config.comparison_operator
  evaluation_periods                    = try(each.value.group.evaluation_periods, each.value.config.evaluation_periods)
  datapoints_to_alarm                   = try(each.value.group.datapoints_to_alarm, each.value.config.datapoints_to_alarm)
  period                                = try(each.value.group.period, each.value.config.period)
  metric_name                           = try(each.value.config.metric_name, null)
  statistic                             = try(each.value.config.statistic, null)
  namespace                             = try(each.value.config.namespace, null)
  threshold                             = try(each.value.group.threshold, each.value.config.default_threshold, null)
  threshold_metric_id                   = try(each.value.config.threshold_metric_id, null)
  unit                                  = try(each.value.config.unit, null)
  treat_missing_data                    = try(each.value.config.treat_missing_data, "missing")
  evaluate_low_sample_count_percentiles = try(each.value.config.evaluate_low_sample, null)
  actions_enabled                       = true
  alarm_actions                         = local.alarm_actions
  ok_actions                            = local.ok_actions
  dimensions = length(try(each.value.config.dimensions, {})) > 0 ? {
    for dim_key, dim_template in each.value.config.dimensions :
    dim_key => templatestring(dim_template, each.value.group)
  } : null
  dynamic "metric_query" {
    for_each = try(each.value.config.metric_query, {})
    content {
      id          = metric_query.key
      account_id  = try(each.value.group.account_id, null)
      expression  = try(metric_query.value.expression, null)
      label       = try(metric_query.value.label, null)
      return_data = try(metric_query.value.return_data, null)
      period      = try(metric_query.value.period, null)
      dynamic "metric" {
        for_each = length(try(metric_query.value.metric, {})) > 0 ? [1] : []
        content {
          metric_name = metric_query.value.metric.metric_name
          namespace   = metric_query.value.metric.namespace
          period      = try(each.value.group.period, metric_query.value.metric.period)
          stat        = metric_query.value.metric.statistic
          unit        = try(metric_query.value.metric.unit, null)
          dimensions = length(try(metric_query.value.metric.dimensions, {})) > 0 ? {
            for dim_key, dim_template in metric_query.value.metric.dimensions :
            dim_key => templatestring(dim_template, each.value.group)
          } : null
        }
      }
    }
  }
}

data "aws_sns_topic" "sns" {
  for_each = {
    for target in var.alarm_targets : target.name => target
    if target.type == "sns"
  }
  name = each.value.name
}

data "aws_lambda_function" "lambda" {
  for_each = {
    for target in var.alarm_targets : target.name => target
    if target.type == "lambda"
  }
  function_name = each.value.name
}
