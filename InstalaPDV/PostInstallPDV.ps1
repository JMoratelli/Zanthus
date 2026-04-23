#Requires -RunAsAdministrator

# --- VERIFICACAO DE PRIVILEGIOS DE ADMINISTRADOR ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Solicitando privilegios de Administrador..." -ForegroundColor Yellow
    # Roda novamente o PowerShell pedindo elevacao (UAC) para este mesmo arquivo
    if ($PSCommandPath) {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        Write-Host "Execute o comando remoto em um terminal PowerShell executado como Administrador." -ForegroundColor Red
        Pause
    }
    exit
}
# ---------------------------------------------------

# --- CONFIGURAÇÕES INICIAIS ---
$caminhoPdv = "C:\Zanthus\Zeus\pdvJava"
$caminhoInterface = "C:\Zanthus\Zeus\Interface"
$caminhoIcones = "$caminhoInterface\resources\icones"
$caminhoImagens = "$caminhoInterface\resources\imagens"

# --- TABELAS DE ESCALABILIDADE (Basta adicionar novas filiais aqui repita para vários gateways) ---
$mapaGateways = @{
    "10.1.1.1"       = 1
    "192.168.11.253" = 3
    "192.168.5.253"  = 9
    "192.168.7.253"  = 53
    "192.168.9.253"  = 52
    "192.168.57.193" = 57
    "192.168.57.1"   = 57
    "192.168.156.1"  = 57
    "192.168.57.129" = 57
    "192.168.58.1"   = 58
}

$configFiliais = @{
    1  = @{ numLoja = "01"; BaseCaixa = 100;  Servidor = "192.168.50.130" }
    3  = @{ numLoja = "02"; BaseCaixa = 200;  Servidor = "192.168.50.2" }
    9  = @{ numLoja = "03"; BaseCaixa = 300;  Servidor = "192.168.51.194" }
    52 = @{ numLoja = "06"; BaseCaixa = 5200; Servidor = "192.168.51.130" }
    53 = @{ numLoja = "05"; BaseCaixa = 5300; Servidor = "192.168.51.2" }
    57 = @{ numLoja = "07"; BaseCaixa = 5700; Servidor = "192.168.51.66" }
    58 = @{ numLoja = "08"; BaseCaixa = 5800; Servidor = "192.168.53.2" }
}

# --- INÍCIO DA EXECUÇÃO ---
Write-Host "Verificando diretorio de destino: $caminhoPdv" -ForegroundColor Cyan
if (-not (Test-Path $caminhoPdv)) {
    Write-Host "Criando pasta $caminhoPdv..."
    New-Item -ItemType Directory -Path $caminhoPdv | Out-Null
}

Write-Host "`nDetectando Gateway da rede..." -ForegroundColor Cyan

# PASSO 1: Captura o Gateway Nativo do PowerShell
$gatewayInfo = Get-CimInstance -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.DefaultIPGateway -ne $null }
$gateway = $gatewayInfo.DefaultIPGateway[0]

if ([string]::IsNullOrWhiteSpace($gateway)) {
    Write-Host "[ERRO] Gateway nao encontrado. Verifique a conexao." -ForegroundColor Red
    Pause
    exit
}
Write-Host "Gateway detectado: [$gateway]" -ForegroundColor Green

# PASSO 2 e 3: Define a FILIAL e IP baseados nas tabelas acima
$filial = $mapaGateways[$gateway]

if ($null -eq $filial) {
    Write-Host "[ERRO] Gateway nao mapeado para nenhuma filial." -ForegroundColor Red
    Pause
    exit
}

# Captura as configs da loja baseada no gateway detectado
$lojaAtual = $configFiliais[$filial]
$ipServidor = $lojaAtual.Servidor
$numLoja = $lojaAtual.numLoja

Write-Host "Filial $filial detectada. IP do Servidor configurado para: $ipServidor" -ForegroundColor Green

