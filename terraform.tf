terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "camptocamp-aws-is-sandbox-terraform-state"
    key            = "813c4849-73ac-48a6-b3bd-dbbc1577145a"
    region         = "eu-west-1"
    dynamodb_table = "camptocamp-aws-is-sandbox-terraform-statelock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5, != 5.71.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7"
    }
    dmsnitch = {
      source  = "plukevdh/dmsnitch"
      version = "0.1.5"
    }
  }
}

# The providers configurations below depend on the output of some of the modules declared on other *tf files.
# However, for clarity and ease of maintenance we grouped them all together in this section.

provider "kubernetes" {
  host                   = module.eks.kubernetes_host
  cluster_ca_certificate = module.eks.kubernetes_cluster_ca_certificate
  token                  = module.eks.kubernetes_token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.kubernetes_host
    cluster_ca_certificate = module.eks.kubernetes_cluster_ca_certificate
    token                  = module.eks.kubernetes_token
  }
}

provider "argocd" {
  auth_token                  = module.argocd_bootstrap.argocd_auth_token
  port_forward_with_namespace = module.argocd_bootstrap.argocd_namespace
  insecure                    = true
  plain_text                  = true

  kubernetes {
    host                   = module.eks.kubernetes_host
    cluster_ca_certificate = module.eks.kubernetes_cluster_ca_certificate
    token                  = module.eks.kubernetes_token
  }
}
