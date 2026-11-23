<#
.SYNOPSIS
    Windows Presentation Foundation (WPF) Graphical User Interface for Windows Toolbox.
    100% standalone, zero external dependencies. Discovers and runs all toolbox scripts.
#>
[CmdletBinding()]
param(
    [switch]$Elevate
)

# ----------------- Dynamic Repository Root -----------------
$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot }
            elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
            else { (Get-Location).Path }

# ----------------- Elevation Detection -----------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Elevate -and -not $isAdmin) {
    try {
        Start-Process powershell.exe -Verb RunAs -WorkingDirectory "$RepoRoot" -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`""
        )
        exit 0
    } catch {
        Write-Warning "Elevation request was cancelled."
    }
}

# ----------------- Load WPF Assemblies -----------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ----------------- Category Color Map -----------------
$CategoryColors = @{
    'Backup'      = '#0284C7' # Sky blue
    'Dev'         = '#8B5CF6' # Purple
    'Gaming'      = '#10B981' # Emerald green
    'Maintenance' = '#F59E0B' # Amber
    'Network'     = '#06B6D4' # Cyan
    'Security'    = '#EF4444' # Red
    'Utilities'   = '#6366F1' # Indigo
    'General'     = '#71717A' # Zinc
}

# ----------------- Script Metadata Parser -----------------
function Get-AllToolboxMetadata {
    $scriptsDir = Join-Path $RepoRoot 'Scripts'
    if (-not (Test-Path $scriptsDir)) { $scriptsDir = $RepoRoot }

    $files = @(Get-ChildItem -Path $scriptsDir -Filter *.ps1 -File -Recurse |
        Where-Object { $_.FullName -ne $PSCommandPath -and $_.Name -notmatch '^(launch|launch-gui|Script-Launcher|Toolbox-GUI)\.ps1$' } |
        Sort-Object FullName)

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue

        $synopsis = "No description provided."
        if ($content -match '(?ms)\.SYNOPSIS\s*\r?\n\s*(.*?)(?=\r?\n\s*\.[A-Z]+|\r?\n\s*#>)') {
            $synopsis = ($Matches[1] -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' '
        }

        $examples = @()
        if ($content -match '(?ms)\.EXAMPLES?\s*\r?\n\s*(.*?)(?=\r?\n\s*\.[A-Z]+|\r?\n\s*#>)') {
            $examples = @($Matches[1] -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        $rel = $file.FullName.Substring($scriptsDir.Length).TrimStart('\', '/')
        $parts = $rel -split '[\\/]'
        $category = if ($parts.Length -gt 1) { $parts[0] } else { 'General' }
        $color = if ($CategoryColors.ContainsKey($category)) { $CategoryColors[$category] } else { '#71717A' }

        # Parse parameters via AST
        $parameters = [System.Collections.Generic.List[PSCustomObject]]::new()
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            if ($ast.ParamBlock -and $ast.ParamBlock.Parameters) {
                foreach ($p in $ast.ParamBlock.Parameters) {
                    $pName = $p.Name.VariablePath.UserPath
                    $pType = if ($p.StaticType) { $p.StaticType.Name } else { 'Object' }
                    $isSwitch = ($pType -eq 'SwitchParameter')
                    $validValues = @()
                    foreach ($attr in $p.Attributes) {
                        if ($attr.TypeName.Name -like '*ValidateSet*') {
                            $validValues = @($attr.PositionalArguments | ForEach-Object { $_.Value } | Where-Object { $_ })
                        }
                    }
                    $defaultVal = if ($p.DefaultValue) { $p.DefaultValue.Extent.Text } else { '' }

                    $parameters.Add([PSCustomObject]@{
                        Name         = $pName
                        Type         = $pType
                        IsSwitch     = $isSwitch
                        ValidValues  = $validValues
                        DefaultValue = $defaultVal
                    })
                }
            }
        } catch { }

        $results.Add([PSCustomObject]@{
            File        = $file
            Name        = $file.Name
            FullName    = $file.FullName
            Category    = $category
            Color       = $color
            Synopsis    = $synopsis
            Examples    = $examples
            Parameters  = $parameters
        })
    }
    return $results
}

# ----------------- XAML Interface Definition -----------------
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Toolbox - Control Center"
        Height="800" Width="1200" MinHeight="620" MinWidth="950"
        WindowStartupLocation="CenterScreen"
        Background="#121214" Foreground="#E4E4E7"
        FontFamily="Segoe UI, Segoe UI Variable, sans-serif">
    
    <Window.Resources>
        <!-- Modern ScrollViewer style -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="#18181B"/>
            <Setter Property="Width" Value="8"/>
        </Style>

        <!-- Base Button Template -->
        <Style x:Key="RoundedButton" TargetType="Button">
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="Border" Background="{TemplateBinding Background}"
                                CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Border" Property="Opacity" Value="0.75"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Border" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource RoundedButton}">
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource RoundedButton}">
            <Setter Property="Background" Value="#27272A"/>
            <Setter Property="Padding" Value="12,6"/>
        </Style>

        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource RoundedButton}">
            <Setter Property="Background" Value="#10B981"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Header -->
            <RowDefinition Height="Auto"/> <!-- Admin Warning Banner if not elevated -->
            <RowDefinition Height="*"/>    <!-- Main Body: Sidebar + Script View + Detail Pane -->
            <RowDefinition Height="Auto"/> <!-- Bottom Status Bar -->
        </Grid.RowDefinitions>

        <!-- [ TOP HEADER ] -->
        <Border Grid.Row="0" Background="#18181B" BorderBrush="#27272A" BorderThickness="0,0,0,1" Padding="20,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- App Title -->
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="&#x26A1;" FontSize="22" Margin="0,0,10,0" VerticalAlignment="Center"/>
                    <StackPanel>
                        <TextBlock Text="Windows Toolbox" FontSize="18" FontWeight="Bold" Foreground="#FFFFFF"/>
                        <TextBlock Text="PowerShell Automation &amp; System Suite" FontSize="11" Foreground="#A1A1AA"/>
                    </StackPanel>
                </StackPanel>

                <!-- Global Search Box -->
                <Border Grid.Column="1" Background="#27272A" CornerRadius="6" Margin="40,0" Padding="10,6" MaxWidth="500">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="&#x1F50D;" FontSize="13" Foreground="#A1A1AA" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBox Name="TxtSearch" Grid.Column="1" Background="Transparent" BorderThickness="0"
                                 Foreground="#FFFFFF" FontSize="13" VerticalAlignment="Center"
                                 ToolTip="Filter scripts by name, category, or description..."/>
                        <Button Name="BtnClearSearch" Grid.Column="2" Content="&#x2715;" Background="Transparent"
                                BorderThickness="0" Foreground="#A1A1AA" Cursor="Hand" Padding="4,0" ToolTip="Clear search"/>
                    </Grid>
                </Border>

                <!-- Status Badges &amp; Quick Links -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Name="BadgeAdmin" Background="#064E3B" CornerRadius="12" Padding="10,4" Margin="0,0,10,0">
                        <TextBlock Name="TxtAdminStatus" Text="&#x1F6E1; Administrator" FontSize="12" FontWeight="SemiBold" Foreground="#34D399"/>
                    </Border>
                    <Button Name="BtnRefresh" Content="&#x1F504; Refresh" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                    <Button Name="BtnTerminalMenu" Content="&#x1F5A5; CLI Launcher" Style="{StaticResource SecondaryButton}"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- [ NOT ADMIN BANNER (IF NOT ELEVATED) ] -->
        <Border Name="BannerElevate" Grid.Row="1" Background="#78350F" BorderBrush="#B45309" BorderThickness="0,0,0,1"
                Padding="16,8" Visibility="Collapsed">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="&#x26A0;" FontSize="14" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Text="Running as Standard User. Tools like Defender, Windows Update, Health Check and Hosts require elevation."
                               FontSize="12" Foreground="#FEF3C7" VerticalAlignment="Center"/>
                </StackPanel>
                <Button Name="BtnElevateNow" Grid.Column="1" Content="&#x1F6E1; Relaunch as Admin"
                        Background="#D97706" Foreground="#FFFFFF" FontWeight="SemiBold"
                        Style="{StaticResource RoundedButton}" Padding="12,5"/>
            </Grid>
        </Border>

        <!-- [ MAIN BODY ] -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="220"/> <!-- Category Sidebar -->
                <ColumnDefinition Width="*"/>   <!-- Script Cards Grid -->
                <ColumnDefinition Width="380"/> <!-- Configuration &amp; Console Drawer -->
            </Grid.ColumnDefinitions>

            <!-- [ SIDEBAR CATEGORIES ] -->
            <Border Grid.Column="0" Background="#18181B" BorderBrush="#27272A" BorderThickness="0,0,1,0" Padding="12,16">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Grid.Row="0" Text="CATEGORIES" FontSize="11" FontWeight="Bold" Foreground="#71717A" Margin="8,0,0,12"/>

                    <!-- Category Items Container -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="PnlCategoryList">
                            <!-- Populated dynamically -->
                        </StackPanel>
                    </ScrollViewer>

                    <!-- System Info Footer -->
                    <Border Grid.Row="2" Background="#27272A" CornerRadius="6" Padding="10,8" Margin="0,10,0,0">
                        <StackPanel>
                            <TextBlock Name="TxtSystemDrive" Text="Drive C: Calculating..." FontSize="11" Foreground="#A1A1AA"/>
                            <TextBlock Name="TxtPsVersion" Text="PS Version..." FontSize="11" Foreground="#71717A" Margin="0,2,0,0"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </Border>

            <!-- [ CENTER SCRIPT CARDS ] -->
            <Grid Grid.Column="1" Background="#121214">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Section Header -->
                <Border Grid.Row="0" Padding="20,16,20,10">
                    <Grid>
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Name="TxtActiveCategory" Text="All Tools" FontSize="16" FontWeight="Bold" Foreground="#FFFFFF"/>
                            <TextBlock Name="TxtScriptCount" Text=" (27 tools)" FontSize="14" Foreground="#71717A" Margin="6,2,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- Script Cards ScrollViewer -->
                <ScrollViewer Grid.Row="1" Padding="14,0,14,14" VerticalScrollBarVisibility="Auto">
                    <StackPanel Name="PnlScriptCards">
                        <!-- Dynamic Script Cards inserted here -->
                    </StackPanel>
                </ScrollViewer>
            </Grid>

            <!-- [ RIGHT CONFIGURATION &amp; CONSOLE DRAWER ] -->
            <Border Grid.Column="2" Background="#18181B" BorderBrush="#27272A" BorderThickness="1,0,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>    <!-- Script Details &amp; Parameter Editor -->
                        <RowDefinition Height="280"/>  <!-- Live Console Output -->
                    </Grid.RowDefinitions>

                    <!-- Script Details &amp; Parameters -->
                    <ScrollViewer Grid.Row="0" Padding="18" VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="PnlDetailContainer">
                            <!-- Header Info -->
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                                <Border Name="BadgeDetailCat" Background="#0284C7" CornerRadius="4" Padding="6,2" Margin="0,0,8,0">
                                    <TextBlock Name="TxtDetailCat" Text="CATEGORY" FontSize="10" FontWeight="Bold" Foreground="#FFFFFF"/>
                                </Border>
                                <TextBlock Name="TxtDetailPath" Text="Scripts/..." FontSize="11" Foreground="#71717A" VerticalAlignment="Center"/>
                            </StackPanel>

                            <TextBlock Name="TxtDetailName" Text="Select a script" FontSize="18" FontWeight="Bold" Foreground="#FFFFFF" Margin="0,0,0,8"/>
                            <TextBlock Name="TxtDetailDesc" Text="Click on any script card on the left to configure arguments and launch it."
                                       TextWrapping="Wrap" FontSize="12" Foreground="#A1A1AA" Margin="0,0,0,16"/>

                            <Separator Background="#27272A" Margin="0,0,0,16"/>

                            <!-- Parameters Section -->
                            <TextBlock Text="PARAMETERS &amp; OPTIONS" FontSize="11" FontWeight="Bold" Foreground="#71717A" Margin="0,0,0,10"/>
                            <StackPanel Name="PnlDynamicParams">
                                <TextBlock Text="No script selected." Foreground="#71717A" FontSize="12"/>
                            </StackPanel>

                            <!-- Command Line Preview -->
                            <TextBlock Text="COMMAND PREVIEW" FontSize="11" FontWeight="Bold" Foreground="#71717A" Margin="0,16,0,6"/>
                            <Border Background="#27272A" CornerRadius="6" Padding="8,6">
                                <TextBox Name="TxtCommandPreview" Background="Transparent" BorderThickness="0"
                                         Foreground="#38BDF8" FontFamily="Consolas, monospace" FontSize="11"
                                         IsReadOnly="True" TextWrapping="Wrap"/>
                            </Border>

                            <!-- Launch Buttons -->
                            <Grid Margin="0,18,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Button Name="BtnRunTerminal" Grid.Column="0" Content="&#x25B6; Run in Terminal"
                                        Style="{StaticResource PrimaryButton}" Margin="0,0,6,0"
                                        ToolTip="Recommended for scripts with interactive prompts (runs in admin PowerShell window)"/>
                                <Button Name="BtnRunDirect" Grid.Column="1" Content="&#x26A1; Run Direct"
                                        Style="{StaticResource SuccessButton}" Margin="6,0,0,0"
                                        ToolTip="Runs in background and streams output into the console below"/>
                            </Grid>
                        </StackPanel>
                    </ScrollViewer>

                    <!-- Live Console Output Panel -->
                    <Border Grid.Row="1" Background="#0E0E10" BorderBrush="#27272A" BorderThickness="0,1,0,0" Padding="14,10">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <Grid Grid.Row="0" Margin="0,0,0,6">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Text="CONSOLE LOG" FontSize="11" FontWeight="Bold" Foreground="#71717A"/>
                                    <TextBlock Name="TxtConsoleStatus" Text=" &#x2022; Ready" FontSize="11" Foreground="#34D399" Margin="6,0,0,0"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button Name="BtnClearConsole" Content="Clear" Style="{StaticResource SecondaryButton}" Padding="8,2" FontSize="10" Margin="0,0,6,0"/>
                                    <Button Name="BtnCopyConsole" Content="Copy" Style="{StaticResource SecondaryButton}" Padding="8,2" FontSize="10"/>
                                </StackPanel>
                            </Grid>

                            <TextBox Name="TxtConsoleLog" Grid.Row="1" Background="#0E0E10" BorderThickness="0"
                                     Foreground="#D4D4D8" FontFamily="Consolas, Cascadia Code, monospace" FontSize="11"
                                     IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                                     Text="[Windows Toolbox Ready] Select a script above and click Run."/>
                        </Grid>
                    </Border>
                </Grid>
            </Border>
        </Grid>

        <!-- [ STATUS BAR ] -->
        <Border Grid.Row="3" Background="#18181B" BorderBrush="#27272A" BorderThickness="0,1,0,0" Padding="16,6">
            <Grid>
                <TextBlock Name="TxtFooterStatus" Text="Windows Toolbox Control Center &#x2022; Standalone &amp; Ready"
                           FontSize="11" Foreground="#71717A" VerticalAlignment="Center"/>
                <TextBlock Text="v2.1" HorizontalAlignment="Right" FontSize="11" Foreground="#71717A" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ----------------- Load XAML Window -----------------
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$Window = [System.Windows.Markup.XamlReader]::Load($reader)

# ----------------- Find Controls -----------------
$TxtSearch         = $Window.FindName('TxtSearch')
$BtnClearSearch    = $Window.FindName('BtnClearSearch')
$BadgeAdmin        = $Window.FindName('BadgeAdmin')
$TxtAdminStatus    = $Window.FindName('TxtAdminStatus')
$BtnRefresh        = $Window.FindName('BtnRefresh')
$BtnTerminalMenu   = $Window.FindName('BtnTerminalMenu')
$BannerElevate     = $Window.FindName('BannerElevate')
$BtnElevateNow     = $Window.FindName('BtnElevateNow')
$PnlCategoryList   = $Window.FindName('PnlCategoryList')
$TxtSystemDrive    = $Window.FindName('TxtSystemDrive')
$TxtPsVersion      = $Window.FindName('TxtPsVersion')
$TxtActiveCategory = $Window.FindName('TxtActiveCategory')
$TxtScriptCount    = $Window.FindName('TxtScriptCount')
$PnlScriptCards    = $Window.FindName('PnlScriptCards')
$BadgeDetailCat    = $Window.FindName('BadgeDetailCat')
$TxtDetailCat      = $Window.FindName('TxtDetailCat')
$TxtDetailPath     = $Window.FindName('TxtDetailPath')
$TxtDetailName     = $Window.FindName('TxtDetailName')
$TxtDetailDesc     = $Window.FindName('TxtDetailDesc')
$PnlDynamicParams  = $Window.FindName('PnlDynamicParams')
$TxtCommandPreview = $Window.FindName('TxtCommandPreview')
$BtnRunTerminal    = $Window.FindName('BtnRunTerminal')
$BtnRunDirect      = $Window.FindName('BtnRunDirect')
$TxtConsoleStatus  = $Window.FindName('TxtConsoleStatus')
$BtnClearConsole   = $Window.FindName('BtnClearConsole')
$BtnCopyConsole    = $Window.FindName('BtnCopyConsole')
$TxtConsoleLog     = $Window.FindName('TxtConsoleLog')
$TxtFooterStatus   = $Window.FindName('TxtFooterStatus')

# ----------------- Application State -----------------
$Global:AllScripts = [System.Collections.Generic.List[PSCustomObject]]::new()
$Global:SelectedScript = $null
$Global:ActiveCategory = 'All'
$Global:CategoryButtons = [System.Collections.Generic.List[System.Windows.Controls.Button]]::new()
$Global:ParamControls = @{}
$Global:IsProcessRunning = $false

# ----------------- Setup Admin Status & System Info -----------------
if ($isAdmin) {
    $TxtAdminStatus.Text = "$([char]::ConvertFromUtf32(0x1F6E1)) Administrator"
    $BadgeAdmin.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064E3B")
    $TxtAdminStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
    $BannerElevate.Visibility = [System.Windows.Visibility]::Collapsed
} else {
    $TxtAdminStatus.Text = "$([char]::ConvertFromUtf32(0x26A0)) Standard User"
    $BadgeAdmin.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#78350F")
    $TxtAdminStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDE68A")
    $BannerElevate.Visibility = [System.Windows.Visibility]::Visible
}

$BtnElevateNow.Add_Click({
    try {
        Start-Process powershell.exe -Verb RunAs -WorkingDirectory "$RepoRoot" -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`""
        )
        $Window.Close()
    } catch {
        [System.Windows.MessageBox]::Show("Elevation request was cancelled.", "Windows Toolbox", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
})

