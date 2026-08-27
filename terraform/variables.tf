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

    t3.micro mieści się w darmowym pułapie (750 h/mies. przez pierwsze
    12 miesięcy konta). Poza tym okresem kosztuje ok. 8 USD/mies.,
    więc instancję wyłącza się po zrobieniu zrzutów.
  OPIS
  type        = string
  default     = "t3.micro"
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
