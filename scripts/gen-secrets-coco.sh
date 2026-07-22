#!/usr/bin/env bash
set -e

# Generate cryptographic material required by the CoCo components.
# Run this once before your first deployment.
#
# Creates:
#   - KBS Ed25519 keypair for Trustee admin API authentication
#   - Container image security policy (insecure default)
#   - SSH keypair for podvm debug access (optional, non-dm-verity images only)
#   - Copies values-secret.yaml.template to ~/values-secret-<pattern>.yaml (if not present)
#
# Will not overwrite existing files. Delete ~/.config/validated-patterns/trustee/
# to regenerate.

SECRETS_DIR="${HOME}/.config/validated-patterns/trustee"
KBS_PRIVATE_KEY="${SECRETS_DIR}/kbsPrivateKey"
KBS_PUBLIC_KEY="${SECRETS_DIR}/kbsPublicKey"
SECURITY_POLICY_FILE="${SECRETS_DIR}/security-policy-config.json"
SSH_KEY_FILE="${SECRETS_DIR}/id_rsa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERN_DIR="${SCRIPT_DIR}/.."

# Determine pattern name from values-global.yaml
PATTERN_NAME=$(yq eval '.global.pattern' "${PATTERN_DIR}/values-global.yaml" 2>/dev/null)
if [ -z "$PATTERN_NAME" ] || [ "$PATTERN_NAME" == "null" ]; then
    echo "ERROR: Could not determine pattern name from values-global.yaml"
    exit 1
fi

VALUES_FILE="${HOME}/.config/validated-patterns/values-secret-${PATTERN_NAME}.yaml"

mkdir -p "${SECRETS_DIR}"

# Generate container image security policy (insecure default)
if [ ! -f "${SECURITY_POLICY_FILE}" ]; then
    echo "Creating security policy (insecure default)..."
    cat > "${SECURITY_POLICY_FILE}" <<EOF
{
  "default": [
  {
    "type": "insecureAcceptAnything"
  }],
  "transports": {}
}
EOF
    echo "  Policy: ${SECURITY_POLICY_FILE}"
else
    echo "Security policy already exists, skipping."
fi

# Generate KBS Ed25519 keypair
if [ ! -f "${KBS_PRIVATE_KEY}" ]; then
    echo "Generating KBS Ed25519 keypair..."
    rm -f "${KBS_PUBLIC_KEY}"
    openssl genpkey -algorithm ed25519 > "${KBS_PRIVATE_KEY}"
    openssl pkey -in "${KBS_PRIVATE_KEY}" -pubout -out "${KBS_PUBLIC_KEY}"
    chmod 600 "${KBS_PRIVATE_KEY}"
    echo "  Private key: ${KBS_PRIVATE_KEY}"
    echo "  Public key:  ${KBS_PUBLIC_KEY}"
else
    echo "KBS keypair already exists, skipping."
fi

# Generate SSH keypair for podvm debug access
if [ ! -f "${SSH_KEY_FILE}" ]; then
    echo "Generating SSH keypair..."
    rm -f "${SSH_KEY_FILE}.pub"
    ssh-keygen -f "${SSH_KEY_FILE}" -N ""
    echo "  SSH key: ${SSH_KEY_FILE}"
else
    echo "SSH keypair already exists, skipping."
fi

# Copy values-secret template
if [ ! -f "${VALUES_FILE}" ]; then
    echo "Copying values-secret template to ${VALUES_FILE}"
    echo "Please review before deploying."
    cp "${PATTERN_DIR}/values-secret.yaml.template" "${VALUES_FILE}"
else
    echo "Values file already exists: ${VALUES_FILE}"
fi

echo ""
echo "Next steps:"
echo "  1. Review ${VALUES_FILE}"
echo "  2. Run ./pattern.sh make install"
