# Alarm kosztowy zakładany RAZEM z infrastrukturą, a nie „kiedyś potem".
#
# Największe ryzyko przy nauce AWS to nie jedna instancja, tylko zapomniana
# instancja. Ten budżet wysyła maila, zanim rachunek zrobi się nieprzyjemny.
resource "aws_budgets_budget" "miesieczny" {
  name         = "${var.nazwa}-budzet"
  budget_type  = "COST"
  limit_amount = tostring(var.limit_budzetu_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Ostrzeżenie przy połowie progu — jest czas zareagować.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.email_budzetu]
  }

  # Alarm przy przekroczeniu progu.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.email_budzetu]
  }

  # Prognoza: ostrzega, zanim koszt faktycznie urośnie.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.email_budzetu]
  }
}
