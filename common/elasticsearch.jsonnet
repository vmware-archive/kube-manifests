// Basic Elasticsearch/Kibana stack.

local kube = import "kube.libsonnet";
local bitnami = import "bitnami.libsonnet";

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

  elasticsearch_logging: kube.Deployment("elasticsearch-logging") {
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
      replicas: 3,
      strategy+: {
        type: "RollingUpdate",
        rollingUpdate: {
          // See MINIMUM_MASTER_NODES quorum settings below. 2-3
          // masters are ok, 4 replicas could potentially lead to
          // problems.
          maxSurge: 0,
          maxUnavailable: 1,
        },
      },

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
              image: "gcr.io/google_containers/elasticsearch:v2.4.1-2",
              resources: {
                // Needs more cpu upon initialization, therefore burstable class
                limits: { cpu: "1000m" },
                requests: { cpu: "100m" },
              },
              ports_+: {
                http: { containerPort: 9200 },
                transport: { containerPort: 9300 },
              },
              volumeMounts_+: {
                storage: { mountPath: "/data" },
              },
              env_+: {
                NAMESPACE: kube.FieldRef("metadata.namespace"),

                min_master_nodes:: 2,
                MINIMUM_MASTER_NODES: std.toString(self.min_master_nodes),
                // Verify quorum requirements
                assert this.spec.replicas >= self.min_master_nodes && this.spec.replicas < self.min_master_nodes * 2,
              },
              livenessProbe: {
                httpGet: { path: "/_cluster/health?local=true", port: "http" },
                // /elasticsearch_logging_discovery has a 5min timeout on cluster bootstrap
                initialDelaySeconds: 5 * 60,
                periodSeconds: 30,
                failureThreshold: 6,
              },
              readinessProbe: self.livenessProbe {
                initialDelaySeconds: 30,
                successThreshold: 2,
              },
            },
            prom_exporter: kube.Container("prom-exporter") {
              image: "crobox/elasticsearch-exporter",
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
          volumes_+: {
            storage: kube.EmptyDirVolume(),
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
              image: "gcr.io/google_containers/kibana:v4.6.1",
              resources: {
                // Keep request = limit to keep this container in guaranteed class
                limits: { cpu: "100m" },
                requests: self.limits,
              },
              env_+: {
                ELASTICSEARCH_URL: "http://elasticsearch-logging:9200",

                local route = $.kibana_logging_ing.spec.rules[0].http.paths[0],
                // Make sure we got the correct route
                assert route.backend == $.kibana_logging_svc.name_port,
                KIBANA_BASE_URL: strip_trailing_slash(route.path),
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

kube.List() { items_+: all }
