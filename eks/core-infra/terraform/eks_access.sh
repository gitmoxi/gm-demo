#!/bin/bash
set -euo pipefail

IAM_ROLE_ARN="$1"
TMP_FILE="tmp-aws-auth.yaml"

kubectl get configmap aws-auth -n kube-system -o yaml > "$TMP_FILE"

# Check if role already present
if grep -q "$IAM_ROLE_ARN" "$TMP_FILE"; then
  echo "✅ IAM role already present in aws-auth"
else
  echo "🔧 Adding IAM role to aws-auth..."

  # Append under mapRoles
  awk -v rolearn="$IAM_ROLE_ARN" '
    /^  mapRoles: \|/ {
      print;
      print "    - rolearn: " rolearn;
      print "      username: gitmoxi-controller";
      print "      groups:";
      print "        - system:masters";
      next
    }
    { print }
  ' "$TMP_FILE" > "${TMP_FILE}.new"

  kubectl replace -f "${TMP_FILE}.new"
  echo "✅ aws-auth updated"
fi

rm -f "$TMP_FILE" "${TMP_FILE}.new"