$TxtPsVersion.Text = "PS $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
try {
    $sysDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
    if ($sysDrive) {
        $freeGB = [math]::Round($sysDrive.FreeSpace / 1GB, 1)
        $totalGB = [math]::Round($sysDrive.Size / 1GB, 1)
        $TxtSystemDrive.Text = "$($env:SystemDrive) Free: $freeGB GB / $totalGB GB"
    }
} catch {
    $TxtSystemDrive.Text = "$($env:SystemDrive) System Drive"
}

# ----------------- Update Command Preview Function -----------------
function Update-CommandPreview {
    if (-not $Global:SelectedScript) {
        $TxtCommandPreview.Text = ""
        return
    }

    $cmd = ".\$($Global:SelectedScript.File.FullName.Substring($RepoRoot.Length).TrimStart('\', '/'))"
    $argsList = @()

    foreach ($key in $Global:ParamControls.Keys) {
        $ctrl = $Global:ParamControls[$key]
        if ($ctrl -is [System.Windows.Controls.CheckBox]) {
            if ($ctrl.IsChecked) { $argsList += "-$key" }
        }
        elseif ($ctrl -is [System.Windows.Controls.ComboBox]) {
            $val = "$($ctrl.SelectedItem)".Trim()
            if ($val -and $val -ne '(default)') { $argsList += "-$key $val" }
        }
        elseif ($ctrl -is [System.Windows.Controls.TextBox]) {
            $val = $ctrl.Text.Trim()
            if ($val) {
                if ($key -eq '__Custom') {
                    $argsList += $val
                } else {
                    if ($val -match '\s') { $val = "`"$val`"" }
                    $argsList += "-$key $val"
                }
            }
        }
    }

    if ($argsList.Count -gt 0) {
        $cmd += " " + ($argsList -join ' ')
    }
    $TxtCommandPreview.Text = $cmd
}

# ----------------- Select Script Handler -----------------
function Select-Script($scriptItem) {
    if (-not $scriptItem) { return }
    $Global:SelectedScript = $scriptItem
    $Global:ParamControls.Clear()

    $TxtDetailName.Text = $scriptItem.Name
    $TxtDetailCat.Text = if ($scriptItem.Category) { $scriptItem.Category.ToUpper() } else { "GENERAL" }
    $catColor = if ($scriptItem.Color) { $scriptItem.Color } else { "#71717A" }
    $BadgeDetailCat.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($catColor)
    $TxtDetailPath.Text = if ($scriptItem.File) { $scriptItem.File.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') } else { "" }
    $TxtDetailDesc.Text = $scriptItem.Synopsis

    $PnlDynamicParams.Children.Clear()

    if ($scriptItem.Parameters.Count -eq 0) {
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = "This tool runs interactively without required CLI flags."
        $lbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#71717A")
        $lbl.FontSize = 12
        $lbl.Margin = [System.Windows.Thickness]::new(0,0,0,8)
        $PnlDynamicParams.Children.Add($lbl) | Out-Null
    } else {
        foreach ($param in $scriptItem.Parameters) {
            $pContainer = [System.Windows.Controls.StackPanel]::new()
            $pContainer.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

            if ($param.IsSwitch) {
                $chk = [System.Windows.Controls.CheckBox]::new()
                $chk.Content = "-$($param.Name)  (Switch)"
                $chk.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E4E4E7")
                $chk.FontSize = 12
                $chk.Cursor = [System.Windows.Input.Cursors]::Hand
                $chk.Add_Checked({ Update-CommandPreview })
                $chk.Add_Unchecked({ Update-CommandPreview })
                $Global:ParamControls[$param.Name] = $chk
                $pContainer.Children.Add($chk) | Out-Null
            }
            elseif ($param.ValidValues.Count -gt 0) {
                $lbl = [System.Windows.Controls.TextBlock]::new()
                $lbl.Text = "-$($param.Name) (Choice)"
                $lbl.FontSize = 11
                $lbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A1A1AA")
                $lbl.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                $pContainer.Children.Add($lbl) | Out-Null

                $combo = [System.Windows.Controls.ComboBox]::new()
                $combo.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272A")
                $combo.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
                $combo.Padding = [System.Windows.Thickness]::new(6,4,6,4)
                $combo.Items.Add("(default)") | Out-Null
                foreach ($val in $param.ValidValues) { $combo.Items.Add($val) | Out-Null }
                $combo.SelectedIndex = 0
                $combo.Add_SelectionChanged({ Update-CommandPreview })
                $Global:ParamControls[$param.Name] = $combo
                $pContainer.Children.Add($combo) | Out-Null
            }
            else {
                $lbl = [System.Windows.Controls.TextBlock]::new()
                $lbl.Text = "-$($param.Name) ($($param.Type))"
                $lbl.FontSize = 11
                $lbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A1A1AA")
                $lbl.Margin = [System.Windows.Thickness]::new(0,0,0,4)
                $pContainer.Children.Add($lbl) | Out-Null

                $tb = [System.Windows.Controls.TextBox]::new()
                $tb.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272A")
                $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
                $tb.BorderThickness = [System.Windows.Thickness]::new(1)
                $tb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
                $tb.Padding = [System.Windows.Thickness]::new(6,4,6,4)
                $tb.FontSize = 12
                if ($param.DefaultValue) {
                    $cleanDefault = $param.DefaultValue.Trim("'", '"')
                    $tb.ToolTip = "Default: $cleanDefault"
                }
                $tb.Add_TextChanged({ Update-CommandPreview })
                $Global:ParamControls[$param.Name] = $tb
                $pContainer.Children.Add($tb) | Out-Null
            }
            $PnlDynamicParams.Children.Add($pContainer) | Out-Null
        }
    }

    # Add custom extra arguments box
    $customBox = [System.Windows.Controls.TextBox]::new()
    $customBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272A")
    $customBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
    $customBox.BorderThickness = [System.Windows.Thickness]::new(1)
    $customBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
    $customBox.Padding = [System.Windows.Thickness]::new(6,4,6,4)
    $customBox.FontSize = 12
    $customBox.ToolTip = "Type any additional parameters here..."
    $customBox.Add_TextChanged({ Update-CommandPreview })
    $Global:ParamControls['__Custom'] = $customBox

    $customContainer = [System.Windows.Controls.StackPanel]::new()
    $customContainer.Margin = [System.Windows.Thickness]::new(0, 6, 0, 4)
    $customLbl = [System.Windows.Controls.TextBlock]::new()
    $customLbl.Text = "Custom Extra Arguments:"
    $customLbl.FontSize = 11
    $customLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#71717A")
    $customLbl.Margin = [System.Windows.Thickness]::new(0,0,0,4)
    $customContainer.Children.Add($customLbl) | Out-Null
    $customContainer.Children.Add($customBox) | Out-Null
    $PnlDynamicParams.Children.Add($customContainer) | Out-Null

    Update-CommandPreview
}

# ----------------- Render Script Cards -----------------
function Render-ScriptCards {
    $PnlScriptCards.Children.Clear()

    $query = ""
    if ($TxtSearch -and $TxtSearch.Text) {
        $query = $TxtSearch.Text.Trim().ToLower()
    }

    $activeCat = $Global:ActiveCategory
    if (-not $activeCat) { $activeCat = 'All' }

    $filtered = @($Global:AllScripts | Where-Object {
        $catMatch = ($activeCat -eq 'All' -or $_.Category -ieq $activeCat)
        $searchMatch = $true
        if ($query) {
            $nameHas = ($_.Name -and $_.Name.ToLower().Contains($query))
            $synHas  = ($_.Synopsis -and $_.Synopsis.ToLower().Contains($query))
            $catHas  = ($_.Category -and $_.Category.ToLower().Contains($query))
            $searchMatch = ($nameHas -or $synHas -or $catHas)
        }
        $catMatch -and $searchMatch
    })

    $TxtScriptCount.Text = " ($($filtered.Count) tools)"

    if ($filtered.Count -eq 0) {
        $emptyBorder = [System.Windows.Controls.Border]::new()
        $emptyBorder.Padding = [System.Windows.Thickness]::new(30)
        $emptyText = [System.Windows.Controls.TextBlock]::new()
        $emptyText.Text = "No scripts found in '$activeCat' category."
        $emptyText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#71717A")
        $emptyText.FontSize = 14
        $emptyText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $emptyBorder.Child = $emptyText
        $PnlScriptCards.Children.Add($emptyBorder) | Out-Null
        return
    }

    foreach ($item in $filtered) {
        $card = [System.Windows.Controls.Border]::new()
        $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E22")
        $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272A")
        $card.BorderThickness = [System.Windows.Thickness]::new(1)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        $card.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
        $card.Cursor = [System.Windows.Input.Cursors]::Hand

        # Highlight if selected
        if ($Global:SelectedScript -and $Global:SelectedScript.FullName -eq $item.FullName) {
            $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0078D4")
            $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#23232A")
        }

        $grid = [System.Windows.Controls.Grid]::new()
        $grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) | Out-Null
        $grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new()) | Out-Null

        # Row 0: Name + Category badge + Quick launch
        $topRow = [System.Windows.Controls.Grid]::new()
        $topRow.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new()) | Out-Null
        $colAuto = [System.Windows.Controls.ColumnDefinition]::new()
        $colAuto.Width = [System.Windows.GridLength]::Auto
        $topRow.ColumnDefinitions.Add($colAuto) | Out-Null

        $titleStack = [System.Windows.Controls.StackPanel]::new()
        $titleStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $nameTxt = [System.Windows.Controls.TextBlock]::new()
        $nameTxt.Text = $item.Name
        $nameTxt.FontSize = 14
        $nameTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $nameTxt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $titleStack.Children.Add($nameTxt) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($titleStack, 0)
        $topRow.Children.Add($titleStack) | Out-Null

        $rightStack = [System.Windows.Controls.StackPanel]::new()
        $rightStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $badge = [System.Windows.Controls.Border]::new()
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($item.Color)
        $badge.Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
        $badge.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $badgeTxt = [System.Windows.Controls.TextBlock]::new()
        $badgeTxt.Text = $item.Category
        $badgeTxt.FontSize = 10
        $badgeTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $badgeTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        $badge.Child = $badgeTxt
        $rightStack.Children.Add($badge) | Out-Null

        # Quick Run Button
        $btnQuick = [System.Windows.Controls.Button]::new()
        $btnQuick.Content = "$([char]0x25B6) Run"
        $btnQuick.FontSize = 11
        $btnQuick.Style = $Window.FindResource('SecondaryButton')
        $btnQuick.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        $btnQuick.Tag = $item
        $btnQuick.Add_Click({
            param($s, $e)
            $e.Handled = $true
            Select-Script $s.Tag
            Invoke-ToolboxScript -Direct
        })
        $rightStack.Children.Add($btnQuick) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($rightStack, 1)
        $topRow.Children.Add($rightStack) | Out-Null

        [System.Windows.Controls.Grid]::SetRow($topRow, 0)
        $grid.Children.Add($topRow) | Out-Null

        # Row 1: Synopsis
        $descTxt = [System.Windows.Controls.TextBlock]::new()
        $descTxt.Text = $item.Synopsis
        $descTxt.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $descTxt.FontSize = 12
        $descTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A1A1AA")
        $descTxt.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
        [System.Windows.Controls.Grid]::SetRow($descTxt, 1)
        $grid.Children.Add($descTxt) | Out-Null

        $card.Child = $grid

        # Card Click selects the script
        $card.Tag = $item
        $card.Add_MouseLeftButtonUp({
            param($s, $e)
            Select-Script $s.Tag
            Render-ScriptCards
        })

        $PnlScriptCards.Children.Add($card) | Out-Null
    }
}

# ----------------- Category Selection Handler -----------------
function Set-ActiveCategory([string]$catName) {
    $Global:ActiveCategory = $catName
    $TxtActiveCategory.Text = if ($catName -eq 'All') { "All Tools" } else { "$catName Tools" }

    # Update button highlights smoothly without recreating them
    foreach ($btn in $Global:CategoryButtons) {
        if ($btn.Tag -eq $catName) {
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0078D4")
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        } else {
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("Transparent")
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D4D4D8")
        }
    }

    Render-ScriptCards
}

# ----------------- Build Category Sidebar Buttons -----------------
function Build-CategoryButtons {
    $PnlCategoryList.Children.Clear()
    $Global:CategoryButtons.Clear()

    $categories = @('All') + @($Global:AllScripts | Select-Object -ExpandProperty Category -Unique | Sort-Object)

    foreach ($cat in $categories) {
        $btn = [System.Windows.Controls.Button]::new()
        $btn.Tag = $cat
        $btn.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $btn.Cursor = [System.Windows.Input.Cursors]::Hand
        $btn.BorderThickness = [System.Windows.Thickness]::new(0)
        $btn.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)

        $count = if ($cat -eq 'All') { $Global:AllScripts.Count } else { ($Global:AllScripts | Where-Object { $_.Category -ieq $cat }).Count }

        $icon = switch ($cat) {
            'All'         { [char]::ConvertFromUtf32(0x1F4C1) }
            'Backup'      { [char]::ConvertFromUtf32(0x1F4BE) }
            'Dev'         { [char]::ConvertFromUtf32(0x1F4BB) }
            'Gaming'      { [char]::ConvertFromUtf32(0x1F3AE) }
            'Maintenance' { [char]::ConvertFromUtf32(0x1F527) }
            'Network'     { [char]::ConvertFromUtf32(0x1F310) }
            'Security'    { [char]::ConvertFromUtf32(0x1F6E1) }
            'Utilities'   { [char]::ConvertFromUtf32(0x1F4E6) }
            default       { [char]::ConvertFromUtf32(0x1F4C4) }
        }

        # Styling depending on active state
        if ($cat -eq $Global:ActiveCategory) {
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0078D4")
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
        } else {
            $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("Transparent")
            $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D4D4D8")
        }

        $grid = [System.Windows.Controls.Grid]::new()
        $col0 = [System.Windows.Controls.ColumnDefinition]::new()
        $col1 = [System.Windows.Controls.ColumnDefinition]::new()
        $col1.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($col0) | Out-Null
        $grid.ColumnDefinitions.Add($col1) | Out-Null

        $txtStack = [System.Windows.Controls.StackPanel]::new()
        $txtStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $iconTxt = [System.Windows.Controls.TextBlock]::new()
        $iconTxt.Text = "$icon "
        $iconTxt.FontSize = 13
        $labelTxt = [System.Windows.Controls.TextBlock]::new()
        $labelTxt.Text = $cat
        $labelTxt.FontSize = 12
        $labelTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
        $txtStack.Children.Add($iconTxt) | Out-Null
        $txtStack.Children.Add($labelTxt) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtStack, 0)
        $grid.Children.Add($txtStack) | Out-Null

        $countTxt = [System.Windows.Controls.TextBlock]::new()
        $countTxt.Text = "$count"
        $countTxt.FontSize = 11
        $countTxt.Opacity = 0.7
        [System.Windows.Controls.Grid]::SetColumn($countTxt, 1)
        $grid.Children.Add($countTxt) | Out-Null

        $btn.Content = $grid

        $btn.Add_Click({
            param($sender, $e)
            Set-ActiveCategory $sender.Tag
        })

        $Global:CategoryButtons.Add($btn)
        $PnlCategoryList.Children.Add($btn) | Out-Null
    }
}

# ----------------- Script Execution Handlers -----------------
function Invoke-ToolboxScript([switch]$Direct) {
    if (-not $Global:SelectedScript) { return }

    $targetFile = $Global:SelectedScript.FullName

    # Assemble arguments
    $argsList = @()
    foreach ($key in $Global:ParamControls.Keys) {
        $ctrl = $Global:ParamControls[$key]
        if ($ctrl -is [System.Windows.Controls.CheckBox]) {
            if ($ctrl.IsChecked) { $argsList += "-$key" }
        }
        elseif ($ctrl -is [System.Windows.Controls.ComboBox]) {
            $val = "$($ctrl.SelectedItem)".Trim()
            if ($val -and $val -ne '(default)') { $argsList += "-$key", $val }
        }
        elseif ($ctrl -is [System.Windows.Controls.TextBox]) {
            $val = $ctrl.Text.Trim()
            if ($val) {
                if ($key -eq '__Custom') {
                    $tokens = [System.Management.Automation.PSParser]::Tokenize($val, [ref]$null) |
                        Where-Object { $_.Type -in 'CommandArgument', 'CommandParameter', 'String', 'Number' } |
                        ForEach-Object { $_.Content }
                    if ($tokens) { $argsList += $tokens } else { $argsList += ($val -split '\s+') }
                } else {
                    $argsList += "-$key", $val
                }
            }
        }
    }

    if ($Direct) {
        # Direct capture run in background
        if ($Global:IsProcessRunning) {
            [System.Windows.MessageBox]::Show("Another script is currently running. Please wait for it to complete.", "Windows Toolbox", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        $Global:IsProcessRunning = $true
        $BtnRunDirect.IsEnabled = $false
        $TxtConsoleStatus.Text = " $([char]0x2022) Running: $($Global:SelectedScript.Name)..."
        $TxtConsoleStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $TxtConsoleLog.Text = "[$(Get-Date -Format 'HH:mm:ss')] Starting $($Global:SelectedScript.Name)...`r`n"
        $TxtConsoleLog.AppendText("Command: $($TxtCommandPreview.Text)`r`n`r`n")

        $bw = [System.ComponentModel.BackgroundWorker]::new()
        $bw.Add_DoWork({
            param($sender, $eventArgs)
            try {
                $psi = [System.Diagnostics.ProcessStartInfo]::new()
                $psi.FileName = "powershell.exe"
                $rawArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$targetFile`"")
                foreach ($arg in $argsList) {
                    if ($arg -match '\s') { $rawArgs += "`"$arg`"" } else { $rawArgs += $arg }
                }
                $psi.Arguments = $rawArgs -join ' '
                $psi.WorkingDirectory = (Split-Path $targetFile -Parent)
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.CreateNoWindow = $true

                $proc = [System.Diagnostics.Process]::Start($psi)

                while (-not $proc.StandardOutput.EndOfStream) {
                    $line = $proc.StandardOutput.ReadLine()
                    $Window.Dispatcher.Invoke([Action]{
                        $TxtConsoleLog.AppendText("$line`r`n")
                        $TxtConsoleLog.ScrollToEnd()
                    })
                }

                $err = $proc.StandardError.ReadToEnd()
                if ($err) {
                    $Window.Dispatcher.Invoke([Action]{
                        $TxtConsoleLog.AppendText("`r`n[ERROR] $err`r`n")
                        $TxtConsoleLog.ScrollToEnd()
                    })
                }

                $proc.WaitForExit()
                $eventArgs.Result = $proc.ExitCode
            }
            catch {
                $eventArgs.Result = -1
                $msg = $_.Exception.Message
                $Window.Dispatcher.Invoke([Action]{
                    $TxtConsoleLog.AppendText("`r`n[Exception] $msg`r`n")
                })
            }
        })

        $bw.Add_RunWorkerCompleted({
            param($sender, $eventArgs)
            $code = $eventArgs.Result
            $Global:IsProcessRunning = $false
            $BtnRunDirect.IsEnabled = $true
            if ($code -eq 0) {
                $TxtConsoleStatus.Text = " $([char]0x2022) Completed Successfully (Exit 0)"
                $TxtConsoleStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
            } else {
                $TxtConsoleStatus.Text = " $([char]0x2022) Finished (Exit Code: $code)"
                $TxtConsoleStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
            }
            $TxtConsoleLog.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] Process finished with exit code $code.`r`n")
            $TxtConsoleLog.ScrollToEnd()
        })

        $bw.RunWorkerAsync()
    }
    else {
        # Run in Elevated Terminal (Standard interactive mode)
        $argStringList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$targetFile`"")
        foreach ($arg in $argsList) {
            if ($arg -match '\s') { $argStringList += "`"$arg`"" } else { $argStringList += $arg }
        }

        try {
            Start-Process powershell.exe -WorkingDirectory (Split-Path $targetFile -Parent) `
                -ArgumentList $argStringList -Verb RunAs
            $TxtConsoleStatus.Text = " $([char]0x2022) Launched in Terminal window"
            $TxtConsoleStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            $TxtConsoleLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Launched $($Global:SelectedScript.Name) in external terminal window.`r`n")
            $TxtConsoleLog.ScrollToEnd()
        }
        catch {
            [System.Windows.MessageBox]::Show("Could not launch terminal: $($_.Exception.Message)", "Windows Toolbox", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }
}

$BtnRunTerminal.Add_Click({ Invoke-ToolboxScript })
$BtnRunDirect.Add_Click({ Invoke-ToolboxScript -Direct })

# ----------------- Search & Filter Events -----------------
$TxtSearch.Add_TextChanged({
    Render-ScriptCards
})

$BtnClearSearch.Add_Click({
    $TxtSearch.Text = ""
})

# ----------------- Refresh & Utility Handlers -----------------
function Load-AllData {
    $Global:AllScripts = Get-AllToolboxMetadata
    Build-CategoryButtons
    Render-ScriptCards

    if ($Global:AllScripts.Count -gt 0 -and -not $Global:SelectedScript) {
        Select-Script $Global:AllScripts[0]
    }
    $catCount = ($Global:AllScripts | Select-Object -ExpandProperty Category -Unique).Count
    $TxtFooterStatus.Text = "Discovered $($Global:AllScripts.Count) tools across $catCount categories."
}

$BtnRefresh.Add_Click({
    Load-AllData
})

$BtnTerminalMenu.Add_Click({
    $cliLauncher = Join-Path $RepoRoot 'Script-Launcher.bat'
    if (Test-Path $cliLauncher) {
        Start-Process cmd.exe -ArgumentList "/c `"$cliLauncher`""
    } else {
        Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$RepoRoot\Script-Launcher.ps1`"")
    }
})

$BtnClearConsole.Add_Click({
    $TxtConsoleLog.Text = ""
    $TxtConsoleStatus.Text = " $([char]0x2022) Log cleared"
})

$BtnCopyConsole.Add_Click({
    if ($TxtConsoleLog.Text) {
        [System.Windows.Clipboard]::SetText($TxtConsoleLog.Text)
        $TxtConsoleStatus.Text = " $([char]0x2022) Copied to clipboard"
    }
})

# ----------------- Initial Load & Show -----------------
Load-AllData
[void]$Window.ShowDialog()
