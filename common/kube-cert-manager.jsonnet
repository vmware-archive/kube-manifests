// LetsEncrypt client using DNS challenges
//
// # Setup notes
//
// ```
// aws route53 list-hosted-zones (find Id for $name.bitnami.net.)
// zid=...
// ```
//
// ## Wildcard DNS setup:
// ```
// elb=$(kubectl get svc -n nginx-ingress nginx-ingress -o jsonpath="{.status.loadBalancer.ingress[*].hostname}")
// jsonnet -V cname='*.k.dev.bitnami.net' -V value=$elb common/route53-upsert.jsonnet >/tmp/change.json
// aws route53 change-resource-record-sets --hosted-zone-id $zid --change-batch file:///tmp/change.json
// ```
//
// ## Service account setup:
// ```
// n=one-k8s-dev-kube-cert-manager
// aws iam create-user --user-name $n
// aws iam create-access-key --user-name $n
// kubectl create secret generic kube-cert-manager-aws -n nginx-ingress \
//  --from-literal=access_key_id=... --from-literal=secret_access_key=...
// aws route53 list-hosted-zones
// aws iam attach-user-policy --user-name $n \
//  --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess
// ```

local kube = import "kube.libsonnet";

local all = {
  namespace:: null,

  kcm_resource: kube.ThirdPartyResource("certificate.stable.k8s.psg.io") {
    description: "A specification of a Let's Encrypt Certificate to manage.",
    versions_: ["v1"],
  },

  kcm_pvc: kube.PersistentVolumeClaim("kube-cert-manager") {
    metadata+: { namespace: $.namespace },
    storage: "8G",
  },

  kcm_secret:: kube.Secret("kube-cert-manager-aws") {
    metadata+: { namespace: $.namespace },
    data_+: {
      access_key_id: error "provided externally",
      secret_access_key: error "provided externally",
    },
  },

  kcm: kube.Deployment("kube-cert-manager") {
    metadata+: { namespace: $.namespace },
    spec+: {
      template+: {
        spec+: {
          default_container: "kcm",
          containers_+: {
            kcm: kube.Container("kube-cert-manager") {
              image: "palmstonegames/kube-cert-manager:0.3.1",
              args_+: {
                "data-dir": "/var/lib/cert-manager",
                // staging: "https://acme-staging.api.letsencrypt.org/directory"
                "acme-url": "https://acme-v01.api.letsencrypt.org/directory",
              },
              env_+: {
                // See https://github.com/PalmStoneGames/kube-cert-manager/blob/master/docs/providers.md
                AWS_ACCESS_KEY_ID: kube.SecretKeyRef($.kcm_secret, "access_key_id"),
                AWS_SECRET_ACCESS_KEY: kube.SecretKeyRef($.kcm_secret, "secret_access_key"),
              },
              ports_+: {
                http: { containerPort: 8080 },
                tls_sni: { containerPort: 8081 },
              },
              volumeMounts_+: {
                data: { mountPath: "/var/lib/cert-manager" },
              },
            },
            kubectl_proxy: kube.Container("kubectl-proxy") {
              image: "palmstonegames/kubectl-proxy:1.4.0",
            },
          },
          volumes_+: {
            data: kube.PersistentVolumeClaimVolume($.kcm_pvc),
          },
        },
      },
    },
  },
};

kube.List() { items_+: all }
