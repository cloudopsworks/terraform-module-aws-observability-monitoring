##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

locals {
  slo_in = concat(try(var.slo_settings.service_level_objectives, []), local.v2_slo_in)
  slo_set_env = [
    for slo in local.slo_in : merge(slo,
      try({
        source_service_key = try(slo.source_service_key, format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, try(slo.service_level_indicator.eks.name, slo.service_level_indicator.name)))
        service_level_indicator = merge(slo.service_level_indicator, {
          environment = format("eks:%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace)
          name        = try(slo.service_level_indicator.eks.name, slo.service_level_indicator.name)
          type        = try(slo.service_level_indicator.eks.type, "Service")
        })
      }, {}),
      try({
        source_service_key = try(slo.source_service_key, format("lambda:%s", slo.service_level_indicator.lambda.function_name))
        service_level_indicator = merge(slo.service_level_indicator, {
          environment = try(slo.service_level_indicator.environment, "lambda:default")
          name        = try(slo.service_level_indicator.lambda.function_name, slo.service_level_indicator.name)
          type        = try(slo.service_level_indicator.lambda.type, "Service")
        })
      }, {}),
      try({
        source_service_key = try(slo.source_service_key, format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name))
        service_level_indicator = merge(slo.service_level_indicator, {
          environment = try(slo.service_level_indicator.environment, format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name))
          name        = try(slo.service_level_indicator.name, slo.service_level_indicator.elasticbeanstalk.environment_name)
          type        = try(slo.service_level_indicator.type, "Service")
        })
      }, {}),
      try({
        source_service_key = try(slo.source_service_key, format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name))
        service_level_indicator = merge(slo.service_level_indicator, {
          environment = try(slo.service_level_indicator.environment, "synthetics:default")
          name        = try(slo.service_level_indicator.name, slo.service_level_indicator.synthetics.canary_name)
          type        = try(slo.service_level_indicator.type, "Service")
        })
      }, {}),
      try({
        source_service_key = try(slo.source_service_key, format("rum:%s", slo.service_level_indicator.rum.app_monitor_name))
        service_level_indicator = merge(slo.service_level_indicator, {
          environment = try(slo.service_level_indicator.environment, "rum:default")
          name        = try(slo.service_level_indicator.name, slo.service_level_indicator.rum.app_monitor_name)
          type        = try(slo.service_level_indicator.type, "Service")
        })
      }, {})
    )
  ]

  # CloudWatch RUM period-based SLI catalog keyed by metric_type; APDEX is request-based and built separately
  rum_sli_catalog = {
    LATENCY     = { metric_name = "PerformanceNavigationDuration", statistic = "Average", comparison = "LessThan", threshold = 3000 }
    JS_ERRORS   = { metric_name = "JsErrorCount", statistic = "Sum", comparison = "LessThan", threshold = null }
    HTTP_ERRORS = { metric_name = "HttpErrorCount", statistic = "Sum", comparison = "LessThan", threshold = null }
    LCP         = { metric_name = "WebVitalsLargestContentfulPaint", statistic = "p75", comparison = "LessThan", threshold = 2500 }
    CLS         = { metric_name = "WebVitalsCumulativeLayoutShift", statistic = "p75", comparison = "LessThan", threshold = 0.1 }
    FID         = { metric_name = "WebVitalsFirstInputDelay", statistic = "p75", comparison = "LessThan", threshold = 100 }
    INP         = { metric_name = "WebVitalsInteractionToNextPaint", statistic = "p75", comparison = "LessThan", threshold = 200 }
  }

  slo_operational = flatten([
    for slo in local.slo_set_env : [
      for operation in try(slo.service_level_indicator.operations, []) : {
        name        = format("%s %s %s OP", try(slo.name, slo.service_level_indicator.name), replace(replace(operation, "*", "ALL"), "/[\\/\\$\\%\\^]/", "-"), coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY"))
        description = coalesce(try(slo.description, null), "SLO Setting for ${try(slo.name, slo.service_level_indicator.name)} - Operation: ${replace(operation, "*", "ALL")} - Metric Type: ${coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
          try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = format("operational-%s-%s", replace(replace(operation, "*", "ALL"), "/[\\/\\$\\%\\^]/", "-"), coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY"))
        sli = {
          comparison_operator = coalesce(try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")) == "AVAILABILITY" ? "GreaterThan" : "LessThan")
          metric_threshold    = try(slo.service_level_indicator.threshold, null)
          sli_metric = {
            key_attributes = {
              Environment = slo.service_level_indicator.environment
              Name        = slo.service_level_indicator.name
              Type        = slo.service_level_indicator.type
            }
            metric_type    = coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")
            operation_name = contains(["ALL", "*"], upper(operation)) ? null : operation
            period_seconds = coalesce(try(slo.service_level_indicator.period_seconds, null), 60)
            statistic      = upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")) == "AVAILABILITY" ? null : coalesce(try(slo.service_level_indicator.statistic, null), "p99")
          }
        }
        goal = {
          attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
          interval = {
            rolling_interval = {
              duration      = coalesce(try(slo.goal.duration, null), 7)
              duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
            }
          }
          warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
        }
        alarm = try(slo.service_level_indicator.alarm, {})
        tags  = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "operational"
  ])

  # Operational Golden Signals, covers all operations "*" and all metric types (LATENCY, AVAILABILITY) for a given SLO
  slo_operational_golden = flatten([
    for slo in local.slo_set_env : [
      { # LATENCY SLO for all operations
        name        = format("%s LATENCY", try(slo.name, slo.service_level_indicator.name))
        description = coalesce(try(slo.description, null), "[Golden Signals] [Latency] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
          try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = "gs-operational-latency"
        sli = {
          comparison_operator = "LessThan"
          metric_threshold    = try(slo.service_level_indicator.latency_threshold, null)
          sli_metric = {
            key_attributes = {
              Environment = slo.service_level_indicator.environment
              Name        = slo.service_level_indicator.name
              Type        = slo.service_level_indicator.type
            }
            metric_type    = "LATENCY"
            operation_name = null
            period_seconds = coalesce(try(slo.service_level_indicator.period_seconds, null), 60)
            statistic      = coalesce(try(slo.service_level_indicator.statistic, null), "p99")
          }
        }
        goal = {
          attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
          interval = {
            rolling_interval = {
              duration      = coalesce(try(slo.goal.duration, null), 7)
              duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
            }
          }
          warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
        }
        alarm = try(slo.service_level_indicator.alarm, {})
        tags  = try(slo.tags, {})
      },
      { # AVAILABILITY SLO for all operations
        name        = format("%s AVAILABILITY", try(slo.name, slo.service_level_indicator.name))
        description = coalesce(try(slo.description, null), "[Golden Signals] [Availability] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
          try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = "gs-operational-availability"
        sli = {
          comparison_operator = "GreaterThan"
          metric_threshold    = try(slo.service_level_indicator.availability_threshold, null)
          sli_metric = {
            key_attributes = {
              Environment = slo.service_level_indicator.environment
              Name        = slo.service_level_indicator.name
              Type        = slo.service_level_indicator.type
            }
            metric_type    = "AVAILABILITY"
            operation_name = null
            period_seconds = coalesce(try(slo.service_level_indicator.period_seconds, null), 60)
            statistic      = null
          }
        }
        goal = {
          attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
          interval = {
            rolling_interval = {
              duration      = coalesce(try(slo.goal.duration, null), 7)
              duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
            }
          }
          warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
        }
        alarm = try(slo.service_level_indicator.alarm, {})
        tags  = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "golden-signal-op"
  ])

  # Golden Signals SLOs - (Latency, Traffic, Errors, Saturation)
  slo_golden_signals = flatten([
    for slo in local.slo_set_env : [
      {
        name        = format("gs-latency-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = coalesce(try(slo.description, null), "[Golden Signals] [Latency] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
          try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = "golden-latency"
        sli = {
          comparison_operator = coalesce(try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), "LessThan")
          metric_threshold    = slo.service_level_indicator.latency_threshold
          sli_metric = {
            metric_data_queries = [
              {
                account_id = try(slo.service_level_indicator.account_id, null)
                id         = "latencyQuery1"
                metric_stat = {
                  metric = {
                    namespace   = "ApplicationSignals"
                    metric_name = "Latency"
                    dimensions = [
                      {
                        name  = "Environment"
                        value = slo.service_level_indicator.environment
                      },
                      {
                        name  = "Service"
                        value = slo.service_level_indicator.name
                      }
                    ]
                  }
                  period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                  stat   = coalesce(try(slo.service_level_indicator.statistic, null), "Average")
                }
                return_data = true
              }
            ]
          }
        }
        goal = {
          attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
          interval = {
            rolling_interval = {
              duration      = coalesce(try(slo.goal.duration, null), 7)
              duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
            }
          }
          warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
        }
        alarm = try(slo.service_level_indicator.alarm, {})
        tags  = try(slo.tags, {})
      },
      {
        name        = format("gs-errors-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = coalesce(try(slo.description, null), "[Golden Signals] [Errors] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
          try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = "golden-errors"
        request_based_sli = {
          request_based_sli_metric = {
            monitored_request_count_metric = {
              bad_count_metric = [
                {
                  account_id = try(slo.service_level_indicator.account_id, null)
                  id         = "badCount1"
                  metric_stat = {
                    metric = {
                      namespace   = "ApplicationSignals"
                      metric_name = "Error"
                      dimensions = [
                        {
                          name  = "Environment"
                          value = slo.service_level_indicator.environment
                        },
                        {
                          name  = "Service"
                          value = slo.service_level_indicator.name
                        }
                      ]
                    }
                    period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                    stat   = "Average"
                  }
                  return_data = true
                }
              ]
            }
            total_request_count_metric = [
              {
                account_id = try(slo.service_level_indicator.account_id, null)
                id         = "totalCount1"
                metric_stat = {
                  metric = {
                    namespace   = "ApplicationSignals"
                    metric_name = "Latency"
                    dimensions = [
                      {
                        name  = "Environment"
                        value = slo.service_level_indicator.environment
                      },
                      {
                        name  = "Service"
                        value = slo.service_level_indicator.name
                      }
                    ]
                  }
                  period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                  stat   = "SampleCount"
                }
                return_data = true
              }
            ]
          }
        }
        goal = {
          attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
          interval = {
            rolling_interval = {
              duration      = coalesce(try(slo.goal.duration, null), 7)
              duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
            }
          }
        }
        alarm = try(slo.service_level_indicator.alarm, {})
        tags  = try(slo.tags, {})
      },
      {
        name        = format("gs-traffic-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = coalesce(try(slo.description, null), "[Golden Signals] [Traffic] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
          try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = "golden-traffic"
        sli = {
          comparison_operator = coalesce(try(slo.service_level_indicator.traffic_comparison, null), try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), "LessThanOrEqualTo")
          metric_threshold    = slo.service_level_indicator.traffic_threshold
          sli_metric = {
            metric_data_queries = [
              {
                account_id = try(slo.service_level_indicator.account_id, null)
                id         = "trafficQuery1"
                metric_stat = {
                  metric = {
                    namespace   = "ApplicationSignals"
                    metric_name = "Latency"
                    dimensions = [
                      {
                        name  = "Environment"
                        value = slo.service_level_indicator.environment
                      },
                      {
                        name  = "Service"
                        value = slo.service_level_indicator.name
                      }
                    ]
                  }
                  period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                  stat   = "SampleCount"
                }
                return_data = true
              }
            ]
          }
        }
        goal = {
          attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
          interval = {
            rolling_interval = {
              duration      = coalesce(try(slo.goal.duration, null), 7)
              duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
            }
          }
          warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
        }
        alarm = try(slo.service_level_indicator.alarm, {})
        tags  = try(slo.tags, {})
      },
      {
        name        = format("gs-saturation-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = coalesce(try(slo.description, null), "[Golden Signals] [Saturation] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
          try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = "golden-saturation"
        sli = {
          comparison_operator = coalesce(try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), "LessThan")
          metric_threshold    = slo.service_level_indicator.saturation_threshold
          sli_metric = {
            metric_data_queries = [
              {
                account_id  = try(slo.service_level_indicator.account_id, null)
                id          = "saturationPercentage"
                expression  = try(slo.service_level_indicator.eks, null) != null ? "100 * (saturationQuery1)" : "saturationQuery1"
                return_data = true
              },
              {
                account_id = try(slo.service_level_indicator.account_id, null)
                id         = "saturationQuery1"
                metric_stat = {
                  metric = {
                    namespace   = try(slo.service_level_indicator.eks, null) != null ? "ContainerInsights" : "AWS/Lambda"
                    metric_name = try(slo.service_level_indicator.eks, null) != null ? (upper(coalesce(try(slo.service_level_indicator.saturation_metric, null), "CPU")) == "CPU" ? "pod_cpu_utilization_over_pod_limit" : "pod_memory_utilization_over_pod_limit") : "Throttles"
                    dimensions = try(slo.service_level_indicator.eks, null) != null ? [
                      {
                        name  = "ClusterName"
                        value = slo.service_level_indicator.eks.cluster_name
                      },
                      {
                        name  = "Namespace"
                        value = slo.service_level_indicator.eks.namespace
                      },
                      {
                        name  = "Service"
                        value = slo.service_level_indicator.eks.name
                      }
                      ] : [
                      {
                        name  = "FunctionName"
                        value = slo.service_level_indicator.lambda.function_name
                      }
                    ]
                  }
                  period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                  stat   = "Average"
                }
                return_data = false
              }
            ]
          }
        }
        goal = {
          attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
          interval = {
            rolling_interval = {
              duration      = coalesce(try(slo.goal.duration, null), 7)
              duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
            }
          }
          warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
        }
        alarm = try(slo.service_level_indicator.alarm, {})
        tags  = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "golden-signal"
  ])

  slo_metric_query = [
    for slo in local.slo_set_env : {
      name        = try(slo.name, format("%s-metric-query", slo.service_level_indicator.name))
      description = coalesce(try(slo.description, null), "Metric query SLO for ${try(slo.name, slo.service_level_indicator.name)}")
      source_service_key = try(slo.source_service_key,
        try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
        try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
        try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
        try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
        try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
        "custom:${try(slo.name, slo.service_level_indicator.name)}"
      )
      slo_key = try(slo.name, "metric-query")
      sli = {
        comparison_operator = coalesce(try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), "LessThan")
        metric_threshold    = slo.service_level_indicator.threshold
        sli_metric = {
          metric_data_queries = [
            {
              account_id = try(slo.service_level_indicator.account_id, null)
              id         = "metricQuery1"
              metric_stat = {
                metric = {
                  namespace   = local.monitor_definition_map[slo.preset].namespace
                  metric_name = local.monitor_definition_map[slo.preset].metric_name
                  dimensions = [
                    for dim_name, dim_value in try(local.monitor_definition_map[slo.preset].dimensions, {}) : {
                      name = dim_name
                      value = replace(
                        replace(tostring(dim_value), "$${group.service_name}", slo.service_level_indicator.name),
                        "$${group.stage}", try(slo.service_level_indicator.stage, "")
                      )
                    }
                  ]
                }
                period = coalesce(try(slo.service_level_indicator.period_seconds, null), try(local.monitor_definition_map[slo.preset].period, null), 60)
                stat   = coalesce(try(slo.service_level_indicator.statistic, null), try(local.monitor_definition_map[slo.preset].statistic, null), "Average")
              }
              return_data = true
            }
          ]
        }
      }
      goal = {
        attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
        interval = {
          rolling_interval = {
            duration      = coalesce(try(slo.goal.duration, null), 7)
            duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
          }
        }
        warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
      }
      alarm = try(slo.service_level_indicator.alarm, {})
      tags  = try(slo.tags, {})
    }
    if try(slo.enabled, true) && slo.type == "metric-query"
  ]

  slo_request_based = [
    for slo in local.slo_set_env : {
      name        = try(slo.name, format("%s-request-based", slo.service_level_indicator.name))
      description = coalesce(try(slo.description, null), "Request-based SLO for ${try(slo.name, slo.service_level_indicator.name)}")
      source_service_key = try(slo.source_service_key,
        try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
        try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
        try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
        try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
        try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
        "custom:${try(slo.name, slo.service_level_indicator.name)}"
      )
      slo_key = try(slo.name, "request-based")
      request_based_sli = {
        request_based_sli_metric = {
          monitored_request_count_metric = {
            bad_count_metric = [
              {
                account_id = try(slo.service_level_indicator.account_id, null)
                id         = "badCount1"
                metric_stat = {
                  metric = {
                    namespace   = "AWS/ElasticBeanstalk"
                    metric_name = "ApplicationRequests5xx"
                    dimensions = [
                      {
                        name  = "EnvironmentName"
                        value = slo.service_level_indicator.elasticbeanstalk.environment_name
                      }
                    ]
                  }
                  period = coalesce(try(slo.service_level_indicator.period_seconds, null), 60)
                  stat   = "Sum"
                }
                return_data = true
              }
            ]
          }
          total_request_count_metric = [
            {
              account_id = try(slo.service_level_indicator.account_id, null)
              id         = "totalCount1"
              metric_stat = {
                metric = {
                  namespace   = "AWS/ElasticBeanstalk"
                  metric_name = "ApplicationRequestsTotal"
                  dimensions = [
                    {
                      name  = "EnvironmentName"
                      value = slo.service_level_indicator.elasticbeanstalk.environment_name
                    }
                  ]
                }
                period = coalesce(try(slo.service_level_indicator.period_seconds, null), 60)
                stat   = "Sum"
              }
              return_data = true
            }
          ]
        }
      }
      goal = {
        attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
        interval = {
          rolling_interval = {
            duration      = coalesce(try(slo.goal.duration, null), 7)
            duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
          }
        }
        warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
      }
      alarm = try(slo.service_level_indicator.alarm, {})
      tags  = try(slo.tags, {})
    }
    if try(slo.enabled, true) && slo.type == "request-based" && try(slo.preset, null) == "eb_5xx_availability"
  ]

  # CloudWatch Synthetics canary SLOs - SuccessPercent (AVAILABILITY) or Duration (LATENCY)
  slo_synthetics = [
    for slo in local.slo_set_env : {
      name        = try(slo.name, format("%s-synthetics-%s", slo.service_level_indicator.synthetics.canary_name, lower(coalesce(try(slo.service_level_indicator.metric_type, null), "AVAILABILITY"))))
      description = coalesce(try(slo.description, null), "[Synthetics] [${upper(coalesce(try(slo.service_level_indicator.metric_type, null), "AVAILABILITY"))}] SLO for canary ${slo.service_level_indicator.synthetics.canary_name}")
      source_service_key = try(slo.source_service_key,
        try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
        try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
        try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
        try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
        try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
        "custom:${try(slo.name, slo.service_level_indicator.name)}"
      )
      slo_key = format("synthetics-%s", lower(coalesce(try(slo.service_level_indicator.metric_type, null), "AVAILABILITY")))
      sli = {
        comparison_operator = coalesce(try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), upper(coalesce(try(slo.service_level_indicator.metric_type, null), "AVAILABILITY")) == "AVAILABILITY" ? "GreaterThanOrEqualTo" : "LessThan")
        metric_threshold    = try(slo.service_level_indicator.threshold, null) != null ? slo.service_level_indicator.threshold : (upper(coalesce(try(slo.service_level_indicator.metric_type, null), "AVAILABILITY")) == "AVAILABILITY" ? 100 : null)
        sli_metric = {
          metric_data_queries = [
            {
              account_id = try(slo.service_level_indicator.account_id, null)
              id         = "syntheticsQuery1"
              metric_stat = {
                metric = {
                  namespace   = "CloudWatchSynthetics"
                  metric_name = upper(coalesce(try(slo.service_level_indicator.metric_type, null), "AVAILABILITY")) == "AVAILABILITY" ? "SuccessPercent" : "Duration"
                  dimensions = [
                    {
                      name  = "CanaryName"
                      value = slo.service_level_indicator.synthetics.canary_name
                    }
                  ]
                }
                period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                stat   = coalesce(try(slo.service_level_indicator.statistic, null), "Average")
              }
              return_data = true
            }
          ]
        }
      }
      goal = {
        attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
        interval = {
          rolling_interval = {
            duration      = coalesce(try(slo.goal.duration, null), 7)
            duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
          }
        }
        warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
      }
      alarm = try(slo.service_level_indicator.alarm, {})
      tags  = try(slo.tags, {})
    }
    if try(slo.enabled, true) && slo.type == "synthetics"
  ]

  # CloudWatch RUM app monitor SLOs - period-based (LATENCY, web vitals, error counts)
  slo_rum_metric = [
    for slo in local.slo_set_env : {
      name        = try(slo.name, format("%s-rum-%s", slo.service_level_indicator.rum.app_monitor_name, replace(lower(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")), "_", "-")))
      description = coalesce(try(slo.description, null), "[RUM] [${upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY"))}] SLO for app monitor ${slo.service_level_indicator.rum.app_monitor_name}")
      source_service_key = try(slo.source_service_key,
        try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
        try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
        try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
        try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
        try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
        "custom:${try(slo.name, slo.service_level_indicator.name)}"
      )
      slo_key = format("rum-%s", replace(lower(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")), "_", "-"))
      sli = {
        comparison_operator = coalesce(try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), local.rum_sli_catalog[upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY"))].comparison)
        metric_threshold    = try(slo.service_level_indicator.threshold, null) != null ? slo.service_level_indicator.threshold : local.rum_sli_catalog[upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY"))].threshold
        sli_metric = {
          metric_data_queries = [
            {
              account_id = try(slo.service_level_indicator.account_id, null)
              id         = "rumQuery1"
              metric_stat = {
                metric = {
                  namespace   = "AWS/RUM"
                  metric_name = local.rum_sli_catalog[upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY"))].metric_name
                  dimensions = [
                    {
                      name  = "application_name"
                      value = slo.service_level_indicator.rum.app_monitor_name
                    }
                  ]
                }
                period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                stat   = coalesce(try(slo.service_level_indicator.statistic, null), local.rum_sli_catalog[upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY"))].statistic)
              }
              return_data = true
            }
          ]
        }
      }
      goal = {
        attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
        interval = {
          rolling_interval = {
            duration      = coalesce(try(slo.goal.duration, null), 7)
            duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
          }
        }
        warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
      }
      alarm = try(slo.service_level_indicator.alarm, {})
      tags  = try(slo.tags, {})
    }
    if try(slo.enabled, true) && slo.type == "rum" && upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")) != "APDEX"
  ]

  # CloudWatch RUM app monitor SLOs - APDEX request-based (frustrated navigations vs. all navigations)
  slo_rum_apdex = [
    for slo in local.slo_set_env : {
      name        = try(slo.name, format("%s-rum-apdex", slo.service_level_indicator.rum.app_monitor_name))
      description = coalesce(try(slo.description, null), "[RUM] [APDEX] SLO for app monitor ${slo.service_level_indicator.rum.app_monitor_name}")
      source_service_key = try(slo.source_service_key,
        try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
        try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
        try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
        try(slo.service_level_indicator.synthetics, null) != null ? format("synthetics:%s", slo.service_level_indicator.synthetics.canary_name) :
        try(slo.service_level_indicator.rum, null) != null ? format("rum:%s", slo.service_level_indicator.rum.app_monitor_name) :
        "custom:${try(slo.name, slo.service_level_indicator.name)}"
      )
      slo_key = "rum-apdex"
      request_based_sli = {
        request_based_sli_metric = {
          monitored_request_count_metric = {
            bad_count_metric = [
              {
                account_id = try(slo.service_level_indicator.account_id, null)
                id         = "frustratedCount"
                metric_stat = {
                  metric = {
                    namespace   = "AWS/RUM"
                    metric_name = "NavigationFrustratedTransaction"
                    dimensions = [
                      {
                        name  = "application_name"
                        value = slo.service_level_indicator.rum.app_monitor_name
                      }
                    ]
                  }
                  period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                  stat   = "Sum"
                }
                return_data = true
              }
            ]
          }
          total_request_count_metric = concat([
            for nav in ["Satisfied", "Tolerated", "Frustrated"] : {
              account_id = try(slo.service_level_indicator.account_id, null)
              id         = format("%sCount", lower(nav))
              metric_stat = {
                metric = {
                  namespace   = "AWS/RUM"
                  metric_name = format("Navigation%sTransaction", nav)
                  dimensions = [
                    {
                      name  = "application_name"
                      value = slo.service_level_indicator.rum.app_monitor_name
                    }
                  ]
                }
                period = coalesce(try(slo.service_level_indicator.period_seconds, null), 300)
                stat   = "Sum"
              }
              return_data = false
              }], [{
              account_id  = try(slo.service_level_indicator.account_id, null)
              id          = "totalCount"
              expression  = "satisfiedCount + toleratedCount + frustratedCount"
              return_data = true
            }]
          )
        }
      }
      goal = {
        attainment_goal = coalesce(try(slo.goal.attainment, null), 99.9)
        interval = {
          rolling_interval = {
            duration      = coalesce(try(slo.goal.duration, null), 7)
            duration_unit = coalesce(try(slo.goal.duration_unit, null), "DAY")
          }
        }
        warning_threshold = coalesce(try(slo.goal.warning_threshold, null), 80)
      }
      alarm = try(slo.service_level_indicator.alarm, {})
      tags  = try(slo.tags, {})
    }
    if try(slo.enabled, true) && slo.type == "rum" && upper(coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")) == "APDEX"
  ]

  slo_all = concat(local.slo_operational, local.slo_golden_signals, local.slo_metric_query, local.slo_request_based, local.slo_synthetics, local.slo_rum_metric, local.slo_rum_apdex, local.slo_operational_golden)
}

resource "awscc_applicationsignals_service_level_objective" "slo" {
  for_each = {
    for slo in local.slo_all : slo.name => slo
  }
  name              = each.value.name
  description       = each.value.description
  sli               = try(each.value.sli, null)
  goal              = try(each.value.goal, null)
  request_based_sli = try(each.value.request_based_sli, null)
  burn_rate_configurations = try(each.value.alarm.enabled, false) ? [{
    look_back_window_minutes = coalesce(try(each.value.alarm.look_back_window_minutes, null), 60)
  }] : try(each.value.burn_rate_configurations, null)
  exclusion_windows = try(each.value.exclusion_windows, null)
  tags = toset([
    for k, v in merge(local.all_tags, each.value.tags) : {
      key   = k
      value = v
    }
  ])
}
