local kube = import "kube.libsonnet";
local bitnami = import "bitnami.libsonnet";

local nginx_ingress = {
  name:: "nginx-ingress",
  namespace:: null,
  cloud:: "aws",
  internal:: true,
  cloud_config:: {
    aws: {
      // Allow anything that can actually reach the nginx port to make
      // PROXY requests, and so arbitrarily specify the user ip.  (ie:
      // leave perimeter security up to k8s).
      // (Otherwise, this needs to be set to the ELB inside subnet)
      "proxy-real-ip-cidr": "0.0.0.0/0",
      "use-proxy-protocol": "true",
    },
    // GKE uses TCP LBs
    gke: {
      "use-proxy-protocol": "false",
    },
  },
  nginx_ingress_ns: kube.Namespace($.namespace),

  nginx_ingress_cluster_role: kube.ClusterRole("nginx-ingress-cluster") {
    rules: [
      {
        apiGroups: [
          "",
          "extensions",
        ],
        resources: [
          "configmaps",
          "secrets",
          "services",
          "endpoints",
          "ingresses",
          "nodes",
          "pods",
        ],
        verbs: [
          "list",
          "watch",
        ],
      },
      {
        apiGroups: [
          "extensions",
        ],
        resources: [
          "ingresses",
        ],
        verbs: [
          "get",
        ],
      },
      {
        apiGroups: [
          "",
        ],
        resources: [
          "events",
          "services",
        ],
        verbs: [
          "create",
          "list",
          "update",
          "get",
        ],
      },
      {
        apiGroups: [
          "extensions",
        ],
        resources: [
          "ingresses/status",
          "ingresses",
        ],
        verbs: [
          "update",
        ],
      },
    ],
  },

  nginx_ingress_role: kube.Role("nginx-ingress") {
    metadata+: { namespace: $.namespace },
    rules: [
      {
        apiGroups: [""],
        resources: ["pods"],
        verbs: ["list"],
      },
      {
        apiGroups: [""],
        resources: ["services"],
        verbs: ["get"],
      },
      {
        apiGroups: [""],
        resources: ["configmaps"],
        verbs: [
          "get",
          "create",
          "update",
        ],
      },
      {
        apiGroups: [""],
        resources: ["endpoints"],
        verbs: [
          "get",
          "create",
          "update",
        ],
      },
    ],
  },

  nginx_ingress_service_account: kube.ServiceAccount("nginx-ingress") {
    metadata+: { namespace: $.namespace },
  },

  nginx_ingress_role_binding: kube.RoleBinding("nginx-ingress-binding") {
    metadata+: { namespace: $.namespace },
    subjects_+: [$.nginx_ingress_service_account],
    roleRef_: $.nginx_ingress_role,
  },

  nginx_ingress_cluster_role_binding: kube.ClusterRoleBinding("nginx-ingress-cluster-binding") {
    subjects_+: [$.nginx_ingress_service_account],
    roleRef_: $.nginx_ingress_cluster_role,
  },

  nginx_config: kube.ConfigMap($.name) {
    metadata+: { namespace: $.namespace },
    data+: $.cloud_config[$.cloud] {
      "proxy-connect-timeout": "15",
      "hosts-include-subdomains": "false",
      "server-name-hash-bucket-size": "256",
      "ssl-protocols": "TLSv1.1 TLSv1.2",  // Remove TLSv1

      // Crazy-high, to support websockets:
      // https://github.com/kubernetes/ingress/blob/7394395715d944f352a3cbc0edbf118497f4d916/controllers/nginx/configuration.md#websockets
      "proxy-read-timeout": "3600",
      "proxy-send-timeout": "3600",

      "enable-vts-status": "true",

    },
  },

  nginx_svc_:: bitnami.ElbService($.name, $.cloud, $.internal),

  nginx_svc: $.nginx_svc_ {
    metadata+: {
      namespace: $.namespace,
    },
    target_pod: $.nginx.spec.template,
    spec+: {
      ports: [
        { port: 80, name: "http" },
        { port: 443, name: "https" },
      ],
    },
  },

  nginx: kube.Deployment($.name) {
    metadata+: { namespace: $.namespace },
    spec+: {
      replicas: 2,
      template+: bitnami.PromScrape(10254) {
        spec+: {
          serviceAccountName: $.nginx_ingress_service_account.metadata.name,
          terminationGracePeriodSeconds: 60,
          containers_+: {
            ingress: kube.Container("nginx-ingress-lb") {
              image: "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.11.0",
              env_+: {
                POD_NAME: kube.FieldRef("metadata.name"),
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              command: ["/nginx-ingress-controller"],
              args_+: {
                "default-backend-service": "$(POD_NAMESPACE)/default-http-backend",
                configmap: "$(POD_NAMESPACE)/" + $.nginx_config.metadata.name,
              },
              ports_+: {
                http: { containerPort: 80 },
                https: { containerPort: 443 },
              },
              readinessProbe: {
                httpGet: { path: "/healthz", port: 10254 },
                timeoutSeconds: 5,
              },
              livenessProbe: self.readinessProbe {
                failureThreshold: 5,
                initialDelaySeconds: 10,
              },
            },
          },
        },
      },
    },
  },

  // Disabled due to https://github.com/kubernetes/kubernetes/issues/34413
  // Fix needs kubectl >= 1.5.2, and we need <1.5 to workaround
  // in-cluster cross-namespace bug - which leaves no solution (yet) :(
  /*
  nginx_hpa: kube.HorizontalPodAutoscaler($.name) {
    metadata+: { namespace: $.namespace },
    target: $.nginx,
    spec+: {
      maxReplicas: 5,
      minReplicas: 2,
    },
  },
  */
};

kube.List() { items_+: nginx_ingress }
