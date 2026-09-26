<#
    PostInstallPDV.ps1
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
# Nao ha '#Requires -RunAsAdministrator' no topo, e isso e proposital: o
# Requires aborta o script antes da primeira linha executar, entao a
# auto-elevacao daqui nunca chegava a rodar - sem admin, a janela so piscava e
# sumia. A checagem abaixo faz o mesmo papel do Requires e ainda relanca
# elevado.
$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $ehAdmin) {
    Add-Type -AssemblyName PresentationFramework
    if ($PSCommandPath) {
        try {
            Start-Process powershell -Verb RunAs -WindowStyle Hidden -ErrorAction Stop -ArgumentList `
                "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        } catch {
            # UAC recusado ou conta sem direito de elevar. Com o console
            # escondido na secao 0, sem esta caixa o tecnico nao ve nada.
            [void][System.Windows.MessageBox]::Show(
                "E preciso autorizar a elevacao para instalar o terminal.", "Machadao Corp")
        }
    } else {
        # Script colado no console ou no ISE: nao ha arquivo para relancar.
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

# Fuso por filial, com os IDs do proprio Windows (a lista sai de 'tzutil /l').
# Fica na tabela, e nao numa lista solta dentro da etapa, porque filial nova
# entra aqui e mais nada precisa ser tocado.
# So a filial 57 e Brasilia; todas as outras sao Cuiaba.
$tzCuiaba   = "Central Brazilian Standard Time"   # UTC-4
$tzBrasilia = "E. South America Standard Time"    # UTC-3

$configFiliais = @{
    1  = @{ numLoja = "01"; BaseCaixa = 100;  Servidor = "192.168.50.130"; ipImpNFe = "10.1.1.139";    Fuso = $tzCuiaba }
    3  = @{ numLoja = "02"; BaseCaixa = 200;  Servidor = "192.168.50.2";   ipImpNFe = "192.168.11.94"; Fuso = $tzCuiaba }
    9  = @{ numLoja = "03"; BaseCaixa = 300;  Servidor = "192.168.51.194"; ipImpNFe = "192.168.4.26";  Fuso = $tzCuiaba }
    21 = @{ numLoja = "21"; BaseCaixa = 2100; Servidor = "192.168.205.1";  ipImpNFe = "127.0.0.1";     Fuso = $tzCuiaba }
    52 = @{ numLoja = "06"; BaseCaixa = 5200; Servidor = "192.168.51.130"; ipImpNFe = "192.168.8.29";  Fuso = $tzCuiaba }
    53 = @{ numLoja = "05"; BaseCaixa = 5300; Servidor = "192.168.51.2";   ipImpNFe = "192.168.6.39";  Fuso = $tzCuiaba }
    57 = @{ numLoja = "07"; BaseCaixa = 5700; Servidor = "192.168.51.66";  ipImpNFe = "192.168.57.126"; Fuso = $tzBrasilia }
    58 = @{ numLoja = "08"; BaseCaixa = 5800; Servidor = "192.168.53.2";   ipImpNFe = "192.168.58.159"; Fuso = $tzCuiaba }
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

# O nome sai de BaseCaixa + (ultimo octeto do IP % 100). O resto por 100 e
# intencional: nenhuma loja passa de 100 caixas, entao a faixa de IP dos
# terminais cabe inteira no resto e nao existe nome repetido na pratica.
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
    Fuso           = $lojaAtual.Fuso
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
        foreach ($p in @($caminhoPdv, $caminhoImagens,
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
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/Zeus_V.gif" -OutFile "$caminhoImagens\Zeus_V.gif"
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/logo_self.png" -OutFile "C:\Zanthus\Zeus\Interface\resources\imagens\logo_self.png"
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/style2.css" -OutFile "C:\Zanthus\Zeus\Interface\resources\css\style2.css"
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/style100.css" -OutFile "C:\Zanthus\Zeus\Interface\resources\css\style100.css"
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/style1000.css" -OutFile "C:\Zanthus\Zeus\Interface\resources\css\style1000.css"
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/PDVComum/config.js" -OutFile "$caminhoInterface\config\config.js"
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/Buttons.js" -OutFile "$caminhoInterface\app\api\dinamico\pdvMouse\Buttons.js"
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
        $wshell  = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
        $startup = [Environment]::GetFolderPath('CommonStartup')

        # Area de trabalho: interface HTML
        $a1 = $wshell.CreateShortcut((Join-Path $desktop "Interface Zeus.lnk"))
        $a1.TargetPath = "C:\Zanthus\Zeus\Interface\index.html"; $a1.Save()
        Log "  desktop: Interface Zeus.lnk -> index.html" $CorOk

        # Inicializacao: SEMPRE o zlauncher
        $zl = "C:\Zanthus\Zeus\zlauncher\zlauncher.exe"
        if (Test-Path -LiteralPath $zl) {
            $a2 = $wshell.CreateShortcut((Join-Path $startup "Zeus Frente de Caixa.lnk"))
            $a2.TargetPath = $zl; $a2.WorkingDirectory = Split-Path $zl -Parent; $a2.Save()
            Log "  startup: Zeus Frente de Caixa.lnk -> zlauncher.exe" $CorOk
        } else { Log "  $zl ausente - atalho de inicializacao nao criado" $CorAviso }

        # O atalho antigo apontava para index.html e duplicava a interface
        $velho = Join-Path $startup "launcherHTML.lnk"
        if (Test-Path -LiteralPath $velho) {
            Remove-Item -LiteralPath $velho -Force
            Log "  atalho antigo launcherHTML.lnk removido" $CorOk
        }
    }}

    @{ Nome = "w_pdv.cmd (tira o kiosk)"; Acao = {
        # O CARG0000.CFG / RESTG0200.CFG nao sao mais forcados aqui: a dinamica de
        # acesso mudou e o endereco vem do que ja esta configurado no terminal.
        $wpdv = "$caminhoPdv\w_pdv.cmd"
        if (-not (Test-Path -LiteralPath $wpdv)) { Log "  w_pdv.cmd ausente" $CorAviso; return }

        $linhas = Get-Content -LiteralPath $wpdv
        $tem = @($linhas | Where-Object { $_ -match 'zifaceloader\.exe' -and $_ -match '\s--kiosk(\s|$)' })
        if ($tem.Count -eq 0) { Log "  ja esta sem --kiosk - ignorado" $CorOk; return }

        Copy-Item -LiteralPath $wpdv -Destination "$wpdv.bak" -Force
        $novas = $linhas | ForEach-Object {
            if ($_ -match 'zifaceloader\.exe') { $_ -replace '\s+--kiosk(?=\s|$)', '' } else { $_ }
        }
        Set-Content -LiteralPath $wpdv -Value $novas -Encoding Default
        Log "  --kiosk removido (backup em w_pdv.cmd.bak)" $CorOk
    }}

    @{ Nome = "Fuso horario"; Acao = {
        # ------------------------------------------------------------------
        # Aqui existia a tarefa agendada HoraCuiaba, que a cada boot, a cada
        # logon e a cada evento de mudanca de hora do kernel consultava um NTP
        # externo na mao, subtraia 4 horas no braco e dava Set-Date.
        #
        # Ela existia por um motivo unico: o servidor Zeus das filiais esta em
        # UTC-3 e as lojas de Mato Grosso em UTC-4, e o w_receb.exe do proprio
        # Zeus copiava a hora de parede do servidor para o terminal via
        # SetLocalTime - empurrando o caixa uma hora para a frente. A tarefa
        # desfazia isso. Duas correcoes erradas que davam um resultado certo.
        #
        # Isso foi resolvido na origem, fora deste script: o w_receb perdeu a
        # capacidade de escrever no relogio, com o privilegio removido apenas
        # daquele servico (sc privs no exec_pdv, so SeSystemtimePrivilege).
        # Com o fuso correto abaixo e o w32tm recebendo servidor e intervalo
        # por diretiva de dominio, nao sobra nada para esta etapa fazer alem
        # de garantir o fuso e limpar o mecanismo antigo.
        #
        # A tarefa ainda era nociva por si: um dos gatilhos dela era o proprio
        # evento "hora do sistema alterada", e ela alterava a hora - media no
        # CAIXA5232-LJ06 em 26/09/2026, 3032 execucoes num unico dia, uma a
        # cada 11 segundos. E cada execucao aceitava a resposta NTP sem
        # validar origem, camada, leap indicator nem Kiss-o'-Death: bastava
        # uma resposta torta para plantar data absurda e cancelar emissao de
        # nota. O w32tm faz todas essas conferencias; a tarefa nao fazia.
        # ------------------------------------------------------------------
        $fuso = $sync.Fuso
        if (-not $fuso) { Log "  filial $filial sem fuso na tabela - etapa ignorada" $CorAviso; return }

        $fusoAtual = (Get-TimeZone).Id
        if ($fusoAtual -eq $fuso) { Log "  fuso ja e $fuso" $CorOk }
        else {
            Set-TimeZone -Id $fuso
            Log "  fuso: $fusoAtual -> $fuso" $CorOk
        }

        # A fonte de tempo NAO e configurada aqui, de proposito: ela chega por
        # diretiva de dominio, e o que vem de diretiva tem precedencia sobre
        # configuracao local. Mexer no w32tm aqui e escrever o que nao vale.
        Log "  fonte de tempo (por diretiva): $(& w32tm /query /source 2>&1 | Select-Object -First 1)"
        Log ("  relogio: " + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))

        if (Get-ScheduledTask -TaskName "HoraCuiaba" -EA 0) {
            Unregister-ScheduledTask -TaskName "HoraCuiaba" -Confirm:$false
            Log "  tarefa HoraCuiaba removida" $CorOk
        }
        if (Test-Path "C:\Scripts\HoraCuiaba.ps1") {
            Remove-Item "C:\Scripts\HoraCuiaba.ps1" -Force
            Log "  script HoraCuiaba.ps1 removido" $CorOk
        }

        # ---------- acerto no boot ----------
        # Sobra um caso que nada mais cobre: terminal que liga com a hora fora
        # porque a bateria de CMOS morreu. O w32time tenta sincronizar no boot,
        # mas se a rede ainda nao subiu ele falha e so tenta de novo na
        # sondagem seguinte - que demora. Esta tarefa fecha essa janela.
        New-Item C:\Scripts -ItemType Directory -Force | Out-Null
        $acerto = "C:\Scripts\RelogioPDV.ps1"
        $corpo = @'
# ---------------------------------------------------------------------
# RelogioPDV.ps1 - acerta o relogio na inicializacao do terminal.
#
# So chama 'w32tm /resync'. Nao escreve a hora, nao calcula fuso, nao
# consulta NTP por conta propria. Quem valida o pacote - origem, camada,
# leap indicator, Kiss-o'-Death - e o w32tm. Foi a falta dessas
# conferencias, num Set-Date escrito a mao, que plantava data absurda.
#
# O UNICO gatilho e a inicializacao, e deve continuar assim. A tarefa
# anterior tinha gatilho no evento de mudanca de hora e ela propria mexia
# na hora: se realimentava, 3032 execucoes num dia, uma a cada 11s.
# ---------------------------------------------------------------------
$Log = 'C:\Scripts\RelogioPDV.log'
function Registrar ($t) {
    Add-Content -LiteralPath $Log -Encoding UTF8 -ErrorAction SilentlyContinue `
        -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $t)
}

Registrar ("boot - antes: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
if ((Get-Service w32time -EA 0).Status -ne 'Running') { Start-Service w32time -EA 0; Start-Sleep 5 }

# A insistencia e o ponto: no boot a rede raramente esta de pe na primeira
# tentativa, e sem repetir a tarefa falha justamente no caso que a motiva.
$ok = $false
foreach ($n in 1..10) {
    & w32tm /resync /rediscover 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $ok = $true; Registrar "resync ok na tentativa $n"; break }
    Start-Sleep 30
}
if (-not $ok) { Registrar "ATENCAO: nao sincronizou em 5 minutos" }

$fim = Get-Date
Registrar ("boot - depois: " + $fim.ToString('yyyy-MM-dd HH:mm:ss'))

# Se a data continua absurda depois do resync, nao e sincronismo: e bateria
# de CMOS ou alguma aplicacao escrevendo no relogio. Precisa de gente.
if ($fim.Year -lt 2025) { Registrar ("ATENCAO: data implausivel: " + $fim.ToString('yyyy-MM-dd')) }
'@
        Set-Content -LiteralPath $acerto -Value $corpo -Encoding UTF8

        Unregister-ScheduledTask -TaskName "RelogioPDV" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "RelogioPDV" `
            -Action (New-ScheduledTaskAction -Execute "powershell.exe" `
                     -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $acerto") `
            -Trigger (New-ScheduledTaskTrigger -AtStartup) `
            -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest) `
            -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                       -StartWhenAvailable -MultipleInstances IgnoreNew `
                       -ExecutionTimeLimit (New-TimeSpan -Minutes 15)) -Force | Out-Null
        Log "  tarefa RelogioPDV registrada (so na inicializacao)" $CorOk
        Log "  log: C:\Scripts\RelogioPDV.log"
    }}

    @{ Nome = "Privilegio de hora do exec_pdv"; Acao = {
        # ------------------------------------------------------------------
        # O w_receb.exe, do proprio Zeus, roda como LocalSystem sob o servico
        # exec_pdv (embrulhado pelo nssm) e escreve no relogio do terminal:
        # habilita o SeSystemtimePrivilege com AdjustTokenPrivileges e chama
        # SetLocalTime.
        #
        # Repare que e SetLocalTime, hora de parede, e nao SetSystemTime. Como
        # o servidor Zeus das filiais esta em UTC-3 e as lojas de Mato Grosso
        # em UTC-4, o efeito e empurrar o caixa uma hora para a frente. Foi
        # medido em campo no CAIXA5232-LJ06, uma a duas vezes por dia. Relogio
        # errado em PDV cancela emissao de nota.
        #
        # A correcao e tirar do servico a capacidade, nao pedir para ele parar.
        # Atribuicao de direitos (secpol ou GPO) NAO resolve: o token do
        # LocalSystem e montado pelo kernel e ja traz o privilegio, apenas
        # desabilitado. No mesmo terminal, o SeSystemtimePrivilege nem constava
        # na atribuicao da maquina e ainda assim o w_receb mudava a hora. O que
        # funciona e o privilegio exigido por servico: o SCM monta o token com
        # APENAS o que estiver na lista.
        #
        # A lista e lida do token em execucao, e nao fixada aqui de proposito:
        # o conjunto padrao do LocalSystem muda entre versoes do Windows, e
        # listar um privilegio que a conta nao possui impede o servico de subir.
        # ------------------------------------------------------------------
        $svc = Get-CimInstance Win32_Service -Filter "Name='exec_pdv'" -EA 0
        if (-not $svc) { Log "  servico exec_pdv nao existe neste terminal - etapa ignorada" $CorAviso; return }
        if ($svc.State -ne 'Running') {
            Start-Service exec_pdv -EA SilentlyContinue
            Start-Sleep -Seconds 6
            $svc = Get-CimInstance Win32_Service -Filter "Name='exec_pdv'"
        }
        if (-not $svc.ProcessId) { Log "  exec_pdv sem processo - nao da para ler o token" $CorErro; return }

        if (-not ('PrivToken' -as [type])) {
            Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Text;
public class PrivToken {
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint a, bool i, int p);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, uint a, out IntPtr t);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr t, int c, IntPtr b, int l, out int r);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool LookupPrivilegeName(string s, ref LUID l, StringBuilder n, ref int len);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
  [StructLayout(LayoutKind.Sequential)] struct LAA { public LUID Luid; public uint Attr; }
  public static string[] Ler(int pid) {
    IntPtr hp = OpenProcess(0x1000, false, pid);
    if (hp == IntPtr.Zero) throw new Exception("OpenProcess " + Marshal.GetLastWin32Error());
    IntPtr ht;
    if (!OpenProcessToken(hp, 0x0008, out ht)) throw new Exception("OpenProcessToken " + Marshal.GetLastWin32Error());
    int len = 0; GetTokenInformation(ht, 3, IntPtr.Zero, 0, out len);
    IntPtr buf = Marshal.AllocHGlobal(len);
    if (!GetTokenInformation(ht, 3, buf, len, out len)) throw new Exception("GetTokenInformation");
    int n = Marshal.ReadInt32(buf); string[] r = new string[n];
    long q = buf.ToInt64() + 4; int sz = Marshal.SizeOf(typeof(LAA));
    for (int i = 0; i < n; i++) {
      LAA la = (LAA)Marshal.PtrToStructure(new IntPtr(q + i*sz), typeof(LAA));
      StringBuilder sb = new StringBuilder(256); int l = 256;
      LookupPrivilegeName(null, ref la.Luid, sb, ref l); r[i] = sb.ToString();
    }
    Marshal.FreeHGlobal(buf); CloseHandle(ht); CloseHandle(hp); return r;
  }
}
"@
        }

        $token = @([PrivToken]::Ler([int]$svc.ProcessId))
        Log "  token do servico: $($token.Count) privilegios"
        if ($token -notcontains 'SeSystemtimePrivilege') {
            Log "  SeSystemtimePrivilege ja fora do token - nada a fazer" $CorOk
            return
        }

        $manter = @($token | Where-Object { $_ -ne 'SeSystemtimePrivilege' } | Sort-Object)
        & sc.exe privs exec_pdv ($manter -join '/') | Out-Null
        if ($LASTEXITCODE -ne 0) { Log "  sc privs falhou (codigo $LASTEXITCODE)" $CorErro; return }
        Log "  $($manter.Count) privilegios exigidos gravados, sem o de hora" $CorOk

        Restart-Service exec_pdv -Force -EA SilentlyContinue
        Start-Sleep -Seconds 12

        $subiu = ((Get-Service exec_pdv).Status -eq 'Running') -and [bool](Get-Process w_receb -EA 0)
        if ($subiu) {
            Log "  exec_pdv e w_receb no ar sem poder escrever no relogio" $CorOk
        } else {
            # Nao voltou: desfaz na hora. PDV fora do ar e pior que relogio errado.
            & cmd.exe /c 'sc privs exec_pdv ""' | Out-Null
            Restart-Service exec_pdv -Force -EA SilentlyContinue
            Start-Sleep -Seconds 12
            Log "  exec_pdv NAO subiu com a restricao - revertido" $CorErro
            Log "  estado apos reverter: $((Get-Service exec_pdv).Status)" $CorAviso
        }
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

    @{ Nome = "Plano de energia"; Acao = {
        # Tela apaga em 30 min; a maquina nunca suspende, hiberna ou desliga disco.
        $ajustes = @(
            @{ c='monitor-timeout-ac';   v=30; t='tela (tomada): 30 min' }
            @{ c='monitor-timeout-dc';   v=30; t='tela (bateria): 30 min' }
            @{ c='standby-timeout-ac';   v=0;  t='suspensao (tomada): nunca' }
            @{ c='standby-timeout-dc';   v=0;  t='suspensao (bateria): nunca' }
            @{ c='hibernate-timeout-ac'; v=0;  t='hibernacao (tomada): nunca' }
            @{ c='hibernate-timeout-dc'; v=0;  t='hibernacao (bateria): nunca' }
            @{ c='disk-timeout-ac';      v=0;  t='disco (tomada): nunca' }
            @{ c='disk-timeout-dc';      v=0;  t='disco (bateria): nunca' }
        )
        foreach ($a in $ajustes) {
            powercfg.exe /change $a.c $a.v 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Log ("  " + $a.t) $CorOk }
            else { Log ("  falhou: " + $a.c + " (powercfg $LASTEXITCODE)") $CorAviso }
        }
        # Botao de energia e tampa nao podem suspender um PDV
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 2>&1 | Out-Null
        powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 2>&1 | Out-Null
        powercfg.exe /setactive SCHEME_CURRENT 2>&1 | Out-Null
        Log "  tampa e botao de energia nao suspendem" $CorOk
    }}

    @{ Nome = "Nome do computador"; Acao = {
        # A ordem e proposital e nao deve ser "corrigida": o rename fica
        # pendente e so vale no reboot do fim, enquanto o ingresso no dominio
        # acontece varias etapas depois, ainda com o nome antigo ativo. E a
        # rede de protecao para quando algo falha no meio da instalacao - o
        # terminal segue alcancavel pelo nome que sempre teve, ate o fim.
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

        # UltraVNC: so detecta, NUNCA instala. O instalador nem sempre usa a
        # pasta "uvnc bvba" - em campo aparece tambem so "uvnc".
        $uvncExe = @(
            "C:\Program Files\uvnc bvba\UltraVNC\winvnc.exe"
            "C:\Program Files\uvnc\UltraVNC\winvnc.exe"
            "C:\Program Files\UltraVNC\winvnc.exe"
            "C:\Program Files (x86)\uvnc bvba\UltraVNC\winvnc.exe"
            "C:\Program Files (x86)\uvnc\UltraVNC\winvnc.exe"
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($uvncExe) { Marcar-Presente 'uvnc' 'UltraVNC' }
        else { Log ("  {0,-14} ausente (instalacao manual, fora do escopo)" -f 'UltraVNC') $CorAviso }

        if (Test-Nome "7-Zip*")             { Marcar-Presente '7zip'       '7-Zip' }
        if (Test-Chrome)                    { Marcar-Presente 'chrome'     'Chrome' }
        if (Test-Nome "Amazon Corretto*8*") { Marcar-Presente 'corretto'   'Corretto 8' }
        if (Test-Nome "*ONLYOFFICE*")       { Marcar-Presente 'onlyoffice' 'ONLYOFFICE' }
        if (Test-Nome "*Lightshot*")        { Marcar-Presente 'lightshot'  'Lightshot' }
        if (Test-Nome "Notepad++*")         { Marcar-Presente 'notepadpp'  'Notepad++' }
        if (Test-Nome "*Sumatra*")          { Marcar-Presente 'sumatra'    'SumatraPDF' }
        if (Test-Nome "VLC media player*")  { Marcar-Presente 'vlc'        'VLC' }
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
        )
        foreach ($p in $fila) {
            if (Falta $p.id) { Winget-Instala $p.wid $p.rot $p.ex }
        }

        if (Falta 'vcredist') {
            foreach ($v in 'Microsoft.VCRedist.2005.x86','Microsoft.VCRedist.2005.x64',
                           'Microsoft.VCRedist.2008.x86','Microsoft.VCRedist.2008.x64',
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
        if (Falta 'gonnect') {
            # Nao existe no winget: pega a ultima release do GitHub que tenha asset win64.
            $exeGonnect = "C:\Program Files\GOnnect\bin\gonnect.exe"
            if (Test-Path -LiteralPath $exeGonnect) { Log "  GOnnect ja presente em disco" $CorOk }
            else {
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    $cab = @{ 'User-Agent' = 'Machadao-Instalador' }
                    Log "  GOnnect: procurando release com instalador win64..."
                    $releases = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop -Headers $cab `
                        -Uri "https://api.github.com/repos/gonicus/gonnect/releases?per_page=100"

                    $asset = $null; $tag = $null
                    foreach ($rel in $releases) {
                        $ach = $rel.assets | Where-Object { $_.name -like "*win64*.exe" } | Select-Object -First 1
                        if ($ach) { $asset = $ach; $tag = $rel.tag_name; break }
                    }
                    if (-not $asset) { throw "nenhuma das $($releases.Count) releases tem instalador win64" }

                    Log "  GOnnect: versao $tag"
                    $dest = "$env:TEMP\$($asset.name)"
                    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest `
                        -UseBasicParsing -Headers $cab -ErrorAction Stop
                    Start-Process -FilePath $dest -ArgumentList "/S" -Wait -WindowStyle Hidden
                    Remove-Item $dest -Force -EA 0

                    if (-not (Test-Path -LiteralPath $exeGonnect)) { throw "executavel nao apareceu em $exeGonnect" }

                    $ws = New-Object -ComObject WScript.Shell
                    $g1 = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('CommonStartup')) "GOnnect.lnk"))
                    $g1.TargetPath = $exeGonnect; $g1.Save()
                    $g2 = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) "GOnnect.lnk"))
                    $g2.TargetPath = $exeGonnect; $g2.Save()
                    Log "  GOnnect $tag instalado, com atalho e inicializacao automatica" $CorOk
                    Log "  o ramal sera pedido no proximo login do usuario" $CorInfo
                }
                catch { Log "  GOnnect falhou: $($_.Exception.Message)" $CorErro }
            }
        }

        Log "  fila de pacotes concluida" $CorOk
    }}

    @{ Nome = "UltraVNC como servico"; Acao = {
        # O UltraVNC precisa ser SERVICO, nao atalho de inicializacao. Como
        # atalho ele so sobe quando alguem faz logon - e este script tira o
        # autologon e desativa PDV e pdvkiosk, entao ninguem loga e o acesso
        # remoto morre junto com o resto da inicializacao.
        $exe = @(
            "C:\Program Files\uvnc bvba\UltraVNC\winvnc.exe"
            "C:\Program Files\uvnc\UltraVNC\winvnc.exe"
            "C:\Program Files\UltraVNC\winvnc.exe"
            "C:\Program Files (x86)\uvnc bvba\UltraVNC\winvnc.exe"
            "C:\Program Files (x86)\uvnc\UltraVNC\winvnc.exe"
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

        if (-not $exe) { Log "  UltraVNC nao instalado - instalacao manual, fora do escopo" $CorAviso; return }
        Log "  binario: $exe"

        # O ini e procurado so para registrar no log onde esta a configuracao.
        # A senha do VNC NAO e definida por este script: ela vem de outro
        # processo de provisionamento, junto com a instalacao do UltraVNC.
        # Nao achar o ini nestes caminhos nao significa servico sem senha.
        $ini = @(
            "C:\ProgramData\UltraVNC\ultravnc.ini"
            (Join-Path (Split-Path $exe -Parent) 'ultravnc.ini')
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($ini) { Log "  configuracao: $ini" }
        else { Log "  ultravnc.ini fora dos caminhos conhecidos - a senha vem de outro processo" }

        $svc = Get-Service -Name 'uvnc_service' -EA 0
        if (-not $svc) { $svc = Get-Service -EA 0 | Where-Object { $_.Name -match 'vnc' } | Select-Object -First 1 }

        if ($svc) { Log "  servico $($svc.Name) ja registrado" }
        else {
            Log "  nenhum servico de VNC - registrando..."
            & $exe -install
            Start-Sleep -Seconds 4
            $svc = Get-Service -Name 'uvnc_service' -EA 0
            if (-not $svc) { Log "  falhou: o servico nao foi criado" $CorErro; return }
            Log "  servico uvnc_service criado" $CorOk
        }

        Set-Service -Name $svc.Name -StartupType Automatic -EA 0
        if ((Get-Service -Name $svc.Name).Status -ne 'Running') { Start-Service -Name $svc.Name -EA 0 }

        # O servico roda na sessao 0 e lanca um helper na sessao do console;
        # e o helper que abre as portas, alguns segundos depois.
        $escutando = $false
        foreach ($tentativa in 1..10) {
            Start-Sleep -Seconds 2
            if (Get-NetTCPConnection -LocalPort 5900 -State Listen -EA 0) { $escutando = $true; break }
        }
        if ($escutando) { Log "  servico ativo, escutando na porta 5900" $CorOk }
        else { Log "  servico rodando mas nada escuta a 5900 - conferir o ultravnc.ini" $CorAviso }

        # Com o servico no ar, o atalho da inicializacao dispara um segundo
        # winvnc na sessao do usuario e bate de frente com ele.
        $lnk = Join-Path ([Environment]::GetFolderPath('CommonStartup')) 'UltraVNC Server.lnk'
        if (Test-Path -LiteralPath $lnk) {
            Remove-Item -LiteralPath $lnk -Force
            Log "  atalho 'UltraVNC Server' removido da inicializacao - o servico cobre isso" $CorOk
        }
    }}

    @{ Nome = "Epson TM-T20X"; Acao = {
        # ------------------------------------------------------------------
        # Conteudo do script original, verbatim. Unica adaptacao: o param()
        # virou variaveis (param() so vale no topo de um arquivo) e o
        # Write-Log espelha no painel alem de gravar no instalacao.log.
        #
        # ATENCAO - ISTO NAO E UM BUG, NAO "CONSERTE"
        #
        # A impressora fiscal destes terminais e uma TM-T20X-II
        # (USB\VID_04B8&PID_0202), mas o utilitario instalado aqui e o do
        # TM-T88V, de proposito: $BASE aponta para a pasta tm-t88v e
        # $EXE_UTIL e o TM-T88VUtility170.exe.
        #
        # Existe uma pasta tm-t20X-ii ao lado, com TM-T20X-IIUtility100.exe,
        # que NAO e usada. O criterio da escolha foi simplicidade e, acima de
        # tudo, funcionar: este caminho esta validado em campo.
        #
        # Trocar para a pasta tm-t20X-ii nao e so mudar $BASE. O setup.iss
        # nao vem no pacote nem e extraido - e gerado logo abaixo, pela
        # New-SetupIss, e o conteudo hardcoded la e o response file do
        # InstallShield do T88V ([Application] Name=EPSON TM-T88V Utility
        # Ver.1.70, GUID {DDA36F98-...}). Response file casa por GUID de
        # dialogo, entao ele nao serve para o instalador do T20X-II: seria
        # preciso gravar um novo com
        #     TM-T20X-IIUtility100.exe /r /f1"setup.iss"
        # percorrendo o wizard uma vez, e so entao trocar o caminho.
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

        # Response file do InstallShield do TM-T88V - ver a nota no topo desta
        # etapa antes de mexer. O GUID e o bloco [Application] abaixo sao do
        # T88V e nao valem para o instalador do T20X-II.
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

        Write-Log '=== INICIO - Epson: impressora TM-T20X-II, utilitario T88V ==='

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

        # Mesma origem do InstalaWindows.ps1: o pacote vive no Google Drive. O
        # endpoint drive.usercontent devolve o arquivo direto; o antigo
        # (drive.google.com/uc) passou a servir pagina de aviso em vez do .7z.
        $GDriveId  = "1YJC2UHbEAAihMMqgS980WbLZe7q4AQ7S"
        $GDriveUrl = "https://drive.usercontent.google.com/download?id=$GDriveId&export=download&confirm=t"

        if (-not (Test-Path -LiteralPath $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }

        function Get-GDriveVersao ($Url) {
            $req = [System.Net.HttpWebRequest]::Create($Url); $req.Method = "HEAD"
            $resp = $req.GetResponse()
            try { "$($resp.ContentLength)|$($resp.Headers['Last-Modified'])" } finally { $resp.Close() }
        }
        function Get-GDriveArquivo ($Url, $Destino) {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $resp = $req.GetResponse()
            $total = $resp.ContentLength
            $ent = $resp.GetResponseStream(); $sai = [System.IO.File]::Create($Destino)
            $buf = New-Object byte[] 65536; $lidoTotal = 0
            $rel = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                while (($n = $ent.Read($buf, 0, $buf.Length)) -gt 0) {
                    $sai.Write($buf, 0, $n); $lidoTotal += $n
                    if ($rel.ElapsedMilliseconds -gt 2000) {
                        $mb = [math]::Round($lidoTotal / 1MB, 1)
                        if ($total -gt 0) {
                            Log ("  baixando drivers... {0}% ({1} MB de {2} MB)" -f `
                                 [math]::Round(($lidoTotal / $total) * 100), $mb, [math]::Round($total / 1MB, 1))
                        } else { Log "  baixando drivers... $mb MB" }
                        $rel.Restart()
                    }
                }
            } finally { $sai.Close(); $ent.Close(); $resp.Close() }
        }

        # Cache local x pacote remoto: sem isso, uma vez extraido em C:\KyoceraDrivers
        # o pacote nunca era atualizado, mesmo trocado por um mais novo no Drive.
        $Marcador = Join-Path $TempDir ".pacote-versao"
        $versaoRemota = $null
        try {
            $versaoRemota = Get-GDriveVersao $GDriveUrl
            $versaoLocal = if (Test-Path -LiteralPath $Marcador) { Get-Content -LiteralPath $Marcador -Raw -EA 0 } else { $null }
            if ($versaoLocal -and $versaoLocal.Trim() -ne $versaoRemota) {
                Log "  pacote mudou no Google Drive - limpando cache local" $CorAviso
                Get-ChildItem -LiteralPath $TempDir -Force | Remove-Item -Recurse -Force -EA 0
            }
        } catch { Log "  nao deu para checar a versao do pacote - usando cache local" $CorAviso }

        $InfFiles = @(Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse -EA 0)
        if ($InfFiles.Count -eq 0) {
            if (-not (Test-Path -LiteralPath $ZipPath)) {
                Log "  baixando drivers Kyocera do Google Drive..."
                try { Get-GDriveArquivo $GDriveUrl $ZipPath }
                catch {
                    Remove-Item -LiteralPath $ZipPath -Force -EA 0
                    Log "  falha no download: $($_.Exception.Message)" $CorErro; return
                }
            } else { Log "  pacote ja existe localmente" }

            $sete = "C:\Program Files\7-Zip\7z.exe"
            if (-not (Test-Path -LiteralPath $sete)) { Log "  7-Zip nao instalado - nao da para extrair" $CorErro; return }
            Log "  extraindo com 7-Zip..."
            & $sete x $ZipPath "-o$TempDir" -y | Out-Null
            if ($LASTEXITCODE -ne 0) { Log "  7-Zip retornou $LASTEXITCODE" $CorErro; return }

            $InfFiles = @(Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse)
            if ($versaoRemota) { Set-Content -LiteralPath $Marcador -Value $versaoRemota -Force }
        } else { Log "  drivers ja extraidos em $TempDir" }

        if ($InfFiles.Count -eq 0) { Log "  nenhum OEMSETUP.INF apos a extracao" $CorErro; return }

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

        # O instalador e servido por HTTP simples de um servidor interno da
        # rede Machadao, e e assim de proposito. Nao trocar por HTTPS nem
        # travar a etapa por conferencia de hash.
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

    @{ Nome = "Bloqueio dos usuarios locais e logon automatico"; Acao = {
        # O script roda no usuario zanthus, entao nenhuma das duas contas esta em uso.
        foreach ($conta in 'PDV', 'pdvkiosk') {
            if (Get-LocalUser -Name $conta -EA 0) {
                Disable-LocalUser -Name $conta -EA 0
                Log "  usuario local $conta desabilitado" $CorOk
            } else { Log "  usuario local $conta nao existe - ignorado" }
        }
        $wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $wl -Name "AutoAdminLogon" -Value "0"
        Set-ItemProperty -Path $wl -Name "DefaultUserName" -Value ""
        Remove-ItemProperty -Path $wl -Name "DefaultPassword" -EA 0
        Log "  logon automatico desativado" $CorOk
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

    @{ Nome = "SSH: bloqueia o usuario local zanthus"; Acao = {
        # Ultima etapa de proposito: so faz sentido depois do ingresso no dominio.
        #
        # DenyUsers bloqueia a CONTA, nao o metodo - chave e senha caem junto.
        # Por isso a trava abaixo: num terminal fora do dominio isso deixaria o
        # PDV sem nenhum caminho de SSH, porque nao haveria conta AD no lugar.
        #
        # E NAO usamos 'PasswordAuthentication no': ele derrubaria a senha de
        # TODAS as contas, inclusive as do AD, que e justamente como se entra
        # na maquina depois do ingresso.
        $cs = Get-CimInstance Win32_ComputerSystem
        if (-not $cs.PartOfDomain) {
            Log "  maquina fora do dominio - etapa ignorada" $CorAviso
            Log "  (bloquear o zanthus agora deixaria o terminal sem SSH nenhum)" $CorAviso
            return
        }
        if (-not (Get-Service sshd -EA 0)) { Log "  sshd nao instalado - nada a fazer"; return }

        $cfg = 'C:\ProgramData\ssh\sshd_config'
        if (-not (Test-Path $cfg)) { Log "  sshd_config nao encontrado" $CorAviso; return }

        $linhas = @(Get-Content $cfg)
        if ($linhas | Where-Object { $_ -match '^\s*DenyUsers\b.*\bzanthus\b' }) {
            Log "  zanthus ja bloqueado no sshd_config - ignorado" $CorOk
            return
        }

        # A diretiva TEM que ficar antes do primeiro bloco Match. Depois dele
        # ela vira uma opcao por-Match: o 'sshd -t' aceita, mas o 'sshd -T'
        # mostra denyusers vazio no escopo global e o bloqueio so vale dentro
        # daquele Match. Testado nesta build (OpenSSH 10.0p2 for Windows).
        $primeiroMatch = ($linhas | Select-String -Pattern '^\s*Match\b' | Select-Object -First 1).LineNumber
        if ($primeiroMatch) {
            $novas = @($linhas[0..($primeiroMatch - 2)]) + 'DenyUsers zanthus' +
                     @($linhas[($primeiroMatch - 1)..($linhas.Count - 1)])
        } else {
            $novas = @($linhas) + 'DenyUsers zanthus'
        }

        # Valida antes de aplicar: config quebrado aqui derruba o sshd e o
        # acesso remoto junto.
        $teste = "$env:TEMP\sshd_config.teste"
        [System.IO.File]::WriteAllLines($teste, $novas, (New-Object System.Text.ASCIIEncoding))
        $saida = (& 'C:\Program Files\OpenSSH\sshd.exe' -t -f $teste) 2>&1
        if ($LASTEXITCODE -ne 0) {
            Log "  config recusado pelo sshd -t, nada alterado: $saida" $CorErro
            Remove-Item $teste -Force -EA 0
            return
        }

        Copy-Item $cfg "$cfg.bak" -Force
        [System.IO.File]::WriteAllLines($cfg, $novas, (New-Object System.Text.ASCIIEncoding))
        Remove-Item $teste -Force -EA 0
        Restart-Service sshd -Force

        $efetivo = (& 'C:\Program Files\OpenSSH\sshd.exe' -T) 2>&1 |
                   Where-Object { $_ -match '^denyusers\b' }
        if ($efetivo -match 'zanthus') {
            Log "  usuario local zanthus bloqueado no SSH" $CorOk
            Log "  contas do dominio seguem entrando normalmente" $CorOk
        } else {
            Log "  aplicado, mas o sshd -T nao confirmou o bloqueio - conferir $cfg" $CorAviso
        }
        Log "  backup do config em $cfg.bak"
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
