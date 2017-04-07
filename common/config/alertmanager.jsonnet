// alertmanager/config.yml

local mapToNamedList(namefield, obj) =
  [{ [namefield]: n } + obj[n] for n in std.objectFields(obj)];

{
  global: {
    resolve_timeout: "5m",

    // Restricted Gmail SMTP server - can only send to GMail or
    // GSuite, and may get spam filtered.
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
    group_by: ["alertmanager", "cluster", "service"],
    group_wait: "1m",
    group_interval: "10m",
    repeat_interval: "8h",
    receiver: "default",

    routes: [],
  },

  receivers: mapToNamedList("name", self.receivers_),
  receivers_:: {
    local slack_defaults = {
      title: "{{ range .Alerts }}{{ .Annotations.summary }} {{ end }}",
      text: "{{ range .Alerts }}{{ .Annotations.description }} {{ end }}",
    },

    default: {
      slack_configs: [
        slack_defaults {
          channel: "#alert-testing",
          send_resolved: true,
        },
      ],
    },

    sre_slack: {
      slack_configs: [
        slack_defaults {
          channel: "#sre-incidents",
        },
      ],
    },

    sre_email: {
      email_configs: [
        { to: "sre+alerts@bitnami.com" },
      ],
    },
  },
}
