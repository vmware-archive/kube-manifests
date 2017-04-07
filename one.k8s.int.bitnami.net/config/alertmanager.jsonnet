local config = import "../../common/config/alertmanager.jsonnet";

config {
  route+: {
    routes: [
      {
        match: { severity: "critical" },
        repeat_interval: "15m",
        receiver: "sre_slack",
      },
      {
        match: { severity: "warning" },
        receiver: "sre_slack",
      },
      {
        match: { severity: "notice" },
        receiver: "sre_email",
      },
    ],
  },
}
