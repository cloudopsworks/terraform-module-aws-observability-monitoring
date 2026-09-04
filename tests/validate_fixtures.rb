#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
FIXTURES = File.join(ROOT, "tests", "fixtures")
ORG = {
  "organization_unit" => "Nexus",
  "environment_name" => "Main",
  "environment_type" => "Prod"
}.freeze

EXPECTED_ALARMS = [
  "[P2] [nexus] [main] [checkout-helm] REQUEST LATENCY - eks - prod",
  "[P1] [nexus] [main] [checkout-helm] REQUEST ERROR RATE - eks - prod",
  "[P3] [nexus] [main] [checkout-helm] REQUEST COUNT - eks - prod",
  "[P3] [nexus] [main] [checkout-helm] CPU USAGE - eks - prod",
  "[P3] [nexus] [main] [checkout-helm] MEMORY USAGE - eks - prod",
  "[P2] [nexus] [main] [auth-lambda-prod] REQUEST LATENCY - lambda - prod",
  "[P1] [nexus] [main] [auth-lambda-prod] REQUEST ERROR RATE - lambda - prod",
  "[P3] [nexus] [main] [auth-lambda-prod] REQUEST COUNT - lambda - prod"
].freeze

EXPECTED_SLOS = [
  "gs-latency-checkout",
  "gs-errors-checkout",
  "gs-traffic-checkout",
  "gs-saturation-checkout",
  "gs-latency-marketplace",
  "gs-errors-marketplace",
  "gs-traffic-marketplace",
  "gs-saturation-marketplace",
  "gs-latency-marketplace-mc",
  "gs-errors-marketplace-mc",
  "gs-traffic-marketplace-mc",
  "gs-saturation-marketplace-mc",
  "sink GET -api-sink-v2-grouped op",
  "sink GET -api-sink-v2-codes op"
].freeze

def assert(condition, message)
  raise message unless condition
end

def monitored_resources(inputs)
  inputs.fetch("monitor_groups").flat_map { |group| group.fetch("monitors") }
end

def alarm_names(inputs)
  monitored_resources(inputs).flat_map do |resource|
    resource.fetch("monitors").map do |monitor|
      format("[P%s] [%s] [%s] [%s] %s - %s - %s",
             monitor.fetch("priority"),
             ORG.fetch("organization_unit").downcase,
             ORG.fetch("environment_name").downcase,
             resource.fetch("service_name"),
             monitor.fetch("name"),
             resource.fetch("type"),
             ORG.fetch("environment_type").downcase)
    end
  end
end

def slo_names(inputs)
  inputs.fetch("slos").fetch("service_level_objectives").flat_map do |slo|
    case slo.fetch("type")
    when "golden-signal"
      %w[latency errors traffic saturation].map { |signal| "gs-#{signal}-#{slo.fetch("name").downcase}" }
    when "operational"
      slo.fetch("service_level_indicator").fetch("operations").map do |operation|
        "#{slo.fetch("name")} #{operation.gsub(/[\/$%^]/, "-")} op"
      end
    else
      []
    end
  end
end

nexus = YAML.load_file(File.join(FIXTURES, "nexus-catalog-svc-inputs.yaml"))
assert(alarm_names(nexus) == EXPECTED_ALARMS, "Nexus legacy alarm names changed")
assert(slo_names(nexus) == EXPECTED_SLOS, "Nexus legacy SLO names changed")
assert(nexus.fetch("alarm_targets") == [], "Nexus fixture must keep alarm_targets empty")

config = YAML.load_file(File.join(ROOT, "observability-config.yaml"))
config_by_name = config.to_h { |entry| [entry.fetch("name"), entry] }
config_names = config_by_name.keys
assert(config_names.include?("custom"), "Missing inline custom monitor target")
monitored_resources(nexus).flat_map { |resource| resource.fetch("monitors") }.each do |monitor|
  assert(config_names.include?(monitor.fetch("target_name")), "Missing monitor preset #{monitor.fetch("target_name")}")
end

%w[eb_environment_health eb_latency_p99 eb_5xx_count eb_requests_total eb_instances_severe sat_lambda_concurrent_executions].each do |preset|
  assert(config_names.include?(preset), "Missing new monitor preset #{preset}")
end

