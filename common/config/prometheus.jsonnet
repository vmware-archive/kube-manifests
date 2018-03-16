// prometheus.yml
//
// See comments below for service/pod annotations (and ec2 tags) used
// to discover targets.

local mapToNamedList(namefield, obj) =
  [{ [namefield]: n } + obj[n] for n in std.objectFields(obj) if obj[n] != null];

{
  global: {
    scrape_interval: "1m",
    scrape_timeout: "30s",
    external_labels: {},
  },

  // NOTE: prometheus-v2 overwrites this to *.rules.yml
  rule_files: ["/etc/prometheus-config/*.rules"],

  kubeauth_scrape:: {
    scheme: "https",

    local creds = "/var/run/secrets/kubernetes.io/serviceaccount",
    tls_config: {
      ca_file: creds + "/ca.crt",
    },
    bearer_token_file: creds + "/token",
  },

  scrape_configs: mapToNamedList("job_name", $.scrape_configs_),
  scrape_configs_:: {
    prometheus: {
      static_configs: [{ targets: ["localhost:9090"] }],
    },

    kubernetes_apiservers: $.kubeauth_scrape {
      kubernetes_sd_configs: [{ role: "endpoints" }],

      tls_config+: {
        // Avoid "Get https://10.110.54.167:443/metrics: x509: certificate is valid for 100.64.0.1, not 10.110.54.167"
        // TODO: There's probably a better way to fix this.
        insecure_skip_verify: true,
      },

      relabel_configs: [
        {
          // Keep only the default/kubernetes service endpoints for
          // the https port. This will add targets for each API server
          // which Kubernetes adds an endpoint to the
          // default/kubernetes service.
          source_labels: [
            "__meta_kubernetes_namespace",
            "__meta_kubernetes_service_name",
            "__meta_kubernetes_endpoint_port_name",
          ],
          action: "keep",
          regex: "default;kubernetes;https",
        },
      ],
    },

    kubernetes_nodes: $.kubeauth_scrape {
      kubernetes_sd_configs: [{ role: "node" }],

      tls_config+: {
        // Avoid "Get https://10.110.51.251:10250/metrics: x509: cannot validate certificate for 10.110.51.251 because it doesn't contain any IP SANs"
        // TODO: There's probably a better way to fix this.
        insecure_skip_verify: true,
      },

      relabel_configs: [
        {
          action: "labelmap",
          regex: "__meta_kubernetes_node_label_(.+)",
        },
        {
          target_label: "__address__",
          replacement: "kubernetes.default.svc.cluster.local:443",
        },
        {
          target_label: "__scheme__",
          replacement: "https",
        },
        {
          source_labels: ["__meta_kubernetes_node_name"],
          regex: "(.+)",
          target_label: "__metrics_path__",
          replacement: "/api/v1/nodes/${1}/proxy/metrics",
        },
      ],
    },
    // Scrape config for Kubelet cAdvisor.
    //
    // This is required for Kubernetes 1.7.3 and later, where cAdvisor metrics
    // (those whose names begin with 'container_') have been removed from the
    // Kubelet metrics endpoint.  This job scrapes the cAdvisor endpoint to
    // retrieve those metrics.
    //
    // In Kubernetes 1.7.0-1.7.2, these metrics are only exposed on the cAdvisor
    // HTTP endpoint; use "replacement: /api/v1/nodes/${1}:4194/proxy/metrics"
    // in that case (and ensure cAdvisor's HTTP server hasn't been disabled with
    // the --cadvisor-port=0 Kubelet flag).
    //
    // This job is not necessary and should be removed in Kubernetes 1.6 and
    // earlier versions, or it will cause the metrics to be scraped twice.
    kubernetes_cadvisor: $.kubeauth_scrape {
      kubernetes_sd_configs: [{ role: "node" }],
      tls_config+: {
        insecure_skip_verify: true,
      },
      relabel_configs: [
        {
          action: "labelmap",
          regex: "__meta_kubernetes_node_label_(.+)",
        },
        {
          target_label: "__address__",
          replacement: "kubernetes.default.svc.cluster.local:443",
        },
        {
          target_label: "__scheme__",
          replacement: "https",
        },
        {
          source_labels: ["__meta_kubernetes_node_name"],
          regex: "(.+)",
          target_label: "__metrics_path__",
          replacement: "/api/v1/nodes/${1}/proxy/metrics/cadvisor",
        },
      ],
    },

    // Scrape config for service endpoints.
    //
    // The relabeling allows the actual service scrape endpoint to be
    // configured via the following annotations:
    //
    // * `prometheus.io/scrape`: Only scrape services that have a
    //   value of `true`
    // * `prometheus.io/scheme`: If the metrics endpoint is secured
    //   then you will need to set this to `https` & most likely set
    //   the `tls_config` of the scrape config.
    // * `prometheus.io/path`: If the metrics path is not `/metrics`
    //   override this.
    // * `prometheus.io/port`: If the metrics are exposed on a
    //   different port to the service then set this appropriately.
    kubernetes_service_endpoints: {
      kubernetes_sd_configs: [{ role: "endpoints" }],

      relabel_configs: [
        {
          source_labels: [
            "__meta_kubernetes_service_annotation_prometheus_io_scrape",
          ],
          action: "keep",
          regex: true,
        },
        {
          source_labels: [
            "__meta_kubernetes_service_annotation_prometheus_io_scheme",
          ],
          action: "replace",
          target_label: "__scheme__",
          regex: "(https?)",
        },
        {
          source_labels: [
            "__meta_kubernetes_service_annotation_prometheus_io_path",
          ],
          action: "replace",
          target_label: "__metrics_path__",
          regex: "(.+)",
        },
        {
          source_labels: [
            "__address__",
            "__meta_kubernetes_service_annotation_prometheus_io_port",
          ],
          action: "replace",
          target_label: "__address__",
          regex: "(.+)(?::\\d+);(\\d+)",
          replacement: "$1:$2",
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_service_label_(.+)",
        },
        {
          source_labels: ["__meta_kubernetes_namespace"],
          action: "replace",
          target_label: "kubernetes_namespace",
        },
        {
          source_labels: ["__meta_kubernetes_service_name"],
          action: "replace",
          target_label: "kubernetes_name",
        },
      ],
    },

    // Blackbox exporter scrape.
    //
    // * `prometheus.io/probe`: Only probe services that have a value
    //   of `true`
    kubernetes_services: {
      metrics_path: "/probe",
      params: { module: ["http_2xx"] },
      kubernetes_sd_configs: [{ role: "service" }],
      relabel_configs: [
        {
          source_labels: [
            "__meta_kubernetes_service_annotation_prometheus_io_probe",
          ],
          action: "keep",
          regex: true,
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_service_label_(.+)",
        },
        {
          source_labels: ["__meta_kubernetes_service_namespace"],
          target_label: "kubernetes_namespace",
        },
        {
          source_labels: ["__meta_kubernetes_service_name"],
          target_label: "kubernetes_name",
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_service_annotation_bitnami_com_(.+)",
        },
        {
          source_labels: [
            "__meta_kubernetes_service_annotation_bitnami_com_vhost",
          ],
          regex: "(.*)",
          replacement: "$1",
          target_label: "__param_target",
        },
        {
          target_label: "__address__",
          replacement: "blackbox:9115",
        },
      ],
    },

    // Example scrape config for pods
    //
    // * `prometheus.io/scrape`: Only scrape pods that have a value of
    //   `true`
    // * `prometheus.io/path`: If the metrics path is not `/metrics`
    //   override this.
    // * `prometheus.io/port`: Scrape the pod on the indicated port
    //   instead of the default of `9102`.
    kubernetes_pods: {
      kubernetes_sd_configs: [{ role: "pod" }],

      relabel_configs: [
        {
          source_labels: [
            "__meta_kubernetes_pod_annotation_prometheus_io_scrape",
          ],
          action: "keep",
          regex: true,
        },
        {
          source_labels: [
            "__meta_kubernetes_pod_annotation_prometheus_io_path",
          ],
          action: "replace",
          target_label: "__metrics_path__",
          regex: "(.+)",
        },
        {
          source_labels: [
            "__address__",
            "__meta_kubernetes_pod_annotation_prometheus_io_port",
          ],
          action: "replace",
          regex: "(.+):(?:\\d+);(\\d+)",
          replacement: "${1}:${2}",
          target_label: "__address__",
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_pod_label_(.+)",
        },
        {
          source_labels: ["__meta_kubernetes_namespace"],
          action: "replace",
          target_label: "kubernetes_namespace",
        },
        {
          source_labels: ["__meta_kubernetes_pod_name"],
          action: "replace",
          target_label: "kubernetes_pod_name",
        },
      ],
    },

    // Scrape config for EC2 servers.
    //
    // We need two scrapers for EC2 since we use two different AWS
    // accounts for dev and prod servers. The servers that are going
    // to be scraped need to declare the tag "monitoring" with values
    // "full" or "whitebox".
    ec2_servers: {
      scheme: "https",
      tls_config: { insecure_skip_verify: true },

      ec2_sd_configs: [{ region: "us-east-1" }],
      relabel_configs: [
        {
          action: "labelmap",
          regex: "__meta_ec2_tag_(.+)",
        },

        {
          source_labels: [
            "__meta_ec2_tag_monitoring_type",
          ],
          action: "keep",
          regex: "full|whitebox",
        },
        {
          source_labels: [
            "__meta_ec2_tag_monitoring_vhost",
          ],
          replacement: "$1",
          target_label: "__address__",
        },
      ],
    },

    // Blackbox exporter scrape for EC2 servers
    //
    // Servers that are going to be monitored must have the tag
    // "monitoring" with the value "full" or "blackbox"
    ec2_servers_blackbox: {
      metrics_path: "/probe",
      params: { module: ["http_2xx"] },
      ec2_sd_configs: [{ region: "us-east-1" }],
      relabel_configs: [
        {
          action: "labelmap",
          regex: "__meta_ec2_tag_(.+)",
        },
        {
          source_labels: [
            "__meta_ec2_tag_probe",
          ],
          action: "keep",
          regex: "true",
        },
        {
          source_labels: [
            "__meta_ec2_tag_probe_target",
          ],
          regex: "(.*)",
          replacement: "$1",
          target_label: "__param_target",
        },
        {
          source_labels: [
            "__meta_ec2_tag_probe_target",
          ],
          target_label: "vhost",
        },
        {
          target_label: "__address__",
          replacement: "blackbox:9115",
        },
      ],
    },
  },
}
