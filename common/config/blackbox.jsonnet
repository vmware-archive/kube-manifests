// blackbox.yml

{
  modules: {
    http_2xx: {
      prober: "http",
      timeout: "5s",
      http: {
        method: "GET",
        //valid_status_codes: [], // Defaults to 2xx
        no_follow_redirects: false,  // ie: *do* follow redirects
      },
    },

    ssh: {
      prober: "tcp",
      timeout: "5s",
      tcp: {
        query_response: [
          { expect: "^SSH-2.0-" },
        ],
      },
    },
  },
}
