provider "aws" {
  region = "ap-southeast-2"
}

# *-\/\/-* COMMON RESOURCES *-\/\/-* #

# --- LOG GROUP --- #
resource "aws_cloudwatch_log_group" "nmm_client_logging_common" {
  name = "nmm-client-group"

  tags = {
    Environment = "prod"
    Application = "nmm"
  }
}

# --- API GATEWAY RESOURCES --- #
resource "aws_api_gateway_rest_api" "nmm_client_logging_common" {
  name        = "CloudWatch logging API"
  description = "An API endpoint to which the NMM client app sends logs"
}

resource "aws_api_gateway_deployment" "nmm_client_logging_common" {
  depends_on = [
    "aws_api_gateway_integration.nmm_client_put_logs",
    "aws_api_gateway_integration.nmm_client_create_streams",
    "aws_api_gateway_integration.nmm_client_put_logs_options",
    "aws_api_gateway_integration.nmm_client_create_streams_options"
  ]
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id

  stage_name = ""
}

# --- API GATEWAY EXECUTION LOGGING --- #
resource "aws_api_gateway_method_settings" "nmm_client_api_gateway_logging" {
  depends_on = ["aws_api_gateway_stage.nmm_client_api_gateway_logging"]

  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  stage_name  = aws_api_gateway_stage.nmm_client_api_gateway_logging.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "ERROR"
    data_trace_enabled = true

  }
}

resource "aws_api_gateway_stage" "nmm_client_api_gateway_logging" {
  depends_on = ["aws_cloudwatch_log_group.nmm_client_api_gateway_logging"]

  rest_api_id   = aws_api_gateway_rest_api.nmm_client_logging_common.id
  deployment_id = aws_api_gateway_deployment.nmm_client_logging_common.id

  stage_name = "prod"
}

resource "aws_cloudwatch_log_group" "nmm_client_api_gateway_logging" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.nmm_client_logging_common.id}/prod"
  retention_in_days = 60
}

# *-\/\/-* PARTICULAR RESOURCES *-\/\/-* #

# --- CREATE STREAM RESOURCES --- #
# OPTIONS
resource "aws_api_gateway_method" "nmm_client_create_streams_options" {
  rest_api_id   = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id   = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "nmm_client_create_streams_options" {
  rest_api_id             = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id             = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method             = aws_api_gateway_method.nmm_client_create_streams_options.http_method
  type                    = "MOCK"
  passthrough_behavior    = "WHEN_NO_TEMPLATES"

  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF
  }
}

resource "aws_api_gateway_integration_response" "nmm_client_create_streams_options" {
  # FIX https://github.com/hashicorp/terraform/issues/7486#issuecomment-257091992
  depends_on = [
    "aws_api_gateway_integration.nmm_client_create_streams_options"
  ]

  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method = aws_api_gateway_method.nmm_client_create_streams_options.http_method
  status_code = aws_api_gateway_method_response.nmm_client_create_streams_options.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Access-Control-Allow-Origin'"
  }
}

resource "aws_api_gateway_method_response" "nmm_client_create_streams_options" {
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method = aws_api_gateway_method.nmm_client_create_streams_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

# POST
resource "aws_api_gateway_resource" "nmm_client_create_streams" {
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  parent_id   = aws_api_gateway_rest_api.nmm_client_logging_common.root_resource_id
  path_part   = "create-streams"
}

resource "aws_api_gateway_method" "nmm_client_create_streams" {
  rest_api_id   = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id   = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "nmm_client_create_streams" {
  rest_api_id             = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id             = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method             = aws_api_gateway_method.nmm_client_create_streams.http_method
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.region}:logs:action/CreateLogStream"
  integration_http_method = "POST"
  credentials             = aws_iam_role.nmm_client_create_streams.arn
  passthrough_behavior    = "WHEN_NO_TEMPLATES"
  request_templates = {
    "application/json" = <<EOF
#set($context.requestOverride.header['X-Amz-Target'] = "Logs_20140328.CreateLogStream")
#set($context.requestOverride.header['Content-Type'] = "application/x-amz-json-1.1")
#set($inputRoot = $input.path('$')) {
  "logGroupName": "$inputRoot.logGroupName",
  "logStreamName": "$inputRoot.logStreamName"
}
EOF
  }
}

