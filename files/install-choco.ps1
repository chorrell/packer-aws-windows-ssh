$ErrorActionPreference = 'Stop'

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iwr https://community.chocolatey.org/install.ps1 -UseBasicParsing | iex

# Globally Auto confirm every action
# See: https://docs.chocolatey.org/en-us/faqs#why-do-i-have-to-confirm-packages-now-is-there-a-way-to-remove-this
choco feature enable -n allowGlobalConfirmation