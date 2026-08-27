# Własna, minimalna sieć. Domyślne VPC też by zadziałało, ale wtedy
# nie widać w kodzie, co dokładnie jest wystawione na świat.
#
# Świadomie NIE MA tu bramy NAT: kosztuje ok. 32 USD/mies. plus transfer,
# a instancja stoi w podsieci publicznej i wychodzi do internetu
# przez bramę internetową, która jest darmowa.

resource "aws_vpc" "glowna" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.nazwa}-vpc" }
}

resource "aws_internet_gateway" "brama" {
  vpc_id = aws_vpc.glowna.id
  tags   = { Name = "${var.nazwa}-igw" }
}

# Strefa dostępności brana z regionu, a nie wpisana na sztywno —
# nie każdy region ma te same litery stref.
data "aws_availability_zones" "dostepne" {
  state = "available"
}

resource "aws_subnet" "publiczna" {
  vpc_id                  = aws_vpc.glowna.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.dostepne.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.nazwa}-publiczna" }
}

resource "aws_route_table" "publiczna" {
  vpc_id = aws_vpc.glowna.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.brama.id
  }

  tags = { Name = "${var.nazwa}-rt" }
}

resource "aws_route_table_association" "publiczna" {
  subnet_id      = aws_subnet.publiczna.id
  route_table_id = aws_route_table.publiczna.id
}

resource "aws_security_group" "wezel" {
  name        = "${var.nazwa}-wezel"
  description = "Dostep do wezla k3s"
  vpc_id      = aws_vpc.glowna.id

  tags = { Name = "${var.nazwa}-sg" }
}

# Reguły jako osobne zasoby, nie bloki inline — inaczej Terraform
# przy każdej zmianie odtwarzałby całą grupę zabezpieczeń.

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.wezel.id
  description       = "SSH wylacznie z mojego adresu"
  cidr_ipv4         = var.moj_ip
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "api_kubernetes" {
  security_group_id = aws_security_group.wezel.id
  description       = "API Kubernetesa dla kubectl z mojej maszyny"
  cidr_ipv4         = var.moj_ip
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.wezel.id
  description       = "Ingress k3s (Traefik) — tylko z mojego adresu"
  cidr_ipv4         = var.moj_ip
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Ruch wychodzący jest potrzebny: instancja musi pobrać k3s i obrazy.
resource "aws_vpc_security_group_egress_rule" "wszystko" {
  security_group_id = aws_security_group.wezel.id
  description       = "Pobieranie k3s i obrazow"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
