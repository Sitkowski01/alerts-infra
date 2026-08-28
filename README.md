# alerts-infra

[![CI](https://github.com/Sitkowski01/alerts-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/Sitkowski01/alerts-infra/actions/workflows/ci.yml)

Infrastruktura jako kod dla [price-alerts-api](https://github.com/Sitkowski01/price-alerts-api):
**Terraform** stawia na AWS jednowęzłowy klaster **k3s** na EC2, na który wchodzą
gotowe manifesty Kubernetesa z tamtego repozytorium.

## Co powstaje

```
VPC 10.20.0.0/16
 └── podsieć publiczna 10.20.1.0/24
      └── EC2 t3.small (Ubuntu 24.04)
           └── k3s — jednowęzłowy Kubernetes
                └── Traefik (Ingress w komplecie z k3s)
brama internetowa · tablica routingu · grupa zabezpieczeń
budżet z alarmem mailowym
```

Grupa zabezpieczeń wpuszcza **wyłącznie mój adres IP** na porty 22 (SSH),
6443 (API Kubernetesa) i 80 (Ingress). Zmienna `moj_ip` ma walidację wymuszającą
maskę `/32`, więc wpisanie `0.0.0.0/0` nie przechodzi przez `terraform plan`.

Klucz SSH powstaje lokalnie (ED25519) przy `apply`. Ani on, ani stan Terraforma,
ani kubeconfig nie mają prawa trafić do repozytorium — pilnuje tego
`terraform/.gitignore`.

## Uruchomione na AWS

Ta konfiguracja **stała na AWS** 28.08.2026 w regionie `eu-central-1`.
Poniżej stan z działającego węzła, nie plan.

```
$ kubectl get nodes -o wide
NAME             STATUS   ROLES           VERSION        OS-IMAGE
ip-10-20-1-253   Ready    control-plane   v1.36.3+k3s1   Ubuntu 24.04.4 LTS

$ kubectl -n price-alerts get pods
postgres-768dbdbb88-szhvr          1/1   Running     0   3m56s
price-alerts-api-b67b8f585-4nq86   1/1   Running     0   48s
price-alerts-api-b67b8f585-c5qtt   1/1   Running     0   48s
price-alerts-migrate-p4zgr         0/1   Completed   0   61s
```

![Klaster k3s na EC2 z wdrożonym price-alerts-api](docs/wdrozenie-aws.png)

Wersja jądra `6.17.0-1019-aws` i adres wewnętrzny `10.20.1.253` z sieci `10.20.0.0/16`
potwierdzają, że to instancja EC2 z tej konfiguracji, a nie klaster lokalny.

Aplikacja odpowiadała przez `Service`, z wnętrza klastra, na dwóch replikach:
sonda `readyz` z osiągalną bazą, utworzenie alertu `HTTP 201`, zapis bez klucza
odrzucony `HTTP 401`, notowanie poniżej progu bez efektu, notowanie powyżej progu
uruchamiające alert.

Zaraz po zrzutach poszło `terraform destroy` — tamten adres już nie odpowiada.

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

### Koszt

Instancja z dyskiem to ok. **0,02 USD/h** i jedyna płatna pozycja — `t3.small`
nie mieści się w darmowym pułapie EC2, który obejmuje wyłącznie `t3.micro`.
Dwie godziny demo i `terraform destroy` zamykają się w kilku centach.

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

Potem **Cost Explorer** z filtrem po tagu `Projekt = price-alerts` — wszystkie zasoby
są tagowane przez `default_tags`, więc cokolwiek zostało, będzie widać.

## Decyzje projektowe

- **k3s zamiast EKS.** k3s jest certyfikowanym Kubernetesem, więc manifesty, sondy
  i `kubectl` są identyczne — to, co działa tutaj, pojedzie na EKS bez zmian.
  Oddaję za to zarządzany control plane: wysoką dostępność, automatyczne aktualizacje
  i integrację z IAM. Przy jednym węźle demonstracyjnym nie skorzystałbym z żadnej
  z tych rzeczy, a EKS liczy ok. 73 USD/mies. za sam fakt istnienia klastra.
- **Węzeł w podsieci publicznej, bez bramy NAT i load balancera.** Instancja ma
  publiczny adres i wychodzi do internetu przez bramę internetową, więc brama NAT
  nie miałaby czego obsługiwać. Ruch przychodzący kończy na Ingressie k3s, więc
  load balancer też odpada. **Na produkcji ta decyzja byłaby odwrotna** — węzeł
  trafiłby do podsieci prywatnej za NAT, a ruch wchodziłby przez ALB.
- **Tryb kredytów procesora na `standard`** (`compute.tf`). t3 to instancje
  burstowalne: powyżej progu bazowego procesor jedzie z kredytów. W domyślnym trybie
  `unlimited` zużycie ponad pulę jest doliczane do rachunku, w `standard` instancja
  po prostu zwalnia. Wybrałem zwalnianie — i ta sama decyzja wydłużyła start k3s
  na `t3.micro` na tyle, że węzeł w ogóle nie wstawał. Opisuję to niżej.
- **Alarm budżetowy powstaje w tym samym `apply` co reszta** (`budget.tf`).
  Zabezpieczenie dokładane po fakcie to zabezpieczenie, którego nie ma. Mail przy
  50% progu, przy 100% i przy prognozie przekroczenia.
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

## Czego nauczyło mnie to uruchomienie

**`t3.micro` nie udźwignie k3s.** Pierwsze podejście stanęło właśnie na tym:

```
Mem:  911 total, 856 used, 54 available    <- pamiec wyczerpana
load average: 9.03                          <- wezel sie dusi
k3s: active od 33 min, zjadl 21 min CPU     <- start nigdy sie nie konczyl
```

Sam serwer k3s zajmował 553 MB przy gigabajcie pamięci, a API na porcie 6443
zwracało `TLS handshake timeout` nawet po pół godzinie. Dokłada się do tego tryb
kredytów `standard`, który dławi procesor dokładnie wtedy, gdy k3s najbardziej go
potrzebuje — przy starcie. Dopiero `t3.small` z 2 GB doprowadził węzeł do `Ready`.
Cały powód siedzi w opisie zmiennej `typ_instancji`, żeby nikt nie cofnął tego
„dla oszczędności".

**AWS odrzuca myślnik pauzę i polskie znaki w opisach reguł grupy zabezpieczeń.**
`terraform validate` tego nie widzi, bo składniowo wszystko jest poprawne — błąd
wychodzi dopiero przy `apply`, gdy część zasobów już powstała. Opisy są teraz
czystym ASCII, z komentarzem ostrzegawczym.

## Czego tu jeszcze nie ma

To jest infrastruktura **demonstracyjna**, nie produkcyjna.

- **Stan Terraforma leży lokalnie.** Na produkcji idzie do S3 z blokadą w DynamoDB,
  żeby dwie osoby nie zaaplikowały naraz.
- **Jeden węzeł** — brak wysokiej dostępności. Padnie instancja, padnie klaster.
- **Baza działa w klastrze** na `emptyDir`. Na produkcji to RDS, nie pod.
- **Brak HTTPS** — Ingress wystawia port 80 wyłącznie na mój adres IP.
  Z prawdziwą domeną doszedłby cert-manager i Let's Encrypt.
