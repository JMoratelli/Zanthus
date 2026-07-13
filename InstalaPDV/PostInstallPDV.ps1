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
    1  = @{ numLoja = "01"; BaseCaixa = 100;  Servidor = "192.168.50.130"; ipImpNFe = "10.1.1.139" }
    3  = @{ numLoja = "02"; BaseCaixa = 200;  Servidor = "192.168.50.2";   ipImpNFe = "192.168.11.94" }
    9  = @{ numLoja = "03"; BaseCaixa = 300;  Servidor = "192.168.51.194"; ipImpNFe = "192.168.4.26" }
    52 = @{ numLoja = "06"; BaseCaixa = 5200; Servidor = "192.168.51.130"; ipImpNFe = "192.168.8.29" }
    53 = @{ numLoja = "05"; BaseCaixa = 5300; Servidor = "192.168.51.2";   ipImpNFe = "192.168.6.39" }
    57 = @{ numLoja = "07"; BaseCaixa = 5700; Servidor = "192.168.51.66";  ipImpNFe = "192.168.57.126" }
    58 = @{ numLoja = "08"; BaseCaixa = 5800; Servidor = "192.168.53.2";   ipImpNFe = "192.168.58.159" }
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
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/style100.css" -OutFile "C:\Zanthus\Zeus\Interface\resources\css\style2.css"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/style100.css" -OutFile "C:\Zanthus\Zeus\Interface\resources\css\style100.css"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/style100.css" -OutFile "C:\Zanthus\Zeus\Interface\resources\css\style1000.css"

$caminhoConfigInterface = "$caminhoInterface\config"
if (-not (Test-Path $caminhoConfigInterface)) { New-Item -ItemType Directory -Path $caminhoConfigInterface | Out-Null }
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/config.js" -OutFile "$caminhoConfigInterface\config.js"

$caminhoAppDinamico = "$caminhoInterface\app\api\dinamico\pdvMouse"
if (-not (Test-Path $caminhoAppDinamico)) { New-Item -ItemType Directory -Path $caminhoAppDinamico | Out-Null }
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Buttons.js" -OutFile "$caminhoAppDinamico\Buttons.js"

# --- INSTALAÇÕES E AJUSTES DE SISTEMA ---

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

$atalhoHTML = $wshell.CreateShortcut("$desktopPublico\Interface Zeus.lnk")
$atalhoHTML.TargetPath = "C:\Zanthus\Zeus\Interface\index.html"
$atalhoHTML.Save()

# Caminho da Inicializacao Publica (Todos os Usuarios - ProgramData)
$startupPublico = [Environment]::GetFolderPath('CommonStartup')

# Startup Interface HTML
$atalhoZlauncher = $wshell.CreateShortcut("$startupPublico\launcherHTML.lnk")
$atalhoZlauncher.TargetPath = "C:\Zanthus\Zeus\Interface\index.html"
$atalhoZlauncher.Save()

#Ajusta Servidor mirage
(Get-Content "C:\Zanthus\Zeus\pdvJava\CARG0000.CFG") -replace '^endereco=.*', 'endereco=192.168.12.42' | Set-Content "C:\Zanthus\Zeus\pdvJava\CARG0000.CFG"
# Ajusta WPDV pra não subir em tela cheia
(Get-Content "C:\Zanthus\Zeus\pdvJava\w_pdv.cmd") -replace 'C:\\Zanthus\\Zeus\\zifaceloader\.exe --operador=unificada --zlauncher', 'C:\Zanthus\Zeus\Interface\index.html' | Set-Content "C:\Zanthus\Zeus\pdvJava\w_pdv.cmd"

