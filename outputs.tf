output "nmm_client_put_logs_url" {
  value = "${aws_api_gateway_deployment.nmm_client_logging_common.invoke_url}prod${aws_api_gateway_resource.nmm_client_put_logs.path}"
}

output "nmm_client_create_stream_url" {
  value = "${aws_api_gateway_deployment.nmm_client_logging_common.invoke_url}prod${aws_api_gateway_resource.nmm_client_create_streams.path}"
}