golden_signals = YAML.load_file(File.join(FIXTURES, "aws-golden-signals-v2-inputs.yaml")).fetch("services")
expected_services = {
  "orders-api" => {
    "resource_type" => "api_gateway",
    "service_name" => "orders-api",
    "stage" => "prod",
    "dimensions" => { "ApiName" => "orders-api", "Stage" => "prod" }
  },
  "batch-worker" => {
    "resource_type" => "ec2_instance",
    "service_name" => "i-0123456789abcdef0",
    "dimensions" => { "InstanceId" => "i-0123456789abcdef0" }
  },
  "public-alb" => {
    "resource_type" => "application_load_balancer",
    "service_name" => "app/public-alb/50dc6c495c0c9188",
    "dimensions" => { "LoadBalancer" => "app/public-alb/50dc6c495c0c9188" }
  }
}.freeze

expected_services.each do |service_key, expected|
  service = golden_signals.fetch(service_key)
  assert(service.fetch("resource_type") == expected.fetch("resource_type"), "#{service_key} resource_type mismatch")

  service.fetch("monitors").each_value do |monitor|
    preset = monitor.fetch("preset")
    assert(config_names.include?(preset), "Missing Golden Signal monitor preset #{preset}")

    dimensions = config_by_name.fetch(preset).fetch("dimensions").transform_values do |value|
      value
        .gsub("${group.service_name}", expected.fetch("service_name"))
        .gsub("${group.stage}", expected.fetch("stage", ""))
    end
    assert(dimensions == expected.fetch("dimensions"), "#{preset} dimensions do not match #{service_key}")
  end

  service.fetch("slos").each_value do |slo|
    assert(slo.fetch("type") == "metric-query", "#{service_key} infrastructure SLO must use metric-query")
    assert(config_names.include?(slo.fetch("preset")), "Missing SLO preset #{slo.fetch('preset')}")
  end
end

%w[trf_ec2_network_in trf_ec2_network_out trf_alb_requests].each do |preset|
  assert(config_by_name.fetch(preset).fetch("dashboard_only") == true, "#{preset} should default to dashboard-only")
end

eks = YAML.load_file(File.join(FIXTURES, "eks-v2-inputs.yaml"))
assert(eks.dig("services", "checkout", "resource_type") == "eks_service", "EKS fixture resource_type mismatch")
assert(eks.dig("services", "checkout", "dashboard", "presets").include?("slo-health"), "EKS fixture must enable SLO dashboard preset")

beanstalk = YAML.load_file(File.join(FIXTURES, "elasticbeanstalk-v2-inputs.yaml"))
eb = beanstalk.fetch("services").fetch("payments-eb")
assert(eb.fetch("resource_type") == "elasticbeanstalk_environment", "EB fixture resource_type mismatch")
assert(eb.dig("monitors", "traffic", "dashboard_only") == true, "EB traffic monitor must be dashboard_only")
assert(eb.dig("slos", "availability_5xx", "preset") == "eb_5xx_availability", "EB availability SLO preset mismatch")
%w[ApplicationRequests5xx ApplicationRequestsTotal ApplicationLatencyP99].each do |metric|
  assert(eb.dig("resource", "elasticbeanstalk", "published_metrics").include?(metric), "EB fixture missing published metric #{metric}")
end

custom = YAML.load_file(File.join(FIXTURES, "custom-monitor-inputs.yaml"))
custom_monitor = monitored_resources(custom).first.fetch("monitors").first
assert(custom_monitor.fetch("target_name") == "custom", "Inline custom monitor must use the custom target")
assert(custom_monitor.dig("metric", "namespace") == "AWS/SQS", "Inline custom monitor metric is missing")

boilerplate_inputs = YAML.load_file(File.join(ROOT, ".boilerplate", "inputs.yaml"))
assert(boilerplate_inputs.key?("monitor_groups"), "Boilerplate inputs must expose monitor_groups")
assert(!boilerplate_inputs.key?("groups"), "Boilerplate inputs must use monitor_groups as its primary key")
assert(boilerplate_inputs.key?("slos"), "Boilerplate inputs must expose the slos Terragrunt key")
assert(boilerplate_inputs.key?("dashboards"), "Boilerplate inputs must expose the dashboards Terragrunt key")
assert(!boilerplate_inputs.key?("monitor_definitions"), "Boilerplate inputs must not expose monitor_definitions")

terragrunt_template = File.read(File.join(ROOT, ".boilerplate", "terragrunt.hcl"))
assert(terragrunt_template.include?('if eq .Name "monitor_groups"'), "Terragrunt template must map groups to monitor_groups")
assert(terragrunt_template.include?('if eq .Name "slo_settings"'), "Terragrunt template must map slos to slo_settings")
assert(terragrunt_template.include?('if eq .Name "dashboard_settings"'), "Terragrunt template must map dashboards to dashboard_settings")

puts "Fixture validation passed"