Write-Host "Ajustando Fuso Horario..." -ForegroundColor Cyan
# O operador "-in" do PowerShell substitui o nosso truque do "find" do CMD
if ($filial -in 1, 3, 9, 52, 53, 58) {
    New-Item C:\Scripts -ItemType Directory -Force | Out-Null; 'Start-Sleep 120;$s="a.ntp.br";$u=New-Object Net.Sockets.UdpClient;$u.Client.ReceiveTimeout=5000;$e=New-Object Net.IPEndPoint(([Net.Dns]::GetHostAddresses($s)[0]),123);$d=New-Object byte[] 48;$d[0]=27;[void]$u.Send($d,$d.Length,$e);$r=New-Object Net.IPEndPoint([Net.IPAddress]::Any,0);$p=$u.Receive([ref]$r);$sec=[BitConverter]::ToUInt32([byte[]]($p[43],$p[42],$p[41],$p[40]),0);$utc=([datetime]"1900-01-01").AddSeconds($sec);$cuiaba=$utc.AddHours(-4);Set-Date $cuiaba' | Set-Content C:\Scripts\HoraCuiaba.ps1; $A=New-ScheduledTaskAction -Execute powershell.exe -Argument '-ExecutionPolicy Bypass -File C:\Scripts\HoraCuiaba.ps1'; $T=New-ScheduledTaskTrigger -AtStartup; Register-ScheduledTask -TaskName HoraCuiaba -Action $A -Trigger $T -User SYSTEM -RunLevel Highest -Force
}
#Ajuste Barras de menu iniciar
#Oculta icone pesquisa
Set-ItemProperty `
  -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" `
  -Name "SearchboxTaskbarMode" `
  -Type DWord `
  -Value 0
#Move barra de menu para a esquerda
# Usuário atual
New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Type DWord -Value 0

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Type DWord -Value 0

Stop-Process -Name explorer -Force
#PerfilPadrão
reg load HKU\DefUser C:\Users\Default\NTUSER.DAT

reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f

reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f

reg unload HKU\DefUser

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
    Write-Host "Nome Alterado..." -ForegroundColor Cyan
    
    try {
        Rename-Computer -NewName $novoNome -Force -ErrorAction Stop
        Write-Host "Nome alterado" -ForegroundColor Green
    }
    catch {
        Write-Host "`n[ERRO] Falha ao tentar renomear automaticamente: $($_.Exception.Message)" -ForegroundColor Red
    }
}

#Removido Parâmetros do UltraVNC

#Atualiza Winget Sources
winget source reset --force

# Instala OnlyOffice
winget install -e --id ONLYOFFICE.DesktopEditors --silent --scope machine --accept-package-agreements --accept-source-agreements

# Instala Microsip
winget install --id MicroSIP.MicroSIP --silent --accept-source-agreements --accept-package-agreements

# Instala Lightshot
winget install -e --id Skillbrains.Lightshot --silent --scope machine --accept-package-agreements --accept-source-agreements

Write-Host "`nAjustando Parametro SumatraPDF..." -ForegroundColor Cyan
winget install --id SumatraPDF.SumatraPDF --scope machine --architecture x64 --silent --accept-package-agreements --accept-source-agreements

#Instala Pacote Completo do Ninite
Write-Host "--- Instalando Ninite ---" -ForegroundColor Cyan

$url = "http://192.168.12.223/uploads/InstaladorWindows/ninite.exe"
$destino = "$env:TEMP\ninite.exe"

try {
    Write-Host "Baixando o Ninite..."
    Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing
    
    Write-Host "Executando..."
    Start-Process -FilePath $destino -Wait -NoNewWindow
    
    Write-Host "Limpando arquivo temporario..."
    Remove-Item -Path $destino -Force
    
    Write-Host "Ninite instalado com sucesso!" -ForegroundColor Green
} 
catch {
    Write-Host "Erro durante o processo do Ninite: $($_.Exception.Message)" -ForegroundColor Red
}
#FimInstala Ninite

#Instala TMT20X II
Write-Host "Instalando Impressora..." -ForegroundColor Cyan

$flag = "C:\ProgramData\Zanthus\impressora_instalada.flag"
$installImpressora = "C:\opt\Zanthus Plug n Play\setup\impressora\epson\tm-t20\install.bat"

if (-not (Test-Path $flag)) {
    if (Test-Path $installImpressora) {
        Start-Process -FilePath $installImpressora -Verb RunAs -Wait

        New-Item -Path $flag -ItemType File -Force | Out-Null
        Write-Host "Instalacao concluida." -ForegroundColor Green
    }
    else {
        Write-Host "Arquivo de instalacao da impressora nao encontrado!" -ForegroundColor Yellow
    }
}
else {
    Write-Host "Impressora ja instalada. Pulando etapa." -ForegroundColor DarkGray
}

