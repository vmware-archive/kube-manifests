// Jenkins master (and slaves) on Kubernetes.
//
// Vaguely inspired by
// https://cloud.google.com/solutions/jenkins-on-container-engine
//
// See doc/jenkins.md for post-install setup instructions.

local kube = import "kube.libsonnet";
local bitnami = import "bitnami.libsonnet";

local jenkins = {
  namespace:: null,

  jenkins_svc: kube.Service("jenkins") + bitnami.PromScrape(8080) {
    target_pod: $.jenkins_master.spec.template,
    spec+: {
      ports: [{ port: 80, targetPort: "ui" }],
    },
    metadata+: {
      namespace: $.namespace,
    },
    prom_path: "/prometheus",
  },

  jenkins_discovery_svc: kube.Service("jenkins-discovery") {
    metadata+: { namespace: $.namespace },
    target_pod: $.jenkins_master.spec.template,
    spec+: {
      ports: [{ port: 50000, targetPort: "slaves" }],
    },
  },

  jenkins_ing: bitnami.Ingress("jenkins") {
    metadata+: {
      namespace: $.namespace,
    },
    target_svc: $.jenkins_svc,
  },

  jenkins_home: kube.PersistentVolumeClaim("jenkins-home") {
    metadata+: { namespace: $.namespace },
    storage: "15Gi",
  },

  jenkins_secret: kube.Secret("jenkins") {
    metadata+: { namespace: $.namespace },
    data_+: {
      // "--argumentsRealm.passwd.jenkins=CHANGE_ME --argumentsRealm.roles.jenkins=admin",
      options: "",
    },
  },

  jenkins_chown:: kube.Container("chown-jenkins") {
    image: "busybox",
    command: ["chown", "1000:1000", "/jenkins_home"],
    volumeMounts_+: {
      jenkinshome: { mountPath: "/jenkins_home" },
    },
  },

  jenkins_master: kube.Deployment("jenkins") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            master: kube.Container("master") {
              local c = self,
              image: "jenkins:2.89.4",
              ports_+: {
                ui: { containerPort: 8080 },
                slaves: { containerPort: 50000 },
              },
              env_+: {
                JENKINS_OPTS: kube.SecretKeyRef($.jenkins_secret, "options"),
                JAVA_OPTS: "-Xmx%dm -Dhudson.slaves.NodeProvisioner.MARGIN=50 -Dhudson.slaves.NodeProvisioner.MARGIN0=0.85" % [
                  kube.siToNum(c.resources.requests.memory) / kube.siToNum("1Mi"),
                ],
              },
              volumeMounts_+: {
                jenkinshome: { mountPath: "/var/jenkins_home" },
              },
              resources: {
                limits: {
                  cpu: "1",
                  memory: "1000Mi",
                },
                requests: {
                  cpu: "0.5",
                  memory: "500Mi",
                },
              },
              livenessProbe: {
                httpGet: {
                  path: "/login",
                  port: "ui",
                },
                // Jenkins can legitimately take a long time to start up
                initialDelaySeconds: 120,
                // Jenkins can legitimately fail health checks while restarting
                timeoutSeconds: 20,
                failureThreshold: 6,  // ie: 6 * periodSeconds (default=10) is ok
              },
              readinessProbe: c.livenessProbe {
                successThreshold: 2,
              },
              lifecycle: {
                preStop: {
                  httpGet: { path: "/quietDown", port: "ui" },
                },
              },
            },
          },
          terminationGracePeriodSeconds: 5 * 60,
          securityContext: {
            // make pvc owned by this gid
            fsGroup: 1000,
          },
          volumes_+: {
            jenkinshome: kube.PersistentVolumeClaimVolume($.jenkins_home),
          },
        },
      },
    },
  },
};

kube.List() { items_+: jenkins }
