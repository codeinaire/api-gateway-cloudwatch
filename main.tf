provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_api_gateway_rest_api" "nmm_client_logging" {
  name        = "CloudWatch logging API"
  description = "An API endpoint to which the NMM client app sends logs"
}

resource "aws_api_gateway_resource" "nmm_client_logging_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.nmm_client_logging.id}"
  parent_id   = "${aws_api_gateway_rest_api.nmm_client_logging.root_resource_id}"
  path_part   = "logs"
}

resource "aws_api_gateway_method" "nmm_client_logging_method" {
  rest_api_id   = "${aws_api_gateway_rest_api.nmm_client_logging.id}"
  resource_id   = "${aws_api_gateway_resource.nmm_client_logging_resource.id}"
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "nmm_client_logging_method_integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.nmm_client_logging.id}"
  resource_id             = "${aws_api_gateway_resource.nmm_client_logging_resource.id}"
  http_method             = "${aws_api_gateway_method.nmm_client_logging_method.http_method}"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.region}:logs:action/PutLogEvents"
  integration_http_method = "POST"
  credentials             = aws_iam_role.nmm_app.arn
  passthrough_behavior    = "WHEN_NO_TEMPLATES"
  request_templates = {
    "application/json" = <<EOF
#set($context.requestOverride.header['X-Amz-Target'] = "Logs_20140328.PutLogEvents")
#set($context.requestOverride.header['Content-Type'] = "application/x-amz-json-1.1")
#set($inputRoot = $input.path('$')) {
#if($inputRoot.sequenceToken.length() != 0)
  "sequenceToken": "$inputRoot.sequenceToken",
#end
  "logGroupName": "$inputRoot.logGroupName",
  "logStreamName": "$inputRoot.logStreamName",
  "logEvents": [
#foreach($elem in $inputRoot.logEvents)
    {
      "timestamp": $elem.timestamp,
      "message": "$elem.message"
    }#if($foreach.hasNext),#end
#end
  ]
}
EOF
  }
}

# ! --- RESPONSES --- ! #
#  Successful
resource "aws_api_gateway_integration_response" "successful_response" {
  # N.B - Needed otherwise won't get green when applying
  # https://www.terraform.io/docs/providers/aws/r/api_gateway_integration_response.html
  depends_on = ["aws_api_gateway_integration.nmm_client_logging_method_integration"]

  rest_api_id       = aws_api_gateway_rest_api.nmm_client_logging.id
  resource_id       = aws_api_gateway_resource.nmm_client_logging_resource.id
  http_method       = aws_api_gateway_method.nmm_client_logging_method.http_method
  status_code       = aws_api_gateway_method_response.successful_response.status_code
  content_handling  = "CONVERT_TO_TEXT"
  selection_pattern = "200"

  response_templates = {
    "application/json" = <<EOF
{
  "nextSequenceToken": "$input.path('$.nextSequenceToken')"
}
EOF
  }
}

resource "aws_api_gateway_method_response" "successful_response" {
  rest_api_id = "${aws_api_gateway_rest_api.nmm_client_logging.id}"
  resource_id = "${aws_api_gateway_resource.nmm_client_logging_resource.id}"
  http_method = "${aws_api_gateway_method.nmm_client_logging_method.http_method}"
  status_code = "200"
}

# Unsuccessful
resource "aws_api_gateway_integration_response" "unsuccessful_response" {
  # N.B - Needed otherwise won't get green when applying
  # https://www.terraform.io/docs/providers/aws/r/api_gateway_integration_response.html
  depends_on = ["aws_api_gateway_integration.nmm_client_logging_method_integration"]

  rest_api_id       = aws_api_gateway_rest_api.nmm_client_logging.id
  resource_id       = aws_api_gateway_resource.nmm_client_logging_resource.id
  http_method       = aws_api_gateway_method.nmm_client_logging_method.http_method
  status_code       = aws_api_gateway_method_response.unsuccessful_response.status_code
  content_handling  = "CONVERT_TO_TEXT"
  selection_pattern = "400"

  response_templates = {
    "application/json" = <<EOF
{
  #if($inputRoot.message.length() != 0)
    "error": "$input.path('$.message')"
  #else
    "error": "$input.path('$.Message')"
  #end
}
EOF
  }
}

resource "aws_api_gateway_method_response" "unsuccessful_response" {
  rest_api_id = "${aws_api_gateway_rest_api.nmm_client_logging.id}"
  resource_id = "${aws_api_gateway_resource.nmm_client_logging_resource.id}"
  http_method = "${aws_api_gateway_method.nmm_client_logging_method.http_method}"
  status_code = "400"
}

resource "aws_api_gateway_deployment" "nmm_client_logging" {
  depends_on = [
    "aws_api_gateway_method.nmm_client_logging_method",
    "aws_api_gateway_integration.nmm_client_logging_method_integration"
  ]
  rest_api_id = "${aws_api_gateway_rest_api.nmm_client_logging.id}"

  stage_name = ""
}

resource "aws_api_gateway_method_settings" "nmm_client_logging" {
  depends_on = ["aws_api_gateway_stage.nmm_client_logging"]

  rest_api_id = "${aws_api_gateway_rest_api.nmm_client_logging.id}"
  stage_name  = aws_api_gateway_stage.nmm_client_logging.stage_name
  method_path = "${aws_api_gateway_resource.nmm_client_logging_resource.path_part}/${aws_api_gateway_method.nmm_client_logging_method.http_method}"

  settings {
    metrics_enabled    = true
    logging_level      = "ERROR"
    data_trace_enabled = true

  }
}

resource "aws_api_gateway_stage" "nmm_client_logging" {
  depends_on = ["aws_cloudwatch_log_group.api_gateway_logging"]

  rest_api_id   = aws_api_gateway_rest_api.nmm_client_logging.id
  deployment_id = aws_api_gateway_deployment.nmm_client_logging.id

  stage_name = "prod"
}

resource "aws_cloudwatch_log_group" "api_gateway_logging" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.nmm_client_logging.id}/prod"
  retention_in_days = 60
}

# CREDS
resource "aws_iam_role_policy_attachment" "nmm_app" {
  role       = aws_iam_role.nmm_app.name
  policy_arn = aws_iam_policy.nmm_app.arn
}

resource "aws_iam_role" "nmm_app" {
  name               = "AddToLogsRole"
  assume_role_policy = data.aws_iam_policy_document.nmm_app_assume_role.json
}

data "aws_iam_policy_document" "nmm_app_assume_role" {
  version = "2012-10-17"

  statement {
    actions = [
      "sts:AssumeRole",
    ]

    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "apigateway.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_policy" "nmm_app" {
  name   = "AddToLogsPolicy"
  policy = data.aws_iam_policy_document.nmm_app.json
}

data "aws_iam_policy_document" "nmm_app" {
  version = "2012-10-17"

  statement {
    sid = "PutCloudwatchLogs"
    actions = [
      "logs:PutLogEvents",
    ]
    effect = "Allow"
    resources = [
      aws_cloudwatch_log_group.nmm_client_logging.arn,
      aws_cloudwatch_log_stream.nmm_client_logging.arn
    ]
  }
}

# LOG GROUP & STREAM
resource "aws_cloudwatch_log_group" "nmm_client_logging" {
  name = "nmm-client-group"

  tags = {
    Environment = "prod"
    Application = "nmm"
  }
}

resource "aws_cloudwatch_log_stream" "nmm_client_logging" {
  name           = "nmm-client-stream"
  log_group_name = aws_cloudwatch_log_group.nmm_client_logging.name
}
