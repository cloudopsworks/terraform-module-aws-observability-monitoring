##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  alarm_targets = coalesce(var.alarm_targets, [])

  configs = yamldecode(file("${path.module}/observability-config.yaml"))
  config_map = {
    for conf in local.configs : conf.name => conf
  }
  custom_monitor_definition_map = {
    for name, conf in var.monitor_definitions : name => jsondecode(jsonencode(merge(conf,
      try(conf.metric, null) != null ? {
        namespace   = conf.metric.namespace
        metric_name = conf.metric.metric_name
        statistic   = try(conf.metric.statistic, null)
        period      = try(conf.metric.period, null)
        unit        = try(conf.metric.unit, null)
        dimensions = {
          for dim_key, dim_value in try(conf.metric.dimensions, {}) :
          dim_key => coalesce(try(dim_value.value, null), try(dim_value.value_from, null), "")
        }
      } : {},
      length(try(conf.metric_query, [])) > 0 ? {
        metric_query = {
          for query in conf.metric_query : query.id => {
            expression  = try(query.expression, null)
            label       = try(query.label, null)
            return_data = try(query.return_data, true)
            metric = try(query.metric, null) != null ? {
              namespace   = query.metric.namespace
              metric_name = query.metric.metric_name
              statistic   = query.metric.statistic
              period      = try(query.metric.period, null)
              unit        = try(query.metric.unit, null)
              dimensions = {
                for dim_key, dim_value in try(query.metric.dimensions, {}) :
                dim_key => coalesce(try(dim_value.value, null), try(dim_value.value_from, null), "")
              }
            } : null
          }
        }
      } : {}
    )))
  }
  monitor_definition_map = merge(local.config_map, local.custom_monitor_definition_map)

  allowed_catalog_placeholders = toset([
    "$${group.service_name}",
    "$${group.cluster_name}",
    "$${group.namespace}",
    "$${group.stage}",
    "$${try(monitor.threshold, 5)}",
    "$${try(monitor.threshold, 10)}",
    "$${try(monitor.threshold, 20)}",
    "$${try(monitor.threshold, 80)}",
    "$${try(monitor.threshold, 100)}",
    "$${try(monitor.threshold, 1000)}",
  ])
  catalog_placeholders         = toset(flatten(regexall("\\$\\{[^}]+\\}", jsonencode(local.configs))))
  unknown_catalog_placeholders = setsubtract(local.catalog_placeholders, local.allowed_catalog_placeholders)

  service_resource_type = {
    eks_service                  = "eks"
    lambda_function              = "lambda"
    elasticbeanstalk_environment = "elasticbeanstalk"
    custom                       = "custom"
  }

  v2_monitor_groups = [
    for service_key, service in var.services : {
      service_key       = service_key
      service_name      = service.resource_type == "eks_service" ? service.resource.eks.service_name : service.resource_type == "lambda_function" ? service.resource.lambda.function_name : service.resource_type == "elasticbeanstalk_environment" ? service.resource.elasticbeanstalk.environment_name : service_key
      display_name      = coalesce(try(service.display_name, null), service_key)
      type              = local.service_resource_type[service.resource_type]
      resource_type     = service.resource_type
      cluster_name      = service.resource_type == "eks_service" ? service.resource.eks.cluster_name : null
      namespace         = service.resource_type == "eks_service" ? service.resource.eks.namespace : null
      function_name     = service.resource_type == "lambda_function" ? service.resource.lambda.function_name : null
      application_name  = service.resource_type == "elasticbeanstalk_environment" ? service.resource.elasticbeanstalk.application_name : null
      environment_name  = service.resource_type == "elasticbeanstalk_environment" ? service.resource.elasticbeanstalk.environment_name : null
      published_metrics = service.resource_type == "elasticbeanstalk_environment" ? service.resource.elasticbeanstalk.published_metrics : []
      account_id        = try(service.resource.account_id, null)
      region            = try(service.resource.region, null)
      canonical_key     = service.resource_type == "eks_service" ? format("eks:%s/%s/%s", service.resource.eks.cluster_name, service.resource.eks.namespace, service.resource.eks.service_name) : service.resource_type == "lambda_function" ? format("lambda:%s", service.resource.lambda.function_name) : service.resource_type == "elasticbeanstalk_environment" ? format("elasticbeanstalk:%s/%s", service.resource.elasticbeanstalk.application_name, service.resource.elasticbeanstalk.environment_name) : format("custom:%s", service_key)
      dashboard         = try(service.dashboard, {})
      tags              = try(service.tags, {})
      monitors = [
        for monitor_key, monitor in try(service.monitors, {}) : merge({
          key                   = monitor_key
          target_name           = coalesce(try(monitor.preset, null), monitor_key)
          name                  = coalesce(try(monitor.name, null), upper(replace(monitor_key, "_", " ")))
          priority              = try(monitor.priority, 3)
          dashboard_only        = try(monitor.dashboard_only, false)
          allow_missing_metrics = try(monitor.allow_missing_metrics, false)
          override              = try(monitor.override, false)
          name_override         = try(monitor.name_override, null)
          threshold             = try(monitor.threshold, null)
          account_id            = try(service.resource.account_id, null)
          period                = try(monitor.period, null)
          statistic             = try(monitor.statistic, null)
          comparison_operator   = try(monitor.comparison_operator, null)
          evaluation_periods    = try(monitor.evaluation_periods, null)
          datapoints_to_alarm   = try(monitor.datapoints_to_alarm, null)
          treat_missing_data    = try(monitor.treat_missing_data, null)
        }, try(monitor.metric, null) != null ? { metric = monitor.metric } : {}, length(try(monitor.metric_query, [])) > 0 ? { metric_query = monitor.metric_query } : {})
        if try(monitor.enabled, true)
      ]
    }
    if try(service.enabled, true)
  ]

  monitor_groups_input = concat(var.monitor_groups, local.v2_monitor_groups)

  service_inventory_from_monitors = {
    for group in local.monitor_groups_input : try(group.canonical_key,
      try(group.type, "") == "eks" ? format("eks:%s/%s/%s", group.cluster_name, group.namespace, group.service_name) :
      try(group.type, "") == "lambda" ? format("lambda:%s", group.service_name) :
      try(group.type, "") == "elasticbeanstalk" ? format("elasticbeanstalk:%s/%s", try(group.application_name, group.service_name), try(group.environment_name, group.service_name)) :
      format("%s:%s", try(group.type, "custom"), group.service_name)
      ) => {
      key = try(group.canonical_key,
        try(group.type, "") == "eks" ? format("eks:%s/%s/%s", group.cluster_name, group.namespace, group.service_name) :
        try(group.type, "") == "lambda" ? format("lambda:%s", group.service_name) :
        try(group.type, "") == "elasticbeanstalk" ? format("elasticbeanstalk:%s/%s", try(group.application_name, group.service_name), try(group.environment_name, group.service_name)) :
        format("%s:%s", try(group.type, "custom"), group.service_name)
      )
      display_name  = try(group.display_name, group.service_name)
      resource_type = try(group.resource_type, try(group.type, "custom"))
      service_name  = group.service_name
      group         = group
      dashboard     = try(group.dashboard, {})
      tags          = try(group.tags, {})
      sources       = toset(["monitor_group"])
    }
  }

  groups = flatten([
    for group in local.monitor_groups_input : [
      for monitor in try(group.monitors, []) : {
        monitor_name = coalesce(try(monitor.name_override, null), format("[P%s] [%s] [%s] [%s] %s - %s - %s",
          monitor.priority,
          lower(var.org.organization_unit),
          lower(var.org.environment_name),
          group.service_name,
          monitor.name,
          group.type,
          lower(var.org.environment_type)
        ))
        service_key = try(group.canonical_key,
          try(group.type, "") == "eks" ? format("eks:%s/%s/%s", group.cluster_name, group.namespace, group.service_name) :
          try(group.type, "") == "lambda" ? format("lambda:%s", group.service_name) :
          try(group.type, "") == "elasticbeanstalk" ? format("elasticbeanstalk:%s/%s", try(group.application_name, group.service_name), try(group.environment_name, group.service_name)) :
          format("%s:%s", try(group.type, "custom"), group.service_name)
        )
        monitor_key    = try(monitor.key, monitor.target_name)
        dashboard_only = try(monitor.dashboard_only, try(local.monitor_definition_map[monitor.target_name].dashboard_only, false))
        group          = group
        monitor        = monitor
        config = merge(local.monitor_definition_map[monitor.target_name], try(monitor.metric, null) != null ? {
          namespace   = monitor.metric.namespace
          metric_name = monitor.metric.metric_name
          statistic   = try(monitor.metric.statistic, try(monitor.statistic, null))
          period      = try(monitor.metric.period, try(monitor.period, null))
          unit        = try(monitor.metric.unit, try(monitor.unit, null))
          dimensions  = try(monitor.metric.dimensions, {})
          } : {}, length(try(monitor.metric_query, [])) > 0 ? {
          metric_query = { for query in monitor.metric_query : query.id => query }
        } : {})
        rendered_description = replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(try(coalesce(try(monitor.description_override, null), try(local.monitor_definition_map[monitor.target_name].description, null), try(local.monitor_definition_map[monitor.target_name].description_template, null)), ""), "$${group.service_name}", (try(group.service_name, null) != null ? tostring(group.service_name) : "")), "$${group.cluster_name}", (try(group.cluster_name, null) != null ? tostring(group.cluster_name) : "")), "$${group.namespace}", (try(group.namespace, null) != null ? tostring(group.namespace) : "")), "$${group.stage}", (try(group.stage, null) != null ? tostring(group.stage) : "")), "$${try(monitor.threshold, 5)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "5")), "$${try(monitor.threshold, 10)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "10")), "$${try(monitor.threshold, 20)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "20")), "$${try(monitor.threshold, 80)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "80")), "$${try(monitor.threshold, 100)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "100")), "$${try(monitor.threshold, 1000)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "1000"))
        rendered_dimensions = {
          for dim_key, dim_template in try(merge(local.monitor_definition_map[monitor.target_name], try(monitor.metric, null) != null ? { dimensions = monitor.metric.dimensions } : {}).dimensions, {}) :
          dim_key => replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(tostring(dim_template), "$${group.service_name}", (try(group.service_name, null) != null ? tostring(group.service_name) : "")), "$${group.cluster_name}", (try(group.cluster_name, null) != null ? tostring(group.cluster_name) : "")), "$${group.namespace}", (try(group.namespace, null) != null ? tostring(group.namespace) : "")), "$${group.stage}", (try(group.stage, null) != null ? tostring(group.stage) : "")), "$${try(monitor.threshold, 5)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "5")), "$${try(monitor.threshold, 10)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "10")), "$${try(monitor.threshold, 20)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "20")), "$${try(monitor.threshold, 80)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "80")), "$${try(monitor.threshold, 100)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "100")), "$${try(monitor.threshold, 1000)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "1000"))
        }
        rendered_metric_query = {
          for query_key, query in try(merge(local.monitor_definition_map[monitor.target_name], length(try(monitor.metric_query, [])) > 0 ? { metric_query = { for query in monitor.metric_query : query.id => query } } : {}).metric_query, {}) :
          query_key => merge(query, try(query.metric, null) != null ? {
            metric = merge(query.metric, {
              dimensions = {
                for dim_key, dim_template in merge(try(query.dimensions, {}), try(query.metric.dimensions, {})) :
                dim_key => replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(tostring(dim_template), "$${group.service_name}", (try(group.service_name, null) != null ? tostring(group.service_name) : "")), "$${group.cluster_name}", (try(group.cluster_name, null) != null ? tostring(group.cluster_name) : "")), "$${group.namespace}", (try(group.namespace, null) != null ? tostring(group.namespace) : "")), "$${group.stage}", (try(group.stage, null) != null ? tostring(group.stage) : "")), "$${try(monitor.threshold, 5)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "5")), "$${try(monitor.threshold, 10)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "10")), "$${try(monitor.threshold, 20)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "20")), "$${try(monitor.threshold, 80)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "80")), "$${try(monitor.threshold, 100)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "100")), "$${try(monitor.threshold, 1000)}", (try(monitor.threshold, null) != null ? tostring(monitor.threshold) : "1000"))
              }
            })
          } : {})
        }
      }
    ]
  ])

  groups_map = {
    for group in local.groups : group.monitor_name => group
    if !group.dashboard_only
  }

  dashboard_monitor_map = {
    for group in local.groups : format("%s/%s", group.service_key, group.monitor_key) => group
  }

  sns_actions    = [for item in data.aws_sns_topic.sns : item.arn]
  lambda_actions = [for item in data.aws_lambda_function.lambda : item.arn]
  alarm_actions  = concat(local.sns_actions, local.lambda_actions)
  ok_actions     = concat(local.sns_actions, local.lambda_actions)
}
