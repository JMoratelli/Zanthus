
**Diretório utilizado para criação de scripts de automação da instalação de algumas funcionalidades.**

**-------------------------------------------------------------------------------------------------------------------**

Novo menu de Instalação do Script, agora tendo sido incluído vários métodos de instalação
```bash
curl -s https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/MenuInstalacao.sh | bash
```
**-------------------------------------------------------------------------------------------------------------------**

Script para terminais Windows, execute no powershell.
```
Set-ExecutionPolicy Bypass -Scope Process -Force; irm "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Windows/PostInstallPDV.ps1" | iex
```

**-------------------------------------------------------------------------------------------------------------------**

## Licença

Copyright (C) 2026 Jurandir Moratelli

Este programa é software livre: você pode redistribuí-lo e/ou modificá-lo
sob os termos da GNU General Public License, conforme publicada pela Free
Software Foundation, na versão 3 da licença.

Este programa é distribuído na esperança de que seja útil, mas SEM QUALQUER
GARANTIA, nem mesmo a garantia implícita de COMERCIALIZAÇÃO ou ADEQUAÇÃO A UM
PROPÓSITO ESPECÍFICO. Veja a GNU General Public License para mais detalhes.

O texto completo da licença está em [LICENSE](LICENSE).
