
**Diretório utilizado para criação de scripts de automação da instalação de algumas funcionalidades.**

**-------------------------------------------------------------------------------------------------------------------**

Novo menu de Instalação do Script, agora tendo sido incluído vários métodos de instalação
```bash
curl -s https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/MenuInstalacao.sh | bash
```
**-------------------------------------------------------------------------------------------------------------------**

Scrip para terminais Windows, execute no powershell.
```
ipconfig /flushdns; del "PostInstallWindows.bat" -ErrorAction SilentlyContinue; iwr -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/main/InstalaPDV/PostInstallWindows.bat?v=$([guid]::NewGuid())" -OutFile "PostInstallWindows.bat" -Headers @{'If-Modified-Since'='Sat, 1 Jan 2000 00:00:00 GMT'}; Start-Process "PostInstallWindows.bat" -Verb RunAs```
