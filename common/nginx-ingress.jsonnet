local kube = import "kube.libsonnet";
local bitnami = import "bitnami.libsonnet";

local ingress = {
  namespace:: null,

  nginx_config: kube.ConfigMap("nginx") {
    metadata+: { namespace: $.namespace },
    data+: {
      "proxy-connect-timeout": "15",
      "hosts-include-subdomains": "false",
      "body-size": "800m",
      "server-name-hash-bucket-size": "256",
      "ssl-protocols": "TLSv1.1 TLSv1.2",  // Remove TLSv1

      // Crazy-high, to support websockets:
      // https://github.com/kubernetes/ingress/blob/7394395715d944f352a3cbc0edbf118497f4d916/controllers/nginx/configuration.md#websockets
      "proxy-read-timeout": "3600",
      "proxy-send-timeout": "3600",

      "enable-vts-status": "true",

      // Allow anything that can actually reach the nginx port to make
      // PROXY requests, and so arbitrarily specify the user ip.  (ie:
      // leave perimeter security up to k8s).
      // (Otherwise, this needs to be set to the ELB inside subnet)
      "proxy-real-ip-cidr": "0.0.0.0/0",
      "use-proxy-protocol": "true",
    },
  },

  default_http_backend_svc: kube.Service("default-http-backend") {
    metadata+: { namespace: $.namespace },
    port: 80,
    target_pod: $.default_http_backend.spec.template,
  },

  // NB: There is deliberately no autoscaler for default-backend.  If
  // lots of traffic falls through to this (DoS?) then we *want* that
  // traffic to see performance degradation and eventually failure.
  default_http_backend: kube.Deployment("default-http-backend") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          terminationGracePeriodSeconds: 60,
          containers_+: {
            backend: kube.Container("default-http-backend") {
              image: "gcr.io/google_containers/defaultbackend:1.2",
              ports_+: {
                http: { containerPort: 8080 },
              },
              livenessProbe: {
                httpGet: { path: "/healthz", port: "http" },
                initialDelaySeconds: 30,
                timeoutSeconds: 5,
              },
              resources: {
                limits: { cpu: "10m", memory: "20Mi" },
                requests: self.limits,
              },
            },
          },
        },
      },
    },
  },

  nginx_svc: bitnami.InternalElbService("nginx-ingress") {
    metadata+: {
      namespace: $.namespace,
      annotations+: {
        // Use PROXY protocol (nginx supports this too)
        "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol": if $.nginx_config.data["use-proxy-protocol"] == "true" then "*" else null,

        // Does LB do NAT or DSR? (OnlyLocal implies DSR)
        // https://kubernetes.io/docs/tutorials/services/source-ip/
        // NB: Don't enable this without modifying set-real-ip-from above!
        // Not supported on aws in k8s 1.5 - immediate close / serves 503s.
        //"service.beta.kubernetes.io/external-traffic": "OnlyLocal",
      },
    },
    target_pod: $.nginx.spec.template,
    spec+: {
      ports: [
        { port: 80, name: "http" },
        { port: 443, name: "https" },
      ],
    },
  },

  nginx: kube.Deployment("nginx-ingress") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: bitnami.PromScrape(9913) {
        spec+: {
          terminationGracePeriodSeconds: 60,
          containers_+: {
            ingress: kube.Container("nginx-ingress-lb") {
              image: "gcr.io/google_containers/nginx-ingress-controller:0.8.3",
              env_+: {
                POD_NAME: kube.FieldRef("metadata.name"),
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              command: ["/nginx-ingress-controller"],
              args_+: {
                "default-backend-service": "$(POD_NAMESPACE)/" + $.default_http_backend.metadata.name,
                "nginx-configmap": "$(POD_NAMESPACE)/" + $.nginx_config.metadata.name,
                //"--publish-service=$(POD_NAMESPACE)/" + $.nginx_svc.metadata.name,
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

            prom_exporter: kube.Container("vts-exporter") {
              image: "anguslees/nginx-vts-exporter:v0.3",
              command: ["nginx-vts-exporter"],
              args_+: {
                "nginx.scrape_uri": "http://localhost:18080/nginx_status/format/json",
              },
              ports_+: {
                prom: { containerPort: 9913 },
              },
              readinessProbe: {
                httpGet: { path: "/", port: "prom" },
                timeoutSeconds: 5,
              },
              livenessProbe: self.readinessProbe {
                failureThreshold: 3,
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
  nginx_hpa: kube.HorizontalPodAutoscaler("nginx-ingress") {
    metadata+: { namespace: $.namespace },
    target: $.nginx,
    spec+: { maxReplicas: 5 },
  },
  */
};

kube.List() { items_+: ingress }
