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
    host: "prometheus.k.int.bitnami.net",
  },

  alertmanager_ing+: {
    host: "alertmanager.k.int.bitnami.net",
  },

  grafana_ing+: {
    host: "grafana.k.int.bitnami.net",
  },

  svc_watch_secret:: kube.Secret("kube-svc-watch") {
    metadata+: { namespace: $.namespace },
    data_+: {
      "slack-token": error "provided externally",
    },
  },

  grafana_rds_secret:: kube.Secret("grafana-rds") {
    metadata+: { namespace: $.namespace },
    data_+: {
      host: error "provided externally",
      database: error "provided externally",
      username: error "provided externally",
      password: error "provided externally",
    },
  },

  grafana_data: kube.PersistentVolumeClaim("grafana-data") {
    metadata+: { namespace: $.namespace },
    storage: "20Gi",
  },

  grafana+: {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            grafana+: {
              env_+: {
                GF_DATABASE_TYPE: "mysql",
                GF_DATABASE_HOST: kube.SecretKeyRef($.grafana_rds_secret, "host"),
                GF_DATABASE_NAME: kube.SecretKeyRef($.grafana_rds_secret, "database"),
                GF_DATABASE_USER: kube.SecretKeyRef($.grafana_rds_secret, "username"),
                GF_DATABASE_PASSWORD: kube.SecretKeyRef($.grafana_rds_secret, "password"),
              },
            },
          },
          volumes_+: {
            storage: kube.PersistentVolumeClaimVolume($.grafana_data),
          },
        },
      },
    },
  },

  svc_watch+: {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            ksw+: {
              env_+: {
                SLACK_TOKEN: kube.SecretKeyRef($.svc_watch_secret, "slack-token"),
              },
              args_+: {
                terminate: true,
                "slack-token": "$(SLACK_TOKEN)",
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
