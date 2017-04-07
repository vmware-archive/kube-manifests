// Prometheus monitoring stack

local kube = import "kube.libsonnet";
local bitnami = import "bitnami.libsonnet";

local prometheus = {
  namespace:: null,

  // prometheus.yml (as jsonnet)
  prom_config:: error ("prom_config is required"),
  // alertmanager/config.yml (as jsonnet)
  am_config:: error ("am_config is required"),
  // blackbox.yml (as jsonnet)
  bb_config:: {},

  prometheus_ing: bitnami.Ingress("prometheus") {
    metadata+: { namespace: $.namespace },
    target_svc: $.prometheus_svc,
  },

  prometheus_svc: kube.Service("prometheus") {
    metadata+: {
      namespace: $.namespace,
      annotations+: {
        "prometheus.io/scrape": "true",
      },
    },
    target_pod: $.prometheus.spec.template,
  },

  prometheus_config: kube.ConfigMap("prometheus") {
    metadata+: { namespace: $.namespace },
    data+: {
      "prometheus.yml": std.toString($.prom_config),
    },
  },

  prometheus_data: kube.PersistentVolumeClaim("prometheus-data") {
    metadata+: { namespace: $.namespace },
    storage: "100Gi",
  },

  alertmanager_data: kube.PersistentVolumeClaim("alertmanager-data") {
    metadata+: { namespace: $.namespace },
    storage: "5Gi",
  },

  node_exporter_svc: kube.Service("node-exporter") {
    metadata+: {
      namespace: $.namespace,
      annotations+: {
        "prometheus.io/scrape": "true",
      },
    },
    target_pod: $.node_exporter.spec.template,
    spec+: {
      clusterIP: "None",
      type: "ClusterIP",
    },
  },

  node_exporter: kube.DaemonSet("node-exporter") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          hostNetwork: true,
          hostPID: true,
          containers_+: {
            node_exporter: kube.Container("node-exporter") {
              local v = self.volumeMounts_,
              image: "prom/node-exporter:v0.13.0",
              args_+: {
                "collector.procfs": v.procfs.mountPath,
                "collector.sysfs": v.sysfs.mountPath,
                "collector.filesystem.ignored-mount-points": "^/(sys|proc|dev|host|etc)($|/)",
              },
              ports_+: {
                scrape: { containerPort: 9100 },
              },
              livenessProbe: {
                httpGet: { path: "/", port: "scrape" },
              },
              readinessProbe: self.livenessProbe {
                successThreshold: 2,
              },
              volumeMounts_+: {
                root: { mountPath: "/rootfs", readOnly: true },
                procfs: { mountPath: "/host/proc", readOnly: true },
                sysfs: { mountPath: "/host/sys", readOnly: true },
              },
            },
          },
          volumes_+: {
            root: kube.HostPathVolume("/"),
            procfs: kube.HostPathVolume("/proc"),
            sysfs: kube.HostPathVolume("/sys"),
          },
        },
      },
    },
  },

  ksm: kube.Deployment("kube-state-metrics") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        local tmpl = self,
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": std.toString(tmpl.spec.containers_.ksm.ports_.metrics.containerPort),
          },
        },
        spec+: {
          containers_+: {
            ksm: kube.Container("kube-state-metrics") {
              image: "gcr.io/google_containers/kube-state-metrics:v0.3.0",
              ports_+: {
                metrics: { containerPort: 8080 },
              },
              resources: {
                limits: { cpu: "10m", memory: "32Mi" },
                requests: self.limits,
              },
            },
          },
        },
      },
    },
  },

  blackbox_config: kube.ConfigMap("blackbox-exporter") {
    metadata+: { namespace: $.namespace },
    data+: {
      "blackbox.yml": std.toString($.bb_config),
    },
  },

  blackbox_svc: kube.Service("blackbox") {
    metadata+: {
      namespace: $.namespace,
      annotations+: {
        "prometheus.io/scrape": "true",
      },
    },
    target_pod: $.blackbox.spec.template,
  },

  blackbox: kube.Deployment("blackbox-exporter") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            exporter: kube.Container("exporter") {
              image: "prom/blackbox-exporter",
              args_+: {
                "config.file": "/config/blackbox.yml",
              },
              ports_+: {
                metrics: { containerPort: 9115 },
              },
              livenessProbe: {
                httpGet: { path: "/", port: "metrics" },
              },
              resources: {
                requests: { cpu: "10m", memory: "32Mi" },
              },
              volumeMounts_+: {
                config: { mountPath: "/config", readOnly: true },
              },
            },
          },
          volumes_+: {
            config: kube.ConfigMapVolume($.blackbox_config),
          },
        },
      },
    },
  },

  aws_credentials_secret:: kube.Secret("aws-credentials-secret") {
    data_+: {
      "access-key": error "provided externally",
      "secret-access-key": error "provided externally",
    },
  },

  prometheus: kube.Deployment("prometheus") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          default_container: "prometheus",
          containers_+: {
            prometheus: kube.Container("prometheus") {
              local c = self,

              image: "prom/prometheus:v1.4.1",

              args_+: {
                "alertmanager.url": $.alertmanager_svc.http_url,
                "web.external-url": "https://%s/" % [$.prometheus_ing.host],
                "storage.local.retention": "%dh" % [24 * 7 * 3],

                // https://prometheus.io/docs/operating/storage/#memory-usage
                // "As a rule of thumb, you should have at least 3
                // times more RAM available than needed by the memory
                // chunks alone"
                // (each "chunk" is 1024B)
                memory_chunks:: kube.siToNum(c.resources.requests.memory) / 3 / 1024,
                "storage.local.memory-chunks": "%d" % [self.memory_chunks],

                "config.file": c.volumeMounts_.config.mountPath + "/prometheus.yml",
                "storage.local.path": c.volumeMounts_.data.mountPath,

                // These are unmodified upstream console files. May
                // want to ship in config instead.
                "web.console.libraries": "/etc/prometheus/console_libraries",
                "web.console.templates": "/etc/prometheus/consoles",
              },

              env_+: {
                AWS_ACCESS_KEY_ID: kube.SecretKeyRef($.aws_credentials_secret, "access-key"),
                AWS_SECRET_ACCESS_KEY: kube.SecretKeyRef($.aws_credentials_secret, "secret-access-key"),
              },

              ports_+: {
                web: { containerPort: 9090 },
              },
              volumeMounts_+: {
                config: { mountPath: "/etc/prometheus-config", readOnly: true },
                data: { mountPath: "/prometheus" },
              },
              resources: {
                requests: {
                  cpu: "500m",
                  memory: "1500Mi",
                },
              },
              livenessProbe: {
                httpGet: { path: "/", port: c.ports[0].name },
                // Crash recovery can take a long time (~1 minute)
                initialDelaySeconds: 3 * 60,
              },
              readinessProbe: self.livenessProbe {
                successThreshold: 2,
                initialDelaySeconds: 5,
              },
            },
            config_reload: kube.Container("configmap-reload") {
              image: "jimmidyson/configmap-reload:v0.1",
              args_+: {
                "volume-dir": "/etc/config",
                "webhook-url": "http://localhost:9090/-/reload",
              },
              volumeMounts_+: {
                config: { mountPath: "/etc/config", readOnly: true },
              },
            },
          },
          volumes_+: {
            config: kube.ConfigMapVolume($.prometheus_config),
            data: kube.PersistentVolumeClaimVolume($.prometheus_data),
          },
          terminationGracePeriodSeconds: 300,
        },
      },
    },
  },

  alertmanager_ing: bitnami.Ingress("alertmanager") {
    metadata+: { namespace: $.namespace },
    target_svc: $.alertmanager_svc,
  },

  alertmanager_svc: kube.Service("alertmanager") {
    metadata+: {
      namespace: $.namespace,
      annotations+: {
        "prometheus.io/scrape": "true",
      },
    },
    target_pod: $.alertmanager.spec.template,
  },

  alertmanager_config: kube.ConfigMap("alertmanager-config") {
    metadata+: { namespace: $.namespace },
    data+: {
      "config.yml": std.toString($.am_config),
    },
  },

  alertmanager_templates: kube.ConfigMap("alertmanager-templates") {
    metadata+: { namespace: $.namespace },
    data+: {
      // empty (for now)
    },
  },

  alertmanager: kube.Deployment("alertmanager") {
    local deploy = self,

    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          default_container: "alertmanager",
          containers_+: {
            alertmanager: kube.Container("alertmanager") {
              image: "prom/alertmanager:v0.5.1",
              args_+: {
                "config.file": "/etc/alertmanager/config.yml",
                "storage.path": "/alertmanager",
                "web.external-url": "https://%s/" % [$.alertmanager_ing.host],
              },
              ports_+: {
                alertmanager: { containerPort: 9093 },
              },
              volumeMounts_+: {
                config: { mountPath: "/etc/alertmanager", readOnly: true },
                templates: { mountPath: "/etc/alertmanager-templates", readOnly: true },
                storage: { mountPath: "/alertmanager" },
              },
            },
            config_reload: kube.Container("configmap-reload") {
              image: "jimmidyson/configmap-reload:v0.1",
              args_+: {
                "volume-dir": "/etc/config",
                "webhook-url": "http://localhost:9093/-/reload",
              },
              volumeMounts_+: {
                config: { mountPath: "/etc/config", readOnly: true },
              },
            },
          },
          volumes_+: {
            config: kube.ConfigMapVolume($.alertmanager_config),
            templates: kube.ConfigMapVolume($.alertmanager_templates),
            storage: kube.PersistentVolumeClaimVolume($.alertmanager_data),
          },
        },
      },
    },
  },

  grafana_ing: bitnami.Ingress("grafana") {
    metadata+: { namespace: $.namespace },
    target_svc: $.grafana_svc,
  },

  grafana_svc: kube.Service("grafana") {
    metadata+: { namespace: $.namespace },
    target_pod: $.grafana.spec.template,
  },

  grafana: kube.Deployment("grafana") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            grafana: kube.Container("grafana") {
              image: "grafana/grafana:4.1.1",
              resources: {
                limits: { cpu: "100m", memory: "100Mi" },
                requests: self.limits,
              },
              ports_+: {
                dashboard: { containerPort: 3000 },
              },
              env_+: {
                GF_AUTH_BASIC_ENABLED: "true",
                GF_AUTH_ANONYMOUS_ENABLED: "true",
                GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer",
                GF_SERVER_DOMAIN: $.grafana_ing.host,
                GF_LOG_MODE: "console",
                GF_LOG_LEVEL: "warn",
                GF_METRICS_ENABLED: "true",
                //GF_DASHBOARDS_JSON_ENABLED: "true",
                //GF_DASHBOARDS_JSON_PATH: "/dashboards",
              },
              volumeMounts_+: {
                storage: { mountPath: "/var/lib/grafana" },
              },
              livenessProbe: {
                httpGet: { path: "/login", port: "dashboard" },
              },
              readinessProbe: self.livenessProbe {
                successThreshold: 2,
              },
            },
          },
          volumes_+: {
            storage: kube.EmptyDirVolume(),
          },
        },
      },
    },
  },
};

kube.List() { items_+: prometheus }
