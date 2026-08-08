#Requires -RunAsAdministrator
<#
    Instala-PDV-Windows.ps1
    Provisionamento de estacao PDV Zanthus - Machadao Corp
    Interface WPF conforme PADRAO-INTERFACE.md
    @JJMoratelli
#>

# ============================================================
#  0. CONSOLE OCULTO
# ============================================================
Add-Type -Namespace Nativo -Name Janela -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
try {
    $h = [Nativo.Janela]::GetConsoleWindow()
    if ($h -ne [System.IntPtr]::Zero) { [Nativo.Janela]::ShowWindow($h, 0) | Out-Null }
} catch { }

# ============================================================
#  1. ELEVACAO
# ============================================================
$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $ehAdmin) {
    if ($PSCommandPath) {
        Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList `
            "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        Add-Type -AssemblyName PresentationFramework
        [void][System.Windows.MessageBox]::Show(
            "Execute em um PowerShell como Administrador.", "Machadao Corp")
    }
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# O ISE mantem variaveis entre execucoes: zera estado
$script:sync = $null
Remove-Variable -Name resultado, etapas, filial, lojaAtual -Scope Script -ErrorAction SilentlyContinue

# ============================================================
#  2. TABELAS DE ESCALABILIDADE
# ============================================================
$mapaGateways = @{
    "10.1.1.1"       = 1
    "192.168.11.253" = 3
    "192.168.5.253"  = 9
    "192.168.205.1"  = 21
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
    21 = @{ numLoja = "21"; BaseCaixa = 2100; Servidor = "192.168.205.1";  ipImpNFe = "127.0.0.1" }
    52 = @{ numLoja = "06"; BaseCaixa = 5200; Servidor = "192.168.51.130"; ipImpNFe = "192.168.8.29" }
    53 = @{ numLoja = "05"; BaseCaixa = 5300; Servidor = "192.168.51.2";   ipImpNFe = "192.168.6.39" }
    57 = @{ numLoja = "07"; BaseCaixa = 5700; Servidor = "192.168.51.66";  ipImpNFe = "192.168.57.126" }
    58 = @{ numLoja = "08"; BaseCaixa = 5800; Servidor = "192.168.53.2";   ipImpNFe = "192.168.58.159" }
}

# Impressora fiscal: '91' ou '92' (izrcb_R<tipo>.dll)
$impressoraTipo = '91'
$forcarEpson    = $false

# ============================================================
#  3. DETECCAO (antes da UI, para o splash ja mostrar o contexto)
# ============================================================
$gatewayInfo = Get-CimInstance -Class Win32_NetworkAdapterConfiguration |
               Where-Object { $null -ne $_.DefaultIPGateway }
$gateway   = if ($gatewayInfo) { @($gatewayInfo.DefaultIPGateway)[0] } else { $null }
$ipMaquina = if ($gatewayInfo) { @($gatewayInfo.IPAddress | Where-Object { $_ -match '^\d+\.' })[0] } else { $null }

$filial     = if ($gateway) { $mapaGateways[$gateway] } else { $null }
$lojaAtual  = if ($filial)  { $configFiliais[$filial] } else { $null }

$novoNome = $env:COMPUTERNAME
if ($lojaAtual -and $ipMaquina) {
    $novoNome = "CAIXA$($lojaAtual.BaseCaixa + ([int]($ipMaquina.Split('.')[-1]) % 100))-LJ$($lojaAtual.numLoja)"
}

$erroDeteccao = $null
if (-not $gateway)   { $erroDeteccao = "Gateway nao encontrado. Verifique a conexao de rede." }
elseif (-not $filial){ $erroDeteccao = "Gateway [$gateway] nao esta mapeado para nenhuma filial." }

# ============================================================
#  4. SPLASH / CONFIRMACAO
# ============================================================
[xml]$xamlSplash = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Machadao Corp" Height="430" Width="720"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        WindowStyle="None" Topmost="True" Background="#EDEFF2">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="96"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#12161C">
      <Grid Margin="36,0,36,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="M A C H A D A O   C O R P" FontFamily="Consolas" FontSize="9" Foreground="#7C93AE"/>
          <TextBlock Text="Instalacao de Estacao PDV" FontFamily="Segoe UI" FontSize="20" Foreground="White" Margin="0,4,0,0"/>
        </StackPanel>
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Right">
          <TextBlock x:Name="TxtMaquina" FontFamily="Consolas" FontSize="13" Foreground="#B4BCC5" HorizontalAlignment="Right"/>
          <TextBlock x:Name="TxtIp" FontFamily="Consolas" FontSize="11" Foreground="#5B6672" HorizontalAlignment="Right"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="36,26,36,20">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="White" CornerRadius="10" BorderBrush="#DDE1E6" BorderThickness="1" Padding="16">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="FILIAL" FontFamily="Segoe UI" FontSize="10" Foreground="#5B6672"/>
            <TextBlock x:Name="TxtFilial" FontFamily="Consolas" FontSize="16" Foreground="#12161C"/>
            <TextBlock x:Name="TxtLoja" FontFamily="Segoe UI" FontSize="9" Foreground="#9AA4AF"/>
          </StackPanel>
          <StackPanel Grid.Column="1">
            <TextBlock Text="GATEWAY" FontFamily="Segoe UI" FontSize="10" Foreground="#5B6672"/>
            <TextBlock x:Name="TxtGw" FontFamily="Consolas" FontSize="16" Foreground="#12161C"/>
            <TextBlock Text="detectado automaticamente" FontFamily="Segoe UI" FontSize="9" Foreground="#9AA4AF"/>
          </StackPanel>
          <StackPanel Grid.Column="2">
            <TextBlock Text="SERVIDOR ZEUS" FontFamily="Segoe UI" FontSize="10" Foreground="#5B6672"/>
            <TextBlock x:Name="TxtServidor" FontFamily="Consolas" FontSize="16" Foreground="#12161C"/>
            <TextBlock x:Name="TxtImp" FontFamily="Segoe UI" FontSize="9" Foreground="#9AA4AF"/>
          </StackPanel>
        </Grid>
      </Border>

      <StackPanel Grid.Row="1" Margin="0,18,0,0">
        <Border Background="#EAF1FB" CornerRadius="6" Padding="12,8" HorizontalAlignment="Left">
          <TextBlock x:Name="TxtAviso" FontFamily="Segoe UI" FontSize="11" Foreground="#1A5FB4" TextWrapping="Wrap"/>
        </Border>
        <TextBlock x:Name="TxtValida" FontFamily="Segoe UI" FontSize="11" Foreground="#C01C28" Margin="2,14,0,0" TextWrapping="Wrap"/>
      </StackPanel>

      <Grid Grid.Row="2">
        <TextBlock Text="Creditos: @JJMoratelli" FontFamily="Segoe UI" FontSize="10"
                   Foreground="#B4BCC5" VerticalAlignment="Bottom" HorizontalAlignment="Left"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnSair" Content="Cancelar" Width="140" Height="50" Margin="0,0,12,0"
                  FontFamily="Segoe UI" FontSize="12" FontWeight="Bold"
                  Background="#5B6672" Foreground="White" BorderThickness="0"/>
          <Button x:Name="BtnIniciar" Content="Iniciar instalacao" Width="210" Height="50"
                  FontFamily="Segoe UI" FontSize="12" FontWeight="Bold"
                  Background="#1A5FB4" Foreground="White" BorderThickness="0"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Grid>
</Window>
"@

$splash = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlSplash))
$el = @{}
'TxtMaquina','TxtIp','TxtFilial','TxtLoja','TxtGw','TxtServidor','TxtImp','TxtAviso','TxtValida','BtnSair','BtnIniciar' |
    ForEach-Object { $el[$_] = $splash.FindName($_) }

$el.TxtMaquina.Text  = $env:COMPUTERNAME
$el.TxtIp.Text       = if ($ipMaquina) { $ipMaquina } else { "sem IP" }
$el.TxtFilial.Text   = if ($filial) { "$filial" } else { "--" }
$el.TxtLoja.Text     = if ($lojaAtual) { "loja $($lojaAtual.numLoja)" } else { "nao identificada" }
$el.TxtGw.Text       = if ($gateway) { $gateway } else { "--" }
$el.TxtServidor.Text = if ($lojaAtual) { $lojaAtual.Servidor } else { "--" }
$el.TxtImp.Text      = if ($lojaAtual) { "IMP-NFE $($lojaAtual.ipImpNFe)" } else { "" }

$script:iniciar = $false

if ($erroDeteccao) {
    $el.TxtAviso.Text = "Sem filial nao ha instalacao possivel."
    $el.TxtValida.Text = $erroDeteccao
    $el.BtnIniciar.IsEnabled = $false
    $el.BtnIniciar.Background = '#A9B2BD'
} else {
    $el.TxtAviso.Text = "A maquina sera renomeada para $novoNome, ingressada no dominio machadao.corp e reiniciada ao final. Confira a filial antes de iniciar."
}

$el.BtnIniciar.Add_Click({ $script:iniciar = $true; $splash.Close() })
$el.BtnSair.Add_Click({ $script:iniciar = $false; $splash.Close() })
[void]$splash.ShowDialog()

if (-not $script:iniciar) { return }

$ipServidor = $lojaAtual.Servidor
$numLoja    = $lojaAtual.numLoja
$ipImpNFe   = $lojaAtual.ipImpNFe

# ============================================================
#  5. JANELA PRINCIPAL
# ============================================================
[xml]$xamlMain = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Machadao Corp" Height="640" Width="900"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        WindowStyle="None" Topmost="True" Background="#EDEFF2">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="96"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#12161C">
      <Grid Margin="36,0,36,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="M A C H A D A O   C O R P" FontFamily="Consolas" FontSize="9" Foreground="#7C93AE"/>
          <TextBlock Text="Instalacao de Estacao PDV" FontFamily="Segoe UI" FontSize="20" Foreground="White" Margin="0,4,0,0"/>
        </StackPanel>
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Right">
          <TextBlock x:Name="HdMaquina" FontFamily="Consolas" FontSize="13" Foreground="#B4BCC5" HorizontalAlignment="Right"/>
          <TextBlock x:Name="HdFilial" FontFamily="Consolas" FontSize="11" Foreground="#5B6672" HorizontalAlignment="Right"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="36,26,36,20">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="White" CornerRadius="10" BorderBrush="#DDE1E6" BorderThickness="1" Padding="16">
        <StackPanel>
          <Grid>
            <TextBlock x:Name="TxtEtapa" FontFamily="Segoe UI" FontSize="13" Foreground="#12161C"/>
            <TextBlock x:Name="TxtContador" FontFamily="Consolas" FontSize="12" Foreground="#9AA4AF" HorizontalAlignment="Right"/>
          </Grid>
          <ProgressBar x:Name="Barra" Height="10" Minimum="0" Maximum="100" Value="0" Margin="0,12,0,0"
                       Foreground="#1A5FB4" Background="#EDEFF2" BorderThickness="0"/>
        </StackPanel>
      </Border>

      <Border Grid.Row="1" Background="#FDF0E3" CornerRadius="6" Padding="12,8" HorizontalAlignment="Left" Margin="0,14,0,0">
        <TextBlock x:Name="TxtNota" FontFamily="Segoe UI" FontSize="11" Foreground="#A8480A"
                   Text="Nao desligue o terminal. A maquina reinicia sozinha ao final."/>
      </Border>

      <Border Grid.Row="2" Background="#0B1020" CornerRadius="10" Margin="0,14,0,0" Padding="14">
        <ScrollViewer x:Name="Rolagem" VerticalScrollBarVisibility="Auto">
          <ItemsControl x:Name="Log">
            <ItemsControl.ItemTemplate>
              <DataTemplate>
                <TextBlock Text="{Binding Texto}" Foreground="{Binding Cor}"
                           FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" Margin="0,1"/>
              </DataTemplate>
            </ItemsControl.ItemTemplate>
          </ItemsControl>
        </ScrollViewer>
      </Border>

      <Grid Grid.Row="3" Margin="0,16,0,0">
        <TextBlock Text="Creditos: @JJMoratelli" FontFamily="Segoe UI" FontSize="10"
                   Foreground="#B4BCC5" VerticalAlignment="Center" HorizontalAlignment="Left"/>
        <Button x:Name="BtnFinal" Content="Aguarde..." Width="210" Height="50" HorizontalAlignment="Right"
                FontFamily="Segoe UI" FontSize="12" FontWeight="Bold"
                Background="#A9B2BD" Foreground="White" BorderThickness="0" IsEnabled="False"/>
      </Grid>
    </Grid>
  </Grid>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlMain))
$ui = @{}
'HdMaquina','HdFilial','TxtEtapa','TxtContador','Barra','TxtNota','Log','Rolagem','BtnFinal' |
    ForEach-Object { $ui[$_] = $win.FindName($_) }

$ui.HdMaquina.Text = $env:COMPUTERNAME
$ui.HdFilial.Text  = "filial $filial - loja $numLoja"
$linhasLog = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$ui.Log.ItemsSource = $linhasLog

# Sem botao de fechar: FormClosing equivalente
$script:podeFechar = $false
$win.Add_Closing({ if (-not $script:podeFechar) { $_.Cancel = $true } })

# Estado compartilhado com o runspace
$script:sync = [hashtable]::Synchronized(@{
    Win            = $win
    Linhas         = $linhasLog
    Barra          = $ui.Barra
    TxtEtapa       = $ui.TxtEtapa
    TxtContador    = $ui.TxtContador
    Concluido      = $false
    Falhou         = $false
    Gateway        = $gateway
    IpMaquina      = $ipMaquina
    Filial         = $filial
    NumLoja        = $numLoja
    IpServidor     = $ipServidor
    IpImpNFe       = $ipImpNFe
    NovoNome       = $novoNome
    ImpressoraTipo = $impressoraTipo
    ForcarEpson    = $forcarEpson
})

# ============================================================
#  6. TRABALHO PESADO (runspace)
# ============================================================
$trabalho = {

    $CorInfo = '#CBD5E1'; $CorOk = '#22C55E'; $CorAviso = '#F59E0B'; $CorErro = '#F87171'; $CorTitulo = '#60A5FA'

    function Log {
        param([string]$Texto, [string]$Cor = $CorInfo)
        $sync.Win.Dispatcher.Invoke([action] {
            $sync.Linhas.Add([pscustomobject]@{ Texto = $Texto; Cor = $Cor })
            while ($sync.Linhas.Count -gt 400) { $sync.Linhas.RemoveAt(0) }
        })
    }
    function Progresso {
        param([int]$Indice, [int]$Total, [string]$Nome)
        $sync.Win.Dispatcher.Invoke([action] {
            $sync.Barra.Value    = [math]::Round(($Indice / $Total) * 100)
            $sync.TxtEtapa.Text  = $Nome
            $sync.TxtContador.Text = "$Indice/$Total"
        })
    }

    $caminhoPdv       = "C:\Zanthus\Zeus\pdvJava"
    $caminhoInterface = "C:\Zanthus\Zeus\Interface"
    $caminhoIcones    = "$caminhoInterface\resources\icones"
    $caminhoImagens   = "$caminhoInterface\resources\imagens"
    $ipServidor       = $sync.IpServidor
    $filial           = $sync.Filial
    $numLoja          = $sync.NumLoja

    function Criar-Arquivo ($NomeArquivo, $Conteudo) {
        $Conteudo | Set-Content -Path (Join-Path $caminhoPdv $NomeArquivo) -Encoding Default
    }

    # ---------- definicao das etapas ----------
    $etapas = @(

    @{ Nome = "Estrutura de pastas"; Acao = {
        foreach ($p in @($caminhoPdv, $caminhoIcones, $caminhoImagens,
                         "$caminhoInterface\config", "$caminhoInterface\app\api\dinamico\pdvMouse",
                         "$caminhoInterface\resources\css")) {
            if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null; Log "  criado $p" }
        }
    }}

    @{ Nome = "Arquivos de configuracao Zeus"; Acao = {
        Criar-Arquivo "ZPPERD01.CFG" "ENDERECO=$ipServidor`r`nPORTA=23454"
        Criar-Arquivo "ZMWS1201.CFG" "timeout=60"
        Criar-Arquivo "ZPDF00.CFG" @"
windows.impressora=IMP-NFE
windows.executavel=C:\Program Files\SumatraPDF\SumatraPDF.exe
windows.comando=-silent -print-to "IMP-NFE"
windows.opcoes=32
"@
        Criar-Arquivo "RESTG4650.CFG" "timeout=5"
        Criar-Arquivo "RESTG4651.CFG" "timeout=5"
        Criar-Arquivo "ZPPERD00.CFG" "TIPO01=1`r`nOPCOESLOG=255"
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
        Log "  8 arquivos gravados em $caminhoPdv" $CorOk
    }}

    @{ Nome = "CliSiTef.ini"; Acao = {
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
        Log "  CliSiTef.ini gravado" $CorOk
    }}

    @{ Nome = "Download de icones e imagens"; Acao = {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/InterfaceUnificada/icones.7z" -OutFile "$caminhoIcones\icones.7z"
        $sevenZip = "C:\Program Files\7-Zip\7z.exe"
        if (Test-Path $sevenZip) {
            & $sevenZip x -y "-o$caminhoIcones" "$caminhoIcones\icones.7z" | Out-Null
            Log "  icones extraidos" $CorOk
        } else { Log "  7-Zip nao encontrado - icones NAO extraidos" $CorAviso }

        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Zeus_V.gif" -OutFile "$caminhoImagens\Zeus_V.gif"
        $css = "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/style100.css"
        foreach ($nome in 'style2.css','style100.css','style1000.css') {
            Invoke-WebRequest -UseBasicParsing -Uri $css -OutFile "$caminhoInterface\resources\css\$nome"
        }
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/config.js" -OutFile "$caminhoInterface\config\config.js"
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Buttons.js" -OutFile "$caminhoInterface\app\api\dinamico\pdvMouse\Buttons.js"
        Log "  interface atualizada" $CorOk
    }}

    @{ Nome = "Servico CTPipe"; Acao = {
        Stop-Process -Name "ctpipe","mmc" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "CTPIPE" -Force -ErrorAction SilentlyContinue
        sc.exe delete CTPIPE | Out-Null
        Start-Sleep -Seconds 5
        New-Service -Name "CTPIPE" -BinaryPathName "C:\Zanthus\Zeus\ctpipe.exe" `
                    -StartupType Automatic -DisplayName "Zanthus - CTPIPE" | Out-Null
        Start-Service -Name "CTPIPE"
        Log "  CTPIPE reinstalado e iniciado" $CorOk
    }}

    @{ Nome = "Atalhos para todos os usuarios"; Acao = {
        $wshell = New-Object -ComObject WScript.Shell
        $alvo = "C:\Zanthus\Zeus\Interface\index.html"
        $a1 = $wshell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) "Interface Zeus.lnk"))
        $a1.TargetPath = $alvo; $a1.Save()
        $a2 = $wshell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('CommonStartup')) "launcherHTML.lnk"))
        $a2.TargetPath = $alvo; $a2.Save()
        Log "  atalhos de desktop e startup criados" $CorOk
    }}

    @{ Nome = "Servidor Mirage e w_pdv"; Acao = {
        $carg = "$caminhoPdv\CARG0000.CFG"
        if (Test-Path $carg) {
            (Get-Content $carg) -replace '^endereco=.*', 'endereco=192.168.12.42' | Set-Content $carg
        } else { Log "  CARG0000.CFG ausente" $CorAviso }
        Set-Content -Path "$caminhoPdv\RESTG0200.CFG" -Value "endereco=192.168.12.42"
        $wpdv = "$caminhoPdv\w_pdv.cmd"
        if (Test-Path $wpdv) {
            (Get-Content $wpdv) -replace 'C:\\Zanthus\\Zeus\\zifaceloader\.exe --operador=unificada --zlauncher',
                                         'C:\Zanthus\Zeus\Interface\index.html' | Set-Content $wpdv
        } else { Log "  w_pdv.cmd ausente" $CorAviso }
        Log "  Mirage 192.168.12.42 aplicado" $CorOk
    }}

    @{ Nome = "Correcao de fuso horario (Cuiaba)"; Acao = {
        if ($filial -in 1,3,9,52,53,58) {
            New-Item C:\Scripts -ItemType Directory -Force | Out-Null
            $scriptContent = @'
Start-Sleep 10
$s = "a.ntp.br"
$u = New-Object Net.Sockets.UdpClient
$u.Client.ReceiveTimeout = 5000
$e = New-Object Net.IPEndPoint(([Net.Dns]::GetHostAddresses($s)[0]), 123)
$d = New-Object byte[] 48
$d[0] = 27
[void]$u.Send($d, $d.Length, $e)
$r = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
$p = $u.Receive([ref]$r)
$sec = [BitConverter]::ToUInt32([byte[]]($p[43], $p[42], $p[41], $p[40]), 0)
$utc = ([datetime]"1900-01-01").AddSeconds($sec)
Set-Date $utc.AddHours(-4)
'@
            Set-Content -Path C:\Scripts\HoraCuiaba.ps1 -Value $scriptContent -Encoding UTF8
            Unregister-ScheduledTask -TaskName "HoraCuiaba" -Confirm:$false -ErrorAction SilentlyContinue
            $A = New-ScheduledTaskAction -Execute "powershell.exe" `
                 -Argument '-WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Scripts\HoraCuiaba.ps1'
            $Query = @'
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Kernel-General'] and (EventID=1)]]</Select>
  </Query>
</QueryList>
'@
            $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
            $tEvt = New-CimInstance -CimClass $cls -ClientOnly
            $tEvt.Subscription = $Query
            $tEvt.Enabled = $true
            Register-ScheduledTask -TaskName "HoraCuiaba" -Action $A `
                -Trigger @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogon), $tEvt) `
                -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest) `
                -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable) `
                -Force | Out-Null
            Log "  tarefa HoraCuiaba registrada" $CorOk
        } else { Log "  filial $filial nao precisa de ajuste de fuso - ignorado" }
    }}

    @{ Nome = "Barra de tarefas (usuario e perfil padrao)"; Acao = {
        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Type DWord -Value 0
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Type DWord -Value 0
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        reg load HKU\DefUser C:\Users\Default\NTUSER.DAT | Out-Null
        reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f | Out-Null
        reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAl /t REG_DWORD /d 0 /f | Out-Null
        [gc]::Collect(); Start-Sleep -Seconds 2
        reg unload HKU\DefUser | Out-Null
        Log "  barra alinhada a esquerda, pesquisa oculta" $CorOk
    }}

    @{ Nome = "Nome do computador"; Acao = {
        if ($env:COMPUTERNAME -eq $sync.NovoNome) {
            Log "  ja esta como $($sync.NovoNome) - ignorado"
        } else {
            Rename-Computer -NewName $sync.NovoNome -Force -ErrorAction Stop
            Log "  renomeado para $($sync.NovoNome) (efetiva no reboot)" $CorOk
        }
    }}

    @{ Nome = "Winget: OnlyOffice, MicroSIP, Lightshot, Sumatra"; Acao = {
        winget source reset --force | Out-Null
        $pacotes = 'ONLYOFFICE.DesktopEditors','MicroSIP.MicroSIP','Skillbrains.Lightshot','SumatraPDF.SumatraPDF'
        foreach ($p in $pacotes) {
            Log "  instalando $p ..."
            winget install -e --id $p --silent --scope machine --accept-package-agreements --accept-source-agreements | Out-Null
        }
        Log "  pacotes winget processados" $CorOk
    }}

    @{ Nome = "Pacote Ninite"; Acao = {
        $url = "http://192.168.12.223/uploads/InstaladorWindows/ninite.exe"
        $destino = "$env:TEMP\ninite.exe"
        Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing
        Start-Process -FilePath $destino -Wait -WindowStyle Hidden
        Remove-Item -Path $destino -Force -ErrorAction SilentlyContinue
        Log "  Ninite concluido" $CorOk
    }}

    @{ Nome = "Epson TM-T20X-II"; Acao = {
        $BASE       = 'C:\opt\Zanthus Plug n Play\setup\impressora\epson\tm-t20X-ii'
        $DIR_DLL    = 'C:\Zanthus\Zeus\Dll'
        $EXE_UTIL   = Join-Path $BASE 'TM-T20X-IIUtility100.exe'
        $ISS        = Join-Path $BASE 'setup.iss'
        $ISS_LOG    = Join-Path $BASE 'setup_utilitario.log'
        $DLL_ORIGEM = Join-Path $BASE 'InterfaceEpsonNF.dll'
        $PORTCONN   = 'C:\Program Files\EPSON\portcommunicationservice\PortConnectorBranch100.dll'
        $tipo       = $sync.ImpressoraTipo
        $forcar     = $sync.ForcarEpson

        if (-not (Test-Path -LiteralPath $BASE)) { Log "  pasta base ausente: $BASE" $CorAviso; return }

        $stPortConn = Test-Path -LiteralPath $PORTCONN
        $stDll = $false
        $destDll = Join-Path $DIR_DLL 'InterfaceEpsonNF.dll'
        if (Test-Path -LiteralPath $destDll) {
            $stDll = -not (Test-Path -LiteralPath $DLL_ORIGEM) -or
                     ((Get-FileHash $destDll).Hash -eq (Get-FileHash $DLL_ORIGEM).Hash)
        }
        $dev = Get-PnpDevice -ErrorAction SilentlyContinue |
               Where-Object { $_.InstanceId -like "USB\VID_04B8&PID_0202\*" } | Select-Object -First 1
        Log ("  PortConnector: {0} | DLL: {1} | USB 0202: {2}" -f
             $(if($stPortConn){'OK'}else{'PENDENTE'}), $(if($stDll){'OK'}else{'PENDENTE'}), $(if($dev){'OK'}else{'NAO DETECTADO'}))

        if (Get-PnpDevice -EA 0 | Where-Object { $_.InstanceId -like "*VID_04B8*PID_0E27*" }) {
            Log "  ATENCAO: PID_0E27 presente - impressora fora de Vendor Class ou resquicio do APD" $CorAviso
        }
        if (Get-PrinterPort -EA 0 | Where-Object Name -like 'TMUSB*') {
            Log "  ATENCAO: porta TMUSB presente - nao existe no PDV de referencia" $CorAviso
        }

        if ($stPortConn -and -not $forcar) { Log "  utilitario ja instalado - ignorado" }
        elseif (-not (Test-Path -LiteralPath $EXE_UTIL)) { Log "  instalador ausente: $EXE_UTIL" $CorAviso }
        elseif (-not (Test-Path -LiteralPath $ISS)) {
            Log "  setup.iss ausente - grave o response file uma vez:" $CorAviso
            Log "    `"$EXE_UTIL`" /r /f1`"$ISS`"" $CorAviso
        } else {
            $p = Start-Process -FilePath $EXE_UTIL -ArgumentList "/s /f1`"$ISS`" /f2`"$ISS_LOG`"" -PassThru -WindowStyle Hidden
            if (-not $p.WaitForExit(180000)) { Log "  TIMEOUT 180s - encerrando instalador" $CorAviso; try { $p.Kill() } catch {} }
            else { Log "  ExitCode = $($p.ExitCode)" }
            Start-Sleep -Seconds 3
            if (Test-Path -LiteralPath $PORTCONN) { Log "  PortConnectorBranch100.dll instalado" $CorOk }
            else { Log "  PortConnectorBranch100.dll NAO apareceu" $CorErro }
        }

        if ($stDll -and -not $forcar) { Log "  InterfaceEpsonNF.dll ja atualizada" }
        elseif (Test-Path -LiteralPath $DLL_ORIGEM) {
            if (-not (Test-Path $DIR_DLL)) { New-Item -ItemType Directory -Path $DIR_DLL -Force | Out-Null }
            Copy-Item -LiteralPath $DLL_ORIGEM -Destination $DIR_DLL -Force
            Log "  InterfaceEpsonNF.dll copiada" $CorOk
        } else { Log "  InterfaceEpsonNF.dll nao encontrada em $BASE" $CorErro }

        $zconf = @((Join-Path $BASE 'zconf.exe'), (Join-Path $BASE 'zconf'), 'C:\Zanthus\Zeus\zconf.exe') |
                 Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $zconf) { $zconf = (Get-Command 'zconf' -EA 0).Source }
        if ($zconf) {
            $cwd = Get-Location
            Set-Location -LiteralPath $BASE
            try {
                & $zconf '-EMUL.INI' '-c' 'FW_PORTA_COMUNIC' '-v' 'USB'
                & $zconf '-ECFRECEB.CFG' '-c' 'biblioteca' '-v' "izrcb_R$tipo"
                Log "  zconf aplicado (izrcb_R$tipo)" $CorOk
            } finally { Set-Location -LiteralPath $cwd }
            foreach ($f in @("$caminhoPdv\EMUL.INI", "$caminhoPdv\ECFRECEB.CFG")) {
                if (Test-Path -LiteralPath $f) {
                    Select-String -Path $f -Pattern 'FW_PORTA_COMUNIC|biblioteca' -EA 0 |
                        ForEach-Object { Log "    $(Split-Path $f -Leaf): $($_.Line.Trim())" }
                } else { Log "    $f nao encontrado" $CorAviso }
            }
        } else { Log "  zconf nao encontrado" $CorErro }
        Log "  LEMBRETE: 'USB Device Class -> Vendor Class' e gravado na NVRAM pelo utilitario, nao ha CLI" $CorAviso
    }}

    @{ Nome = "Impressora IMP-NFE (Kyocera)"; Acao = {
        $IP = $sync.IpImpNFe
        $NomeImpressora = "IMP-NFE"
        $TempDir = "C:\KyoceraDrivers"
        $ZipPath = "$TempDir\drivers.7z"
        if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }
        if (-not (Test-Path $ZipPath)) {
            Log "  baixando drivers Kyocera..."
            Invoke-WebRequest -Uri "http://192.168.12.223/uploads/InstaladorWindows/KyoceraDrivers.7z" -OutFile $ZipPath -UseBasicParsing
        } else { Log "  pacote ja existe localmente" }

        $InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse -EA 0
        if (-not $InfFiles) {
            & "C:\Program Files\7-Zip\7z.exe" x $ZipPath "-o$TempDir" -y | Out-Null
            $InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse
        }

        $SNMP = New-Object -ComObject olePrn.OleSNMP
        $SNMP.Open($IP, "public")
        $ModeloCru = $SNMP.Get(".1.3.6.1.2.1.25.3.2.1.3.1")
        $SNMP.Close()
        if (-not $ModeloCru) { Log "  SNMP nao respondeu em $IP" $CorErro; return }
        Log "  hardware detectado: $ModeloCru" $CorOk

        $CoreModel = ($ModeloCru -split ' ' | Where-Object { $_ -match '\d' } | Select-Object -First 1)
        if (-not $CoreModel) { $CoreModel = $ModeloCru }

        $InfPath = $null; $DriverName = $null
        foreach ($file in $InfFiles) {
            foreach ($line in (Get-Content $file.FullName)) {
                if ($line -match '^"([^"]+)"\s*=\s*([^,]+)') {
                    if ($Matches[1].Trim() -like "*$CoreModel*" -or $Matches[2].Trim() -like "*$CoreModel*") {
                        $DriverName = $Matches[1].Trim(); $InfPath = $file.FullName; break
                    }
                }
            }
            if ($DriverName) { break }
        }
        if (-not $DriverName) { Log "  driver para '$CoreModel' nao localizado no INF" $CorErro; return }
        Log "  driver: $DriverName" $CorOk

        $PortName = "IP_$IP"
        if (-not (Get-PrinterPort -Name $PortName -EA 0)) { Add-PrinterPort -Name $PortName -PrinterHostAddress $IP }

        $CatFile = Get-ChildItem -Path (Split-Path $InfPath) -Filter "*.cat" | Select-Object -First 1
        if ($CatFile) {
            $Cert = (Get-AuthenticodeSignature $CatFile.FullName).SignerCertificate
            if ($Cert) {
                $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher","LocalMachine")
                $Store.Open("ReadWrite"); $Store.Add($Cert); $Store.Close()
            }
        }
        pnputil.exe /add-driver $InfPath | Out-Null
        $proc = Start-Process rundll32.exe -ArgumentList "printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$InfPath`"" -Wait -PassThru -WindowStyle Hidden
        if ($proc.ExitCode -ne 0) { Log "  falha no PrintUI (exit $($proc.ExitCode))" $CorErro; return }

        if (Get-Printer -Name $NomeImpressora -EA 0) { Remove-Printer -Name $NomeImpressora }
        Add-Printer -Name $NomeImpressora -DriverName $DriverName -PortName $PortName
        Set-PrintConfiguration -PrinterName $NomeImpressora -Duplexing TwoSidedLongEdge

        $ns = "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework"
        [xml]$Ticket = (Get-PrintConfiguration -PrinterName $NomeImpressora).PrintTicketXML
        $nsm = New-Object System.Xml.XmlNamespaceManager($Ticket.NameTable)
        $nsm.AddNamespace("psf", $ns)
        $pref = $Ticket.DocumentElement.GetPrefixOfNamespace($ns)
        foreach ($par in @(@('psk:PageInputBin','psk:Cassette'), @('psk:PageMediaType','psk:Plain'))) {
            $no = $Ticket.SelectSingleNode("//psf:Feature[@name='$($par[0])']/psf:Option", $nsm)
            if ($no) { $no.SetAttribute("name", $par[1]) }
            else {
                $feat = $Ticket.CreateElement($pref, "Feature", $ns)
                $feat.SetAttribute("name", $par[0])
                $opt = $Ticket.CreateElement($pref, "Option", $ns)
                $opt.SetAttribute("name", $par[1])
                [void]$feat.AppendChild($opt)
                [void]$Ticket.DocumentElement.AppendChild($feat)
            }
        }
        Set-PrintConfiguration -PrinterName $NomeImpressora -PrintTicketXML $Ticket.OuterXml
        Log "  IMP-NFE instalada (duplex, cassete, papel comum)" $CorOk
    }}

    @{ Nome = "BitDefender Endpoint"; Acao = {
        if (Get-Process -Name "EPSecurityConsole" -EA 0) { Log "  ja instalado e em execucao" $CorOk; return }
        $baseUrl = "http://192.168.12.223/uploads/InstaladorWindows/"
        $pastaDestino = Join-Path $env:USERPROFILE "Downloads"
        if (-not (Test-Path -LiteralPath $pastaDestino)) { New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null }
        $pagina = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -ErrorAction Stop
        $arquivo = ($pagina.Content -split '["''<>\s]') | Where-Object { $_ -like "setupdownloader_*.exe" } | Select-Object -First 1
        if (-not $arquivo) { Log "  nenhum instalador encontrado no servidor" $CorErro; return }
        $nomeLimpo = [uri]::UnescapeDataString($arquivo)
        $local = Join-Path $pastaDestino $nomeLimpo
        (New-Object System.Net.WebClient).DownloadFile("$baseUrl$arquivo", $local)
        Log "  baixado: $nomeLimpo"
        $cwd = Get-Location
        Set-Location -LiteralPath $pastaDestino
        try { Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$nomeLimpo`"`"" -Wait -WindowStyle Hidden }
        finally { Set-Location -LiteralPath $cwd }
        Remove-Item -LiteralPath $local -Force -EA 0
        Log "  BitDefender instalado" $CorOk
    }}

    @{ Nome = "Bloqueio do usuario PDV e logon automatico"; Acao = {
        Disable-LocalUser -Name "PDV" -EA 0
        $wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $wl -Name "AutoAdminLogon" -Value "0"
        Set-ItemProperty -Path $wl -Name "DefaultUserName" -Value ""
        Remove-ItemProperty -Path $wl -Name "DefaultPassword" -EA 0
        Log "  logon automatico desativado, usuario PDV desabilitado" $CorOk
    }}

    @{ Nome = "Ingresso no dominio machadao.corp"; Acao = {
        $dominio = "machadao.corp"
        $st = Get-CimInstance Win32_ComputerSystem
        if ($st.PartOfDomain -and $st.Domain -eq $dominio) { Log "  ja ingressado - ignorado" $CorOk; return }

        while ($true) {
            $cred = $sync.Win.Dispatcher.Invoke([func[object]] { PedirCredencial })
            if (-not $cred) { Log "  ingresso cancelado pelo tecnico" $CorAviso; return }
            try {
                Add-Computer -DomainName $dominio -Credential $cred -Force -ErrorAction Stop
                Log "  terminal ingressado no dominio" $CorOk
                return
            } catch {
                Log "  falha: $($_.Exception.Message)" $CorErro
            }
        }
    }}
    )

    # ---------- execucao ----------
    $total = $etapas.Count
    $i = 0
    foreach ($etapa in $etapas) {
        $i++
        Progresso $i $total $etapa.Nome
        Log ""
        Log ("[{0:d2}/{1:d2}] {2}" -f $i, $total, $etapa.Nome) $CorTitulo
        try { & $etapa.Acao }
        catch {
            $sync.Falhou = $true
            Log "  ERRO: $($_.Exception.Message)" $CorErro
        }
    }

    $sync.Win.Dispatcher.Invoke([action] {
        $sync.Barra.Value = 100
        $sync.TxtEtapa.Text = if ($sync.Falhou) { "Concluido com pendencias - confira o log" } else { "Instalacao concluida" }
    })
    $sync.Concluido = $true
}

