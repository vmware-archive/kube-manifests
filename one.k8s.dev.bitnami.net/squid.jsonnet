local kube = import "kube.libsonnet";
local squid = import "../common/squid.jsonnet";

squid {
  items_+: {
    namespace: "webcache",

    squid_ns: kube.Namespace(self.namespace),
  },
}
