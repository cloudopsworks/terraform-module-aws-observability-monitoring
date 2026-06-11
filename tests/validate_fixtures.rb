#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
FIXTURES = File.join(ROOT, "tests", "fixtures")
ORG = {
  "organization_unit" => "Forward",
  "environment_name" => "Main",
  "environment_type" => "Prod"
}.freeze

EXPECTED_ALARMS = [
  "[P2] [forward] [main] [bankbot-helm] REQUEST LATENCY - eks - prod",
  "[P1] [forward] [main] [bankbot-helm] REQUEST ERROR RATE - eks - prod",
  "[P3] [forward] [main] [bankbot-helm] REQUEST COUNT - eks - prod",
  "[P3] [forward] [main] [bankbot-helm] CPU USAGE - eks - prod",
  "[P3] [forward] [main] [bankbot-helm] MEMORY USAGE - eks - prod",
  "[P2] [forward] [main] [cognito-lambda-auth-prod] REQUEST LATENCY - lambda - prod",
  "[P1] [forward] [main] [cognito-lambda-auth-prod] REQUEST ERROR RATE - lambda - prod",
  "[P3] [forward] [main] [cognito-lambda-auth-prod] REQUEST COUNT - lambda - prod"
].freeze

EXPECTED_SLOS = [
  "gs-latency-bankbot",
  "gs-errors-bankbot",
  "gs-traffic-bankbot",
  "gs-saturation-bankbot",
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

def alarm_names(inputs)
  inputs.fetch("monitor_groups").flat_map do |group|
    group.fetch("monitors").map do |monitor|
      format("[P%s] [%s] [%s] [%s] %s - %s - %s",
             monitor.fetch("priority"),
             ORG.fetch("organization_unit").downcase,
             ORG.fetch("environment_name").downcase,
             group.fetch("service_name"),
             monitor.fetch("name"),
             group.fetch("type"),
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

forward = YAML.load_file(File.join(FIXTURES, "forward-core-ms-inputs.yaml"))
assert(alarm_names(forward) == EXPECTED_ALARMS, "Forward legacy alarm names changed")
assert(slo_names(forward) == EXPECTED_SLOS, "Forward legacy SLO names changed")
assert(forward.fetch("alarm_targets") == [], "Forward fixture must keep alarm_targets empty")

config_names = YAML.load_file(File.join(ROOT, "observability-config.yaml")).map { |entry| entry.fetch("name") }
forward.fetch("monitor_groups").flat_map { |group| group.fetch("monitors") }.each do |monitor|
  assert(config_names.include?(monitor.fetch("target_name")), "Missing monitor preset #{monitor.fetch("target_name")}")
end

%w[eb_environment_health eb_latency_p99 eb_5xx_count eb_requests_total eb_instances_severe sat_lambda_concurrent_executions].each do |preset|
  assert(config_names.include?(preset), "Missing new monitor preset #{preset}")
end

eks = YAML.load_file(File.join(FIXTURES, "eks-v2-inputs.yaml"))
assert(eks.dig("services", "bankbot", "resource_type") == "eks_service", "EKS fixture resource_type mismatch")
assert(eks.dig("services", "bankbot", "dashboard", "presets").include?("slo-health"), "EKS fixture must enable SLO dashboard preset")

beanstalk = YAML.load_file(File.join(FIXTURES, "elasticbeanstalk-v2-inputs.yaml"))
eb = beanstalk.fetch("services").fetch("payments-eb")
assert(eb.fetch("resource_type") == "elasticbeanstalk_environment", "EB fixture resource_type mismatch")
assert(eb.dig("monitors", "traffic", "dashboard_only") == true, "EB traffic monitor must be dashboard_only")
assert(eb.dig("slos", "availability_5xx", "preset") == "eb_5xx_availability", "EB availability SLO preset mismatch")
%w[ApplicationRequests5xx ApplicationRequestsTotal ApplicationLatencyP99].each do |metric|
  assert(eb.dig("resource", "elasticbeanstalk", "published_metrics").include?(metric), "EB fixture missing published metric #{metric}")
end

puts "Fixture validation passed"
