local config = import "../../common/config/alertmanager.jsonnet";

config {
  route+: {
    // dev cluster -> just let everything fall through to 'default'.
    // TODO: We still care about *some* level of service-availability.
    routes: [],
  },
}
