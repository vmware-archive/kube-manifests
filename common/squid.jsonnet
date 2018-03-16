// Basic squid web cache
//
// Good for accelerating in-cluster docker builds, jenkins jobs, etc.
// Also serves as a simple example.

local kube = import "kube.libsonnet";


local squid = {
  namespace:: null,

  // eg: http_proxy=http://proxy.$namespace:80/
  url:: $.squid_service.http_url,

  squid_service: kube.Service("proxy") {
    metadata+: { namespace: $.namespace },
    target_pod: $.squid.spec.template,
    port: 80,
  },

  squid_data: kube.PersistentVolumeClaim("proxy") {
    metadata+: { namespace: $.namespace },
    storage: "10G",
  },

  squid: kube.Deployment("proxy") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            squid: kube.Container("squid") {
              local container = self,
              image: "jpetazzo/squid-in-a-can",
              env_+: {
                // Allow access from everything that k8s might use
                // (RFC1918 is already in the list)
                SQUID_DIRECTIVES: "acl localnet src 100.64.0.0/10",

                // As the squid docs say: "Do NOT put the size of your
                // disk drive here.  Instead, if you want Squid to use
                // the entire disk drive, subtract 20% and use that
                // value."  (in MB)
                DISK_CACHE_SIZE: "%d" % (kube.siToNum($.squid_data.storage) * 0.8 / 1e6),
              },
              ports_+: {
                proxy: { containerPort: 3128 },
              },
              volumeMounts_+: {
                cache: { mountPath: "/var/cache/squid3" },
              },
              livenessProbe: {
                tcpSocket: { port: "proxy" },
              },
              readinessProbe: {
                tcpSocket: container.livenessProbe.tcpSocket,
              },
            },
          },
          volumes_+: {
            cache: kube.PersistentVolumeClaimVolume($.squid_data),
          },
        },
      },
    },
  },
};

kube.List() { items_+: squid }
