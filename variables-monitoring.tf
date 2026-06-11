##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

## Settings for the monitoring module - yaml format
# slo_settings:
#   service_level_objectives:
#     - name: "Golden Signal SLO"
#       description: "Service Level Objective 1"   # (Optional) Description for the SLO. Default: generated from the SLO name.
#       type: golden-signal                        # (Required) SLO type. Valid values: golden-signal, operational, metric-query, request-based.
#       service_level_indicator:
#         eks:                                     # (Optional) EKS service identity.
#           cluster_name: "my-cluster"             # (Required) EKS cluster name.
#           namespace: "my-namespace"              # (Required) Kubernetes namespace.
#           name: "my-service"                     # (Required) Kubernetes service name.
#         lambda:                                  # (Optional) Lambda service identity.
#           function_name: "my-function"           # (Required) Lambda function name.
#         comparison: LessThan                     # (Optional) Comparison operator. Default: LessThan.
#         latency_threshold: 100                   # (Required for golden-signal) Latency threshold in milliseconds.
#         errors_threshold: 5                      # (Required for golden-signal) Error threshold.
#         saturation_threshold: 80                 # (Required for golden-signal) Saturation threshold.
#         saturation_metric: CPU                   # (Optional) Saturation metric. Valid values: CPU, MEMORY. Default: CPU.
#         traffic_threshold: 1000                  # (Required for golden-signal) Traffic threshold.
#         period_seconds: 300                      # (Optional) Period in seconds. Default: 300.
#       goal:
#         attainment: 99.9                         # (Optional) Attainment percentage. Default: 99.9.
#         duration: 7                              # (Optional) Rolling interval duration. Default: 7.
#         duration_unit: DAY                       # (Optional) Valid values: DAY, HOUR, WEEK, MONTH, YEAR. Default: DAY.
#       tags: {}                                   # (Optional) Additional SLO tags. Default: {}.
variable "slo_settings" {
  description = "Legacy SLO settings for the monitoring module. Kept for backward compatibility."
  type        = any
  default     = {}
  nullable    = false
}

## Monitoring groups configuration - yaml format
# monitor_groups:
#   - service_name: "checkout-helm"                    # (Required) Service or resource name used by monitor presets.
#     type: eks                                       # (Required) Resource type. Valid legacy values: eks, lambda, apigateway.
#     cluster_name: "eks-main"                       # (Required for eks) EKS cluster name.
#     namespace: "default"                           # (Required for eks) Kubernetes namespace.
#     monitors:
#       - name: "REQUEST LATENCY"                    # (Required) Alarm display name.
#         target_name: lat_eks_service_requests_apm  # (Required) Built-in monitor preset key.
#         priority: 2                                # (Required) Alarm priority used in the generated name.
#         threshold: 80                              # (Optional) Alarm threshold; preset default applies when omitted.
variable "monitor_groups" {
  description = "Legacy list of monitoring groups. Kept for backward compatibility."
  type        = any
  default     = []
  nullable    = false
}

variable "alarm_targets" {
  description = "List of alarm action targets. Supported types are `sns` and `lambda`; empty or null disables actions."
  type = list(object({
    type = string
    name = string
  }))
  default  = []
  nullable = true
}

variable "services" {
  description = "Typed v2 service observability definitions for alarms, SLOs, and dashboards."
  type = map(object({
    enabled       = optional(bool, true)
    display_name  = optional(string)
    resource_type = string
    profile       = optional(string)

    resource = object({
      account_id = optional(string)
      region     = optional(string)
      partition  = optional(string, "aws")

      eks = optional(object({
        cluster_name = string
        namespace    = string
        service_name = string
      }))

      lambda = optional(object({
        function_name = string
        alias         = optional(string)
      }))

      elasticbeanstalk = optional(object({
        application_name         = string
        environment_name         = string
        platform                 = optional(string, "linux")
        enhanced_health_required = optional(bool, true)
        published_metrics        = optional(set(string), ["EnvironmentHealth"])
      }))

      app_signals = optional(object({
        enabled     = optional(bool, true)
        environment = optional(string)
        service     = optional(string)
      }), {})

      dimensions = optional(map(string), {})
    })

    monitors = optional(map(object({
      enabled               = optional(bool, true)
      preset                = optional(string)
      name                  = optional(string)
      priority              = optional(number, 3)
      threshold             = optional(number)
      comparison_operator   = optional(string)
      evaluation_periods    = optional(number)
      datapoints_to_alarm   = optional(number)
      period                = optional(number)
      statistic             = optional(string)
      unit                  = optional(string)
      treat_missing_data    = optional(string)
      dashboard_only        = optional(bool, false)
      allow_missing_metrics = optional(bool, false)
      override              = optional(bool, false)
      name_override         = optional(string)
      description_override  = optional(string)
      metric = optional(object({
        namespace   = string
        metric_name = string
        dimensions  = optional(map(string), {})
        statistic   = optional(string)
        period      = optional(number)
        unit        = optional(string)
      }))
      metric_query = optional(list(object({
        id          = string
        expression  = optional(string)
        label       = optional(string)
        return_data = optional(bool, true)
        metric = optional(object({
          namespace   = string
          metric_name = string
          dimensions  = optional(map(string), {})
          statistic   = string
          period      = optional(number)
          unit        = optional(string)
        }))
      })), [])
      dashboard = optional(object({
        widget_type = optional(string, "metric")
        title       = optional(string)
        width       = optional(number, 12)
        height      = optional(number, 6)
      }), {})
    })), {})

    slos = optional(map(object({
      enabled              = optional(bool, true)
      type                 = string
      preset               = optional(string)
      name_override        = optional(string)
      description          = optional(string)
      comparison           = optional(string)
      comparisson          = optional(string)
      threshold            = optional(number)
      metric_type          = optional(string)
      statistic            = optional(string)
      period_seconds       = optional(number)
      operations           = optional(list(string), [])
      latency_threshold    = optional(number)
      errors_threshold     = optional(number)
      traffic_threshold    = optional(number)
      saturation_threshold = optional(number)
      saturation_metric    = optional(string)
      goal = optional(object({
        attainment        = optional(number, 99.9)
        duration          = optional(number, 7)
        duration_unit     = optional(string, "DAY")
        warning_threshold = optional(number, 80)
      }), {})
    })), {})

    dashboard = optional(object({
      enabled     = optional(bool, true)
      presets     = optional(list(string), [])
      runbook_url = optional(string)
      custom_widgets = optional(list(object({
        id         = string
        position   = optional(string, "append")
        type       = string
        title      = optional(string)
        markdown   = optional(string)
        width      = optional(number)
        height     = optional(number)
        properties = optional(any)
      })), [])
    }), {})

    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for service_key, service in var.services :
      service.resource_type == "eks_service" ? (
        try(service.resource.eks, null) != null && try(service.resource.lambda, null) == null && try(service.resource.elasticbeanstalk, null) == null
        ) : service.resource_type == "lambda_function" ? (
        try(service.resource.lambda, null) != null && try(service.resource.eks, null) == null && try(service.resource.elasticbeanstalk, null) == null
        ) : service.resource_type == "elasticbeanstalk_environment" ? (
        try(service.resource.elasticbeanstalk, null) != null && try(service.resource.eks, null) == null && try(service.resource.lambda, null) == null
        ) : service.resource_type == "custom" ? (
        length(try(service.resource.dimensions, {})) > 0 && try(service.resource.eks, null) == null && try(service.resource.lambda, null) == null && try(service.resource.elasticbeanstalk, null) == null
      ) : false
    ])
    error_message = "Each service must match exactly one identity block for its resource_type; custom services require non-empty dimensions."
  }

  validation {
    condition = alltrue(flatten([
      for service_key, service in var.services : [
        for slo_key, slo in try(service.slos, {}) :
        try(slo.comparison, null) == null || try(slo.comparisson, null) == null || try(slo.comparison, null) == try(slo.comparisson, null)
      ]
    ]))
    error_message = "A service SLO cannot set both comparison and comparisson with different values. Use comparison; comparisson is a deprecated compatibility alias."
  }
}