#Adiciona impressora
$IP = $lojaAtual.ipImpNFe
$NomeImpressora = "IMP-NFE"

Write-Host "`n[IMP-NFE] Iniciando a instalacao da impressora fiscal..." -ForegroundColor Cyan

# Definindo caminhos de drivers locais e repositório web
$DriverUrl = "http://192.168.12.223/uploads/InstaladorWindows/KyoceraDrivers.7z"
$TempDir = "C:\KyoceraDrivers"
$ZipPath = "$TempDir\drivers.7z"

# 1. Garantir diretório local de drivers 
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

# 2. Download do pacote de drivers (Apenas se não existir)
if (-not (Test-Path $ZipPath)) {
    Write-Host "[$IP] Baixando pacote de drivers Kyocera..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DriverUrl -OutFile $ZipPath -UseBasicParsing
} else {
    Write-Host "[$IP] O pacote de drivers ja existe localmente. Pulando download!" -ForegroundColor Yellow
}

# 3. Extração silenciosa dos drivers 
$InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse -ErrorAction SilentlyContinue 
if (-not $InfFiles) {
    Write-Host "[$IP] Extraindo os arquivos de driver..." -ForegroundColor Cyan
    if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
        & "C:\Program Files\7-Zip\7z.exe" x $ZipPath "-o$TempDir" -y | Out-Null
    } else {
        7z x $ZipPath "-o$TempDir" -y | Out-Null
    }
    $InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse 
} else {
    Write-Host "[$IP] Drivers ja extraidos anteriormente. Pulando extracao!" -ForegroundColor Yellow
}

# 4. Validar hardware ativo na rede via SNMP 
Write-Host "[$IP] Consultando o modelo do equipamento via SNMP..." -ForegroundColor Cyan
$SNMP = New-Object -ComObject olePrn.OleSNMP
$SNMP.Open($IP, "public")
$ModeloCru = $SNMP.Get(".1.3.6.1.2.1.25.3.2.1.3.1")
$SNMP.Close()

