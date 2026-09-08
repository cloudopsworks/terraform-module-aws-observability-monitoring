##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

mock_provider "awscc" {}

run "existing_eks_v2_compatibility" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    services = yamldecode(file("tests/fixtures/eks-v2-inputs.yaml")).services
  }

  assert {
    condition     = length(output.alarm_names["eks:eks-nexus-main-prod-003-usea1/checkout-prod/checkout-helm"]) == 5
    error_message = "Existing EKS v2 monitors must remain compatible."
  }

  assert {
    condition     = length(output.slo_names["eks:eks-nexus-main-prod-003-usea1/checkout-prod/checkout-helm"]) == 4
    error_message = "Existing EKS Golden Signal SLOs must remain compatible."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.slo) == 0
    error_message = "Typed service SLO alarms must remain disabled unless explicitly enabled."
  }
}

run "existing_elasticbeanstalk_v2_compatibility" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    services = yamldecode(file("tests/fixtures/elasticbeanstalk-v2-inputs.yaml")).services
  }

  assert {
    condition     = length(output.alarm_names["elasticbeanstalk:payments/payments-prod"]) == 4
    error_message = "Existing Elastic Beanstalk alarms must remain compatible."
  }

  assert {
    condition     = length(output.slo_names["elasticbeanstalk:payments/payments-prod"]) == 2
    error_message = "Existing Elastic Beanstalk SLOs must remain compatible."
  }
}

run "aws_infrastructure_golden_signals" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    services = yamldecode(file("tests/fixtures/aws-golden-signals-v2-inputs.yaml")).services
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.monitor) == 9
    error_message = "Expected nine Golden Signal alarms after dashboard-only traffic presets are excluded."
  }

  assert {
    condition     = length(output.alarm_names["apigateway:orders-api/prod"]) == 3
    error_message = "API Gateway alarms must use the API/stage canonical key."
  }

  assert {
    condition     = length(output.alarm_names["ec2:i-0123456789abcdef0"]) == 2
    error_message = "EC2 alarms must use the instance canonical key and inherit dashboard-only traffic defaults."
  }

  assert {
    condition     = length(output.alarm_names["alb:app/public-alb/50dc6c495c0c9188"]) == 4
    error_message = "Application Load Balancer alarms must use the ARN-suffix canonical key."
  }

  assert {
    condition     = length(output.slo_names) == 3
    error_message = "Each infrastructure service must produce its metric-query SLO."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.monitor["[P2] [platform] [prod] [orders-api] LATENCY - apigateway - production"].extended_statistic == "p99"
    error_message = "Direct percentile alarms must use extended_statistic."
  }

  assert {
    condition = one([
      for dimension in awscc_applicationsignals_service_level_objective.slo["orders-api-latency"].sli.sli_metric.metric_data_queries[0].metric_stat.metric.dimensions : dimension.value
      if dimension.name == "Stage"
    ]) == "prod"
    error_message = "API Gateway metric-query SLOs must render the Stage dimension."
  }
}

run "legacy_inline_custom_monitor" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    monitor_groups = yamldecode(file("tests/fixtures/custom-monitor-inputs.yaml")).monitor_groups
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.monitor["[P2] [platform] [prod] [payments-prod] QUEUE DEPTH - custom - production"].metric_name == "ApproximateNumberOfMessagesVisible"
    error_message = "A custom monitor must accept its metric definition inline."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.monitor["[P2] [platform] [prod] [payments-prod] QUEUE DEPTH - custom - production"].dimensions.QueueName == "payments-prod"
    error_message = "A custom monitor must preserve inline metric dimensions."
  }

  assert {
    condition     = length(aws_cloudwatch_dashboard.service) == 0 && length(aws_cloudwatch_dashboard.fleet) == 0
    error_message = "Dashboards must be disabled by default."
  }
}

run "named_monitor_group_fleet_dashboard" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    monitor_groups = yamldecode(file("tests/fixtures/custom-monitor-inputs.yaml")).monitor_groups
    dashboard_settings = {
      enabled            = true
      name_prefix        = "observability"
      create_fleet       = true
      create_per_service = false
    }
  }

  assert {
    condition     = keys(aws_cloudwatch_dashboard.fleet) == ["payments"]
    error_message = "Each named monitor group must own its fleet dashboard."
  }

  assert {
    condition     = aws_cloudwatch_dashboard.fleet["payments"].dashboard_name == "observability-payments-fleet"
    error_message = "The fleet dashboard name must include its monitor group name."
  }
}

