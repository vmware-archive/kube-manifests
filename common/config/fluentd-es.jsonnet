// Run fluentd-es/import-from-upstream.py to update below files
//
// In case you feel empowered: NO, you can't create a looped comprehension of
// below, neither use variables for the directory/etc, `jsonnet` fails with ->
//  "Computed imports are not allowed."
//
{
  "containers.input.conf": importstr "fluentd-es/containers.input.conf",
  "forward.input.conf": importstr "fluentd-es/forward.input.conf",
  "monitoring.conf": importstr "fluentd-es/monitoring.conf",
  "output.conf": importstr "fluentd-es/output.conf",
  "system.input.conf": importstr "fluentd-es/system.input.conf",
}
