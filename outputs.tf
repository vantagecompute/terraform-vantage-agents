output "installed_components" {
  description = "The components this module installed or kept in place."
  value = concat(
    ["slurm-accounts-reconciler"],
    var.install_vref_agent ? ["vref-agent"] : [],
    var.install_presence_agent ? ["cluster-presence-agent"] : [],
  )
}