# --- POST RESPONSES --- #
#  Successful
resource "aws_api_gateway_integration_response" "successful_create_stream" {
  # N.B - Needed otherwise won't get green when applying
  # https://www.terraform.io/docs/providers/aws/r/api_gateway_integration_response.html
  depends_on = ["aws_api_gateway_integration.nmm_client_create_streams"]

  rest_api_id       = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id       = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method       = aws_api_gateway_method.nmm_client_create_streams.http_method
  status_code       = aws_api_gateway_method_response.successful_create_stream.status_code
  content_handling  = "CONVERT_TO_TEXT"
  selection_pattern = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
  }

  response_templates = {
    "application/json" = <<EOF
{
  "message": "Log stream successfully created!"
}
EOF
  }
}

resource "aws_api_gateway_method_response" "successful_create_stream" {
  rest_api_id = "${aws_api_gateway_rest_api.nmm_client_logging_common.id}"
  resource_id = "${aws_api_gateway_resource.nmm_client_create_streams.id}"
  http_method = "${aws_api_gateway_method.nmm_client_create_streams.http_method}"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Unsuccessful
resource "aws_api_gateway_integration_response" "unsuccessful_create_stream" {
  # N.B - Needed otherwise won't get green when applying
  # https://www.terraform.io/docs/providers/aws/r/api_gateway_integration_response.html
  depends_on = ["aws_api_gateway_integration.nmm_client_create_streams"]

  rest_api_id       = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id       = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method       = aws_api_gateway_method.nmm_client_create_streams.http_method
  status_code       = aws_api_gateway_method_response.unsuccessful_create_stream.status_code
  content_handling  = "CONVERT_TO_TEXT"
  selection_pattern = "400"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
  }

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

resource "aws_api_gateway_method_response" "unsuccessful_create_stream" {
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id = aws_api_gateway_resource.nmm_client_create_streams.id
  http_method = aws_api_gateway_method.nmm_client_create_streams.http_method
  status_code = "400"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# --- CREATE STREAM ENDPOINT CREDENTIALS --- #
resource "aws_iam_role_policy_attachment" "nmm_client_create_streams" {
  role       = aws_iam_role.nmm_client_create_streams.name
  policy_arn = aws_iam_policy.nmm_client_create_streams.arn
}

resource "aws_iam_role" "nmm_client_create_streams" {
  name               = "NmmClientCreateStreamRole"
  assume_role_policy = data.aws_iam_policy_document.nmm_client_create_streams_assume_role.json
}

data "aws_iam_policy_document" "nmm_client_create_streams_assume_role" {
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

resource "aws_iam_policy" "nmm_client_create_streams" {
  name   = "NmmClientCreateStreamPolicy"
  policy = data.aws_iam_policy_document.nmm_client_create_streams.json
}

data "aws_iam_policy_document" "nmm_client_create_streams" {
  version = "2012-10-17"

  statement {
    sid = "NmmClientCreateStream"
    actions = [
      "logs:CreateLogStream"
    ]
    effect = "Allow"
    resources = [
      aws_cloudwatch_log_group.nmm_client_logging_common.arn
    ]
  }
}


# --- PUTS LOGGING ENDPOINT --- #
# OPTIONS
resource "aws_api_gateway_method" "nmm_client_put_logs_options" {
  rest_api_id   = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id   = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "nmm_client_put_logs_options" {
  rest_api_id             = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id             = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method             = aws_api_gateway_method.nmm_client_put_logs_options.http_method
  type                    = "MOCK"
  passthrough_behavior    = "WHEN_NO_TEMPLATES"

  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF
  }
}

resource "aws_api_gateway_method_response" "nmm_client_put_logs_options" {
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method = aws_api_gateway_method.nmm_client_put_logs_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

resource "aws_api_gateway_integration_response" "nmm_client_put_logs_options" {
  # FIX https://github.com/hashicorp/terraform/issues/7486#issuecomment-257091992
  depends_on = [
    "aws_api_gateway_integration.nmm_client_put_logs_options"
  ]

  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method = aws_api_gateway_method.nmm_client_put_logs_options.http_method
  status_code = aws_api_gateway_method_response.nmm_client_put_logs_options.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Access-Control-Allow-Origin'"
  }
}

# POST
resource "aws_api_gateway_resource" "nmm_client_put_logs" {
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  parent_id   = aws_api_gateway_rest_api.nmm_client_logging_common.root_resource_id
  path_part   = "put-logs"
}

resource "aws_api_gateway_method" "nmm_client_put_logs" {
  rest_api_id   = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id   = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "nmm_client_put_logs" {
  rest_api_id             = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id             = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method             = aws_api_gateway_method.nmm_client_put_logs.http_method
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.region}:logs:action/PutLogEvents"
  integration_http_method = "POST"
  credentials             = aws_iam_role.nmm_client_put_logs.arn
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

# --- RESPONSES --- #
#  Successful
resource "aws_api_gateway_integration_response" "successful_put_logs" {
  # N.B - Needed otherwise won't get green when applying
  # https://www.terraform.io/docs/providers/aws/r/api_gateway_integration_response.html
  depends_on = ["aws_api_gateway_integration.nmm_client_put_logs"]

  rest_api_id       = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id       = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method       = aws_api_gateway_method.nmm_client_put_logs.http_method
  status_code       = aws_api_gateway_method_response.successful_put_logs.status_code
  content_handling  = "CONVERT_TO_TEXT"
  selection_pattern = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
  }

  response_templates = {
    "application/json" = <<EOF
{
  "nextSequenceToken": "$input.path('$.nextSequenceToken')"
}
EOF
  }
}

resource "aws_api_gateway_method_response" "successful_put_logs" {
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method = aws_api_gateway_method.nmm_client_put_logs.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# Unsuccessful
resource "aws_api_gateway_integration_response" "unsuccessful_put_logs" {
  # N.B - Needed otherwise won't get green when applying
  # https://www.terraform.io/docs/providers/aws/r/api_gateway_integration_response.html
  depends_on = ["aws_api_gateway_integration.nmm_client_put_logs"]

  rest_api_id       = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id       = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method       = aws_api_gateway_method.nmm_client_put_logs.http_method
  status_code       = aws_api_gateway_method_response.unsuccessful_put_logs.status_code
  content_handling  = "CONVERT_TO_TEXT"
  selection_pattern = "400"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = var.allowed_origin
  }

  response_templates = {
    "application/json" = <<EOF
{
  #if($inputRoot.message.length() != 0)
    "error": "$input.path('$.message')",
    "expectedSequenceToken": "$input.path('$.expectedSequenceToken')"
  #else
    "error": "$input.path('$.Message')",
    "expectedSequenceToken": "$input.path('$.expectedSequenceToken')"
  #end
}
EOF
  }
}

resource "aws_api_gateway_method_response" "unsuccessful_put_logs" {
  rest_api_id = aws_api_gateway_rest_api.nmm_client_logging_common.id
  resource_id = aws_api_gateway_resource.nmm_client_put_logs.id
  http_method = aws_api_gateway_method.nmm_client_put_logs.http_method
  status_code = "400"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# --- PUTS LOGGING ENDPOINT CREDENTIALS --- #
resource "aws_iam_role_policy_attachment" "nmm_client_put_logs" {
  role       = aws_iam_role.nmm_client_put_logs.name
  policy_arn = aws_iam_policy.nmm_client_put_logs.arn
}

resource "aws_iam_role" "nmm_client_put_logs" {
  name               = "NmmClientPutLogsRole"
  assume_role_policy = data.aws_iam_policy_document.nmm_client_put_logs_assume_role.json
}

data "aws_iam_policy_document" "nmm_client_put_logs_assume_role" {
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

resource "aws_iam_policy" "nmm_client_put_logs" {
  name   = "NmmClientPutLogsPolicy"
  policy = data.aws_iam_policy_document.nmm_client_put_logs.json
}

data "aws_iam_policy_document" "nmm_client_put_logs" {
  version = "2012-10-17"

  statement {
    sid = "NmmClientPutLogs"
    actions = [
      "logs:PutLogEvents"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:logs:ap-southeast-2:829131444792:log-group:nmm-client-group:log-stream:*"
    ]
  }
}