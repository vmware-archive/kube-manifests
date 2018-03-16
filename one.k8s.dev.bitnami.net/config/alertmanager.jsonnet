local config = import "../../common/config/alertmanager.jsonnet";

config {
  cluster: "one.k8s.dev.bitnami.net",
  route+: {
    // dev cluster -> just let everything fall through to 'default'.
    // TODO: We still care about *some* level of service-availability.
    routes: [],
  },
}
