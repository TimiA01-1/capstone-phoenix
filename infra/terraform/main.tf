module "network" {
  source       = "./modules/network"
  project_name = var.project_name
  region       = var.region
}

module "security_group" {
  source       = "./modules/security_group"
  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  my_ip        = var.my_ip
}

module "compute" {
  source             = "./modules/compute"
  project_name       = var.project_name
  instance_type      = var.instance_type
  subnet_id          = module.network.subnet_id
  security_group_id  = module.security_group.security_group_id
  public_key_path    = var.public_key_path
  worker_count       = var.worker_count
}
