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
        preferred_ip_protocol: "ip4",
        fail_if_ssl: false,
        fail_if_not_ssl: false,
        tls_config: {
          insecure_skip_verify: true,
        },
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

    dns_public: {
      prober: "dns",
      timeout: "5s",
      dns: {
        query_name: "www.google.com",
        query_type: "A",
        valid_rcodes: ["NOERROR"],
      },
    },

    dns_internal: {
      prober: "dns",
      timeout: "5s",
      dns: {
        query_name: "endor.nami",
        query_type: "A",
        valid_rcodes: ["NOERROR"],
        validate_answer_rrs: {
          fail_if_not_matches_regexp: [
            "endor\\.nami\\.\\t[0-9]+\\tIN\\tA\\t23\\.21\\.148\\.169",
          ],
        },
      },
    },
  },
}
