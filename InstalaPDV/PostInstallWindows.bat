@echo off
setlocal

REM Define o caminho base
set "CAMINHO=C:\Zanthus\Zeus\pdvJava"

REM 1. Cria o diret\Uffffffff se ele n\Uffffffffexistir
if not exist "%CAMINHO%" (
    echo Criando diret\Uffffffff: %CAMINHO%
    mkdir "%CAMINHO%"
)

REM 2. Solicita o IP para o ZPPERD01.CFG (SEM VALIDA\UffffffffO DE FORMATO IP)
echo.
set /p IP_SERVIDOR="IP Servidor Darwin: "

REM 3. Cria\Uffffffff de ZPPERD01.CFG (Conte\Uffffffffin\Uffffffffco)
echo Criando ZPPERD01.CFG...
(
    echo ENDERECO=%IP_SERVIDOR%
    echo PORTA=23454
) > "%CAMINHO%\ZPPERD01.CFG"


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
    echo windows.opcoes=2
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


echo.
echo Todos os arquivos foram criados/atualizados com sucesso em: %CAMINHO%
echo.
pause
endlocal
