local kube = import "kube.libsonnet";
local prometheus = import "../common/prometheus.jsonnet";
local ksw = import "../common/kube-svc-watch.jsonnet";

local all = prometheus.items_ + ksw.items_ {
  namespace: "monitoring",

  prom_config: import "config/prometheus.jsonnet",
  am_config: import "config/alertmanager.jsonnet",
  bb_config: import "config/blackbox.jsonnet",

  prometheus_ns: kube.Namespace($.namespace),

  prometheus_config+: {
    data+: {
      "sre.rules": importstr "../common/config/sre.rules",
    },
  },

  prometheus_ing+: {
    host: "prometheus.k.dev.bitnami.net",
  },

  alertmanager_ing+: {
    host: "alertmanager.k.dev.bitnami.net",
  },

  grafana_ing+: {
    host: "grafana.k.dev.bitnami.net",
  },

  svc_watch+: {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            ksw+: {
              args_+: {
                terminate: true,
                "slack-token": "<redacted>",
                "slack-channel": "#sre-alerts",
              },
            },
          },
        },
      },
    },
  },
};

kube.List() { items_+: all }