# --- PASSO 4: CRIACAO DOS ARQUIVOS DE CONFIGURAÇÃO ---
Write-Host "`nCriando arquivos de configuracao..." -ForegroundColor Cyan

# Função auxiliar para criar arquivos rapidamente
function Criar-Arquivo ($NomeArquivo, $Conteudo) {
    $caminhoCompleto = Join-Path $caminhoPdv $NomeArquivo
    $Conteudo | Set-Content -Path $caminhoCompleto -Encoding Default
}

Criar-Arquivo "ZPPERD01.CFG" @"
ENDERECO=$ipServidor
PORTA=23454
"@

Criar-Arquivo "ZMWS1201.CFG" "timeout=60"

Criar-Arquivo "ZPDF00.CFG" @"
windows.impressora=IMP-NFE
windows.executavel=C:\Program Files\SumatraPDF\SumatraPDF.exe
windows.comando=-silent -print-to "IMP-NFE"
windows.opcoes=32
"@

Criar-Arquivo "RESTG4650.CFG" "timeout=5"
Criar-Arquivo "RESTG4651.CFG" "timeout=5"

Criar-Arquivo "ZPPERD00.CFG" @"
TIPO01=1
OPCOESLOG=255
"@

Criar-Arquivo "RECRGOP0.CFG" @"
Vivo=22
Claro=12000000
Oi=35000000
Tim=74000000
Brasil Telecom=11
CTBC-Celular=12201
CTBC-Fixo=12299
Embratel=14000000
Sercomtel-Celular=12301
Sercomtel-Fixo=12399
L Economica=97100
Nextel=75000000
"@

# CliSiTef.ini
Criar-Arquivo "CliSiTef.ini" @"
[PinPad]
Tipo=Compartilhado
MensagemPadrao=:: MACHADAO ::
;GeraLogPinPad=1

[PinPadCompartilhado]
Porta=AUTO_USB

[Cheques]
;POTTENCIAL=1
;Serasa=1
;NomeArqCheques=cheque.ini

[PagamentoContas]
HabilitaPagamentoContasFininvest=0
TrataConsultaSaqueComSaque=1

[Redes]
HabilitaRedeBancoIbi=0
TrataConsultaSaqueComSaque=0

[RecargaCelular]
HabilitaRecargaMultiConcessionaria=1
HabilitaTratamentoTrocoPagtoDinheiro=1
TipoConfirmacaoNumeroCelular=1
ConfirmaOperadoraCelular=1
DesabilitaDuplaDigitacaoCelular=1
DeveConfirmarPrimeiroNumeroDoCelular=1


[Geral]
TipoComunicacaoExterna=TLSGWP
TrataConsultaSaqueComSaque=1
PermiteDevolucaoCodigoAutorizacaoEstendido=1
;DataEmAmbienteDeDesenvolvimento=20070721
NumeroDeDiasNoLog=5
ConfirmarValorPinPad=1
TransacoesAdicionaisHabilitadas=10;16;25;24;26;27;28;29;30;36;40;42;43;44;56;57;58;72;78;671;672;675;676;3006;3007;3034;3035;3036;3037;60;62;63;64;4178;3379;


[CliSiTef]
HabilitaTrace=1

[CliSiTefI]
HabilitaTrace=1

[SiTef]
MantemConexaoAtiva=0
TempoEsperaConexao=10
EnderecoIP=tls-prod.fiservapp.com
ConfiguracaoEnderecoIP=tls-prod.fiservapp.com
"@

Write-Host "Todos os arquivos de configuracao foram criados com sucesso!" -ForegroundColor Green

# --- DOWNLOADS E EXTRACOES ---
Write-Host "`nBaixando Icones e Imagens..." -ForegroundColor Cyan