# ============================================================
#  7. JANELA DE CREDENCIAL DO DOMINIO (roda na thread da UI)
# ============================================================
function PedirCredencial {
    [xml]$xamlCred = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dominio" Height="330" Width="600" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" WindowStyle="None" Topmost="True" Background="#EDEFF2">
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="92"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#12161C">
      <StackPanel VerticalAlignment="Center" Margin="36,0,36,0">
        <TextBlock Text="M A C H A D A O   C O R P" FontFamily="Consolas" FontSize="9" Foreground="#7C93AE"/>
        <TextBlock Text="Ingresso no dominio machadao.corp" FontFamily="Segoe UI" FontSize="19" Foreground="White" Margin="0,4,0,0"/>
      </StackPanel>
    </Border>
    <Grid Grid.Row="1" Margin="36,22,36,20">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Grid.Row="0">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="Usuario do AD" FontFamily="Segoe UI" FontSize="10" Foreground="#5B6672"/>
            <TextBox x:Name="CxUser" FontFamily="Consolas" FontSize="14" Padding="6,4" BorderBrush="#DDE1E6"/>
            <TextBlock Text="sem o prefixo machadao\" FontFamily="Segoe UI" FontSize="9" Foreground="#9AA4AF"/>
          </StackPanel>
          <StackPanel Grid.Column="2">
            <TextBlock Text="Senha" FontFamily="Segoe UI" FontSize="10" Foreground="#5B6672"/>
            <PasswordBox x:Name="CxSenha" FontFamily="Consolas" FontSize="14" Padding="6,4" BorderBrush="#DDE1E6"/>
          </StackPanel>
        </Grid>
        <TextBlock x:Name="CxMsg" FontFamily="Segoe UI" FontSize="11" Foreground="#C01C28" Margin="2,14,0,0" TextWrapping="Wrap"/>
      </StackPanel>
      <Grid Grid.Row="2">
        <TextBlock Text="Creditos: @JJMoratelli" FontFamily="Segoe UI" FontSize="10" Foreground="#B4BCC5"
                   VerticalAlignment="Bottom" HorizontalAlignment="Left"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="CxPular" Content="Pular etapa" Width="140" Height="50" Margin="0,0,12,0"
                  FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Background="#5B6672" Foreground="White" BorderThickness="0"/>
          <Button x:Name="CxOk" Content="Ingressar" Width="180" Height="50"
                  FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Background="#1A5FB4" Foreground="White" BorderThickness="0"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Grid>
</Window>
"@
    $w = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlCred))
    $cU = $w.FindName('CxUser'); $cS = $w.FindName('CxSenha'); $cM = $w.FindName('CxMsg')
    $bO = $w.FindName('CxOk');   $bP = $w.FindName('CxPular')

    $script:credResultado = $null
    $script:credFechar = $false
    $w.Add_Closing({ if (-not $script:credFechar) { $_.Cancel = $true } })

    $bO.Add_Click({
        if ([string]::IsNullOrWhiteSpace($cU.Text)) { $cM.Text = "Informe o usuario do AD."; return }
        if ($cS.SecurePassword.Length -eq 0)        { $cM.Text = "Informe a senha."; return }
        $script:credResultado = New-Object System.Management.Automation.PSCredential(
            "machadao\$($cU.Text.Trim())", $cS.SecurePassword)
        $script:credFechar = $true
        $w.Close()
    })
    $bP.Add_Click({
        $script:credResultado = $null
        $script:credFechar = $true
        $w.Close()
    })
    $cU.Focus()
    [void]$w.ShowDialog()
    return $script:credResultado
}

