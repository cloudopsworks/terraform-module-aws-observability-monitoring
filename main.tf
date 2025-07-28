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
  slo_set_env = [
    for slo in local.slo_in : merge(slo,
      length(try(slo.service_level_indicator.eks, {})) > 0 ? {
        service_level_indicator = merge(slo.service_level_indicator, {
          environment = format("eks:%s/%s", slo.service_level_indicator.eks.cluster_name, slo.service_level_indicator.eks.namespace)
          name        = try(slo.service_level_indicator.eks.name, slo.service_level_indicator.name)
          type        = try(slo.service_level_indicator.eks.type, "Service")
        })
      } : {},
      length(try(slo.service_level_indicator.lambda, {})) > 0 ? {
        service_level_indicator = merge(slo.service_level_indicator, {
          environment = format("lambda:%s", slo.service_level_indicator.lambda.function_name)
          name        = try(slo.service_level_indicator.lambda.function_name, slo.service_level_indicator.name)
          type        = try(slo.service_level_indicator.lambda.type, "Service")
        })
      } : {},
    )
  ]
  slo_operational = flatten([
    for slo in local.slo_set_env : [
      for operation in slo.service_level_indicator.operations : {
        name        = format("%s %s op", try(slo.name, slo.service_level_indicator.name), replace(operation, "/[\\/\\$\\%\\^]/", "-"))
        description = try(slo.description, "SLO Setting for ${try(slo.name, slo.service_level_indicator.name)} - ${operation}")
        sli = {
          comparison_operator = try(slo.service_level_indicator.comparisson, "LessThan")
          metric_threshold    = try(slo.service_level_indicator.threshold, null)
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
          warning_threshold = try(slo.goal.warning_threshold, 80)
        }
        tags = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "operational"
  ])
  # Golden Signals SLOs - (Latency, Traffic, Errors, Saturation)
  slo_golden_signals = flatten([
    for slo in local.slo_set_env : [
      # Latency signal
      {
        name        = format("gs-latency-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = try(slo.description, "[Golden Signals] [Latency] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        sli = {
          comparison_operator = try(slo.service_level_indicator.comparisson, "LessThan")
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
                  period = try(slo.service_level_indicator.period_seconds, 300)
                  stat   = try(slo.service_level_indicator.statistic, "Average")
                }
                return_data = true
              }
            ]
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
          warning_threshold = try(slo.goal.warning_threshold, 80)
        }
        tags = try(slo.tags, {})
      },
      # Errors Signal
      {
        name        = format("gs-errors-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = try(slo.description, "[Golden Signals] [Errors] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
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
                    period = try(slo.service_level_indicator.period_seconds, 300)
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
                  period = try(slo.service_level_indicator.period_seconds, 300)
                  stat   = "SampleCount"
                }
                return_data = true
              }
            ]
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
      },
      # Traffic Signal
      {
        name        = format("gs-traffic-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = try(slo.description, "[Golden Signals] [Traffic] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        sli = {
          comparison_operator = try(slo.service_level_indicator.comparisson, "LessThanOrEqualTo")
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
                  period = try(slo.service_level_indicator.period_seconds, 300)
                  stat   = "SampleCount"
                }
                return_data = true
              }
            ]
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
          warning_threshold = try(slo.goal.warning_threshold, 80)
        }
        tags = try(slo.tags, {})
      },
      # Saturation Signal
      {
        name        = format("gs-saturation-%s", lower(try(slo.name, slo.service_level_indicator.name)))
        description = try(slo.description, "[Golden Signals] [Saturation] SLO for ${try(slo.name, slo.service_level_indicator.name)}")
        sli = {
          comparison_operator = try(slo.service_level_indicator.comparisson, "LessThan")
          metric_threshold    = slo.service_level_indicator.saturation_threshold
          sli_metric = {
            metric_data_queries = [
              {
                account_id = try(slo.service_level_indicator.account_id, null)
                id         = "saturationQuery1"
                metric_stat = {
                  metric = {
                    namespace   = "ContainerInsights"
                    metric_name = upper(slo.service_level_indicator.saturation_metric) == "CPU" ? "pod_cpu_utilization_over_pod_limit" : "pod_memory_utilization_over_pod_limit"
                    dimensions = [
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
                    ]
                  }
                  period = try(slo.service_level_indicator.period_seconds, 300)
                  stat   = "Average"
                }
                return_data = true
              }
            ]
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
          warning_threshold = try(slo.goal.warning_threshold, 80)
        }
        tags = try(slo.tags, {})
      }
    ] if try(slo.enabled, true) && slo.type == "golden-signal"
  ])

  slo_all = concat(local.slo_operational, local.slo_golden_signals, [])
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