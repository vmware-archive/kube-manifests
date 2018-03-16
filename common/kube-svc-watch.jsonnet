// Report on count of internal/external Services, and optionally kill
// external services when found.

local kube = import "kube.libsonnet";

local kube_svc_watch = {
  namespace:: null,

  svc_watch: kube.Deployment("kube-svc-watch") {
    metadata+: { namespace: $.namespace },

    spec+: {
      template+: {
        local tmpl = self,
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": std.toString(tmpl.spec.containers_.ksw.ports_.metrics.containerPort),
          },
        },
        spec+: {
          containers_+: {
            ksw: kube.Container("kube-svc-watch") {
              // This is https://github.com/anguslees/kube-svc-watch
              image: "gcr.io/bitnami-images/kube-svc-watch:jenkins-sre-k8s-kube-svc-watch-22",
              command: ["kube-svc-watch"],
              args_+: {
                logtostderr: true,
              },
              ports_+: {
                metrics: { containerPort: 8080 },
              },
              resources: {
                limits: { cpu: "10m", memory: "32Mi" },
              },
            },
          },
        },
      },
    },
  },
};

kube.List() { items_+: kube_svc_watch }
