local kube = import "kube.libsonnet";

// Implement elasticsearch-curator as a Kubernetes CronJob
// Heavily inspired on https://github.com/HagaiBarel/kube-charts
local elasticsearch_curator = {
  namespace:: null,
  name:: "elasticsearch-curator",
  retention_days:: 30,
  elasticsearch_host:: "elasticsearch-logging",
  elasticsearch_port:: 9200,
  elasticsearch_curator_config: kube.ConfigMap($.name) {
    metadata+: {
      namespace: $.namespace,
    },
    data+: {
      action_file_yml_tmpl:: |||
        ---
        # Remember, leave a key empty if there is no value.  None will be a string,
        # not a Python "NoneType"
        #
        # Also remember that all examples have 'disable_action' set to True.  If you
        # want to use this action as a template, be sure to set this to False after
        # copying it.
        actions:
          1:
            action: delete_indices
            description: "Clean up ES by deleting old indices"
            options:
              timeout_override:
              continue_if_exception: False
              disable_action: False
              ignore_empty_list: True
            filters:
            - filtertype: age
              source: name
              direction: older
              timestring: '%%Y.%%m.%%d'
              unit: days
              unit_count: %d
              field:
              stats_result:
              epoch:
              exclude: False
      |||,
      config_yml_tmpl:: |||
        ---
        # Remember, leave a key empty if there is no value.  None will be a string,
        # not a Python "NoneType"
        client:
          hosts:
            - %s
          port: %d
          url_prefix:
          use_ssl: False
          certificate:
          client_cert:
          client_key:
          ssl_no_validate: False
          http_auth:
          timeout: 30
          master_only: False

        logging:
          loglevel: INFO
          logfile:
          logformat: default
          blacklist: ['elasticsearch', 'urllib3']
      |||,
      "action_file.yml": std.format(self.action_file_yml_tmpl, [$.retention_days]),
      "config.yml": std.format(self.config_yml_tmpl, [$.elasticsearch_host, $.elasticsearch_port]),
    },
  },
  elasticsearch_curator_cronjob: kube.CronJob($.name) {
    metadata+: {
      namespace: $.namespace,
    },
    spec+: {
      schedule: "30 0 * * *",
      jobTemplate+: {
        spec+:
          {
            template+: {
              spec+: {
                containers_+: {
                  curator: kube.Container("curator") {
                    image: "bobrik/curator:5.1.1",
                    args: ["--config", "/etc/config/config.yml", "/etc/config/action_file.yml"],
                    volumeMounts_+: {
                      config_vol: {
                        mountPath: "/etc/config",
                        readOnly: true,
                      },
                    },
                  },
                },
                volumes_+: {
                  config_vol: kube.ConfigMapVolume($.elasticsearch_curator_config),
                },
              },
            },
          },
      },
    },
  },
};

kube.List() { items_+: elasticsearch_curator }
