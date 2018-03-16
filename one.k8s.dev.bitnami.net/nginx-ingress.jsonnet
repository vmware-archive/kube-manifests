local kube = import "kube.libsonnet";
local ingress = import "../common/nginx-ingress.jsonnet";

ingress {
  items_+: {
    namespace: "nginx-ingress",

    nginx_svc+: {
      metadata+: {
        annotations+: {
          "service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout": "1200",
        },
      },
    },


  },
}