variable "monitor_definitions" {
  description = "Custom monitor presets keyed by preset name."
  type = map(object({
    resource_type        = string
    signal               = string
    display_name         = string
    description_template = optional(string)
    default_threshold    = optional(number)
    comparison_operator  = optional(string)
    evaluation_periods   = optional(number, 1)
    datapoints_to_alarm  = optional(number, 1)
    period               = optional(number)
    statistic            = optional(string)
    unit                 = optional(string)
    treat_missing_data   = optional(string, "missing")
    dashboard_only       = optional(bool, false)
    prerequisites        = optional(list(string), [])
    metric = optional(object({
      namespace   = string
      metric_name = string
      dimensions = map(object({
        value      = optional(string)
        value_from = optional(string)
      }))
      statistic = optional(string)
      period    = optional(number)
      unit      = optional(string)
    }))
    metric_query = optional(list(object({
      id          = string
      expression  = optional(string)
      label       = optional(string)
      return_data = optional(bool, true)
      metric = optional(object({
        namespace   = string
        metric_name = string
        dimensions = map(object({
          value      = optional(string)
          value_from = optional(string)
        }))
        statistic = string
        period    = optional(number)
        unit      = optional(string)
      }))
    })), [])
    slo = optional(object({
      supported          = optional(bool, false)
      type               = optional(string)
      bad_count_preset   = optional(string)
      total_count_preset = optional(string)
    }), {})
    dashboard = optional(object({
      widget_type = optional(string, "metric")
      width       = optional(number, 12)
      height      = optional(number, 6)
      title       = optional(string)
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "resource_profiles" {
  description = "Custom resource profiles keyed by profile name."
  type = map(object({
    resource_type = string
    identity = object({
      required_fields      = list(string)
      canonical_key_format = string
      environment_format   = optional(string)
      service_name_from    = string
    })
    capabilities = object({
      latency           = optional(bool, false)
      errors            = optional(bool, false)
      faults            = optional(bool, false)
      traffic           = optional(bool, false)
      saturation        = optional(bool, false)
      health            = optional(bool, false)
      app_signals_slo   = optional(bool, false)
      metric_query_slo  = optional(bool, false)
      request_based_slo = optional(bool, false)
    })
    default_monitor_presets   = optional(map(string), {})
    default_dashboard_presets = optional(list(string), [])
    prerequisites             = optional(list(string), [])
  }))
  default  = {}
  nullable = false
}

variable "dashboard_settings" {
  description = "CloudWatch dashboard generation settings."
  type = object({
    enabled            = optional(bool, true)
    name_prefix        = optional(string)
    create_fleet       = optional(bool, true)
    create_per_service = optional(bool, true)
    include_slo_only   = optional(bool, true)
    period             = optional(number, 300)
    start              = optional(string, "-PT6H")
    widgets_per_row    = optional(number, 2)
    presets            = optional(list(string), ["golden-signals", "alarm-status", "slo-health"])
    custom_widgets = optional(list(object({
      id         = string
      position   = optional(string, "append")
      type       = string
      title      = optional(string)
      markdown   = optional(string)
      width      = optional(number)
      height     = optional(number)
      properties = optional(any)
    })), [])
  })
  default  = {}
  nullable = false
}