if (-not $ModeloCru) {
    Write-Host "[$IP] [ERRO] Nao foi possivel obter o modelo via SNMP. Verifique a rede da impressora." -ForegroundColor Red
} else {
    Write-Host "[$IP] Hardware detectado: $ModeloCru" -ForegroundColor Green

    # Isolar codenome numérico técnico para busca (Ex: "M3655idn") 
    $CoreModel = $ModeloCru -split ' ' | Where-Object { $_ -match '\d' } | Select-Object -First 1
    if (-not $CoreModel) { $CoreModel = $ModeloCru }

    # 5. Mapear dinamicamente o driver compatível dentro do INF 
    $InfPath = $null
    $DriverName = $null
    foreach ($file in $InfFiles) {
        $Lines = Get-Content $file.FullName
        foreach ($line in $Lines) {
            if ($line -match '^"([^"]+)"\s*=\s*([^,]+)') {
                $PossivelDriver = $Matches[1].Trim()
                $PossivelSecao = $Matches[2].Trim()
                if ($PossivelDriver -like "*$CoreModel*" -or $PossivelSecao -like "*$CoreModel*") {
                    $DriverName = $PossivelDriver
                    $InfPath = $file.FullName
                    break
                }
            }
        }
        if ($DriverName) { break }
    }

    if (-not $InfPath -or -not $DriverName) {
        Write-Host "[$IP] [ERRO] Driver para o modelo '$CoreModel' nao localizado no arquivo INF." -ForegroundColor Red 
    } else {
        Write-Host "[$IP] Driver correspondente localizado: $DriverName" -ForegroundColor Green

        # 6. Criar Porta TCP/IP no Windows
        $PortName = "IP_$IP"
        if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
            Write-Host "[$IP] Criando porta de impressao ($PortName)..." -ForegroundColor Cyan
            Add-PrinterPort -Name $PortName -PrinterHostAddress $IP
        }

        # 7. Injetar Assinatura Digital (.cat) na maquina para bypass de pop-ups
        $InfDirectory = Split-Path $InfPath
        $CatFile = Get-ChildItem -Path $InfDirectory -Filter "*.cat" | Select-Object -First 1
        if ($CatFile) {
            $Cert = (Get-AuthenticodeSignature $CatFile.FullName).SignerCertificate
            if ($Cert) {
                $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
                $Store.Open("ReadWrite")
                $Store.Add($Cert)
                $Store.Close()
            }
        }

        # Injetar driver no repositório nativo do Windows (DriverStore)
        pnputil.exe /add-driver $InfPath | Out-Null

        # 8. Mapear o driver no Spooler com o subsistema PrintUI 
        Write-Host "[$IP] Registrando driver no Spooler..." -ForegroundColor Cyan
        $PrintUIArgs = "printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$InfPath`"" 
        $Process = Start-Process rundll32.exe -ArgumentList $PrintUIArgs -Wait -PassThru -NoNewWindow 

        if ($Process.ExitCode -ne 0) {
            Write-Host "[$IP] [ERRO] Falha ao registrar o driver via subsistema PrintUI." -ForegroundColor Red 
        } else {
            # Se a impressora já existir, deleta para fazer instalação limpa
            if (Get-Printer -Name "$NomeImpressora" -ErrorAction SilentlyContinue) {
                Remove-Printer -Name "$NomeImpressora" | Out-Null
            }

            # 9. Criar a Impressora física com o nome fixo solicitado
            Write-Host "[$IP] Criando dispositivo de impressao '$NomeImpressora'..." -ForegroundColor Cyan
            Add-Printer -Name "$NomeImpressora" -DriverName $DriverName -PortName $PortName

            # 10. Ajustar Preferências Nativas de Impressão (Duplex, Cassete e Comum)
            Write-Host "[$IP] Aplicando preferencias (Frente/Verso, Cassete)..." -ForegroundColor Cyan
            Set-PrintConfiguration -PrinterName "$NomeImpressora" -Duplexing TwoSidedLongEdge

            $Config = Get-PrintConfiguration -PrinterName "$NomeImpressora"
            [xml]$Ticket = $Config.PrintTicketXML
            $nsm = New-Object System.Xml.XmlNamespaceManager($Ticket.NameTable)
            $nsm.AddNamespace("psf", "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework")

            # Configura a Origem para "psk:Cassette" (Tag calibrada para Kyocera)
            $BinNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageInputBin']/psf:Option", $nsm)
            if ($BinNode) { $BinNode.SetAttribute("name", "psk:Cassette") }
            else {
                $FragmentBin = $Ticket.CreateDocumentFragment()
                $FragmentBin.InnerXml = '<psf:Feature name="psk:PageInputBin"><psf:Option name="psk:Cassette" /></psf:Feature>'
                $Ticket.DocumentElement.AppendChild($FragmentBin) | Out-Null
            }

            # Configura o Tipo de Mídia para Papel Comum ("psk:Plain")
            $MediaNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageMediaType']/psf:Option", $nsm)
            if ($MediaNode) { $MediaNode.SetAttribute("name", "psk:Plain") }
            else {
                $FragmentMedia = $Ticket.CreateDocumentFragment()
                $FragmentMedia.InnerXml = '<psf:Feature name="psk:PageMediaType"><psf:Option name="psk:Plain" /></psf:Feature>'
                $Ticket.DocumentElement.AppendChild($FragmentMedia) | Out-Null
            }

            # Grava as modificações finais do XML na impressora
            Set-PrintConfiguration -PrinterName "$NomeImpressora" -PrintTicketXML $Ticket.OuterXml
            Write-Host "[$IP] Impressora '$NomeImpressora' instalada e configurada com sucesso!" -ForegroundColor Green
        }
    }
}
#Fim Adiciona impressora
# Instala BitDefender
$nomeDoProcesso = "EPSecurityConsole" 
Write-Host "Verificando se o processo '$nomeDoProcesso' esta ativo..." -ForegroundColor Cyan
$processoAtivo = Get-Process -Name $nomeDoProcesso -ErrorAction SilentlyContinue

