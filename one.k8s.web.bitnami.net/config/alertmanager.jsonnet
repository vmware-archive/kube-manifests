local config = import "../../common/config/alertmanager.jsonnet";

config {
  cluster: "one.k8s.web.bitnami.net",
  route+: {
    routes: [
      {
        match: { severity: "critical" },
        repeat_interval: "15m",
        receiver: "slack",
      },
      {
        match: { severity: "warning" },
        receiver: "slack",
      },
      {
        match: { severity: "notice" },
        receiver: "email",
      },
    ],
  },
}
