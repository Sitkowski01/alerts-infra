# alerts-infra

[![CI](https://github.com/Sitkowski01/alerts-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/Sitkowski01/alerts-infra/actions/workflows/ci.yml)

Infrastruktura jako kod dla [price-alerts-api](https://github.com/Sitkowski01/price-alerts-api):
**Terraform** stawia na AWS jednowęzłowy klaster **k3s** na EC2, na który wdrażasz
gotowe manifesty Kubernetesa.

## 🔴 Zanim cokolwiek odpalisz — o kosztach

To jest repozytorium, które **wydaje Twoje pieniądze**. Trzy rzeczy, zanim ruszysz:

1. **`terraform destroy`, gdy skończysz.** Największe ryzyko przy nauce AWS to nie
   jedna instancja, tylko instancja zapomniana na trzy tygodnie.
2. **Alarm budżetowy zakłada się razem z infrastrukturą** (`budget.tf`), a nie „kiedyś
   potem". Ostrzeżenie idzie mailem przy 50% i 100% progu oraz przy prognozie
   przekroczenia. Domyślny próg to 5 USD.
3. **Świadomie nie ma tu EKS-a.** Zarządzany control plane kosztuje ok. **73 USD/mies.
   nawet przy zerze podów**. k3s to pełny, certyfikowany Kubernetes w jednym procesie
   i mieści się na instancji z darmowego pułapu.

Czego jeszcze tu nie ma, żeby nie generować rachunku: **bramy NAT** (ok. 32 USD/mies.
plus transfer — instancja stoi w podsieci publicznej), **load balancera** (ruch wchodzi
przez Ingress k3s), **Elastic IP** trzymanego bez instancji.

Przy koncie w darmowym pułapie (pierwsze 12 miesięcy) `t3.micro` mieści się
w 750 h/mies., a 12 GB dysku w limicie 30 GB. Poza tym okresem to ok. **8 USD/mies.**
za samą instancję — czyli tyle, ile trwa demo, jeśli je wyłączysz.

## Co powstaje

```
VPC 10.20.0.0/16
 └── podsieć publiczna 10.20.1.0/24
      └── EC2 t3.micro (Ubuntu 24.04)
           └── k3s — jednowęzłowy Kubernetes
                └── Traefik (Ingress w komplecie z k3s)
brama internetowa · tablica routingu · grupa zabezpieczeń
budżet z alarmem mailowym
```

Grupa zabezpieczeń wpuszcza **wyłącznie Twój adres IP** na porty 22 (SSH),
6443 (API Kubernetesa) i 80 (Ingress). Zmienna `moj_ip` ma walidację wymuszającą
maskę `/32` — wpisanie `0.0.0.0/0` nie przejdzie.

Klucz SSH jest generowany lokalnie (ED25519) i zapisywany na dysk;
`.gitignore` pilnuje, żeby ani on, ani stan Terraforma, ani kubeconfig
nie trafiły do repozytorium.

## Uruchomienie

Potrzebne: konto AWS, `aws` CLI z poświadczeniami (`aws configure`) i `terraform`.

```bash
cd terraform
cp przyklad.tfvars terraform.tfvars

# Wpisz swój adres IP i e-mail do alarmu budżetowego
curl -s https://checkip.amazonaws.com     # to jest Twój moj_ip, dopisz /32

terraform init
terraform plan      # przeczytaj, co powstanie, ZANIM zatwierdzisz
terraform apply
```

Po kilku minutach:

```bash
# Kubeconfig prosto z węzła
scp -i terraform/klucz-ssh ubuntu@$(terraform -chdir=terraform output -raw publiczny_ip):/home/ubuntu/kubeconfig ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig

kubectl get nodes -o wide
```

Gdyby węzeł nie wstawał, cały przebieg instalacji k3s jest w logu:

```bash
ssh -i terraform/klucz-ssh ubuntu@<ip> sudo tail -f /var/log/bootstrap-k3s.log
```

### Wdrożenie aplikacji

Manifesty leżą w [price-alerts-api](https://github.com/Sitkowski01/price-alerts-api/tree/main/k8s):

```bash
kubectl apply -f ../price-alerts-api/k8s/00-namespace.yaml
kubectl -n price-alerts create secret generic price-alerts-secret \
  --from-literal=DATABASE_URL="postgresql+asyncpg://postgres:postgres@postgres:5432/price_alerts" \
  --from-literal=API_KEY="..."
kubectl apply -f ../price-alerts-api/k8s/dev/postgres.yaml
kubectl -n price-alerts wait --for=condition=available deployment/postgres --timeout=180s
kubectl apply -f ../price-alerts-api/k8s/10-configmap.yaml -f ../price-alerts-api/k8s/20-migrate-job.yaml
kubectl -n price-alerts wait --for=condition=complete job/price-alerts-migrate --timeout=180s
kubectl apply -f ../price-alerts-api/k8s/30-deployment.yaml -f ../price-alerts-api/k8s/40-service.yaml
```

### Sprzątanie

```bash
terraform destroy
```

Sprawdź potem w **Cost Explorerze**, filtrując po tagu `Projekt = price-alerts`,
czy na pewno nic nie zostało. Wszystkie zasoby są otagowane przez `default_tags`.

## Decyzje, o które warto zapytać

- **k3s zamiast EKS** — powód kosztowy opisany wyżej. To nadal certyfikowany
  Kubernetes: te same manifesty, te same sondy, ten sam `kubectl`.
- **Reguły grupy zabezpieczeń jako osobne zasoby**, nie bloki `inline`. Przy blokach
  inline Terraform odtwarza całą grupę przy każdej zmianie jednej reguły.
- **IMDSv2 wymuszone** (`http_tokens = "required"`). Pierwsza wersja usługi metadanych
  pozwalała pobrać poświadczenia roli zwykłym zapytaniem HTTP z wnętrza instancji,
  co bywało wektorem ataku SSRF.
- **AMI z `data source`, nie wpisane na sztywno.** Identyfikator obrazu jest inny
  w każdym regionie — wpisany na stałe zepsułby konfigurację przy zmianie `region`.
- **`--tls-san` z publicznym adresem** przy instalacji k3s. Bez tego certyfikat
  serwera API nie obejmuje adresu zewnętrznego i `kubectl` z laptopa odrzuca połączenie.
- **Dysk szyfrowany** (`encrypted = true`) — nic nie kosztuje, a jest domyślnym
  wymogiem w większości audytów.
- **Bootstrap czeka, aż węzeł zgłosi gotowość**, zamiast kończyć się od razu.
  Inaczej pierwszy `kubectl apply` trafiałby w niedziałające API.

## Czego tu jeszcze nie ma

Uczciwie: to jest infrastruktura **demonstracyjna**, nie produkcyjna.

- **Stan Terraforma leży lokalnie.** Na produkcji idzie do S3 z blokadą w DynamoDB,
  żeby dwie osoby nie zaaplikowały naraz.
- **Jeden węzeł** — brak wysokiej dostępności. Padnie instancja, padnie klaster.
- **Baza działa w klastrze** na `emptyDir`. Na produkcji to RDS, nie pod.
- **Brak HTTPS** — Ingress wystawia port 80 wyłącznie na Twój adres IP.
  Z prawdziwą domeną doszedłby cert-manager i Let's Encrypt.
