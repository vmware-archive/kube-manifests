// Basic Elasticsearch/Kibana stack.

local kube = import "kube.libsonnet";
local bitnami = import "bitnami.libsonnet";

local elasticsearch_curator = import "elasticsearch-curator.jsonnet";

local strip_trailing_slash(s) = (
  if std.endsWith(s, "/") then
    strip_trailing_slash(std.substr(s, 0, std.length(s) - 1))
  else
    s
);

local all = {
  namespace:: null,

  kibana_logging_ing: bitnami.Ingress("kibana-logging") {
    metadata+: { namespace: $.namespace },
    target_svc: $.kibana_logging_svc,
  },

  elasticsearch_logging_svc: kube.Service("elasticsearch-logging") {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "elasticsearch-logging",
        "kubernetes.io/name": "Elasticsearch",
      },
    },
    target_pod: $.elasticsearch_logging.spec.template,
  },

  elasticsearch_logging: kube.StatefulSet("elasticsearch-logging") {
    local this = self,

    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "elasticsearch-logging",
      },
    },
    spec+: {
      // Random notes on replica elasticsearch crash/recovery:
      // Individual peer REST queries are run with 15s timeout.
      // Takes 3 failed pings with 30s timeout (ie: 1.5min total)
      // before node is considered failed.
      podManagementPolicy: "OrderedReady",
      replicas: 3,
      updateStrategy: { type: "RollingUpdate" },
      template+: {
        metadata+: {
          annotations+: bitnami.PodZoneAntiAffinityAnnotation(this.spec.template) {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "9102",
          },
        },
        spec+: {
          default_container: "elasticsearch_logging",
          containers_+: {
            elasticsearch_logging: kube.Container("elasticsearch-logging") {
              image: "gcr.io/google-containers/elasticsearch:v5.5.1-1",
              resources: {
                // Needs more cpu upon initialization, therefore burstable class
                limits: { cpu: "2" },
                requests: { cpu: "500m" },
              },
              ports_+: {
                http: { containerPort: 9200 },
                transport: { containerPort: 9300 },
              },
              volumeMounts_+: {
                datadir: { mountPath: "/data" },
              },
              env_+: {
                NAMESPACE: kube.FieldRef("metadata.namespace"),

                min_master_nodes:: 2,
                MINIMUM_MASTER_NODES: std.toString(self.min_master_nodes),
                // ES_JAVA_OPTS: "-Xms4g -Xmx4g",
                // Verify quorum requirements
                assert this.spec.replicas >= self.min_master_nodes && this.spec.replicas < self.min_master_nodes * 2,
              },
              livenessProbe: {
                httpGet: { path: "/_cluster/health?local=true", port: "http" },
                // /elasticsearch_logging_discovery has a 5min timeout on cluster bootstrap
                initialDelaySeconds: 5 * 60,  // Number of seconds after the container has started before liveness probes are initiated.
                periodSeconds: 30,  // How often (in seconds) to perform the probe.
                failureThreshold: 4,  // Minimum consecutive failures for the probe to be considered failed after having succeeded.

              },
              readinessProbe: self.livenessProbe {
                httpGet: { path: "/_cluster/health?local=true", port: "http" },
                // don't allow rolling updates to kill containers until the cluster is green
                // ...meaning it's not allocating replicas or relocating any shards
                initialDelaySeconds: 120,
                periodSeconds: 30,
                failureThreshold: 4,
                successThreshold: 2,  // Minimum consecutive successes for the probe to be considered successful after having failed.
              },
            },
            prom_exporter: kube.Container("prom-exporter") {
              image: "justwatch/elasticsearch_exporter:1.0.1",
              command: ["elasticsearch_exporter"],
              args_+: {
                "es.uri": "http://localhost:9200/",
                "es.all": "false",
                "es.timeout": "20s",
                "web.listen-address": ":9102",
                "web.telemetry-path": "/metrics",
              },
              ports_+: {
                metrics: { containerPort: 9102 },
              },
              livenessProbe: {
                httpGet: { path: "/", port: "metrics" },
              },
            },
          },
          // Generous grace period, to complete shard reallocation
          terminationGracePeriodSeconds: 5 * 60,
        },
      },
      volumeClaimTemplates_+: {
        datadir: kube.PersistentVolumeClaim("datadir") {
          metadata+: { namespace: $.namespace },
          storage: "100Gi",
        },
      },
    },
  },

  fluentd_es_config: kube.ConfigMap("fluentd-es-config-v0.1.0") {
    metadata+: {
      namespace: $.namespace,
    },
    data+: import "config/fluentd-es.jsonnet",
  },
  fluentd_es: kube.DaemonSet("fluentd-es") {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "fluentd-es",
      },
    },
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            fluentd_es: kube.Container("fluentd-es") {
              image: "gcr.io/google-containers/fluentd-elasticsearch:v2.0.1",
              env_+: {
                FLUENTD_ARGS: "--no-supervisor -q",
              },
              resources: {
                limits: { memory: "500Mi" },
                requests: { cpu: "100m", memory: "200Mi" },
              },
              volumeMounts_+: {
                varlog: { mountPath: "/var/log" },
                varlibdockercontainers: {
                  mountPath: "/var/lib/docker/containers",
                  readOnly: true,
                },
                libsystemddir: {
                  mountPath: "/host/lib",
                  readOnly: true,
                },
                configvolume: {
                  mountPath: "/etc/fluent/config.d",
                  readOnly: true,
                },
              },
            },
          },
          // Note: upstream has this for migration reasons that don't
          // apply to us.  Disable so the rest of this template works
          // before that version of kubelet is rolled out.
          // See:
          //  https://github.com/kubernetes/kubernetes/pull/32088/files#diff-cdd69ab3be318e9c7aafd6ca1b9577a6
          // nodeSelector: {
          //   "alpha.kubernetes.io/fluentd-ds-ready": "true",
          // },
          terminationGracePeriodSeconds: 30,
          volumes_+: {
            varlog: kube.HostPathVolume("/var/log"),
            varlibdockercontainers: kube.HostPathVolume("/var/lib/docker/containers"),
            libsystemddir: kube.HostPathVolume("/usr/lib64"),
            configvolume: kube.ConfigMapVolume($.fluentd_es_config),
          },
        },
      },
    },
  },

  kibana_logging_svc: kube.Service("kibana-logging") {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "kibana-logging",
        "kubernetes.io/name": "Kibana",
      },
    },
    target_pod: $.kibana_logging.spec.template,
  },

  kibana_logging: kube.Deployment("kibana-logging") {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "kibana-logging",
      },
    },
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            kibana_logging: kube.Container("kibana-logging") {
              image: "docker.elastic.co/kibana/kibana:5.5.1",
              resources: {
                // Keep request = limit to keep this container in guaranteed class
                limits: { cpu: "1" },
                requests: { cpu: "100m" },
              },
              env_+: {
                ELASTICSEARCH_URL: "http://elasticsearch-logging:9200",

                local route = $.kibana_logging_ing.spec.rules[0].http.paths[0],
                // Make sure we got the correct route
                assert route.backend == $.kibana_logging_svc.name_port,
                SERVER_BASEPATH: strip_trailing_slash(route.path),
                KIBANA_HOST: "0.0.0.0",
                XPACK_MONITORING_ENABLED: "false",
                XPACK_SECURITY_ENABLED: "false",
              },
              ports_+: {
                ui: { containerPort: 5601 },
              },
            },
          },
        },
      },
    },
  },
};

kube.List() { items_+: all + elasticsearch_curator.items_ }
