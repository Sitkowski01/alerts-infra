output "publiczny_ip" {
  description = "Adres węzła k3s."
  value       = aws_instance.wezel.public_ip
}

output "polecenie_ssh" {
  description = "Gotowe polecenie do zalogowania się na węzeł."
  value       = "ssh -i terraform/klucz-ssh ubuntu@${aws_instance.wezel.public_ip}"
}

output "pobierz_kubeconfig" {
  description = "Ściąga kubeconfig z węzła i ustawia go dla kubectl."
  value = join(" ", [
    "scp -i terraform/klucz-ssh",
    "ubuntu@${aws_instance.wezel.public_ip}:/home/ubuntu/kubeconfig",
    "./kubeconfig && export KUBECONFIG=$PWD/kubeconfig"
  ])
}

output "log_bootstrapu" {
  description = "Podgląd instalacji k3s — przydaje się, gdy węzeł nie wstaje."
  value       = "ssh -i terraform/klucz-ssh ubuntu@${aws_instance.wezel.public_ip} sudo tail -f /var/log/bootstrap-k3s.log"
}

output "przypomnienie_o_kosztach" {
  description = "Najważniejsza komenda w całym repozytorium."
  value       = "Skończyłeś? -> terraform destroy"
}
