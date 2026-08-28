# Skopiuj do terraform.tfvars i uzupełnij własnymi wartościami.
#
# Swój adres IP sprawdzisz poleceniem:
#   curl -s https://checkip.amazonaws.com

moj_ip        = "1.2.3.4/32"
email_budzetu = "twoj@email.pl"

# Opcjonalnie:
# region            = "eu-central-1"
# typ_instancji     = "t3.small"   # mniejsza nie udzwignie k3s — patrz variables.tf
# limit_budzetu_usd = 5
