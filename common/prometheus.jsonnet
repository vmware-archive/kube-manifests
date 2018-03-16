local kube = import "kube.libsonnet";
local bitnami = import "bitnami.libsonnet";

local image_v1 = "prom/prometheus:v1.8.2";
local image_v2 = "prom/prometheus:v2.1.0";

local promBase = {
  namespace:: null,
  name:: "prometheus",
  alertmanager_url:: null,
  version:: 1,
  rbac_rules:: [
    {
      apiGroups: [""],
      resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods"],
      verbs: ["get", "list", "watch"],
    },
    {
      nonResourceURLs: ["/metrics"],
      verbs: ["get"],
    },
  ],

  // prometheus.yml (as jsonnet)
  prom_config:: error ("prom_config is required"),

  // TODO: using "default" account to avoid redeploying for now,
  // consider creating "prometheus" one for final
  // "system:serviceaccount:monitoring:prometheus" instead
  prometheus_account:: kube.ServiceAccount("default") {
    metadata+: { namespace: $.namespace },
  },
  prometheus_role_binding: kube.ClusterRoleBinding("prometheus") {
    roleRef_: $.prometheus_role,
    subjects_: [$.prometheus_account],
  },
  prometheus_role: kube.ClusterRole("prometheus") {
    rules: $.rbac_rules,
  },
  prometheus_ing: bitnami.Ingress($.name) {
    metadata+: {
      namespace: $.namespace,
    },
    target_svc: $.prometheus_svc,
  },

  prometheus_svc: kube.Service($.name) {
    metadata+: {
      namespace: $.namespace,
      annotations+: {
        "prometheus.io/scrape": "true",
      },
    },
    target_pod: $.prometheus.spec.template,
  },

  prometheus_config: kube.ConfigMap($.name) {
    local c = self,
    extra_config:: {},
    metadata+: { namespace: $.namespace },
    data+: {
      "prometheus.yml": std.toString($.prom_config + c.extra_config),
    },
  },

  prometheus_data: kube.PersistentVolumeClaim(std.join("-", [$.name, "data"])) {
    metadata+: { namespace: $.namespace },
    storage: "100Gi",
  },

  prometheus: kube.Deployment($.name) {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          default_container: "prometheus",
          containers_+: {
            prometheus: kube.Container("prometheus") {
              local c = self,

              image: null,

              retention:: "%dh" % [24 * 7 * 3],
              args_+: {
                "web.external-url": "https://%s/" % [$.prometheus_ing.host],
                "config.file": c.volumeMounts_.config.mountPath + "/prometheus.yml",
                // These are unmodified upstream console files. May
                // want to ship in config instead.
                "web.console.libraries": "/etc/prometheus/console_libraries",
                "web.console.templates": "/etc/prometheus/consoles",
              },
              ports_+: {
                web: { containerPort: 9090 },
              },
              volumeMounts_+: {
                config: { mountPath: "/etc/prometheus-config", readOnly: true },
                data: { mountPath: "/prometheus" },
              },
              readinessProbe: {
                initialDelaySeconds_:: 0,
                httpGet: { path: "/", port: c.ports[0].name },
                initialDelaySeconds: self.initialDelaySeconds_,
                failureThreshold: 20,
                periodSeconds: 60,
              },
              livenessProbe: self.readinessProbe {
                initialDelaySeconds: self.initialDelaySeconds_ + 60,
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
};
local promVersion = {
  local v_idx = self.version - 1,
  prometheus_config+: {
    extra_config+: [
      {
        // v1
        rule_files: ["/etc/prometheus-config/*.rules"],
      },
      {
        // v2
        rule_files: ["/etc/prometheus-config/*.rules.yml"],
        alerting: {
          alertmanagers: [
            {
              scheme: std.split($.alertmanager_url, ":")[0],
              static_configs: [
                { targets: [std.split($.alertmanager_url, "/")[2]] },
              ],
            },
          ],
        },
      },
    ][v_idx],
  },
  prometheus+: {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            prometheus+: {
              local c = self,
              args_+:
                [
                  // v1
                  std.prune({
                    // https://prometheus.io/docs/operating/storage/#memory-usage
                    //
                    // As a rule of thumb, you should have at least 50% headroom in
                    // physical memory over the configured heap size.
                    // (Or, in other words, set storage.local.target-heap-size to a
                    // value of two thirds of the physical memory limit Prometheus
                    // should not exceed.)
                    //
                    // Prior to v1.6, there was no flag storage.local.target-heap-size.
                    // Instead, the number of chunks kept in memory had to be
                    // configured using the flags storage.local.memory-chunks
                    heap_size:: kube.siToNum(c.resources.requests.memory) * 2 / 3,
                    "storage.local.target-heap-size": "%d" % [self.heap_size],
                    "storage.local.retention": c.retention,
                    "storage.local.path": c.volumeMounts_.data.mountPath,
                    "alertmanager.url": $.alertmanager_url,
                  }),
                  // v2
                  {
                    "storage.tsdb.retention": c.retention,
                    "storage.tsdb.path": c.volumeMounts_.data.mountPath,
                  },
                ][v_idx],
              args+: [[], ["--web.enable-lifecycle"]][v_idx],
              image: [image_v1, image_v2][v_idx],
              resources: [
                // v1
                {
                  limits: { cpu: "500m", memory: "4000Mi" },
                  requests: { cpu: "500m", memory: "4000Mi" },
                },
                // v2
                {
                  limits: { cpu: "500m", memory: "3000Mi" },
                  requests: { cpu: "200m", memory: "1500Mi" },
                },
              ][v_idx],
              readinessProbe+: {
                // Crash recovery can take a long time (~15 minutes) for v1
                initialDelaySeconds_: [15, 2][v_idx] * 60,
              },
            },
          },
          securityContext+: [
            // v1
            {},
            // v2: non-root upstream container running as nobody:nogroup
            { fsGroup: 65534 },
          ][v_idx],
        },
      },
    },
  },
};

local prometheus = promBase + promVersion;

kube.List() { items_+: prometheus }
