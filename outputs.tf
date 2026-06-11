##
# (c) 2021-2026
#     Cloud Ops Works LLC - https://cloudops.works/
#     Find us on:
#       GitHub: https://github.com/cloudopsworks
#       WebSite: https://cloudops.works
#     Distributed Under Apache v2.0 License
#

output "alarm_names" {
  description = "CloudWatch alarm names keyed by canonical service key and monitor key."
  value       = { for service_key, alarms in local.alarm_names_by_service : service_key => alarms if length(alarms) > 0 }
}

output "alarm_arns" {
  description = "CloudWatch alarm ARNs keyed by canonical service key and monitor key."
  value       = { for service_key, alarms in local.alarm_arns_by_service : service_key => alarms if length(alarms) > 0 }
}

output "slo_names" {
  description = "Application Signals service level objective names keyed by canonical service key and SLO key."
  value       = { for service_key, slos in local.slo_names_by_service : service_key => slos if length(slos) > 0 }
}

output "dashboard_names" {
  description = "CloudWatch dashboard names keyed by dashboard key."
  value = merge(
    { for dashboard_key, dashboard in aws_cloudwatch_dashboard.service : dashboard_key => dashboard.dashboard_name },
    { for dashboard_key, dashboard in aws_cloudwatch_dashboard.fleet : dashboard_key => dashboard.dashboard_name }
  )
}
