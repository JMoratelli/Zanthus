
**Diretório utilizado para criação de scripts de automação da instalação de algumas funcionalidades.**

**-------------------------------------------------------------------------------------------------------------------**

Novo menu de Instalação do Script, agora tendo sido incluído vários métodos de instalação
```bash
curl -s https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/MenuInstalacao.sh | bash
```
**-------------------------------------------------------------------------------------------------------------------**

Scrip para terminais Windows, execute no powershell.
```
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallPDV.ps1" | iex
```
