data "aws_availability_zones" "available" {}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "~> 5.0"
  name                 = module.eks.cluster_name
  cidr                 = local.vpc_cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = local.private_subnets
  public_subnets       = local.public_subnets
  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${module.eks.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                  = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${module.eks.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                           = "1"
  }
}

module "eks" {
  source = "git::https://github.com/camptocamp/devops-stack-module-cluster-eks.git?ref=v3.0.0"
  # source = "../../devops-stack-module-cluster-eks"

  cluster_name       = local.cluster_name
  kubernetes_version = local.kubernetes_version
  base_domain        = local.base_domain

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  public_subnet_ids  = module.vpc.public_subnets

  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  node_groups = {
    "${module.eks.cluster_name}-main" = {
      instance_types  = ["m5a.xlarge"]
      min_size        = 3
      max_size        = 3
      desired_size    = 3
      nlbs_attachment = true
      block_device_mappings = {
        "default" = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
          }
        }
      }
    },
    # "${module.eks.cluster_name}-monit" = {
    #   instance_types     = ["m5a.large"]
    #   min_size          = 1
    #   max_size          = 2
    #   desired_size      = 1
    #   target_group_arns = module.eks.nlb_target_groups
    #   taints = {
    #     nodegroup = {
    #       key    = "nodegroup"
    #       value  = "monitoring"
    #       effect = "NO_SCHEDULE"
    #     }
    #   }
    # },
  }

  create_public_nlb = true
}

module "oidc" {
  source = "git::https://github.com/camptocamp/devops-stack-module-oidc-aws-cognito.git?ref=v1.0.0"
  # source = "../../devops-stack-module-oidc-aws-cognito"

  cluster_name = module.eks.cluster_name
  base_domain  = module.eks.base_domain

  create_pool = true

  user_map = {
    gheleno = {
      username   = "gheleno"
      email      = "goncalo.heleno@camptocamp.com"
      first_name = "Gonçalo"
      last_name  = "Heleno"
    }
  }
}

module "argocd_bootstrap" {
  source = "git::https://github.com/camptocamp/devops-stack-module-argocd.git//bootstrap?ref=v3.4.0"
  # source = "../../devops-stack-module-argocd/bootstrap"

  depends_on = [module.eks]
}

module "metrics-server" {
  # source = "git::https://github.com/camptocamp/devops-stack-module-metrics-server.git?ref=v1.0.0"
  source = "git::https://github.com/camptocamp/devops-stack-module-metrics-server.git?ref=feat_first_implementation"

  target_revision = "feat_first_implementation"

  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  app_autosync = local.app_autosync

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "traefik" {
  source = "git::https://github.com/camptocamp/devops-stack-module-traefik.git//eks?ref=v3.0.0"
  # source = "../../devops-stack-module-traefik/eks"

  cluster_name     = module.eks.cluster_name
  base_domain      = module.eks.base_domain
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "cert-manager" {
  source = "git::https://github.com/camptocamp/devops-stack-module-cert-manager.git//eks?ref=v5.2.0"
  # source = "../../devops-stack-module-cert-manager/eks"

  cluster_name     = module.eks.cluster_name
  base_domain      = module.eks.base_domain
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor

  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "loki-stack" {
  source = "git::https://github.com/camptocamp/devops-stack-module-loki-stack.git//eks?ref=v5.0.0"
  # source = "../../devops-stack-module-loki-stack/eks"

  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  app_autosync = local.app_autosync

  logs_storage = {
    bucket_id    = aws_s3_bucket.loki_logs_storage.id
    region       = aws_s3_bucket.loki_logs_storage.region
    iam_role_arn = module.iam_assumable_role_loki.iam_role_arn
  }

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
    ebs    = module.ebs.id
  }
}

module "thanos" {
  source = "git::https://github.com/camptocamp/devops-stack-module-thanos.git//eks?ref=v2.5.0"
  # source          = "../../devops-stack-module-thanos/eks"

  # target_revision = "chart-autoupdate-patch-thanos"

  cluster_name     = module.eks.cluster_name
  base_domain      = module.eks.base_domain
  cluster_issuer   = local.cluster_issuer
  argocd_namespace = module.argocd_bootstrap.argocd_namespace

  app_autosync = local.app_autosync

  metrics_storage = {
    bucket_id    = aws_s3_bucket.thanos_metrics_storage.id
    region       = aws_s3_bucket.thanos_metrics_storage.region
    iam_role_arn = module.iam_assumable_role_thanos.iam_role_arn
  }
  thanos = {
    oidc = module.oidc.oidc
  }

  dependency_ids = {
    argocd       = module.argocd_bootstrap.id
    ebs          = module.ebs.id
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    oidc         = module.oidc.id
  }
}

module "kube-prometheus-stack" {
  source = "git::https://github.com/camptocamp/devops-stack-module-kube-prometheus-stack.git//eks?ref=v7.0.0"
  # source = "../../devops-stack-module-kube-prometheus-stack/eks"

  # target_revision = "chart-autoupdate-major-kube-prometheus-stack"

  cluster_name     = module.eks.cluster_name
  argocd_namespace = module.argocd_bootstrap.argocd_namespace
  base_domain      = module.eks.base_domain
  cluster_issuer   = local.cluster_issuer

  app_autosync = local.app_autosync

  metrics_storage = {
    bucket_id    = aws_s3_bucket.thanos_metrics_storage.id
    region       = aws_s3_bucket.thanos_metrics_storage.region
    iam_role_arn = module.iam_assumable_role_thanos.iam_role_arn
  }

  prometheus = {
    oidc = module.oidc.oidc
  }

  alertmanager = {
    oidc = module.oidc.oidc
  }

  grafana = {
    oidc = module.oidc.oidc
  }

  dependency_ids = {
    argocd       = module.argocd_bootstrap.id
    ebs          = module.ebs.id
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    oidc         = module.oidc.id
    thanos       = module.thanos.id
    loki-stack   = module.loki-stack.id
  }
}

module "argocd" {
  source = "git::https://github.com/camptocamp/devops-stack-module-argocd.git?ref=v3.4.0"
  # source = "../../devops-stack-module-argocd"

  # target_revision = "chart-autoupdate-minor-argocd"

  cluster_name   = module.eks.cluster_name
  base_domain    = module.eks.base_domain
  cluster_issuer = local.cluster_issuer

  accounts_pipeline_tokens = module.argocd_bootstrap.argocd_accounts_pipeline_tokens
  server_secretkey         = module.argocd_bootstrap.argocd_server_secretkey

  app_autosync = local.app_autosync

  admin_enabled = false
  exec_enabled  = true

  oidc = {
    name         = "OIDC"
    issuer       = module.oidc.oidc.issuer_url
    clientID     = module.oidc.oidc.client_id
    clientSecret = module.oidc.oidc.client_secret
    requestedIDTokenClaims = {
      groups = {
        essential = true
      }
    }
    requestedScopes = [
      "openid", "profile", "email"
    ]
  }

  rbac = {
    policy_csv = <<-EOT
      g, pipeline, role:admin
      g, devops-stack-admins, role:admin
    EOT
  }

  dependency_ids = {
    argocd                = module.argocd_bootstrap.id
    traefik               = module.traefik.id
    cert-manager          = module.cert-manager.id
    oidc                  = module.oidc.id
    kube-prometheus-stack = module.kube-prometheus-stack.id
  }
}
