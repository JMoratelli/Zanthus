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
$impressoraTipo = '92'
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

    <Border x:Name="Cabecalho" Grid.Row="0" Background="#12161C">
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

function Habilitar-Arrasto ($Janela) {
    $cab = $Janela.FindName('Cabecalho')
    if ($cab) {
        $cab.Cursor = 'SizeAll'
        $cab.Add_MouseLeftButtonDown({ try { $Janela.DragMove() } catch { } }.GetNewClosure())
    }
}

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

Habilitar-Arrasto $splash
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

    <Border x:Name="Cabecalho" Grid.Row="0" Background="#12161C">
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

Habilitar-Arrasto $win
$ui.HdMaquina.Text = $env:COMPUTERNAME
$ui.HdFilial.Text  = "filial $filial - loja $numLoja"
$linhasLog = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$ui.Log.ItemsSource = $linhasLog

# Sem botao de fechar: FormClosing equivalente
$script:podeFechar = $false
$win.Add_Closing({ if (-not $script:podeFechar) { $_.Cancel = $true } })

# Estado compartilhado com o runspace (sem scriptblock cruzando runspace!)
$script:sync = [hashtable]::Synchronized(@{
    Fila           = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    Etapa          = "Preparando..."
    Indice         = 0
    Total          = 0
    Concluido      = $false
    Falhou         = $false
    Interativo     = $false
    PedirCred      = $false
    CredPronta     = $false
    CredUser       = $null
    CredSenha      = $null
    CredDominio    = "machadao.corp"
    CredPulou      = $false
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
        param([string]$Texto, [string]$Cor = '#CBD5E1')
        $sync.Fila.Enqueue([pscustomobject]@{ Texto = $Texto; Cor = $Cor })
    }
    function Progresso {
        param([int]$Indice, [int]$Total, [string]$Nome)
        $sync.Indice = $Indice; $sync.Total = $Total; $sync.Etapa = $Nome
    }

    $caminhoPdv       = "C:\Zanthus\Zeus\pdvJava"
    $caminhoInterface = "C:\Zanthus\Zeus\Interface"
    $caminhoIcones    = "$caminhoInterface\resources\icones"
    $caminhoImagens   = "$caminhoInterface\resources\imagens"
    $ipServidor       = $sync.IpServidor
    $filial           = $sync.Filial
    $numLoja          = $sync.NumLoja

    # ---------- inventario de software ----------
    # $Inv e mutado pelas etapas (hashtable = referencia, sobrevive ao escopo filho do '&')
    $Inv = @{ Nomes = @(); Presentes = @{} }

    function Ler-Instalados {
        $chaves = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        @(Get-ItemProperty $chaves -EA 0 |
            Where-Object { $_.DisplayName } |
            Select-Object -ExpandProperty DisplayName) | Sort-Object -Unique
    }
    function Test-Nome ($Padrao) { [bool](@($Inv.Nomes) -like $Padrao) }
    function Test-Chrome {
        (Test-Nome "Google Chrome*") -or
        (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe") -or
        (Test-Path "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")
    }
    function Marcar-Presente ($id, $rotulo) {
        $Inv.Presentes[$id] = $true
        Log ("  {0,-14} ja instalado" -f $rotulo) $CorOk
    }
    function Falta ($id) { -not $Inv.Presentes[$id] }

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

    @{ Nome = "Inventario de software"; Acao = {
        $Inv.Nomes = Ler-Instalados
        $Inv.Presentes.Clear()
        Log "  $($Inv.Nomes.Count) programas registrados na maquina"

        if ((Get-Process -Name "EPSecurityConsole" -EA 0) -or
            (Test-Nome "*Bitdefender*") -or
            (Test-Path "C:\Program Files\Bitdefender\Endpoint Security")) { Marcar-Presente 'bitdefender' 'BitDefender' }

        # UltraVNC: so detecta, NUNCA instala
        if (Test-Path "C:\Program Files\uvnc bvba\UltraVNC\winvnc.exe") { Marcar-Presente 'uvnc' 'UltraVNC' }
        else { Log ("  {0,-14} ausente (instalacao manual, fora do escopo)" -f 'UltraVNC') $CorAviso }

        if (Test-Nome "7-Zip*")             { Marcar-Presente '7zip'       '7-Zip' }
        if (Test-Chrome)                    { Marcar-Presente 'chrome'     'Chrome' }
        if (Test-Nome "Amazon Corretto*8*") { Marcar-Presente 'corretto'   'Corretto 8' }
        if (Test-Nome "*ONLYOFFICE*")       { Marcar-Presente 'onlyoffice' 'ONLYOFFICE' }
        if (Test-Nome "*Lightshot*")        { Marcar-Presente 'lightshot'  'Lightshot' }
        if (Test-Nome "Notepad++*")         { Marcar-Presente 'notepadpp'  'Notepad++' }
        if (Test-Nome "*Sumatra*")          { Marcar-Presente 'sumatra'    'SumatraPDF' }
        if (Test-Nome "VLC media player*")  { Marcar-Presente 'vlc'        'VLC' }
        if (Test-Nome "*MicroSIP*")         { Marcar-Presente 'microsip'   'MicroSIP' }
        if (Test-Nome "*GOnnect*")          { Marcar-Presente 'gonnect'    'GOnnect' }

        $qtdVc = @($Inv.Nomes | Where-Object { $_ -like "Microsoft Visual C++*Redistributable*" }).Count
        if     ($qtdVc -ge 12) { Marcar-Presente 'vcredist' 'VC++ Redist' }
        elseif ($qtdVc -gt 0)  { Log ("  {0,-14} {1} de 12 - sera completado" -f 'VC++ Redist', $qtdVc) $CorAviso }

        $temNet6 = Test-Nome "Microsoft Windows Desktop Runtime - 6.*x64*"
        $temNet8 = Test-Nome "Microsoft Windows Desktop Runtime - 8.*x64*"
        if ($temNet6 -and $temNet8) { Marcar-Presente 'dotnet' '.NET 6/8' }
        elseif ($temNet6 -or $temNet8) { Log ("  {0,-14} parcial - sera completado" -f '.NET 6/8') $CorAviso }

        if (-not (Get-Command winget -EA 0)) {
            Log "  AVISO: winget nao encontrado nesta maquina." $CorAviso
            Log "  Instale o App Installer pela Microsoft Store antes de continuar." $CorAviso
        }
    }}

    @{ Nome = "Instalacao dos pacotes faltantes"; Acao = {
        if (-not (Get-Command winget -EA 0)) { Log "  winget indisponivel - etapa ignorada" $CorErro; return }
        winget source reset --force | Out-Null

        function Winget-Instala ($id, $rotulo, $extra = @()) {
            Log "  instalando $rotulo ($id)..."
            $arg = @('install','-e','--id',$id,'--silent','--accept-package-agreements','--accept-source-agreements') + $extra
            $saida = & winget @arg 2>&1
            if ($LASTEXITCODE -eq 0) { Log "    $rotulo OK" $CorOk }
            else {
                Log "    $rotulo terminou com codigo $LASTEXITCODE" $CorAviso
                @($saida)[-1..-3] | Where-Object { $_ } | ForEach-Object { Log "      $_" $CorAviso }
            }
        }

        $fila = @(
            @{ id='7zip'       ; wid='7zip.7zip'                  ; rot='7-Zip'      ; ex=@('--scope','machine') }
            @{ id='chrome'     ; wid='Google.Chrome'              ; rot='Chrome'     ; ex=@('--scope','machine') }
            @{ id='corretto'   ; wid='Amazon.Corretto.8.JDK'      ; rot='Corretto 8' ; ex=@('--scope','machine') }
            @{ id='onlyoffice' ; wid='ONLYOFFICE.DesktopEditors'  ; rot='ONLYOFFICE' ; ex=@('--scope','machine') }
            @{ id='notepadpp'  ; wid='Notepad++.Notepad++'        ; rot='Notepad++'  ; ex=@('--scope','machine') }
            @{ id='sumatra'    ; wid='SumatraPDF.SumatraPDF'      ; rot='SumatraPDF' ; ex=@('--scope','machine','--architecture','x64') }
            @{ id='vlc'        ; wid='VideoLAN.VLC'               ; rot='VLC'        ; ex=@('--scope','machine') }
            @{ id='lightshot'  ; wid='Skillbrains.Lightshot'      ; rot='Lightshot'  ; ex=@() }
            @{ id='microsip'   ; wid='MicroSIP.MicroSIP'          ; rot='MicroSIP'   ; ex=@() }
        )
        foreach ($p in $fila) {
            if (Falta $p.id) { Winget-Instala $p.wid $p.rot $p.ex }
        }

        if (Falta 'vcredist') {
            foreach ($v in 'Microsoft.VCRedist.2005.x86','Microsoft.VCRedist.2008.x86','Microsoft.VCRedist.2008.x64',
                           'Microsoft.VCRedist.2010.x86','Microsoft.VCRedist.2010.x64','Microsoft.VCRedist.2012.x86',
                           'Microsoft.VCRedist.2012.x64','Microsoft.VCRedist.2013.x86','Microsoft.VCRedist.2013.x64',
                           'Microsoft.VCRedist.2015+.x86','Microsoft.VCRedist.2015+.x64') {
                $rot = ($v -replace '^Microsoft\.VCRedist\.', 'VC++ ')
                Winget-Instala $v $rot @('--scope','machine')
            }
        }
        if (Falta 'dotnet') {
            Winget-Instala 'Microsoft.DotNet.DesktopRuntime.6' '.NET 6 Desktop' @('--scope','machine','--architecture','x64')
            Winget-Instala 'Microsoft.DotNet.DesktopRuntime.8' '.NET 8 Desktop' @('--scope','machine','--architecture','x64')
        }
        if (Falta 'gonnect') { Log "  GOnnect nao esta no winget - use o Configura-Ramal.ps1" $CorAviso }

        Log "  fila de pacotes concluida" $CorOk
    }}

    @{ Nome = "Epson TM-T20X"; Acao = {
        # ------------------------------------------------------------------
        # Conteudo do script original, verbatim. Unica adaptacao: o param()
        # virou variaveis (param() so vale no topo de um arquivo) e o
        # Write-Log espelha no painel alem de gravar no instalacao.log.
        # ------------------------------------------------------------------
        $Forcar         = $sync.ForcarEpson
        $ImpressoraTipo = $sync.ImpressoraTipo

        $BASE      = 'C:\opt\Zanthus Plug n Play\setup\impressora\epson\tm-t88v'
        $DIR_DLL   = 'C:\Zanthus\Zeus\Dll'
        $LOG       = Join-Path $BASE 'instalacao.log'

        $EXE_UTIL   = Join-Path $BASE 'TM-T88VUtility170.exe'
        $ISS        = Join-Path $BASE 'setup.iss'
        $ISS_LOG    = Join-Path $BASE 'setup_utilitario.log'
        $DLL_ORIGEM = Join-Path $BASE 'InterfaceEpsonNF.dll'

        $PORTCONN = 'C:\Program Files\EPSON\portcommunicationservice\PortConnectorBranch100.dll'

        $VID      = 'VID_04B8'
        $PID_CTRL = 'PID_0202'

        function Write-Log {
            param([string]$Msg, [string]$Nivel = 'INFO')
            $linha = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Msg
            $cor = switch ($Nivel) { 'ERRO' { '#F87171' } 'AVISO' { '#F59E0B' } default { '#CBD5E1' } }
            Log ("    " + $Msg) $cor
            Add-Content -LiteralPath $LOG -Value $linha -Encoding UTF8 -EA 0
        }

        function Test-Admin {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function Test-PortConnector { Test-Path -LiteralPath $PORTCONN }

        function New-SetupIss {
            $conteudo = @'
[InstallShield Silent]
Version=v7.00
File=Response File
[File Transfer]
OverwrittenReadOnly=NoToAll
[{DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-DlgOrder]
Dlg0={DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdWelcome-0
Count=5
Dlg1={DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdLicense2-0
Dlg2={DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-AskOptions-0
Dlg3={DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdStartCopy2-0
Dlg4={DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdFinish-0
[{DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdWelcome-0]
Result=1
[{DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdLicense2-0]
Result=1
[{DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-AskOptions-0]
Result=1
Sel-0=1
[{DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdStartCopy2-0]
Result=1
[Application]
Name=EPSON TM-T88V Utility Ver.1.70
Version=1.7.5.1
Company=Seiko Epson Corporation
Lang=0816
[{DDA36F98-A44D-46F2-88A9-9CDDB8A9625D}-SdFinish-0]
Result=1
bOpt1=0
bOpt2=0
'@
            try {
                [System.IO.File]::WriteAllText($ISS, $conteudo, [System.Text.Encoding]::ASCII)
                Write-Log "setup.iss gerado em $ISS"
                return $true
            } catch {
                Write-Log "Falha ao gerar setup.iss: $($_.Exception.Message)" 'ERRO'
                return $false
            }
        }

        function Get-DispositivoEpson {
            Get-PnpDevice -ErrorAction SilentlyContinue |
                Where-Object { $_.InstanceId -like "USB\$VID&$PID_CTRL\*" } |
                Select-Object -First 1
        }

        function Test-DllCopiada {
            $destino = Join-Path $DIR_DLL 'InterfaceEpsonNF.dll'
            if (-not (Test-Path -LiteralPath $destino))    { return $false }
            if (-not (Test-Path -LiteralPath $DLL_ORIGEM)) { return $true }
            $h1 = (Get-FileHash -LiteralPath $destino    -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $DLL_ORIGEM -Algorithm SHA256).Hash
            ($h1 -eq $h2)
        }

        if (-not (Test-Admin))                   { Write-Log 'Execute como Administrador.' 'ERRO'; return }
        if (-not (Test-Path -LiteralPath $BASE)) { Write-Log "Pasta base nao encontrada: $BASE" 'ERRO'; return }

        Write-Log '=== INICIO - Epson TM-T20X-II ==='

        $stPortConn = Test-PortConnector
        $stDll      = Test-DllCopiada
        $dev        = Get-DispositivoEpson

        Write-Log '--- Estado atual ---'
        Write-Log ("  PortConnectorBranch100 .. {0}" -f $(if ($stPortConn) { 'OK' } else { 'PENDENTE' }))
        Write-Log ("  InterfaceEpsonNF.dll .... {0}" -f $(if ($stDll)      { 'OK' } else { 'PENDENTE' }))
        Write-Log ("  USB Controller (0202) ... {0}" -f $(if ($dev) { "OK ($($dev.InstanceId))" } else { 'NAO DETECTADO' }))

        $modelo = Get-PnpDevice -ErrorAction SilentlyContinue |
                  Where-Object { $_.InstanceId -like "*$VID*PID_0E27*" }
        if ($modelo) {
            Write-Log '  ATENCAO: PID_0E27 presente. A impressora pode nao estar em' 'AVISO'
            Write-Log '  Vendor Class, ou ha resquicio do APD. Rode Limpa-Epson-APD.ps1.' 'AVISO'
        }
        if (Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object Name -like 'TMUSB*') {
            Write-Log '  ATENCAO: porta TMUSB presente - nao existe no PDV de referencia.' 'AVISO'
        }

        if ($stPortConn -and $stDll -and -not $Forcar) {
            Write-Log ''
            Write-Log 'Software ja instalado. Reaplicando apenas o zconf...'
        }

        Write-Log '--- Etapa 1/3: utilitario Epson ---'

        if ($stPortConn -and -not $Forcar) {
            Write-Log 'PortConnectorBranch100.dll ja presente - ignorado.'
        }
        elseif (-not (Test-Path -LiteralPath $EXE_UTIL)) {
            Write-Log "Instalador nao encontrado: $EXE_UTIL" 'ERRO'
        }
        else {
            if (-not (Test-Path -LiteralPath $ISS)) {
                Write-Log 'setup.iss ausente - gerando...'
                New-SetupIss | Out-Null
            } else {
                Write-Log 'setup.iss ja presente na pasta.'
            }

            Write-Log 'Instalando utilitario em modo silencioso...'
            $sync.Interativo = $true
            try {
                $p = Start-Process -FilePath $EXE_UTIL `
                     -ArgumentList "/s /f1`"$ISS`" /f2`"$ISS_LOG`"" -PassThru

                if (-not $p.WaitForExit(180000)) {
                    Write-Log 'TIMEOUT (180s) - abriu janela interativa? Encerrando.' 'AVISO'
                    try { $p.Kill() } catch { }
                } else {
                    Write-Log "ExitCode = $($p.ExitCode)"
                }
            }
            finally { $sync.Interativo = $false }

            Start-Sleep -Seconds 3

            if (Test-Path -LiteralPath $ISS_LOG) {
                $rcIss = (Select-String -Path $ISS_LOG -Pattern 'ResultCode=(-?\d+)' -EA 0 |
                          Select-Object -First 1).Matches.Groups[1].Value
                switch ($rcIss) {
                    '0'  { Write-Log '  ResultCode=0 (sucesso)' }
                    '-5' { Write-Log '  ResultCode=-5: response file nao encontrado.' 'ERRO' }
                    '-3' { Write-Log '  ResultCode=-3: response file invalido/corrompido.' 'ERRO' }
                    default { Write-Log "  ResultCode=$rcIss - consulte $ISS_LOG" 'AVISO' }
                }
            }

            if (Test-PortConnector) {
                Write-Log 'PortConnectorBranch100.dll instalado.'
            } else {
                Write-Log 'PortConnectorBranch100.dll NAO apareceu.' 'ERRO'
                if (Test-Path -LiteralPath $ISS_LOG) {
                    Get-Content -LiteralPath $ISS_LOG -EA 0 | ForEach-Object { Write-Log "  iss: $_" 'ERRO' }
                }
            }
        }

        Write-Log '--- Etapa 2/3: InterfaceEpsonNF.dll ---'
        if ($stDll -and -not $Forcar) {
            Write-Log 'Ja atualizada - ignorada.'
        } else {
            if (-not (Test-Path -LiteralPath $DIR_DLL)) {
                New-Item -ItemType Directory -Path $DIR_DLL -Force | Out-Null
            }
            if (Test-Path -LiteralPath $DLL_ORIGEM) {
                Copy-Item -LiteralPath $DLL_ORIGEM -Destination $DIR_DLL -Force
                Write-Log "Copiada para $DIR_DLL"
            } else {
                Write-Log "InterfaceEpsonNF.dll nao encontrada em $BASE" 'ERRO'
            }
        }

        Write-Log '--- Etapa 3/3: zconf ---'

        $ZCONF_CANDIDATOS = @(
            (Join-Path $BASE 'zconf.exe'),
            (Join-Path $BASE 'zconf'),
            'C:\Zanthus\Zeus\zconf.exe'
        )
        $zconf = $null
        foreach ($c in $ZCONF_CANDIDATOS) { if (Test-Path -LiteralPath $c) { $zconf = $c; break } }
        if (-not $zconf) {
            $cmd = Get-Command 'zconf' -ErrorAction SilentlyContinue
            if ($cmd) { $zconf = $cmd.Source }
        }

        if ($zconf) {
            Write-Log "zconf: $zconf"
            Write-Log "IMPRESSORA_TIPO = $ImpressoraTipo (izrcb_R$ImpressoraTipo.dll)"
            $cwdAnterior = Get-Location
            Set-Location -LiteralPath $BASE
            try {
                & $zconf '-EMUL.INI' '-c' 'FW_PORTA_COMUNIC' '-v' 'USB'
                Write-Log "  EMUL.INI     -> ExitCode $LASTEXITCODE"
                & $zconf '-ECFRECEB.CFG' '-c' 'biblioteca' '-v' "izrcb_R$ImpressoraTipo"
                Write-Log "  ECFRECEB.CFG -> ExitCode $LASTEXITCODE"
            }
            finally { Set-Location -LiteralPath $cwdAnterior }

            $cfg = 'C:\Zanthus\Zeus\pdvJava\ECFRECEB.CFG'
            $emu = 'C:\Zanthus\Zeus\pdvJava\EMUL.INI'
            foreach ($f in @($emu, $cfg)) {
                if (Test-Path -LiteralPath $f) {
                    Select-String -Path $f -Pattern 'FW_PORTA_COMUNIC|biblioteca' -EA 0 |
                        ForEach-Object { Write-Log "  $(Split-Path $f -Leaf): $($_.Line.Trim())" }
                } else {
                    Write-Log "  $f nao encontrado - zconf gravou em outro lugar?" 'AVISO'
                }
            }
        } else {
            Write-Log 'zconf nao encontrado. Procurado em:' 'ERRO'
            $ZCONF_CANDIDATOS | ForEach-Object { Write-Log "    $_" 'ERRO' }
        }

        Write-Log ''
        Write-Log '--- Estado final ---'
        Write-Log ("  PortConnectorBranch100 .. {0}" -f $(if (Test-PortConnector) { 'OK' } else { 'FALHOU' }))
        Write-Log ("  InterfaceEpsonNF.dll .... {0}" -f $(if (Test-DllCopiada)    { 'OK' } else { 'FALHOU' }))
        Write-Log ("  USB Controller (0202) ... {0}" -f $(if (Get-DispositivoEpson) { 'OK' } else { 'NAO DETECTADO' }))
        Write-Log ''
        Write-Log 'LEMBRETE: "USB Device Class" -> "Vendor Class" e gravado na NVRAM'
        Write-Log 'da impressora pelo utilitario. Nao ha CLI para isso.'
        Write-Log '=== FIM ==='
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

    @{ Nome = "BitDefender Endpoint (interativo)"; Acao = {
        if (-not (Falta 'bitdefender')) { Log "  ja instalado - etapa ignorada" $CorOk; return }

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

        # O setupdownloader do BitDefender NAO tem modo silencioso util:
        # sem janela visivel ele encerra sem instalar nada. Roda visivel e espera.
        Log "  ATENCAO: a janela do BitDefender vai abrir - conclua o assistente." $CorAviso
        $cwd = Get-Location
        Set-Location -LiteralPath $pastaDestino
        $sync.Interativo = $true
        try {
            $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"`"$nomeLimpo`"`"" -PassThru -WindowStyle Normal
            if (-not $p.WaitForExit(900000)) { Log "  TIMEOUT de 15 min aguardando o assistente" $CorAviso; try { $p.Kill() } catch {} }
        }
        finally { Set-Location -LiteralPath $cwd; $sync.Interativo = $false }

        # o downloader sai antes do agente terminar: espera o servico aparecer
        $limite = (Get-Date).AddMinutes(10)
        while ((Get-Date) -lt $limite) {
            if ((Get-Process -Name "EPSecurityConsole" -EA 0) -or
                (Test-Path "C:\Program Files\Bitdefender\Endpoint Security")) { break }
            Start-Sleep -Seconds 10
        }
        if ((Get-Process -Name "EPSecurityConsole" -EA 0) -or
            (Test-Path "C:\Program Files\Bitdefender\Endpoint Security")) {
            Log "  BitDefender instalado" $CorOk
        } else {
            Log "  BitDefender NAO foi detectado apos a instalacao" $CorErro
        }
        Remove-Item -LiteralPath $local -Force -EA 0
    }}

    @{ Nome = "Bloqueio do usuario PDV e logon automatico"; Acao = {
        Disable-LocalUser -Name "PDV" -EA 0
        $wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $wl -Name "AutoAdminLogon" -Value "0"
        Set-ItemProperty -Path $wl -Name "DefaultUserName" -Value ""
        Remove-ItemProperty -Path $wl -Name "DefaultPassword" -EA 0
        Log "  logon automatico desativado, usuario PDV desabilitado" $CorOk
    }}

    @{ Nome = "Ingresso no dominio"; Acao = {
        $st = Get-CimInstance Win32_ComputerSystem
        if ($st.PartOfDomain) { Log "  ja ingressado em $($st.Domain) - ignorado" $CorOk; return }

        while ($true) {
            $sync.CredPronta = $false
            $sync.CredUser   = $null
            $sync.CredSenha  = $null
            $sync.CredPulou  = $false
            $sync.PedirCred  = $true
            while (-not $sync.CredPronta) { Start-Sleep -Milliseconds 200 }

            if ($sync.CredPulou) { Log "  ingresso cancelado pelo tecnico" $CorAviso; return }

            $usuario = $sync.CredUser
            $senha   = $sync.CredSenha
            $dominio = $sync.CredDominio
            if ([string]::IsNullOrWhiteSpace($usuario) -or $null -eq $senha -or $senha.Length -eq 0) {
                Log "  usuario ou senha vazios - tente de novo" $CorErro
                continue
            }

            # PSCredential montado aqui dentro: SecureString atravessa runspace, objeto composto nao
            $cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)
            Log "  ingressando $dominio como $usuario ..."
            try {
                Add-Computer -DomainName $dominio -Credential $cred -Force -ErrorAction Stop
                Log "  terminal ingressado em $dominio" $CorOk
                return
            } catch {
                Log "  falha: $($_.Exception.Message)" $CorErro
            }
        }
    }}
    )

    # ---------- execucao ----------
    try {
        $total = $etapas.Count
        $sync.Total = $total
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
        $sync.Etapa = if ($sync.Falhou) { "Concluido com pendencias - confira o log" } else { "Instalacao concluida" }
    }
    catch {
        $sync.Falhou = $true
        $sync.Etapa  = "Falha geral"
        $sync.Fila.Enqueue([pscustomobject]@{ Texto = "FALHA GERAL: $($_.Exception.Message)"; Cor = '#F87171' })
    }
    finally {
        $sync.Indice = $sync.Total
        $sync.Concluido = $true
    }
}

# ============================================================
#  7. JANELA DE CREDENCIAL DO DOMINIO (roda na thread da UI)
# ============================================================
function PedirCredencial {
    [xml]$xamlCred = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dominio" Height="410" Width="620" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" WindowStyle="None" Topmost="True" Background="#EDEFF2">
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="92"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Border x:Name="Cabecalho" Grid.Row="0" Background="#12161C">
      <Grid Margin="36,0,36,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="M A C H A D A O   C O R P" FontFamily="Consolas" FontSize="9" Foreground="#7C93AE"/>
          <TextBlock Text="Ingresso no dominio" FontFamily="Segoe UI" FontSize="19" Foreground="White" Margin="0,4,0,0"/>
        </StackPanel>
        <TextBlock x:Name="CxMaquina" FontFamily="Consolas" FontSize="13" Foreground="#B4BCC5"
                   VerticalAlignment="Center" HorizontalAlignment="Right"/>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="36,22,36,20">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

      <StackPanel Grid.Row="0">

        <TextBlock Text="Dominio" FontFamily="Segoe UI" FontSize="10" Foreground="#5B6672"/>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="120"/></Grid.ColumnDefinitions>
          <TextBox x:Name="CxDominio" Grid.Column="0" FontFamily="Consolas" FontSize="14" Padding="6,4"
                   BorderBrush="#DDE1E6" IsReadOnly="True" Background="#EDEFF2" Foreground="#5B6672"/>
          <Button x:Name="CxEditar" Grid.Column="2" Content="Editar" Height="30"
                  FontFamily="Segoe UI" FontSize="11" FontWeight="Bold"
                  Background="#5B6672" Foreground="White" BorderThickness="0"/>
        </Grid>
        <TextBlock x:Name="CxDicaDom" Text="valor padrao da rede Machadao" FontFamily="Segoe UI" FontSize="9" Foreground="#9AA4AF"/>

        <Grid Margin="0,16,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="Usuario do AD" FontFamily="Segoe UI" FontSize="10" Foreground="#5B6672"/>
            <TextBox x:Name="CxUser" FontFamily="Consolas" FontSize="14" Padding="6,4" BorderBrush="#DDE1E6"/>
            <TextBlock x:Name="CxDicaUser" FontFamily="Segoe UI" FontSize="9" Foreground="#9AA4AF"/>
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
    $cD  = $w.FindName('CxDominio'); $cU = $w.FindName('CxUser'); $cS = $w.FindName('CxSenha')
    $cM  = $w.FindName('CxMsg');     $bO = $w.FindName('CxOk');   $bP = $w.FindName('CxPular')
    $bE  = $w.FindName('CxEditar');  $cDD = $w.FindName('CxDicaDom'); $cDU = $w.FindName('CxDicaUser')
    Habilitar-Arrasto $w
    $w.FindName('CxMaquina').Text = $script:sync.NovoNome

    $cD.Text  = $script:sync.CredDominio
    $cDU.Text = "sem o prefixo $(($script:sync.CredDominio -split '\.')[0])\"

    $bE.Add_Click({
        if ($cD.IsReadOnly) {
            $cD.IsReadOnly  = $false
            $cD.Background  = 'White'
            $cD.Foreground  = '#12161C'
            $bE.Content     = "Travar"
            $bE.Background  = '#1A5FB4'
            $cDD.Text       = "FQDN do dominio, ex.: machadao.corp"
            $cD.Focus(); $cD.SelectAll()
        } else {
            if ([string]::IsNullOrWhiteSpace($cD.Text)) { $cM.Text = "O dominio nao pode ficar vazio."; return }
            $cD.Text        = $cD.Text.Trim()
            $cD.IsReadOnly  = $true
            $cD.Background  = '#EDEFF2'
            $cD.Foreground  = '#5B6672'
            $bE.Content     = "Editar"
            $bE.Background  = '#5B6672'
            $cDD.Text       = "valor padrao da rede Machadao"
            $cDU.Text       = "sem o prefixo $(($cD.Text -split '\.')[0])\"
            $cM.Text        = ""
        }
    })

    $script:credFechar = $false
    $w.Add_Closing({ if (-not $script:credFechar) { $_.Cancel = $true } })

    $bO.Add_Click({
        if ([string]::IsNullOrWhiteSpace($cD.Text)) { $cM.Text = "Informe o dominio."; return }
        if ([string]::IsNullOrWhiteSpace($cU.Text)) { $cM.Text = "Informe o usuario do AD."; return }
        if ($cS.SecurePassword.Length -eq 0)        { $cM.Text = "Informe a senha."; return }

        $dom    = $cD.Text.Trim()
        $curto  = ($dom -split '\.')[0]
        $nome   = $cU.Text.Trim()
        # aceita "usuario", "machadao\usuario" ou "usuario@machadao.corp" sem duplicar prefixo
        if ($nome -notmatch '[\\@]') { $nome = "$curto\$nome" }

        $senha = $cS.SecurePassword
        $senha.MakeReadOnly()

        $script:sync.CredDominio = $dom
        $script:sync.CredUser    = $nome
        $script:sync.CredSenha   = $senha
        $script:sync.CredPulou   = $false
        $script:credFechar = $true
        $w.Close()
    })

    $bP.Add_Click({
        $script:sync.CredUser  = $null
        $script:sync.CredSenha = $null
        $script:sync.CredPulou = $true
        $script:credFechar = $true
        $w.Close()
    })

    $cU.Focus()
    [void]$w.ShowDialog()
}

# ============================================================
#  8. DISPARA O RUNSPACE E BOMBEIA A FILA NA THREAD DA UI
# ============================================================
$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = 'STA'
$rs.ThreadOptions  = 'ReuseThread'
$rs.Open()
$rs.SessionStateProxy.SetVariable('sync', $script:sync)

$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript($trabalho.ToString())
$handle = $ps.BeginInvoke()

$script:podeFechar = $false
$script:credAberta = $false
$script:topoAtual  = $false
$script:restam     = 15
$script:t2         = $null

$ui.BtnFinal.Add_Click({ $script:podeFechar = $true; $win.Close() })

$bomba = New-Object System.Windows.Threading.DispatcherTimer
$bomba.Interval = [TimeSpan]::FromMilliseconds(150)
$bomba.Add_Tick({

    # 1. drena o log
    $novas = $false
    while ($script:sync.Fila.Count -gt 0) {
        $item = $script:sync.Fila.Dequeue()
        $linhasLog.Add($item)
        $novas = $true
    }
    while ($linhasLog.Count -gt 500) { $linhasLog.RemoveAt(0) }
    if ($novas) { $ui.Rolagem.ScrollToEnd() }

    # 2. progresso
    if ($script:sync.Total -gt 0) {
        $ui.Barra.Value       = [math]::Round(($script:sync.Indice / $script:sync.Total) * 100)
        $ui.TxtContador.Text  = "$($script:sync.Indice)/$($script:sync.Total)"
    }
    $ui.TxtEtapa.Text = $script:sync.Etapa

    # 2b. durante instalador interativo, sai da frente e libera o arrasto
    if ($script:sync.Interativo -ne $script:topoAtual) {
        $script:topoAtual = $script:sync.Interativo
        $win.Topmost = -not $script:sync.Interativo
        if ($script:sync.Interativo) {
            $ui.TxtNota.Text = "Assistente externo aberto - conclua a janela do instalador. Arraste esta tela pelo cabecalho se ela atrapalhar."
        } else {
            $ui.TxtNota.Text = "Nao desligue o terminal. A maquina reinicia sozinha ao final."
            $win.Activate()
        }
    }

    # 3. erros nao tratados do runspace
    if ($ps.Streams.Error.Count -gt 0) {
        foreach ($e in @($ps.Streams.Error)) {
            $linhasLog.Add([pscustomobject]@{ Texto = "RUNSPACE: $e"; Cor = '#F87171' })
        }
        $ps.Streams.Error.Clear()
        $script:sync.Falhou = $true
    }

    # 4. o worker pediu a credencial do dominio
    if ($script:sync.PedirCred -and -not $script:credAberta) {
        $script:credAberta = $true
        $script:sync.PedirCred = $false
        PedirCredencial
        $script:sync.CredPronta = $true
        $script:credAberta = $false
    }

    # 5. fim
    if ($script:sync.Concluido -and $script:sync.Fila.Count -eq 0 -and -not $script:t2) {
        $bomba.Stop()
        $ui.Barra.Value = 100
        $ui.BtnFinal.IsEnabled  = $true
        $ui.BtnFinal.Content    = "Reiniciar agora"
        $ui.BtnFinal.Background = if ($script:sync.Falhou) { '#8A5A00' } else { '#0A6F66' }
        $script:t2 = New-Object System.Windows.Threading.DispatcherTimer
        $script:t2.Interval = [TimeSpan]::FromSeconds(1)
        $script:t2.Add_Tick({
            $script:restam--
            $ui.TxtNota.Text = "Reinicio automatico em $($script:restam) segundos."
            if ($script:restam -le 0) {
                $script:t2.Stop()
                $script:podeFechar = $true
                $win.Close()
            }
        })
        $ui.TxtNota.Text = "Reinicio automatico em $($script:restam) segundos."
        $script:t2.Start()
    }
})

$win.Add_ContentRendered({ $bomba.Start() })
[void]$win.ShowDialog()

try { $ps.EndInvoke($handle) | Out-Null } catch { }
$ps.Dispose(); $rs.Close(); $rs.Dispose()

Restart-Computer -Force