if ($processoAtivo) {
    Write-Host "BitDefender ja instalado e em execucao. Pulando instalacao." -ForegroundColor Green
}
else {
    Write-Host "Iniciando download via HTTP..." -ForegroundColor Yellow  
    $baseUrl = "http://192.168.12.223/uploads/InstaladorWindows/"
    
    # Define a pasta Downloads do usuario
    $pastaDestino = Join-Path $env:USERPROFILE "Downloads"
    
    # GARANTIA: Se a pasta Downloads ainda não existir, ele cria!
    if (-not (Test-Path -LiteralPath $pastaDestino)) {
        New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null
    }
    
    try {
        $paginaWeb = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -ErrorAction Stop
        
        $todasAsPalavras = $paginaWeb.Content -split '["''<>\s]'
        $arquivoExeNome = $todasAsPalavras | Where-Object { $_ -like "setupdownloader_*.exe" } | Select-Object -First 1
        
        if ($arquivoExeNome) {
            $nomeLimpoParaSalvar = [uri]::UnescapeDataString($arquivoExeNome)
            Write-Host "Arquivo encontrado: $nomeLimpoParaSalvar" -ForegroundColor Green
        } else {
            Write-Host "Falha: Nenhum instalador do Bitdefender encontrado no servidor." -ForegroundColor Red
            return
        }
    } 
    catch {
        Write-Host "Erro ao conectar no servidor HTTP: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Constroi os caminhos
    $urlDownload = "${baseUrl}${arquivoExeNome}"
    $caminhoExeLocal = Join-Path $pastaDestino $nomeLimpoParaSalvar
    
    Write-Host "Baixando o instalador para a pasta Downloads..." -ForegroundColor Cyan
    
    # Bloco isolado só para o DOWNLOAD - AGORA USANDO .NET PURO (WebClient)
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($urlDownload, $caminhoExeLocal)
        Write-Host "Download salvo com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Host "ERRO NO DOWNLOAD: $($_.Exception.Message)" -ForegroundColor Red
        return 
    }

    # Bloco isolado só para a EXECUÇÃO
    try {
        if (Test-Path -LiteralPath $caminhoExeLocal) {
            Write-Host "Iniciando instalacao..." -ForegroundColor Green
            
            # Vamos entrar na pasta Downloads e chamar via CMD para blindar contra o bug dos colchetes
            Set-Location -LiteralPath $pastaDestino
            $comandoExecucao = "/c `"`"$nomeLimpoParaSalvar`"`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $comandoExecucao -Wait -NoNewWindow
            
            Write-Host "Instalacao concluida!" -ForegroundColor Green
        } else {
            Write-Host "ERRO: O arquivo sumiu ou nao foi encontrado na pasta Downloads." -ForegroundColor Red
        }    
    }
    catch {
        Write-Host "ERRO NA EXECUÇÃO: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Limpeza
    try {
        Write-Host "Limpando instalador da pasta Downloads..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $caminhoExeLocal -Force
        Write-Host "Processo finalizado!" -ForegroundColor Green
    }
    catch {
        Write-Host "Aviso: O instalador ainda esta na pasta Downloads." -ForegroundColor DarkGray
    }
}
# --- INGRESSO NO DOMÍNIO (ACTIVE DIRECTORY) ---
$dominio = "machadao.corp"
$dominioCurto = "machadao"

#0 - Desativa usuário PDV por segurança
Disable-LocalUser -Name "PDV"
# 1. Desativa a função de login automático do Windows
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value "0"

# 2. Apaga o "PDV" da memória de usuário padrão do login automático
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUserName" -Value ""

# 3. (Opcional) Remove a senha salva em texto claro no registro, se houver
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -PathType Container) {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -ErrorAction SilentlyContinue
}

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
            Add-Computer -DomainName $dominio -Credential $credenciais -Force -ErrorAction Stop
             
            Write-Host "Terminal adicionado ao dominio com sucesso!" -ForegroundColor Green 
            Write-Host "O computador sera reiniciado em 10 segundos..." -ForegroundColor Yellow 
            Write-Host "Créditos IG @jjmorateli" -ForegroundColor Green 
            Start-Sleep -Seconds 10 
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
Restart-Computer -Force 
Pause
