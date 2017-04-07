// Generic stuff is in kube.libsonnet - this file contains
// additional AWS or Bitnami -specific conventions.

local kube = import "kube.libsonnet";

{
  ElbService(name): kube.Service(name) {
    local service = self,

    metadata+: {
      annotations+: {
        "service.beta.kubernetes.io/aws-load-balancer-connection-draining-enabled": "true",
        "service.beta.kubernetes.io/aws-load-balancer-connection-draining-timeout": std.toString(service.target_pod.spec.terminationGracePeriodSeconds),
      },
    },
    spec+: { type: "LoadBalancer" },
  },

  InternalElbService(name): $.ElbService(name) {
    metadata+: {
      annotations+: {
        "service.beta.kubernetes.io/aws-load-balancer-internal": "0.0.0.0/0",
      },
    },
  },

  Ingress(name): kube.Ingress(name) {
    local ing = self,

    host:: error "host required",
    target_svc:: error "target_svc required",

    metadata+: {
      annotations+: {
        "stable.k8s.psg.io/kcm.enabled": "true",
        "stable.k8s.psg.io/kcm.provider": "route53",
        "stable.k8s.psg.io/kcm.email": "sre@bitnami.com",
      },
    },

    spec+: {
      tls: [
        {
          hosts: std.uniq([r.host for r in ing.spec.rules]),
          secretName: "%s-cert" % [ing.metadata.name],

          assert std.length(self.hosts) <= 1 : "kube-cert-manager only supports one host per secret - make a separate Ingress resource",
        },
      ],

      // Default to single-service - override if you want something else.
      rules: [
        {
          host: ing.host,
          http: {
            paths: [
              { path: "/", backend: ing.target_svc.name_port },
            ],
          },
        },
      ],
    },
  },

  PromScrape(port): {
    local scrape = self,
    prom_path:: "/metrics",

    metadata+: {
      annotations+: {
        "prometheus.io/scrape": "true",
        "prometheus.io/port": std.toString(port),
        "prometheus.io/path": scrape.prom_path,
      },
    },
  },

  PodZoneAntiAffinityAnnotation(pod): {
    affinity:: {
      podAntiAffinity: {
        preferredDuringSchedulingIgnoredDuringExecution: [
          {
            weight: 50,
            podAffinityTerm: {
              labelSelector: { matchLabels: pod.metadata.labels },
              topologyKey: "failure-domain.beta.kubernetes.io/zone",
            },
          },
          {
            weight: 100,
            podAffinityTerm: {
              labelSelector: { matchLabels: pod.metadata.labels },
              topologyKey: "kubernetes.io/hostname",
            },
          },
        ],
      },
    },
    "scheduler.alpha.kubernetes.io/affinity": std.toString(self.affinity),
  },
}
