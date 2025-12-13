@echo off
setlocal

REM --- CONFIGURACOES INICIAIS ---
set "CAMINHO=C:\Zanthus\Zeus\pdvJava"

echo.
echo Verificando diretorio de destino: %CAMINHO%
if not exist "%CAMINHO%" (
    echo Criando pasta %CAMINHO%...
    mkdir "%CAMINHO%"
)

echo.
echo Detectando Gateway da rede...

REM --- PASSO 1: Captura o Gateway usando PowerShell (Mais robusto) ---
set "GATEWAY="

REM Este comando invoca o PowerShell apenas para pegar o IP do Gateway e joga dentro da variavel GATEWAY do CMD
for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "(Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.DefaultIPGateway -ne $null }).DefaultIPGateway[0]"`) do (
    set "GATEWAY=%%a"
)

REM Remove espacos em branco caso existam
set "GATEWAY=%GATEWAY: =%"

if "%GATEWAY%"=="" (
    echo [ERRO] Gateway nao encontrado. Verifique a conexao.
    pause
    exit /b
)
echo Gateway detectado: [%GATEWAY%]

REM --- PASSO 2: Define a FILIAL baseada no Gateway ---
set "FILIAL="
if "%GATEWAY%"=="10.1.1.1"       set "FILIAL=1"
if "%GATEWAY%"=="192.168.11.253" set "FILIAL=3"
if "%GATEWAY%"=="192.168.5.253"  set "FILIAL=9"
if "%GATEWAY%"=="192.168.7.253"  set "FILIAL=53"
if "%GATEWAY%"=="192.168.9.253"  set "FILIAL=52"

REM Multiplos gateways para Loja 57
if "%GATEWAY%"=="192.168.57.193" set "FILIAL=57"
if "%GATEWAY%"=="192.168.57.1"   set "FILIAL=57"
if "%GATEWAY%"=="192.168.156.1"  set "FILIAL=57"
if "%GATEWAY%"=="192.168.57.129" set "FILIAL=57"

echo Ate aqui rodou 6
REM --- PASSO 3: Define IP do Servidor ---
set "IP_SERVIDOR="

if "%FILIAL%"=="1" set "IP_SERVIDOR=192.168.50.130" & echo Loja 1 detectada.
if "%FILIAL%"=="3" set "IP_SERVIDOR=192.168.50.2" & echo Loja 2 detectada.
if "%FILIAL%"=="9" set "IP_SERVIDOR=192.168.51.194" & echo Loja 3 detectada.
if "%FILIAL%"=="52" set "IP_SERVIDOR=192.168.51.130" & echo Loja 6 (Primavera) detectada.
if "%FILIAL%"=="53" set "IP_SERVIDOR=192.168.51.2" & echo Loja 5 (Alta Floresta) detectada.
if "%FILIAL%"=="57" set "IP_SERVIDOR=192.168.51.66" & echo Loja 7 (Confresa) detectada.

REM --- PASSO 4: Criacao dos Arquivos ---

echo.
echo Criando ZPPERD01.CFG em %CAMINHO% com IP: %IP_SERVIDOR%...
(
    echo ENDERECO=%IP_SERVIDOR%
    echo PORTA=23454
) > "%CAMINHO%\ZPPERD01.CFG"

echo.
echo Criando ZMWS1201.CFG em %CAMINHO%...
(
    echo timeout=60
) > "%CAMINHO%\ZMWS1201.CFG"

echo.
echo Configuracao Darwin EasyCash concluida!

REM 4. Cria\Uffffffff dos Arquivos com Conte\Uffffffffixo
echo.
echo Criando arquivos com conteudo fixo...

REM ZMWS1201.CFG
(
    echo timeout=60
) > "%CAMINHO%\ZMWS1201.CFG"

REM ZPDF00.CFG
(
    echo windows.impressora=IMP-NFE
    echo windows.executavel=C:\Program Files\SumatraPDF\SumatraPDF.exe
    echo windows.comando=-silent -print-to "IMP-NFE"
    echo windows.opcoes=32
) > "%CAMINHO%\ZPDF00.CFG"

REM RESTG4650.CFG
(
    echo timeout=5
) > "%CAMINHO%\RESTG4650.CFG"

REM RESTG4651.CFG
(
    echo timeout=5
) > "%CAMINHO%\RESTG4651.CFG"

REM ZPPERD00.CFG
(
    echo TIPO01=1
    echo OPCOESLOG=255
) > "%CAMINHO%\ZPPERD00.CFG"

REM RECRGOP0.CFG
(
    echo Vivo=22
    echo Claro=12000000
    echo Oi=35000000
    echo Tim=74000000
    echo Brasil Telecom=11
    echo CTBC-Celular=12201
    echo CTBC-Fixo=12299
    echo Embratel=14000000
    echo Sercomtel-Celular=12301
    echo Sercomtel-Fixo=12399
    echo L Economica=97100
    echo Nextel=75000000
) > "%CAMINHO%\RECRGOP0.CFG"

REM CliSiTef.ini (ARQUIVO MAIS LONGO)
echo Criando CliSiTef.ini...
(
    echo [PinPad]
    echo Tipo=Compartilhado
    echo MensagemPadrao=:: MACHADAO ::
    echo ;GeraLogPinPad=1
    echo.
    echo [PinPadCompartilhado]
    echo Porta=AUTO_USB
    echo.
    echo [Cheques]
    echo ;POTTENCIAL=1
    echo ;Serasa=1
    echo ;NomeArqCheques=cheque.ini
    echo.
    echo [PagamentoContas]
    echo HabilitaPagamentoContasFininvest=1
    echo TrataConsultaSaqueComSaque=1
    echo.
    echo [Redes]
    echo HabilitaRedeBancoIbi=0
    echo TrataConsultaSaqueComSaque=0
    echo.
    echo [RecargaCelular]
    echo HabilitaRecargaMultiConcessionaria=1
    echo HabilitaTratamentoTrocoPagtoDinheiro=1
    echo TipoConfirmacaoNumeroCelular=1
    echo ConfirmaOperadoraCelular=1
    echo DesabilitaDuplaDigitacaoCelular=1
    echo DeveConfirmarPrimeiroNumeroDoCelular=1
    echo.
    echo.
    echo [Geral]
    echo TipoComunicacaoExterna=TLSGWP
    echo TrataConsultaSaqueComSaque=1
    echo PermiteDevolucaoCodigoAutorizacaoEstendido=1
    echo ;DataEmAmbienteDeDesenvolvimento=20070721
    echo NumeroDeDiasNoLog=5
    echo ConfirmarValorPinPad=1
    echo TransacoesAdicionaisHabilitadas=10;16;25;24;26;27;28;29;30;36;40;42;43;44;56;57;58;72;78;671;672;675;676;3006;3007;3034;3035;3036;3037;60;62;63;64;4178;
    echo.
    echo.
    echo [CliSiTef]
    echo HabilitaTrace=1
    echo.
    echo [CliSiTefI]
    echo HabilitaTrace=1
    echo.
    echo [SiTef]
    echo MantemConexaoAtiva=0
    echo TempoEsperaConexao=10
    echo EnderecoIP=tls-prod.fiservapp.com
    echo ConfiguracaoEnderecoIP=tls-prod.fiservapp.com
) > "%CAMINHO%\CliSiTef.ini"

echo Todos os arquivos foram criados/atualizados com sucesso em: %CAMINHO%

setlocal
set SEVENZIP="C:\Program Files\7-Zip\7z.exe"

echo Copiando Icones
if not exist "C:\Zanthus\Zeus\Interface\resources\icones" mkdir "C:\Zanthus\Zeus\Interface\resources\icones"

curl -L -o "C:\Zanthus\Zeus\Interface\resources\icones\icones.7z" "https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/InterfaceUnificada/icones.7z"

pushd "C:\Zanthus\Zeus\Interface\resources\icones"
%SEVENZIP% x -y icones.7z *
popd

echo Copiando Zeus_V.gif
curl -L -o "C:\Zanthus\Zeus\Interface\resources\imagens\Zeus_V.gif" "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Zeus_V.gif"

echo Copiando cancela_sel.png
curl -L -o "C:\Zanthus\Zeus\Interface\resources\imagens\cancela_sel.png" "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/cancela_sel.png"

echo Copiando cancela.png
curl -L -o "C:\Zanthus\Zeus\Interface\resources\imagens\cancela.png" "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/cancela.png"

echo Copiando config.js
curl -L -o "C:\Zanthus\Zeus\Interface\config\config.js" "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/config.js"

echo Copiando Buttons.js
curl -L -o "C:\Zanthus\Zeus\Interface\app\api\dinamico\pdvMouse\Buttons.js" "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Buttons.js"

echo Aplicando permissoes na pasta de interface (Nota: No Windows as permissoes sao herdadas por padrao)

echo Concluido.
pause
endlocal
