local addons = import "../common/aws-addons.jsonnet";

addons {
  items_+: {
    num_nodes: 10,  // approximate

    kibana_logging_ing+: {
      host: "kibana.k.dev.bitnami.net",
    },
  },
}