# Força o uso do TLS 1.2 para evitar erros de conexão no GitHub
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path $caminhoIcones)) { New-Item -ItemType Directory -Path $caminhoIcones | Out-Null }
if (-not (Test-Path $caminhoImagens)) { New-Item -ItemType Directory -Path $caminhoImagens | Out-Null }

Invoke-WebRequest -Uri "https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/InterfaceUnificada/icones.7z" -OutFile "$caminhoIcones\icones.7z"

Write-Host "Extraindo Icones..."
$sevenZip = "C:\Program Files\7-Zip\7z.exe"
Set-Location -Path $caminhoIcones
& $sevenZip x -y icones.7z * | Out-Null
Set-Location -Path $PSScriptRoot # Retorna ao diretorio original

Write-Host "Baixando arquivos de Interface..."
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Zeus_V.gif" -OutFile "$caminhoImagens\Zeus_V.gif"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/cancela_sel.png" -OutFile "$caminhoImagens\cancela_sel.png"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/cancela.png" -OutFile "$caminhoImagens\cancela.png"

$caminhoConfigInterface = "$caminhoInterface\config"
if (-not (Test-Path $caminhoConfigInterface)) { New-Item -ItemType Directory -Path $caminhoConfigInterface | Out-Null }
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/config.js" -OutFile "$caminhoConfigInterface\config.js"

$caminhoAppDinamico = "$caminhoInterface\app\api\dinamico\pdvMouse"
if (-not (Test-Path $caminhoAppDinamico)) { New-Item -ItemType Directory -Path $caminhoAppDinamico | Out-Null }
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Buttons.js" -OutFile "$caminhoAppDinamico\Buttons.js"

# --- INSTALAÇÕES E AJUSTES DE SISTEMA ---
Write-Host "`nAjustando Parametro SumatraPDF..." -ForegroundColor Cyan
winget install --id SumatraPDF.SumatraPDF --scope machine --architecture x64 --silent --accept-package-agreements --accept-source-agreements

Write-Host "Reinstalando servico CTPipe..." -ForegroundColor Cyan
Stop-Process -Name "ctpipe", "mmc" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "CTPIPE" -Force -ErrorAction SilentlyContinue
sc.exe delete CTPIPE | Out-Null
Start-Sleep -Seconds 5
New-Service -Name "CTPIPE" -BinaryPathName "C:\Zanthus\Zeus\ctpipe.exe" -StartupType Automatic -DisplayName "Zanthus - CTPIPE" | Out-Null
Start-Service -Name "CTPIPE"

# --- ATALHOS PARA TODOS OS USUÁRIOS ---
Write-Host "Criando Atalhos para Todos os Usuarios..." -ForegroundColor Cyan
$wshell = New-Object -ComObject WScript.Shell

# Caminho da Area de Trabalho Publica (Todos os Usuarios)
$desktopPublico = [Environment]::GetFolderPath('CommonDesktopDirectory')

$atalhoDesktop = $wshell.CreateShortcut("$desktopPublico\Zeus Frente de Caixa.lnk")
$atalhoDesktop.TargetPath = "C:\Windows\System32\schtasks.exe"
$atalhoDesktop.Arguments = '/run /tn "Zanthus\pdv\Zeus Frente de Caixa"'
$atalhoDesktop.WorkingDirectory = "C:\Windows\system32"
$atalhoDesktop.WindowStyle = 1
$atalhoDesktop.Save()

# Caminho da Inicializacao Publica (Todos os Usuarios - ProgramData)
$startupPublico = [Environment]::GetFolderPath('CommonStartup')

# Startup Scheduled Task
$atalhoStartup = $wshell.CreateShortcut("$startupPublico\Zeus Frente de Caixa.lnk")
$atalhoStartup.TargetPath = "C:\Windows\System32\schtasks.exe"
$atalhoStartup.Arguments = '/run /tn "Zanthus\pdv\Zeus Frente de Caixa"'
$atalhoStartup.WorkingDirectory = "C:\Windows\system32"
$atalhoStartup.WindowStyle = 1
$atalhoStartup.Save()

