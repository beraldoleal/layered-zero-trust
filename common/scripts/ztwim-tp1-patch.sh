#!/usr/bin/env bash

set -eu

# Wait for the ZTWIM pods to be ready
oc wait -n zero-trust-workload-identity-manager --for=condition=Ready pod --all &>/dev/null

# Install kyverno
if ! oc get crd clusterpolicies.kyverno.io &>/dev/null; then
    oc create -k https://github.com/redhat-cop/gitops-catalog/kyverno/base
fi

# Wait for the kyverno pods to be ready
oc wait -n kyverno --for=condition=Ready pod -l app.kubernetes.io/component=admission-controller &>/dev/null
oc wait -n kyverno --for=condition=Ready pod -l app.kubernetes.io/component=background-controller &>/dev/null

# Check if the spire-bundle policy exists
if ! oc get clusterpolicy spire-bundle &>/dev/null; then

# Create the spire-bundle policy
    oc apply -f - <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: spire-bundle
spec:
  generateExisting: true
  background: false
  rules:
  - name: spire-bundle
    match:
      any:
      - resources:
          kinds:
          - ConfigMap
          namespaces:
          - zero-trust-workload-identity-manager
          names:
          - spire-bundle
    generate:
      kind: Secret
      apiVersion: v1
      name: "{{request.object.metadata.name}}"
      namespace: "{{request.namespace}}"
      synchronize: true
      data:
        metadata:
          ownerReferences:
          - apiVersion: v1
            kind: ConfigMap
            name: "{{request.object.metadata.name}}"
            uid: "{{request.object.metadata.uid}}"
        data:
          tls.crt: "{{ base64_encode(request.object.data.\"bundle.crt\") }}"
EOF
fi

# Wait for the spire-bundle secret to be created
until oc get secret -n zero-trust-workload-identity-manager spire-bundle &>/dev/null; do sleep 5; done


oidc_url="https://$(oc get ingress -n zero-trust-workload-identity-manager spire-spiffe-oidc-discovery-provider -o jsonpath='{ .spec.rules[0].host }')"

# Check the oidc status
if [ "$(curl -skL -o /dev/null -w "%{http_code}" "${oidc_url}/.well-known/openid-configuration")" -ne 200 ]; then
  echo "OIDC configuration is not available"
  exit 1
fi

# Scale down the spire-server deployment
oc patch csv -n zero-trust-workload-identity-manager zero-trust-workload-identity-manager.v0.1.0 --type='json' \
  -p='[{"op": "replace", "path": "/spec/install/spec/deployments/0/spec/replicas", "value": 0}]'

# Update the spire-server configuration
if [ "$(oc get cm spire-server -n zero-trust-workload-identity-manager -o jsonpath='{ .data.server\.conf }' | jq -r '.server.jwt_issuer')" != "${oidc_url}" ]; then
    oc get cm spire-server -n zero-trust-workload-identity-manager -o jsonpath='{ .data.server\.conf }'\
        | jq --arg jwt_issuer "$oidc_url" -r '.server.jwt_issuer = $jwt_issuer' > /tmp/ztwim-server.conf

    oc create cm -n zero-trust-workload-identity-manager spire-server --from-file=server.conf=/tmp/ztwim-server.conf -o yaml --dry-run=client \
        | oc apply --server-side=true --force-conflicts -f-

    rm /tmp/ztwim-server.conf

    # Restart the pods
    oc delete pod --all -n zero-trust-workload-identity-manager
fi

# Wait for the ZTWIM pods to be ready
oc wait -n zero-trust-workload-identity-manager --for=condition=Ready pod --all &>/dev/null
