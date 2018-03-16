// alertmanager/config.yml

local mapToNamedList(namefield, obj) =
  [{ [namefield]: n } + obj[n] for n in std.objectFields(obj)];

{
  cluster:: error "cluster must be defined",

  global: {
    resolve_timeout: "5m",

    // Restricted Gmail SMTP server - can only send to GMail or
    // GSuite, and may get spam filtered.
    // TODO: Don't want alerts spam-filtered!  Should switch to
    // authenticated sender (by password or source IP) - see
    // https://support.google.com/a/answer/176600
    smtp_smarthost: "aspmx.l.google.com",
    smtp_from: "sre+alertmanager@bitnami.com",

    slack_api_url: "https://hooks.slack.com/services/<redacted>",
  },

  templates: ["/etc/alertmanager-templates/*.tmpl"],

  inhibit_rules: [
    {
      source_match: { severity: "critical" },
      target_match: { severity: "warning" },
      equal: ["alertname", "cluster", "service"],
    },
  ],

  route: {
    group_by: ["alertmanager", "alertname", "cluster", "notify_to", "slack_channel"],
    group_wait: "1m",
    group_interval: "5m",
    repeat_interval: "6h",
    receiver: "default",
    routes: [
      {
        receiver: "slack",
        match_re: {
          notify_to: "^slack$",
          slack_channel: "^#[a-z].+",
        },
      },
    ],
  },

  receivers: mapToNamedList("name", self.receivers_),
  receivers_:: {
    local slack_defaults = {
      title: "{{ with $alert := index .Alerts 0 }}{{ $alert.Annotations.summary }}{{ end }}",
      text: "Cluster: " + $.cluster + "\n{{ range .Alerts }}[{{ .Status | toUpper }}] {{ .Annotations.description }}\n{{ end }}",
      send_resolved: true,
    },

    default: {
      slack_configs: [
        slack_defaults {
          channel: "#alert-testing",
          send_resolved: true,
        },
      ],
    },

    slack: {
      slack_configs: [
        slack_defaults {
          channel: "{{ .GroupLabels.slack_channel }}",
        },
      ],
    },

    email: {
      email_configs: [
        { to: "sre+alerts@example.com" },
      ],
    },
  },
}
