output "nmm_client_logging_invoke_url" {
  value = "${aws_api_gateway_deployment.nmm_client_logging.invoke_url}prod${aws_api_gateway_resource.nmm_client_logging_resource.path}"
}

