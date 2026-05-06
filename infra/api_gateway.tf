# ============================================================
# API Gateway — REST API → SQS direct integration
# ============================================================

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name        = "${var.project_name}-apigw-cloudwatch-${var.environment}"
  description = "Allows API Gateway to write logs to CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAPIGatewayToAssumeRole"
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
  depends_on          = [aws_iam_role_policy_attachment.api_gateway_cloudwatch]
}

resource "aws_iam_role" "api_gateway_sqs" {
  name        = "${var.project_name}-apigw-sqs-${var.environment}"
  description = "Allows API Gateway to send messages to SQS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAPIGatewayToAssumeRole"
      Effect    = "Allow"
      Principal = { Service = "apigateway.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "api_gateway_sqs" {
  name = "apigw-sqs-sendmessage"
  role = aws_iam_role.api_gateway_sqs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowSendMessageToEventsQueue"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.events.arn
      },
      {
        Sid    = "AllowKMSForSQSEncryption"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.flux.arn
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "flux" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "Project Flux telemetry ingestion API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.flux.id
  parent_id   = aws_api_gateway_rest_api.flux.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "post_events" {
  rest_api_id   = aws_api_gateway_rest_api.flux.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "NONE"

  request_parameters = {
    "method.request.header.Content-Type" = false
  }
}

resource "aws_api_gateway_integration" "post_events_sqs" {
  rest_api_id             = aws_api_gateway_rest_api.flux.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.post_events.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:path/${var.aws_account_id}/${aws_sqs_queue.events.name}"
  credentials             = aws_iam_role.api_gateway_sqs.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }
}

resource "aws_api_gateway_integration_response" "post_events_200" {
  rest_api_id = aws_api_gateway_rest_api.flux.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method
  status_code = "202"

  response_templates = {
    "application/json" = jsonencode({ message = "Event accepted" })
  }

  depends_on = [aws_api_gateway_integration.post_events_sqs]
}

resource "aws_api_gateway_method_response" "post_events_202" {
  rest_api_id = aws_api_gateway_rest_api.flux.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method
  status_code = "202"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_deployment" "flux" {
  rest_api_id = aws_api_gateway_rest_api.flux.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.events.id,
      aws_api_gateway_method.post_events.id,
      aws_api_gateway_integration.post_events_sqs.id,
      aws_api_gateway_integration_response.post_events_200.id,
      aws_api_gateway_method_response.post_events_202.id,
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.post_events_sqs,
    aws_api_gateway_integration_response.post_events_200,
    aws_api_gateway_method_response.post_events_202,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = 14
  kms_key_id        = aws_kms_key.flux.arn
}

resource "aws_api_gateway_stage" "dev" {
  deployment_id = aws_api_gateway_deployment.flux.id
  rest_api_id   = aws_api_gateway_rest_api.flux.id
  stage_name    = var.environment

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.resourcePath"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  depends_on = [
    aws_cloudwatch_log_group.api_gateway,
    aws_api_gateway_account.main
  ]
}
