locals {
  cluster_version        = "1.27"
  cluster_name           = "gh-eks-cluster"
  base_domain            = "is-sandbox.camptocamp.com"
  cluster_issuer         = "letsencrypt-staging"
  enable_service_monitor = false # Can be enabled after the first bootstrap
  app_autosync           = true ? { allow_empty = false, prune = true, self_heal = true } : {}

  vpc_cidr            = "10.56.0.0/16"
  vpc_private_subnets = ["10.56.1.0/24", "10.56.2.0/24", "10.56.3.0/24"]
  vpc_public_subnets  = ["10.56.4.0/24", "10.56.5.0/24", "10.56.6.0/24"]
}
