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
    host: "prometheus.k.bitnami.net",
  },

  alertmanager_ing:: null,
  alertmanager_svc:: null,
  alertmanager_data:: null,
  alertmanager_config:: null,
  alertmanager:: null,

  // Disable grafana in web cluster
  grafana_ing:: null,
  grafana_svc:: null,
  grafana:: null,

  svc_watch+: {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            ksw+: {
              args_+: {
                terminate: false,  // Note: we don't terminate public ELBs on 'web'
              },
            },
          },
        },
      },
    },
  },

  prometheus+: {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            prometheus+: {
              args_+: {
                // NB: this is point to the *int* cluster
                "alertmanager.url": "https://alertmanager.k.int.bitnami.net",
              },
            },
          },
        },
      },
    },
  },
};

kube.List() { items_+: all }
