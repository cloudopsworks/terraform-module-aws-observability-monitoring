##
# (c) 2021-2025
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

## Settings for the monitoring module - yaml format
# settings:
#   service_level_objectives:
#     - name: "Golden Signal SLO"
#       description: "Service Level Objective 1"   # (optional)
#       type: golden-signal          # (required)
#       service_level_indicator:
#         eks:                           # (optional) EKS cluster Service SLO
#           cluster_name: "my-cluster"   # (required) EKS cluster name
#           namespace: "my-namespace"     # (required) EKS namespace
#           name: "my-service"            # (required) Service name
#         lambda:                        # (optional) Lambda function Service SLO
#           function_name: "my-function"  # (required) Lambda function name
#         latency_threshold: 100         # (required) Latency threshold in milliseconds
#         errors_threshold: 5          # (required) Errors threshold in percentage
#         saturation_threshold: 80  # (required) Saturation threshold in percentage
#         saturation_metric: CPU | MEMORY | DISK | NETWORK  # (required) Saturation metric
#         traffic_threshold: 1000  # (required) Traffic threshold in requests per second
#         period_seconds: 300 # (required) Period in seconds for the SLO evaluation
#       goal:
#         attainment: 99.9  # (required) Attainment percentage for the SLO
#         duartion: 7 # (required) Duration in unit below for the SLO evaluation
#         duration_unit: DAY | HOUR | WEEK | MONTH | YEAR  # (required) Duration unit for the SLO evaluation
#       tags:                      # (optional) Tags for the SLO
#         - tag_key: tag_value
#     - name: "Operational SLO"
#       description: "Service Level Objective 2"   # (optional)
#       type: operational            # (required)
#       service_level_indicator:
#         comparison: LessThan | GreaterThan | LessThanOrEqual | GreaterThanOrEqual # (required) Comparison operator for the SLO
#         environment: "" # (required) Environment for the SLO
#         name: "" # (required) Service name for the SLO
#         type: Service
#         threshold: 100 # (required) Threshold for the SLO
#         metric_type: LATENCY | AVAILABILITY    # (required) Metric type for the SLO
#         period_seconds: 300 # (required) Period in seconds for the SLO evaluation
#         statistics: p90 | p99 | ... # (required) Statistics for the SLO
#         operations:
#           - "GET /"
#           - "GET /health"
#           - "POST /access"
#           - "POST /access2"
#       goal:
#         attainment: 99.9  # (required) Attainment percentage for the SLO
#         duartion: 7 # (required) Duration in unit below for the SLO evaluation
#         duration_unit: DAY | HOUR | WEEK | MONTH | YEAR  # (required) Duration unit for the SLO evaluation
#       tags:                      # (optional) Tags for the SLO
#         - tag_key: tag_value
variable "settings" {
  description = "Settings for the monitoring module"
  type        = any
  default     = {}
  nullable    = false
}