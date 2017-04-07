local config = import "../../common/config/prometheus.jsonnet";

config {
  global+: {
    external_labels+: {
      cluster: "one.k8s.int.bitnami.net",
    },
  },
}
