local kube = import "kube.libsonnet";
local jenkins = import "../common/jenkins.jsonnet";

local proxy = import "squid.jsonnet";
local http_proxy = proxy.items_.url;

jenkins {
  items_+: {
    namespace: "jenkins",

    jenkins_ns: kube.Namespace(self.namespace),

    jenkins_ing+: {
      host: "jenkins.k.int.bitnami.net",
    },

    jenkins_master+: {
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              master+: {
                env_+: {
                  http_proxy: http_proxy,
                },
              },
            },
          },
        },
      },
    },
  },
}
