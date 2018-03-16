// Various kube-system cluster "addons" that we want above and beyond
// what we get out of the box from kops

local kube = import "kube.libsonnet";
local elasticsearch = (import "elasticsearch.jsonnet").items_;

local cluster_service = {
  metadata+: {
    namespace: "kube-system",
    labels+: {
      "kubernetes.io/cluster-service": "true",
    },
  },
};

local critical_pod = {
  metadata+: {
    annotations+: {
      "scheduler.alpha.kubernetes.io/critical-pod": "",

      tolerations:: [{ key: "CriticalAddonsOnly", operator: "Exists" }],
      "scheduler.alpha.kubernetes.io/tolerations": std.toString(self.tolerations),
    },
  },
};

local all = elasticsearch {
  namespace:: "kube-system",

  // Used to estimate heapster_nanny memory requirement
  num_nodes:: 3,

  default: $.fast {
    metadata+: {
      name: "default",
      annotations+: {
        "storageclass.beta.kubernetes.io/is-default-class": "true",
      },
    },
  },

  slow: kube.StorageClass("slow") {
    provisioner: "kubernetes.io/aws-ebs",
    parameters: { type: "sc1" },
  },

  fast: kube.StorageClass("fast") {
    provisioner: "kubernetes.io/aws-ebs",
    parameters: { type: "gp2" },
  },

  dashboard_certs: kube.Secret("kubernetes-dashboard-certs") {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "kubernetes-dashboard",
      },
    },
  },

  dashboard_sa: kube.ServiceAccount("kubernetes-dashboard") {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "kubernetes-dashboard",
      },
    },
  },

  dashboard_role: kube.Role("kubernetes-dashboard-minimal") {
    metadata+: {
      namespace: $.namespace,
    },
    rules: [{
      apiGroups: [""],
      resources: ["secrets"],
      verbs: ["create"],
    }, {
      apiGroups: [""],
      resources: ["configmaps"],
      verbs: ["create"],
    }, {
      apiGroups: [""],
      resources: ["secrets"],
      resourceNames: ["kubernetes-dashboard-key-holder", "kubernetes-dashboard-certs"],
      verbs: ["get", "update", "delete"],
    }, {
      apiGroups: [""],
      resources: ["configmaps"],
      resourceNames: ["kubernetes-dashboard-settings"],
      verbs: ["get", "update"],

    }, {
      apiGroups: [""],
      resources: ["services"],
      resourceNames: ["heapster"],
      verbs: ["proxy"],
    }, {
      apiGroups: [""],
      resources: ["services/proxy"],
      resourceNames: ["heapster", "http:heapster:", "https:heapster:"],
      verbs: ["get"],
    }],
  },

  dashboard_role_binding: kube.RoleBinding("kubernetes-dashboard-minimal") {
    metadata+: {
      namespace: $.namespace,
    },
    roleRef_: $.dashboard_role,
    subjects_: [$.dashboard_sa],
  },

  dashboard_svc: kube.Service("kubernetes-dashboard") + cluster_service {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "kubernetes-dashboard",
      },
    },
    target_pod: $.dashboard.spec.template,
    spec+: {
      // Needs to not use a port name in order for default URL to work
      ports: [{ port: 443, targetPort: 8443 }],
      selector: { "k8s-app": "kubernetes-dashboard" },
    },
  },

  dashboard_deploy: kube.Deployment("kubernetes-dashboard") + cluster_service {
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "k8s-app": "kubernetes-dashboard",
      },
    },
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: $.dashboard_sa.metadata.name,
          containers_+: {
            dashboard: kube.Container("kubernetes-dashboard") {
              image: "k8s.gcr.io/kubernetes-dashboard-amd64:v1.8.2",
              args: ["--auto-generate-certificates"],
              resources: {
                limits: { cpu: "200m", memory: "500Mi" },
                requests: { cpu: "100m", memory: "200Mi" },
              },
              ports_+: {
                web: { containerPort: 8443 },
              },
              livenessProbe: {
                httpGet: { path: "/", port: 8443, scheme: "HTTPS" },
                initialDelaySeconds: 30,
                timeoutSeconds: 30,
              },
              volumeMounts_+: {
                kubernetes_dashboard_certs: {
                  mountPath: "/certs",
                },
                tmp_volume: {
                  mountPath: "/tmp",
                },
              },
            },
          },
          volumes_+: {
            kubernetes_dashboard_certs: kube.SecretVolume($.dashboard_certs),
            tmp_volume: kube.EmptyDirVolume(),
          },
        },
      },
    },
  },

  // https://github.com/kubernetes/kubernetes/blob/master/cluster/addons/cluster-monitoring/standalone/heapster-controller.yaml
  heapster_svc: kube.Service("heapster") + cluster_service {
    metadata+: {
      labels+: {
        "kubernetes.io/name": "Heapster",
      },
    },
    spec+: {
      ports: [{ port: 80, targetPort: 8082 }],
      selector: { "k8s-app": "heapster" },
    },
  },
  local heapster_version = "v1.4.2",
  heapster: kube.Deployment("heapster") + cluster_service {
    metadata+: {
      labels+: {
        "k8s-app": "heapster",
        version: heapster_version,
      },
    },

    spec+: {
      template+: critical_pod {
        spec+: {
          default_container: "heapster",
          containers_+: {
            heapster: kube.Container("heapster") {
              image: "gcr.io/google_containers/heapster:" + heapster_version,
              livenessProbe: {
                httpGet: {
                  path: "/healthz",
                  port: 8082,
                },
                initialDelaySeconds: 180,
                timeoutSeconds: 5,
              },
              command: ["/heapster"],
              args_+: {
                source: "kubernetes.summary_api:''",
              },
            },
            heapster_nanny: kube.Container("heapster-nanny") {
              image: "gcr.io/google_containers/addon-resizer:1.6",
              resources: {
                local mem = 90 * 1024 + $.num_nodes * 200,
                limits: { cpu: "50m", memory: "%dKi" % [mem] },
                requests: self.limits,
              },
              env_+: {
                MY_POD_NAME: kube.FieldRef("metadata.name"),
                MY_POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              command: ["/pod_nanny"],
              args_+: {
                cpu: "80m",
                "extra-cpu": "0.5m",
                memory: "140Mi",
                "extra-memory": "4Mi",
                threshold: 5,  // percent
                deployment: $.heapster.metadata.name,
                container: "heapster",
                "poll-period": 5 * 60 * 1000,  // in ms
                estimator: "exponential",
              },
            },
          },
        },
      },
    },
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
              image: "gcr.io/google_containers/fluentd-elasticsearch:1.20",
              command: [
                "/bin/sh",
                "-c",
                "/usr/sbin/td-agent 2>&1 >> /var/log/fluentd.log",
              ],
              resources: {
                limits: { memory: "200Mi" },
                requests: { cpu: "100m", memory: "200Mi" },
              },
              volumeMounts_+: {
                varlog: { mountPath: "/var/log" },
                varlibdockercontainers: {
                  mountPath: "/var/lib/docker/containers",
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
          },
        },
      },
    },
  },

  kibana_logging_svc+: cluster_service,
};

kube.List() { items_+: all }
