# Najświeższy Ubuntu 24.04 LTS dla architektury x86_64.
# AMI ma inny identyfikator w każdym regionie, więc wpisanie go na sztywno
# zepsułoby konfigurację przy zmianie `var.region`.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Klucz SSH generowany lokalnie i zapisywany na dysk.
# Klucz prywatny NIE trafia do repozytorium — pilnuje tego .gitignore.
resource "tls_private_key" "dostep" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "dostep" {
  key_name   = "${var.nazwa}-klucz"
  public_key = tls_private_key.dostep.public_key_openssh
}

resource "local_sensitive_file" "klucz_prywatny" {
  content         = tls_private_key.dostep.private_key_openssh
  filename        = "${path.module}/klucz-ssh"
  file_permission = "0600"
}

resource "aws_instance" "wezel" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.typ_instancji

  subnet_id              = aws_subnet.publiczna.id
  vpc_security_group_ids = [aws_security_group.wezel.id]
  key_name               = aws_key_pair.dostep.key_name

  user_data                   = file("${path.module}/cloud-init/k3s.sh")
  user_data_replace_on_change = true

  # NAJWAZNIEJSZA linia kosztowa w calym repo.
  #
  # Instancje z rodziny t3 startuja domyslnie w trybie "unlimited": gdy procesor
  # pracuje dluzej powyzej progu bazowego, AWS DOLICZA oplate za nadmiarowe
  # kredyty — poza darmowym pulapem, po cichu. Wezel k3s potrafi tak obciazyc
  # procesor przy starcie i przy budowaniu obrazow.
  #
  # "standard" znaczy: przy braku kredytow instancja ZWALNIA zamiast naliczac.
  # Wolniejsze demo jest lepsze niz niespodzianka na rachunku.
  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_size = var.dysk_gb
    volume_type = "gp3"
    encrypted   = true
  }

  # IMDSv2 wymuszone: wersja pierwsza pozwalała pobrać poświadczenia roli
  # przez zwykłe zapytanie HTTP z wnętrza instancji, co bywało wektorem SSRF.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "${var.nazwa}-k3s" }
}
