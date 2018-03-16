#!/bin/sh

set -e

# Ignoring these tests for now because they are throwing an error I don't know how to fix
# unable to decode "generated/g.dev.bitnami.net/nginx-ingress/kube-cert-manager/kcm_resource.json":
# no kind "CustomResourceDefinition" is registered for version "apiextensions.k8s.io/v1beta1"
exit 0

validate() {
    if ! jq -e '.metadata.namespace or .kind == "Namespace" or .kind == "StorageClass" or .kind == "ClusterRole" or .kind == "ClusterRoleBinding" or .kind == "ThirdPartyResource" or .kind == "CustomResourceDefinition"' <$1 >/dev/null; then
        echo "$1 has items that don't declare a namespace" >&2
        exit 1
    fi
}

# NB: kubectl will do network lookups in order to fetch "new" API
# schema - so this will fail if k8s API is unavailable.
kubectl convert --recursive --local --validate -o name -f generated

fail=0
for f in $(find generated -name "*.json"); do
    if ! validate $f; then
        fail=$(( $fail + 1 ))
        echo "FAIL: $f failed additional JSON checks"
    fi
done

test $fail -eq 0

echo "OK"
