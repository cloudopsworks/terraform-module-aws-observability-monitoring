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
      }, {})
    )
  ]

  slo_operational = flatten([
    for slo in local.slo_set_env : [
      for operation in try(slo.service_level_indicator.operations, []) : {
        name        = format("%s %s op", try(slo.name, slo.service_level_indicator.name), replace(operation, "/[\\/\\$\\%\\^]/", "-"))
        description = coalesce(try(slo.description, null), "SLO Setting for ${try(slo.name, slo.service_level_indicator.name)} - ${operation}")
        source_service_key = try(slo.source_service_key,
          try(slo.service_level_indicator.eks, null) != null ? format("eks:%s/%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace, slo.service_level_indicator.eks.name) :
          try(slo.service_level_indicator.lambda, null) != null ? format("lambda:%s", slo.service_level_indicator.lambda.function_name) :
          try(slo.service_level_indicator.elasticbeanstalk, null) != null ? format("elasticbeanstalk:%s/%s", slo.service_level_indicator.elasticbeanstalk.application_name, slo.service_level_indicator.elasticbeanstalk.environment_name) :
          "custom:${try(slo.name, slo.service_level_indicator.name)}"
        )
        slo_key = format("operational-%s", replace(operation, "/[\\/\\$\\%\\^\\s]+/", "-"))
        sli = {
          comparison_operator = coalesce(try(slo.service_level_indicator.comparison, null), try(slo.service_level_indicator.comparisson, null), "LessThan")
          metric_threshold    = try(slo.service_level_indicator.threshold, null)
          sli_metric = {
            key_attributes = {
              Environment = slo.service_level_indicator.environment
              Name        = slo.service_level_indicator.name
              Type        = slo.service_level_indicator.type
            }
            metric_type    = coalesce(try(slo.service_level_indicator.metric_type, null), "LATENCY")
            operation_name = operation
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
        tags = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "operational"
  ])

  # Golden Signals SLOs - (Latency, Traffic, Errors, Saturation)
  slo_golden_signals = flatten([
    for slo in local.slo_set_env : [
      {
        name               = format("gs-latency-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description        = coalesce(try(slo.description, null), "[Golden Signals] [Latency] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key, "")
        slo_key            = "golden-latency"
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
        tags = try(slo.tags, {})
      },
      {
        name               = format("gs-errors-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description        = coalesce(try(slo.description, null), "[Golden Signals] [Errors] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key, "")
        slo_key            = "golden-errors"
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
        tags = try(slo.tags, {})
      },
      {
        name               = format("gs-traffic-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description        = coalesce(try(slo.description, null), "[Golden Signals] [Traffic] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key, "")
        slo_key            = "golden-traffic"
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
        tags = try(slo.tags, {})
      },
      {
        name               = format("gs-saturation-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description        = coalesce(try(slo.description, null), "[Golden Signals] [Saturation] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        source_service_key = try(slo.source_service_key, "")
        slo_key            = "golden-saturation"
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
        tags = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "golden-signal"
  ])

  slo_metric_query = [
    for slo in local.slo_set_env : {
      name               = try(slo.name, format("%s-metric-query", slo.service_level_indicator.name))
      description        = coalesce(try(slo.description, null), "Metric query SLO for ${try(slo.name, slo.service_level_indicator.name)}")
      source_service_key = try(slo.source_service_key, "")
      slo_key            = try(slo.name, "metric-query")
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
                      name  = dim_name
                      value = replace(tostring(dim_value), "$${group.service_name}", slo.service_level_indicator.name)
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
      tags = try(slo.tags, {})
    }
    if try(slo.enabled, true) && slo.type == "metric-query"
  ]

  slo_request_based = [
    for slo in local.slo_set_env : {
      name               = try(slo.name, format("%s-request-based", slo.service_level_indicator.name))
      description        = coalesce(try(slo.description, null), "Request-based SLO for ${try(slo.name, slo.service_level_indicator.name)}")
      source_service_key = try(slo.source_service_key, "")
      slo_key            = try(slo.name, "request-based")
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
      tags = try(slo.tags, {})
    }
    if try(slo.enabled, true) && slo.type == "request-based" && try(slo.preset, null) == "eb_5xx_availability"
  ]

  slo_all = concat(local.slo_operational, local.slo_golden_signals, local.slo_metric_query, local.slo_request_based)
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
