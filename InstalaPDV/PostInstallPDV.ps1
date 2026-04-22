# --- VERIFICACAO DE PRIVILEGIOS DE ADMINISTRADOR ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Solicitando privilegios de Administrador..." -ForegroundColor Yellow
    # Roda novamente o PowerShell pedindo elevacao (UAC) para este mesmo arquivo
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    
    # Encerra a janela atual sem privilegios
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
    "192.168.58.1" = 58
}

$mapaServidores = @{
    1  = "192.168.50.130" # Loja 1
    3  = "192.168.50.2"   # Loja 2
    9  = "192.168.51.194" # Loja 3
    52 = "192.168.51.130" # Loja 6 (Primavera)
    53 = "192.168.51.2"   # Loja 5 (Alta Floresta)
    57 = "192.168.51.66"  # Loja 7 (Confresa)
    58 = "192.168.53.2" #Loja 8 (Lucas do Rio Verde)
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

$ipServidor = $mapaServidores[$filial]
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

# --- ATALHOS ---
Write-Host "Criando Atalhos..." -ForegroundColor Cyan
$wshell = New-Object -ComObject WScript.Shell

# Desktop
$atalhoDesktop = $wshell.CreateShortcut("$env:USERPROFILE\Desktop\Zeus Frente de Caixa.lnk")
$atalhoDesktop.TargetPath = "C:\Windows\System32\schtasks.exe"
$atalhoDesktop.Arguments = '/run /tn "Zanthus\pdv\Zeus Frente de Caixa"'
$atalhoDesktop.WorkingDirectory = "C:\Windows\system32"
$atalhoDesktop.WindowStyle = 1
$atalhoDesktop.Save()

# Startup Scheduled Task
$startupPath = [Environment]::GetFolderPath('Startup')
$atalhoStartup = $wshell.CreateShortcut("$startupPath\Zeus Frente de Caixa.lnk")
$atalhoStartup.TargetPath = "C:\Windows\System32\schtasks.exe"
$atalhoStartup.Arguments = '/run /tn "Zanthus\pdv\Zeus Frente de Caixa"'
$atalhoStartup.WorkingDirectory = "C:\Windows\system32"
$atalhoStartup.WindowStyle = 1
$atalhoStartup.Save()

# Startup Interface HTML
$atalhoHTML = $wshell.CreateShortcut("$startupPath\Interface Zeus.lnk")
$atalhoHTML.TargetPath = "C:\Zanthus\Zeus\Interface\index.html"
$atalhoHTML.Save()

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

Write-Host "Instalando Impressora..." -ForegroundColor Cyan
$installImpressora = "C:\opt\Zanthus Plug n Play\setup\impressora\epson\tm-t20\install.bat"
if (Test-Path $installImpressora) {
    Start-Process -FilePath $installImpressora -Verb RunAs -Wait
} else {
    Write-Host "Arquivo de instalacao da impressora nao encontrado!" -ForegroundColor Yellow
}

Write-Host "`nConcluido com sucesso!" -ForegroundColor Green
Pause
