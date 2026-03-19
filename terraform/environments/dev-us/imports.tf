###############################################################################
# Dev-US orphaned resource imports
# These resources were created by a previous partial apply but are missing
# from state. Import blocks (Terraform 1.7+) are idempotent – once a resource
# is in state the block becomes a no-op.
###############################################################################

# EFS security group
import {
  to = module.helixbeat.module.efs[0].aws_security_group.efs
  id = "sg-059c1cc93f6b77244"
}

# EFS filesystem
import {
  to = module.helixbeat.module.efs[0].aws_efs_file_system.this
  id = "fs-0b6d556c63e42d356"
}

# EFS access points
import {
  to = module.helixbeat.module.efs[0].aws_efs_access_point.kafka
  id = "fsap-0a40f3bf58ae2f116"
}

import {
  to = module.helixbeat.module.efs[0].aws_efs_access_point.app
  id = "fsap-0cf51272d51d84672"
}

# EFS CSI driver IAM role
import {
  to = module.helixbeat.module.efs[0].aws_iam_role.efs_csi
  id = "helixbeat-dev-us-efs-csi-driver"
}

# EKS node groups
import {
  to = module.helixbeat.module.eks[0].aws_eks_node_group.system
  id = "helixbeat-dev-us:helixbeat-dev-us-system"
}

import {
  to = module.helixbeat.module.eks[0].aws_eks_node_group.app
  id = "helixbeat-dev-us:helixbeat-dev-us-app"
}

# IAM roles (iam module)
import {
  to = module.helixbeat.module.iam[0].aws_iam_role.cluster_autoscaler
  id = "helixbeat-dev-us-cluster-autoscaler"
}

import {
  to = module.helixbeat.module.iam[0].aws_iam_role.aws_lb_controller
  id = "helixbeat-dev-us-aws-lb-controller"
}

import {
  to = module.helixbeat.module.iam[0].aws_iam_role.external_dns
  id = "helixbeat-dev-us-external-dns"
}

import {
  to = module.helixbeat.module.iam[0].aws_iam_role.monitoring
  id = "helixbeat-dev-us-monitoring"
}
