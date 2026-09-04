resource "aws_lambda_layer_version" "barracuda_ca" {
  count            = var.http_proxy != null ? 1 : 0
  filename         = "${path.module}/../../lambdas/barracuda-ca-layer.zip"
  source_code_hash = filebase64sha256("${path.module}/../../lambdas/barracuda-ca-layer.zip")
  layer_name       = "${var.prefix}-barracuda-ca"
  description      = "Barracuda proxy CA; SHA256 6E:E9:38:62:86:07:55:3D:F1:45:9A:8A:1F:68:11:4E:86:84:6C:8A:C7:C1:E9:FF:0E:A3:74:73:D2:EE:59:7D; expires 2028-04-04"
}
