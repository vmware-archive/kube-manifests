local kube = import "kube.libsonnet";
local ingress = (import "../common/nginx-ingress.jsonnet").items_;
local kcm = (import "../common/kube-cert-manager.jsonnet").items_;

local all = ingress + kcm {
  namespace: "nginx-ingress",

  nginx_ingress_ns: kube.Namespace($.namespace),
};

kube.List() { items_+: all }