# Startup Interface HTML
$atalhoHTML = $wshell.CreateShortcut("$startupPublico\Interface Zeus.lnk")
$atalhoHTML.TargetPath = "C:\Zanthus\Zeus\Interface\index.html"
$atalhoHTML.Save()

# Startup Zanthus Plug n Play (zpnp.exe) desativado por enquanto
#Write-Host "Adicionando Zanthus Plug n Play a inicializacao..." -ForegroundColor Cyan
#$atalhoZPNP = $wshell.CreateShortcut("$startupPublico\Zanthus Plug n Play.lnk")
#$atalhoZPNP.TargetPath = "C:\opt\Zanthus Plug n Play\zpnp.exe"
#$atalhoZPNP.WorkingDirectory = "C:\opt\Zanthus Plug n Play"
#$atalhoZPNP.WindowStyle = 1
#$atalhoZPNP.Save()

Write-Host "Ajustando w_pdv.cmd..." -ForegroundColor Cyan
$arquivoCmd = "C:\Zanthus\Zeus\pdvJava\w_pdv.cmd"
if (Test-Path $arquivoCmd) {
    (Get-Content $arquivoCmd) -replace ' --kiosk', '' | Set-Content $arquivoCmd
}

Write-Host "Ajustando Fuso Horario..." -ForegroundColor Cyan
# O operador "-in" do PowerShell substitui o nosso truque do "find" do CMD
if ($filial -in 1, 3, 9, 52, 53, 58) {
    Set-TimeZone -Id "Central Brazilian Standard Time"
}

# --- NOMECLATURA DO COMPUTADOR (HOSTNAME) ---
Write-Host "`nCalculando o nome do computador com base no IP..." -ForegroundColor Cyan

# 1. Pega o IP local da maquina (filtra apenas IPv4)
$ipMaquina = $gatewayInfo.IPAddress | Where-Object { $_ -match "\." } | Select-Object -First 1

# 2. Quebra o IP nos pontos e pega o ultimo bloco
$ultimoOctetoIP = [int]($ipMaquina.Split('.')[-1])

# 3. Garante que pegara apenas os ultimos 2 digitos matematicamente
$doisUltimosDigitos = $ultimoOctetoIP % 100

# 4. Faz a soma com a Base da Caixa cadastrada na filial
$numeroCaixaCalculado = $lojaAtual.BaseCaixa + $doisUltimosDigitos

# 5. Monta o nome final utilizando as variaveis calculadas e a numLoja
$novoNome = "CAIXA$numeroCaixaCalculado-LJ$numLoja"
$nomeAtual = $env:COMPUTERNAME

if ($nomeAtual -eq $novoNome) {
    Write-Host "O terminal ja esta com o nome correto calculado: $nomeAtual. Pulando etapa." -ForegroundColor Green
}
else {
    Write-Host "O IP detectado foi $ipMaquina (Finais: $doisUltimosDigitos)" -ForegroundColor Gray
    Write-Host "Base desta filial: $($lojaAtual.BaseCaixa) | Novo nome sera: $novoNome" -ForegroundColor Yellow
    Write-Host "O nome do computador será alterado ao adicioná-lo ao AD..." -ForegroundColor Cyan
    
    try {
        Write-Host "Aguarde adicionar ao AD para aplicar nome" -ForegroundColor Green
    }
    catch {
        Write-Host "`n[ERRO] Falha ao tentar renomear automaticamente: $($_.Exception.Message)" -ForegroundColor Red
    }
}
# --- AJUSTE ULTRA VNC EXPERIMENTAL---
Stop-Process -Name "winvnc" -Force -ErrorAction SilentlyContinue
Stop-Service -Name "uvnc_service" -Force -ErrorAction SilentlyContinue
Get-Process -Name "*vnc*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 5

