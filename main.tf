terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "mysqlaulatf" {
  name = "mysqlaulatf"
  location = "eastus"

  tags = {
    "Organization" = "Impacta"
    "Class" = "Infrastructure_and_Cloud_Computing"
  }
}

resource "azurerm_virtual_network" "vnmysqlaulatf" {
  name = "vnmysqlaulatf"
  address_space = ["10.0.0.0/16"]
  location = "eastus"
  resource_group_name = azurerm_resource_group.mysqlaulatf.name
}

resource "azurerm_subnet" "subnetmysqlaulatf" {
  name = "subnetmysqlaulatf"
  resource_group_name = azurerm_resource_group.mysqlaulatf.name
  virtual_network_name = azurerm_virtual_network.vnmysqlaulatf.name
  address_prefixes = [ "10.0.1.0/24" ]
}

resource "azurerm_public_ip" "pimysqlaulatf" {
  name = "pimysqlaulatf"
  location = "eastus"
  resource_group_name = azurerm_resource_group.mysqlaulatf.name
  allocation_method = "Static"
}

resource "azurerm_network_security_group" "ngsmysqlaulatf" {
  name = "ngsmysqlaulatf"
  location = "eastus"
  resource_group_name = azurerm_resource_group.mysqlaulatf.name

  security_rule {
      name                       = "mysql"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3306"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "nicmysqlaulatf" {
    name                      = "nicmysqlaulatf"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.mysqlaulatf.name

    ip_configuration {
        name                          = "niccmysqlaulatf"
        subnet_id                     = azurerm_subnet.subnetmysqlaulatf.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.pimysqlaulatf.id
    }
}

resource "azurerm_network_interface_security_group_association" "isgpmysqlaulatf" {
    network_interface_id      = azurerm_network_interface.nicmysqlaulatf.id
    network_security_group_id = azurerm_network_security_group.ngsmysqlaulatf.id
}

data "azurerm_public_ip" "ip_mysql_aula_tf_data_db" {
  name                = azurerm_public_ip.pimysqlaulatf.name
  resource_group_name = azurerm_resource_group.mysqlaulatf.name
}

resource "azurerm_storage_account" "samysqlaulatf" {
    name                        = "samysqlaulatf"
    resource_group_name         = azurerm_resource_group.mysqlaulatf.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

resource "azurerm_linux_virtual_machine" "vmmysqlaulatf" {
    name                  = "vmmysqlaulatf"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.mysqlaulatf.name
    network_interface_ids = [azurerm_network_interface.nicmysqlaulatf.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "vmMySqlAulaFfOsDiskMySQL"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "vmmysqlaulatf"
    admin_username = var.user
    admin_password = var.password
    disable_password_authentication = false

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.samysqlaulatf.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.mysqlaulatf ]
}

output "public_ip_address_mysql" {
    value = azurerm_public_ip.pimysqlaulatf.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.vmmysqlaulatf]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_mysql_aula_tf_data_db.ip_address
        }
        source = "config"
        destination = "/home/azureuser"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_mysql_aula_tf_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/azureuser/config/user.sql",
            "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}