run "operational_availability_omits_statistic" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    slo_settings = {
      service_level_objectives = [
        {
          name = "checkout-availability"
          type = "operational"
          service_level_indicator = {
            environment = "eks:platform/checkout"
            name        = "checkout"
            type        = "Service"
            threshold   = 1
            metric_type = "AVAILABILITY"
            operations  = ["GET /health"]
          }
          goal = {}
        }
      ]
    }
  }

  assert {
    condition     = awscc_applicationsignals_service_level_objective.slo["checkout-availability GET -health AVAILABILITY OP"].sli.sli_metric.statistic == null
    error_message = "Operational availability SLOs must omit the latency-only statistic."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.slo) == 0
    error_message = "Legacy service-level indicator alarms must remain disabled unless explicitly enabled."
  }
}

run "legacy_slo_burn_rate_alarm" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    slo_settings = {
      service_level_objectives = [
        {
          name = "checkout-availability"
          type = "operational"
          service_level_indicator = {
            environment = "eks:platform/checkout"
            name        = "checkout"
            type        = "Service"
            threshold   = 1
            metric_type = "AVAILABILITY"
            operations  = ["GET /health"]
            alarm = {
              enabled                  = true
              priority                 = 2
              threshold                = 2
              datapoints_to_alarm      = 3
              period                   = 120
              look_back_window_minutes = 30
            }
          }
          goal = {}
        }
      ]
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.slo) == 1
    error_message = "An enabled legacy SLI burn-rate alarm must create one alarm per expanded SLO."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.slo["checkout-availability GET -health AVAILABILITY OP"].alarm_name == "[P2] [SLO] [platform] [prod] [checkout] checkout-availability GET -health AVAILABILITY OP - custom - production"
    error_message = "Legacy SLO alarms must follow the monitor naming pattern with the SLO marker."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.slo["checkout-availability GET -health AVAILABILITY OP"].threshold == 2 &&
      aws_cloudwatch_metric_alarm.slo["checkout-availability GET -health AVAILABILITY OP"].datapoints_to_alarm == 3 &&
      aws_cloudwatch_metric_alarm.slo["checkout-availability GET -health AVAILABILITY OP"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.slo["checkout-availability GET -health AVAILABILITY OP"].period == 120
    )
    error_message = "Legacy SLO alarm overrides must be applied."
  }

  assert {
    condition     = one(awscc_applicationsignals_service_level_objective.slo["checkout-availability GET -health AVAILABILITY OP"].burn_rate_configurations).look_back_window_minutes == 30
    error_message = "Enabling a legacy SLO alarm must configure its burn-rate look-back window."
  }
}

run "service_slo_burn_rate_alarm_defaults" {
  command = plan

  variables {
    org = {
      organization_name = "Cloud Ops Works"
      organization_unit = "Platform"
      environment_type  = "production"
      environment_name  = "prod"
    }
    services = {
      orders = {
        resource_type = "api_gateway"
        resource = {
          api_gateway = {
            api_name = "orders-api"
            stage    = "prod"
          }
        }
        slos = {
          latency = {
            type       = "metric-query"
            preset     = "lat_apigateway_service_requests"
            comparison = "LessThan"
            threshold  = 500
            alarm = {
              enabled = true
            }
          }
        }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.slo["orders-latency"].alarm_name == "[P1] [SLO] [platform] [prod] [orders-api] orders-latency - apigateway - production"
    error_message = "Typed service SLO alarms must use the canonical service identity and SLO naming pattern."
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.slo["orders-latency"].threshold == 1 &&
      aws_cloudwatch_metric_alarm.slo["orders-latency"].datapoints_to_alarm == 1 &&
      aws_cloudwatch_metric_alarm.slo["orders-latency"].evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.slo["orders-latency"].period == 60 &&
      aws_cloudwatch_metric_alarm.slo["orders-latency"].metric_name == "BurnRate" &&
      aws_cloudwatch_metric_alarm.slo["orders-latency"].namespace == "AWS/ApplicationSignals"
    )
    error_message = "Typed service SLO alarm defaults must match the accepted burn-rate configuration."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.slo["orders-latency"].dimensions.BurnRateWindowMinutes == "60"
    error_message = "Typed service SLO alarms must default the burn-rate look-back window to 60 minutes."
  }
}
