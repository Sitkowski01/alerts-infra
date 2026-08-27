#!/bin/bash
# Bootstrap węzła k3s.
#
# k3s zamiast EKS-a świadomie: EKS kosztuje ok. 73 USD/mies. za sam działający
# control plane, nawet przy zerze podów. k3s to pełny, certyfikowany Kubernetes
# w jednym procesie i mieści się na instancji z darmowego pułapu.
set -euo pipefail

exec > >(tee /var/log/bootstrap-k3s.log) 2>&1
echo "[$(date -Is)] start"

apt-get update -y
apt-get install -y curl ca-certificates

# --tls-san z publicznym IP: bez tego certyfikat serwera API nie obejmuje
# adresu zewnętrznego i kubectl z laptopa odrzuca połączenie.
PUBLICZNY_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $(curl -sf -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/public-ipv4)
echo "[$(date -Is)] publiczny adres: ${PUBLICZNY_IP}"

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san ${PUBLICZNY_IP} --write-kubeconfig-mode 644" sh -

# Czekamy, aż węzeł faktycznie zgłosi gotowość — inaczej pierwszy `kubectl apply`
# po stronie użytkownika trafiłby w niedziałające API.
for _ in $(seq 1 60); do
  if k3s kubectl get nodes 2>/dev/null | grep -q " Ready "; then
    echo "[$(date -Is)] wezel gotowy"
    break
  fi
  sleep 5
done

# Kubeconfig z podmienionym adresem — gotowy do pobrania na laptopa.
sed "s/127.0.0.1/${PUBLICZNY_IP}/" /etc/rancher/k3s/k3s.yaml > /home/ubuntu/kubeconfig
chown ubuntu:ubuntu /home/ubuntu/kubeconfig
chmod 600 /home/ubuntu/kubeconfig

k3s kubectl get nodes -o wide
echo "[$(date -Is)] gotowe"