Write-Host "`nConfigurando UltraVNC..." 
$CaminhoDestino = "C:\ProgramData\UltraVNC"
$CaminhoDestinoAlt = "C:\Program Files\uvnc bvba\UltraVNC"
$NomeArquivo = "ultravnc.ini"
$CaminhoCompleto = Join-Path -Path $CaminhoDestino -ChildPath $NomeArquivo
$CaminhoCompleto = Join-Path -Path $CaminhoDestinoAlt -ChildPath $NomeArquivo

$ConteudoINI = @"
[Permissions]
[admin]
UseRegistry=0
SendExtraMouse=1
Secure=0
MSLogonRequired=1
NewMSLogon=1
DebugMode=0
Avilog=0
path=C:\Program Files\uvnc bvba\UltraVnc
accept_reject_mesg=
DebugLevel=0
DisableTrayIcon=0
rdpmode=0
noscreensaver=0
LoopbackOnly=0
UseDSMPlugin=0
AllowLoopback=1
AuthRequired=1
ConnectPriority=0
DSMPlugin=
AuthHosts=
DSMPluginConfig=
AllowShutdown=1
AllowProperties=1
AllowInjection=0
AllowEditClients=1
FileTransferEnabled=1
FTUserImpersonation=1
BlankMonitorEnabled=1
BlankInputsOnly=0
DefaultScale=1
primary=1
secondary=0
SocketConnect=1
HTTPConnect=1
AutoPortSelect=1
PortNumber=5900
HTTPPortNumber=5800
IdleTimeout=0
IdleInputTimeout=0
RemoveWallpaper=0
RemoveAero=0
QuerySetting=2
QueryTimeout=10
QueryDisableTime=0
QueryAccept=0
QueryIfNoLogon=1
InputsEnabled=1
LockSetting=0
LocalInputsDisabled=0
EnableJapInput=0
EnableUnicodeInput=0
EnableWin8Helper=0
kickrdp=0
clearconsole=0
ReverseAuthRequired=1
service_commandline=
MaxViewerSetting=0
Collabo=0
Frame=0
Notification=0
OSD=0
NotificationSelection=0
MaxViewers=128
cloudServer=
cloudEnabled=0
[admin_auth]
group1=VNC@redemachado.local
group2=Administrators
group3=VNCVIEWONLY
locdom1=0
locdom2=0
locdom3=0
[UltraVNC]
passwd=B13D7EFBCA30697A44
passwd2=B13D7EFBCA30697A44
[poll]
TurboMode=1
PollUnderCursor=0
PollForeground=0
PollFullScreen=1
OnlyPollConsole=0
OnlyPollOnEvent=0
MaxCpu=40
EnableDriver=0
EnableHook=1
EnableVirtual=0
SingleWindow=0
SingleWindowName=
MaxCpu2=100
MaxFPS=25
"@

# Usa -Force para substituir o arquivo se ele já existir
Set-Content -Path $CaminhoCompleto -Value $ConteudoINI -Force
Write-Host "O arquivo '$NomeArquivo' foi gravado ou substituído em '$CaminhoCompleto'."

Write-Host "`nGravando permissoes binarias no registro (WinVNC3)..." -ForegroundColor Cyan

# Chama o executavel reg.exe diretamente, passando os exatos mesmos parametros do CMD
& reg.exe add "HKEY_LOCAL_MACHINE\SOFTWARE\ORL\WinVNC3" /v "ACL" /t REG_BINARY /d "02002c0001000000000024000300000001050000000000051500000009d846e9fc8f6fb7b8cea7c30a0f0000" /f

if ($LASTEXITCODE -eq 0) {
    Write-Host "Registro inserido com sucesso via CMD!" -ForegroundColor Green
} else {
    Write-Host "[ERRO] Falha ao gravar o registro." -ForegroundColor Red
}
Start-Service -Name "uvnc_service"

#Atualiza Winget Sources
winget source update

