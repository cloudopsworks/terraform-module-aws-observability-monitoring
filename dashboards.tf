##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  dashboard_name_prefix = coalesce(try(var.dashboard_settings.name_prefix, null), local.system_name_short)

  slo_service_entries = [
    for slo in local.slo_set_env : {
      key = try(slo.source_service_key,
        try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
        try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
        try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
        format("custom:%s", try(slo.name, slo.service_level_indicator.name))
      )
      display_name  = try(slo.service_level_indicator.name, slo.name)
      resource_type = try(slo.resource_type, try(slo.service_level_indicator.eks, null) != null ? "eks_service" : try(slo.service_level_indicator.lambda, null) != null ? "lambda_function" : try(slo.service_level_indicator.elasticbeanstalk, null) != null ? "elasticbeanstalk_environment" : "custom")
      service_name  = try(slo.service_level_indicator.name, slo.name)
      dashboard     = {}
      tags          = try(slo.tags, {})
      sources       = toset(["slo"])
    }
  ]

  slo_service_inventory = {
    for service_key in toset([for item in local.slo_service_entries : item.key]) :
    service_key => [for item in local.slo_service_entries : item if item.key == service_key][0]
  }

  dashboard_service_inventory = merge(
    {
      for service_key, service in local.slo_service_inventory : service_key => service
      if var.dashboard_settings.include_slo_only
    },
    local.service_inventory_from_monitors
  )

  alarm_names_by_service = {
    for service_key in keys(local.dashboard_service_inventory) : service_key => {
      for alarm_key, alarm in aws_cloudwatch_metric_alarm.monitor : local.groups_map[alarm_key].monitor_key => alarm.alarm_name
      if local.groups_map[alarm_key].service_key == service_key
    }
  }

  alarm_arns_by_service = {
    for service_key in keys(local.dashboard_service_inventory) : service_key => {
      for alarm_key, alarm in aws_cloudwatch_metric_alarm.monitor : local.groups_map[alarm_key].monitor_key => alarm.arn
      if local.groups_map[alarm_key].service_key == service_key
    }
  }

  slo_names_by_service = {
    for service_key in keys(local.dashboard_service_inventory) : service_key => {
      for slo_key, slo in awscc_applicationsignals_service_level_objective.slo : try(local.slo_all[index([for item in local.slo_all : item.name], slo_key)].slo_key, slo_key) => slo.name
      if try(local.slo_all[index([for item in local.slo_all : item.name], slo_key)].source_service_key, "") == service_key
    }
  }

  dashboard_metrics_by_service = {
    for service_key in keys(local.dashboard_service_inventory) : service_key => [
      for monitor_key, item in local.dashboard_monitor_map : item
      if item.service_key == service_key && (try(item.config.metric_name, null) != null || length(try(item.rendered_metric_query, {})) > 0)
    ]
  }

  dashboard_base_widgets = {
    for service_key, service in local.dashboard_service_inventory : service_key => concat(
      [
        {
          type   = "text"
          width  = 24
          height = 3
          properties = {
            markdown = format("# %s\n\nResource key: `%s`", service.display_name, service_key)
          }
        }
      ],
      length(local.alarm_arns_by_service[service_key]) > 0 ? [
        {
          type   = "alarm"
          width  = 24
          height = 4
          properties = {
            title  = "Alarm status"
            alarms = values(local.alarm_arns_by_service[service_key])
          }
        }
      ] : [],
      [
        for item in local.dashboard_metrics_by_service[service_key] : {
          type   = "metric"
          width  = 12
          height = 6
          properties = {
            title  = item.monitor.name
            region = data.aws_region.current.region
            period = coalesce(try(item.monitor.period, null), try(item.config.period, null), var.dashboard_settings.period)
            stat   = coalesce(try(item.monitor.statistic, null), try(item.config.statistic, null), "Average")
            metrics = jsondecode(jsonencode(concat(
              [
                for query_key, query in item.rendered_metric_query : concat(
                  [query.metric.namespace, query.metric.metric_name],
                  flatten([for dim_key, dim_value in try(query.metric.dimensions, {}) : [dim_key, dim_value]]),
                  [merge(
                    {
                      id     = query_key
                      stat   = coalesce(try(item.monitor.statistic, null), try(query.metric.statistic, null), try(item.config.statistic, null), "Average")
                      period = coalesce(try(item.monitor.period, null), try(query.metric.period, null), try(query.period, null), var.dashboard_settings.period)
                    },
                    try(query.label, null) != null ? { label = query.label } : {},
                    try(query.return_data, null) != null ? { visible = query.return_data } : {}
                  )]
                )
                if try(query.metric, null) != null
              ],
              [
                for query_key, query in item.rendered_metric_query : [merge(
                  {
                    id         = query_key
                    expression = query.expression
                  },
                  try(query.label, null) != null ? { label = query.label } : {},
                  try(query.period, null) != null ? { period = query.period } : {},
                  try(query.return_data, null) != null ? { visible = query.return_data } : {}
                )]
                if try(query.metric, null) == null
              ],
              [
                for direct_metric in [item] : concat(
                  [direct_metric.config.namespace, direct_metric.config.metric_name],
                  flatten([for dim_key, dim_value in direct_metric.rendered_dimensions : [dim_key, dim_value]]),
                  [{ stat = coalesce(try(direct_metric.monitor.statistic, null), try(direct_metric.config.statistic, null), "Average") }]
                )
                if length(try(item.rendered_metric_query, {})) == 0
              ]
            )))
          }
        }
      ],
      length(local.slo_names_by_service[service_key]) > 0 ? [
        {
          type   = "text"
          width  = 24
          height = 4
          properties = {
            markdown = format("## SLOs\n%s", join("\n", [for slo_name in values(local.slo_names_by_service[service_key]) : format("- `%s`", slo_name)]))
          }
        }
      ] : [],
      [
        for widget in try(service.dashboard.custom_widgets, []) : merge({
          type   = widget.type
          width  = coalesce(try(widget.width, null), 24)
          height = coalesce(try(widget.height, null), 4)
          properties = coalesce(try(widget.properties, null), widget.type == "text" ? {
            markdown = coalesce(try(widget.markdown, null), "")
          } : {})
        }, {})
        if try(widget.position, "append") == "append" && contains(["text", "metric", "alarm", "custom"], widget.type)
      ]
    )
  }

  dashboard_widgets = {
    for service_key, widgets in local.dashboard_base_widgets : service_key => [
      for index, widget in widgets : merge(widget, {
        x = (index % var.dashboard_settings.widgets_per_row) * floor(24 / var.dashboard_settings.widgets_per_row)
        y = floor(index / var.dashboard_settings.widgets_per_row) * 6
      })
    ]
  }

  fleet_alarm_arns = flatten([
    for service_key, alarms in local.alarm_arns_by_service : values(alarms)
  ])

  fleet_widgets = concat([
    {
      type   = "text"
      x      = 0
      y      = 0
      width  = 24
      height = 3
      properties = {
        markdown = format("# %s observability fleet", local.dashboard_name_prefix)
      }
    }
    ], length(local.fleet_alarm_arns) > 0 ? [
    {
      type   = "alarm"
      x      = 0
      y      = 3
      width  = 24
      height = 6
      properties = {
        title  = "Fleet alarm status"
        alarms = slice(local.fleet_alarm_arns, 0, min(length(local.fleet_alarm_arns), 100))
      }
    }
  ] : [])
}

