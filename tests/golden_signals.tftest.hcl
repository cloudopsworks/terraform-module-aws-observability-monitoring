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
