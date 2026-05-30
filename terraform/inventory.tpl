[master]
${master_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[worker]
${worker_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[all:vars]
master_ip=${master_ip}
worker_ip=${worker_ip}
# Private IPs for intra-cluster communication (public IPs route via IGW, breaking the self SG rule)
master_private_ip=${master_private_ip}
worker_private_ip=${worker_private_ip}
