// Generates alerts for testing non-default config variants.
// Usage: jsonnet --tla-code '_config={etcdEnabled: true}' lib/test-alerts.jsonnet
function(_config={})
  std.manifestYamlDoc(
    ((import '../mixin.libsonnet') { _config+:: _config }).prometheusAlerts
  )