#Instala OnlyOffice
winget install ONLYOFFICE.DesktopEditors --silent --locale pt-BR --scope machine --accept-package-agreements --accept-source-agreements

#Instala Linphone
winget install BelledonneCommunications.Linphone --silent --scope machine --accept-package-agreements --accept-source-agreements

#Instala Lighshot
winget install Skillbrains.Lightshot --silent --locale pt-BR --scope machine --accept-package-agreements --accept-source-agreements

#Instala TMT20X II
Write-Host "Instalando Impressora..." -ForegroundColor Cyan
$installImpressora = "C:\opt\Zanthus Plug n Play\setup\impressora\epson\tm-t20\install.bat"
if (Test-Path $installImpressora) {
    Start-Process -FilePath $installImpressora -Verb RunAs -Wait
} else {
    Write-Host "Arquivo de instalacao da impressora nao encontrado!" -ForegroundColor Yellow
}

# --- INGRESSO NO DOMÍNIO (ACTIVE DIRECTORY) ---
$dominio = "redemachado.local"
$dominioCurto = "redemachado"

Write-Host "`nVerificando status do Active Directory..." -ForegroundColor Cyan

# 1. Verifica se o computador JÁ ESTÁ no domínio
$statusComputador = Get-CimInstance Win32_ComputerSystem
if ($statusComputador.PartOfDomain -and $statusComputador.Domain -eq $dominio) {
    Write-Host "O terminal ja esta ingressado no dominio $dominio! Pulando etapa." -ForegroundColor Green
} 
else {
    Write-Host "O terminal NAO esta no dominio. Iniciando processo de ingresso..." -ForegroundColor Yellow

    # 2. Inicia o Loop de tentativa
    while ($true) {
        try {
            # Pede o nome do usuario na propria tela preta
            $nomeUsuario = Read-Host "Digite o seu usuario do AD (apenas o nome, sem o '$dominioCurto\')"
            
            # Monta o padrao exigido pelo Windows (DOMINIO\Usuario)
            $usuarioCompleto = "$dominioCurto\$nomeUsuario"
            
            Write-Host "Abrindo janela para digitar a senha do usuario: $usuarioCompleto..." -ForegroundColor Cyan
            
            # Chama a janela do Windows. O campo "Usuario" ja vem preenchido e travado!
            $credenciais = Get-Credential -UserName $usuarioCompleto -Message "Digite a senha da rede para a maquina."

            Write-Host "Ingressando no dominio, por favor aguarde..." -ForegroundColor Cyan
            Add-Computer -DomainName $dominio -NewName $novoNome -Credential $credenciais -Force -ErrorAction Stop
            
            Write-Host "Terminal adicionado ao dominio com sucesso!" -ForegroundColor Green
            Write-Host "O computador sera reiniciado em 10 segundos..." -ForegroundColor Yellow
            Write-Host "Créditos IG @jjmorateli" -ForegroundColor Green
            Start-Sleep -Seconds 10
            Restart-Computer -Force
            
            # Se deu tudo certo, o comando 'break' encerra o loop
            break 
        }
        catch {
            # Se der erro (senha errada, sem rede, etc), ele cai aqui
            Write-Host "`n[ERRO] Falha ao ingressar no dominio: $($_.Exception.Message)" -ForegroundColor Red
            
            # 3. Pergunta se o usuario quer tentar novamente
            $tentarNovamente = Read-Host "Deseja tentar novamente? (S/N)"
            
            if ($tentarNovamente -notmatch "^[Ss]$") {
                Write-Host "Processo de ingresso no dominio cancelado. O script continuara sem adicionar ao AD." -ForegroundColor Yellow
                break # Sai do loop se a pessoa digitar 'N'
            }
            Write-Host "Reiniciando tentativa..." -ForegroundColor Cyan
        }
    }
}

Write-Host "`nOperacoes concluidas." -ForegroundColor Green
Pause
