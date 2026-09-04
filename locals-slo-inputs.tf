##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  v2_slo_in = flatten([
    for service_key, service in var.services : [
      for slo_key, slo in try(service.slos, {}) : {
        name        = coalesce(try(slo.name_override, null), slo_key == "golden" ? service_key : format("%s-%s", service_key, slo_key))
        description = try(slo.description, null)
        type        = slo.type
        preset      = try(slo.preset, null)
        source_service_key = coalesce(
          try(format("eks:%s/%s/%s", service.resource.eks.cluster_name, service.resource.eks.namespace, service.resource.eks.service_name), null),
          try(format("lambda:%s", service.resource.lambda.function_name), null),
          try(format("elasticbeanstalk:%s/%s", service.resource.elasticbeanstalk.application_name, service.resource.elasticbeanstalk.environment_name), null),
          try(format("apigateway:%s/%s", service.resource.api_gateway.api_name, service.resource.api_gateway.stage), null),
          try(format("ec2:%s", service.resource.ec2.instance_id), null),
          try(format("alb:%s", service.resource.load_balancer.arn_suffix), null),
          format("custom:%s", service_key)
        )
        resource_type = service.resource_type
        service_level_indicator = merge({
          comparison           = try(coalesce(try(slo.comparison, null), try(slo.comparisson, null)), null)
          threshold            = try(slo.threshold, null)
          metric_type          = try(slo.metric_type, null)
          statistic            = try(slo.statistic, null)
          period_seconds       = try(slo.period_seconds, null)
          operations           = try(slo.operations, [])
          latency_threshold    = try(slo.latency_threshold, null)
          errors_threshold     = try(slo.errors_threshold, null)
          traffic_threshold    = try(slo.traffic_threshold, null)
          saturation_threshold = try(slo.saturation_threshold, null)
          saturation_metric    = try(slo.saturation_metric, null)
          account_id           = try(service.resource.account_id, null)
          published_metrics    = try(service.resource.elasticbeanstalk.published_metrics, [])
          }, try({
            eks = {
              cluster_name = service.resource.eks.cluster_name
              namespace    = service.resource.eks.namespace
              name         = service.resource.eks.service_name
            }
            environment = coalesce(try(service.resource.app_signals.environment, null), format("eks:%s/%s", service.resource.eks.cluster_name, service.resource.eks.namespace))
            name        = coalesce(try(service.resource.app_signals.service, null), service.resource.eks.service_name)
            type        = "Service"
            }, {}), try({
            lambda = {
              function_name = service.resource.lambda.function_name
            }
            environment = coalesce(try(service.resource.app_signals.environment, null), "lambda:default")
            name        = coalesce(try(service.resource.app_signals.service, null), service.resource.lambda.function_name)
            type        = "Service"
            }, {}), try({
            elasticbeanstalk = {
              application_name = service.resource.elasticbeanstalk.application_name
              environment_name = service.resource.elasticbeanstalk.environment_name
            }
            environment = coalesce(try(service.resource.app_signals.environment, null), format("elasticbeanstalk:%s/%s", service.resource.elasticbeanstalk.application_name, service.resource.elasticbeanstalk.environment_name))
            name        = coalesce(try(service.resource.app_signals.service, null), service.resource.elasticbeanstalk.environment_name)
            type        = "Service"
            }, {}), try({
            api_gateway = {
              api_name = service.resource.api_gateway.api_name
              stage    = service.resource.api_gateway.stage
            }
            name  = service.resource.api_gateway.api_name
            stage = service.resource.api_gateway.stage
            }, {}), try({
            ec2 = {
              instance_id = service.resource.ec2.instance_id
            }
            name = service.resource.ec2.instance_id
            }, {}), try({
            load_balancer = {
              arn_suffix = service.resource.load_balancer.arn_suffix
            }
            name = service.resource.load_balancer.arn_suffix
        }, {}))
        goal = try(slo.goal, {})
        tags = try(service.tags, {})
      }
      if try(slo.enabled, true)
    ]
    if try(service.enabled, true)
  ])
}