resource "aws_cloudwatch_dashboard" "service" {
  for_each = var.dashboard_settings.enabled && var.dashboard_settings.create_per_service ? local.dashboard_widgets : {}

  dashboard_name = substr(replace(replace(format("%s-%s", local.dashboard_name_prefix, each.key), ":", "-"), "/", "-"), 0, 255)
  dashboard_body = jsonencode({
    start   = var.dashboard_settings.start
    widgets = each.value
  })

  lifecycle {
    precondition {
      condition     = length(each.value) <= 500
      error_message = "CloudWatch dashboard ${each.key} exceeds the 500 widget limit."
    }
  }
}

resource "aws_cloudwatch_dashboard" "fleet" {
  for_each = var.dashboard_settings.enabled && var.dashboard_settings.create_fleet ? { fleet = local.fleet_widgets } : {}

  dashboard_name = substr(format("%s-fleet", local.dashboard_name_prefix), 0, 255)
  dashboard_body = jsonencode({
    start   = var.dashboard_settings.start
    widgets = each.value
  })

  lifecycle {
    precondition {
      condition     = length(each.value) <= 500 && length(local.fleet_alarm_arns) <= 100
      error_message = "CloudWatch fleet dashboard exceeds supported widget or alarm-widget limits."
    }
  }
}
