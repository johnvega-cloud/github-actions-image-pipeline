# Build guide

## 1. Order

1. **Dockerfile** first: the pipeline needs an image that builds for amd64 and arm64.
   The build stage uses `--platform=$BUILDPLATFORM` and cross-compiles with
   `GOARCH=$TARGETARCH`, so arm64 is not compiled under QEMU emulation.
2. **`scan` job**: build + Trivy. This alone already works on PRs, with no cloud account.
3. **AWS side** (section 2): ECR repository, OIDC provider, IAM role.
4. **`publish` job**: AWS login, multi-arch push, Cosign signature.
5. **Branch protection** on `main`, otherwise `github.ref_protected` is false and
   `publish` is skipped.

## 2. AWS setup

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
ROLE=cloudbatch818-gha-ecr-push

aws ecr create-repository --repository-name hello --region "$REGION"

# Once per account (skip if it already exists)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

# The OIDC "sub" claim GitHub sends for this repo. New repos use the immutable
# form, with owner and repo IDs: repo:OWNER@ID/REPO@ID:ref:refs/heads/main
gh api repos/johnvega-cloud/github-actions-image-pipeline/actions/oidc/customization/sub
# -> put its sub_claim_prefix + ":ref:refs/heads/main" in iam/trust-policy.json

sed "s/ACCOUNT_ID/$ACCOUNT_ID/" iam/trust-policy.json > /tmp/trust.json
sed -e "s/ACCOUNT_ID/$ACCOUNT_ID/" -e "s/REGION/$REGION/" iam/ecr-push-policy.json > /tmp/push.json

aws iam create-role --role-name "$ROLE" --assume-role-policy-document file:///tmp/trust.json
aws iam put-role-policy --role-name "$ROLE" --policy-name ecr-push --policy-document file:///tmp/push.json

echo "AWS_ROLE_ARN=arn:aws:iam::$ACCOUNT_ID:role/$ROLE"
```

Then set the three repository variables from the README.

## 3. Design decisions

| Decision | Why |
|---|---|
| Two jobs, `publish` needs `scan` | a vulnerable image never reaches ECR |
| Scan amd64 only | Trivy reads the local Docker, which can hold one platform |
| `github.ref_protected` instead of `github.ref == 'refs/heads/main'` | it is what the task asks: any branch with protection, not a hard-coded name |
| OIDC instead of access keys | nothing to leak or rotate |
| Trust policy `sub` = `repo:OWNER@ID/REPO@ID:ref:refs/heads/main` | a PR or another repo cannot assume the role; the IDs mean a deleted and re-created repo with the same name cannot either |
| Push policy limited to one repository | least privilege |
| Tag = commit SHA, sign the digest | the signature is bound to exact content, not a movable tag |
| Keyless Cosign | no signing key to store; the certificate names this workflow |

## 4. What broke in the first real run

The role could not be assumed (`Not authorized to perform
sts:AssumeRoleWithWebIdentity`). The trust policy expected
`repo:johnvega-cloud/github-actions-image-pipeline:ref:refs/heads/main`, but
this repo sends the immutable subject, which includes the owner and repo IDs.
Read the real value with the `gh api .../oidc/customization/sub` call above
instead of guessing it.

## 5. Cleanup

```bash
aws ecr delete-repository --repository-name hello --region "$REGION" --force
aws iam delete-role-policy --role-name "$ROLE" --policy-name ecr-push
aws iam delete-role --role-name "$ROLE"
# The GitHub OIDC provider is shared by the account: do not delete it.
```