# ============================================================
#  8. DISPARA O RUNSPACE E MOSTRA A JANELA
# ============================================================
$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = 'STA'
$rs.ThreadOptions  = 'ReuseThread'
$rs.Open()
$rs.SessionStateProxy.SetVariable('sync', $script:sync)
$rs.SessionStateProxy.SetVariable('funcPedirCredencial', ${function:PedirCredencial})

$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript('Set-Item function:PedirCredencial $funcPedirCredencial').AddStatement().AddScript($trabalho)
$handle = $ps.BeginInvoke()

# Botao final: so libera quando terminar
$script:tarefaFinal = $null
$ui.BtnFinal.Add_Click({
    $script:podeFechar = $true
    $win.Close()
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    $ui.Rolagem.ScrollToEnd()
    if ($script:sync.Concluido) {
        $timer.Stop()
        $ui.BtnFinal.IsEnabled = $true
        $ui.BtnFinal.Content    = "Reiniciar agora"
        $ui.BtnFinal.Background = if ($script:sync.Falhou) { '#8A5A00' } else { '#0A6F66' }
        $ui.TxtNota.Text = "Reinicio automatico em 15 segundos."
        # contagem regressiva antes do reboot automatico
        $script:restam = 15
        $t2 = New-Object System.Windows.Threading.DispatcherTimer
        $t2.Interval = [TimeSpan]::FromSeconds(1)
        $t2.Add_Tick({
            $script:restam--
            $ui.TxtNota.Text = "Reinicio automatico em $($script:restam) segundos."
            if ($script:restam -le 0) {
                $t2.Stop()
                $script:podeFechar = $true
                $win.Close()
            }
        })
        $t2.Start()
        $script:tarefaFinal = $t2
    }
})
$timer.Start()

[void]$win.ShowDialog()

$ps.EndInvoke($handle) | Out-Null
$ps.Dispose(); $rs.Close(); $rs.Dispose()

Restart-Computer -Force
