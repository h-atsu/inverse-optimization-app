# GCP infrastructure

単一のGoogle Cloud project `inverse-optimization-app`を管理するTerraform root moduleです。環境別directoryやmoduleは、必要になるまで追加しません。

現時点では次だけを管理します。

- Google providerと既定region `asia-northeast1`
- Cloud Run、Cloud Tasks、Artifact Registry、Secret Manager、IAMで使用するAPI
- application共通label

Cloud Run、service account、Artifact Registry等のresource本体は後続stepで追加します。Terraform stateは当面localに保存し、GitHub Actionsを導入する前にremote backendへの移行を検討します。state fileと`.terraform/`はrepository rootの`.gitignore`で除外しています。

## Bootstrap

Terraformはグローバルにインストール済みであることを前提にします。local認証にはApplication Default Credentialsを使用します。

```bash
gcloud config set project inverse-optimization-app
gcloud auth application-default login
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=inverse-optimization-app
```

最初の2 APIは、Terraformが残りのAPIを管理するためのbootstrapとして先に有効化します。Terraform側にも定義しているため、以後は構成との差分を確認できます。

## Terraform

repository rootから実行します。

```bash
terraform -chdir=infra init
terraform -chdir=infra fmt -check
terraform -chdir=infra validate
terraform -chdir=infra plan
```

`plan`を確認し、意図したAPIの有効化だけであることを確認してから適用します。

```bash
terraform -chdir=infra apply
```

`.terraform.lock.hcl`はprovider versionを再現するためGitへcommitします。`terraform.tfstate`はcommitしません。
