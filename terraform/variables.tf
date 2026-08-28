variable "nazwa" {
  description = "Prefiks nazw wszystkich zasobów."
  type        = string
  default     = "price-alerts"
}

variable "region" {
  description = "Region AWS. eu-central-1 (Frankfurt) jest najbliżej Polski."
  type        = string
  default     = "eu-central-1"
}

variable "typ_instancji" {
  description = <<-OPIS
    Typ instancji EC2.

    t3.small, a NIE t3.micro — sprawdzone na żywym węźle 27.08.2026.
    Na t3.micro (1 GB RAM) sam serwer k3s zajmował 553 MB, pamięć schodziła
    do 54 MB wolnego, obciążenie skakało do 9, a start nigdy się nie kończył:
    API na porcie 6443 zwracało "TLS handshake timeout" nawet po 30 minutach.
    Dokłada się do tego tryb kredytów "standard", który dławi procesor
    dokładnie wtedy, gdy k3s najbardziej go potrzebuje — przy starcie.

    t3.small ma 2 GB RAM i dwa razy wyższy pułap bazowy procesora.
    Kosztuje ok. 0,022 USD/h, czyli jakieś 4 centy za dwie godziny demo.
    Uwaga: t3.small NIE jest objęty darmowym pułapem EC2 — pułap obejmuje
    wyłącznie t3.micro. To jedyna płatna pozycja w całej konfiguracji.
  OPIS
  type        = string
  default     = "t3.small"
}

variable "moj_ip" {
  description = <<-OPIS
    Twój publiczny adres IP z maską /32 — stąd i tylko stąd wolno się łączyć
    po SSH i do panelu.

    Sprawdzisz go poleceniem: curl -s https://checkip.amazonaws.com
    Wpisanie 0.0.0.0/0 otwiera port 22 na cały internet. Nie rób tego.
  OPIS
  type        = string

  validation {
    condition     = can(cidrhost(var.moj_ip, 0)) && endswith(var.moj_ip, "/32")
    error_message = "Podaj pojedynczy adres z maską /32, na przykład 83.20.11.7/32."
  }
}

variable "email_budzetu" {
  description = "Adres, na który przyjdzie ostrzeżenie o kosztach."
  type        = string

  validation {
    condition     = strcontains(var.email_budzetu, "@") && strcontains(var.email_budzetu, ".")
    error_message = "To nie wygląda na adres e-mail."
  }
}

variable "limit_budzetu_usd" {
  description = "Miesięczny próg alarmu kosztowego w dolarach."
  type        = number
  default     = 5

  validation {
    condition     = var.limit_budzetu_usd > 0 && var.limit_budzetu_usd <= 100
    error_message = "Próg powinien być dodatni i nie większy niż 100 USD — to demo, nie produkcja."
  }
}

variable "dysk_gb" {
  description = "Rozmiar dysku. Darmowy pułap to 30 GB łącznie."
  type        = number
  default     = 12
}
