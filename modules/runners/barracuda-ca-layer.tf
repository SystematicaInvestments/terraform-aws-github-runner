resource "aws_lambda_layer_version" "barracuda_ca" {
  count            = var.http_proxy != null ? 1 : 0
  filename         = "${path.module}/../../lambdas/barracuda-ca-layer.zip"
  source_code_hash = filebase64sha256("${path.module}/../../lambdas/barracuda-ca-layer.zip")
  layer_name       = "${var.prefix}-barracuda-ca"
  description      = "Barracuda proxy CA certificate for TLS-intercepting proxy"
}
