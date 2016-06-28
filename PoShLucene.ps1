using assembly Lucene.Net.dll

using namespace System.IO
using namespace Lucene.Net.Analysis
using namespace Lucene.Net.Analysis.Standard
using namespace Lucene.Net.Documents
using namespace Lucene.Net.Index
using namespace Lucene.Net.QueryParsers
using namespace Lucene.Net.Store
using namespace Lucene.Net.Util
using namespace Lucene.Net.Search

Add-Type -AssemblyName presentationframework
Add-Type -AssemblyName System.Windows.Forms

$XAML=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PoShLucene"
        Width="850"
        Height="500"
        Background="#282c34"
        WindowStartupLocation="CenterScreen">

    <Grid>
        <Grid.Resources>
            <VisualBrush x:Key="SearchHint"
                         AlignmentX="Left"
                         AlignmentY="Top"
                         Stretch="None">
                <VisualBrush.Transform>
                    <TranslateTransform X="5" Y="7" />
                </VisualBrush.Transform>
                <VisualBrush.Visual>
                    <Grid HorizontalAlignment="Left">
                        <TextBlock HorizontalAlignment="Left"
                                   VerticalAlignment="Center"
                                   FontStyle="Italic"
                                   Foreground="Gray"
                                   Opacity="1"
                                   Text="Search in file contents" />
                    </Grid>
                </VisualBrush.Visual>
            </VisualBrush>
        </Grid.Resources>

        <Grid.RowDefinitions>
            <RowDefinition Height="75" />
            <RowDefinition />
            <RowDefinition Height="45" />
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="50" />
                <ColumnDefinition />
            </Grid.ColumnDefinitions>

            <Grid.RowDefinitions>
                <RowDefinition />
                <RowDefinition />
            </Grid.RowDefinitions>

            <Label Grid.Row="0"
                   Grid.Column="0"
                   Margin="3"
                   Content="_Target"
                   Foreground="#99ffcc" />
            <TextBox Name="txtTarget"
                     Grid.Row="0"
                     Grid.Column="1"
                     Margin="3" />
            <Label Grid.Row="1"
                   Grid.Column="0"
                   Margin="3"
                   Content="_Query"
                   Foreground="#99ffcc" />
            <TextBox x:Name="query"
                     Grid.Row="1"
                     Grid.Column="1"
                     Margin="3">
                <TextBox.Style>
                    <Style TargetType="{x:Type TextBox}">
                        <Setter Property="Background" Value="White" />
                        <Style.Triggers>
                            <DataTrigger Binding="{Binding ElementName=query, Path=Text}" Value="">
                                <Setter Property="Background" Value="{StaticResource SearchHint}" />
                            </DataTrigger>
                        </Style.Triggers>
                    </Style>
                </TextBox.Style>
            </TextBox>
        </Grid>

        <Grid Grid.Row="1" Margin="5">
            <Grid.ColumnDefinitions>
				<ColumnDefinition Width="200" />
                <ColumnDefinition Width="5" />
				<ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>

            <ListBox Name="hits"
                     Grid.Column="0"
                     Margin="5"
					 Background="#282c34"
					 Foreground="#4cd2ff" />

			<GridSplitter Grid.Column="1"
                          Width="3"
                          HorizontalAlignment="Stretch"
                          Background="#ff265c" />

            <TextBox Name="OutputPane"
                     Grid.Column="2"
                     Margin="5"
                     Background="#282c34"
                     Foreground="#ccff99"
                     HorizontalScrollBarVisibility="Auto"
                     VerticalScrollBarVisibility="Auto" />
        </Grid>

        <StackPanel Grid.Row="2"
                    Grid.Column="1"
                    Grid.ColumnSpan="2"
                    Orientation="Horizontal">
            <TextBlock Name="txtStatus"
                       Margin="8"
                       FontStyle="Italic"
                       Foreground="#99ffcc"
                       TextWrapping="Wrap" />

            <Label x:Name="txtPath"
                   Margin="8"
                   FontStyle="Italic"
                   Foreground="#4cd2ff" />
        </StackPanel>

    </Grid>

</Window>
'@

$Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$XAML)))

$txtTarget  = $Window.FindName("txtTarget")
$query      = $Window.FindName("query")
$hits       = $Window.FindName("hits")
$OutputPane = $Window.FindName("OutputPane")
$txtStatus  = $Window.FindName("txtStatus")
$txtPath    = $Window.FindName("txtPath")

$txtTarget.Text = "$PSScriptRoot\*.ps1, $([System.Environment]::GetFolderPath('Desktop'))\*.cs"

$null=$txtTarget.Focus()

$analyzer  = [StandardAnalyzer]::new("LUCENE_CURRENT")
$directory = [RAMDirectory]::new()

$theIndex=@{name='';indexed=$false}

function DoIndex ($targetFileList)
{
    if($theIndex.name -eq $targetFileList -and $theIndex.index -eq $true) { return }

    $timing = Measure-Command {
		$iwriter = [IndexWriter]::new($directory, $analyzer, $true, [IndexWriter+MaxFieldLength]::new(25000))

		$count = 0
		$cmd = "ls -rec {0} -File | % fullname " -f $targetFileList
		foreach ($file in ($cmd | iex))
		{
			try
			{
				$doc = [Document]::new()
				$text = [IO.file]::ReadAllText($file)

				Write-Verbose -Message "Analyzed the file: $file"
				$doc.Add([Field]::new("fulltext", $text, "YES", "ANALYZED"))
				$doc.Add([Field]::new("filepath", $file, "YES", "ANALYZED"))
				$iwriter.AddDocument($doc)
				$count++
			}
			catch [Exception]
			{
				$errMsg = "Unable to read the file {0} `nException: {1}" -f $file, $_.Exception.ToString()
				Write-Error $errMsg
			}
		}
	}

	$txtStatus.text = "{0} files indexed in {1} seconds" -f $count, $timing.TotalSeconds
    $iwriter.close()
    $theIndex.name=$targetFileList
    $theIndex.index=$true
}

function DoSearch ($q)
{
	try
	{
		$timing = Measure-Command {
			$script:isearcher = [IndexSearcher]::new($directory, $true) # read-only-true
			$parser = [QueryParser]::new("LUCENE_CURRENT", "fulltext", $analyzer)
			$query = $parser.Parse($q)
			$totalHits = $isearcher.Search($query, $null, 1000).ScoreDocs
		}

		 $totalHits
		# if ([String]::IsNullOrWhiteSpace($txtStatus.text)) {
		# 	$txtStatus.text = "{0} hits found in {1} seconds" -f $totalHits.count, $timing.TotalSeconds
		# } else {
		# 	$txtStatus.text = "{0}`n{1} hits found in {2} seconds" -f $txtStatus.text, $totalHits.count, $timing.TotalSeconds
		# }
        $txtStatus.text = "{0}`n{1} hits found in {2} seconds" -f $txtStatus.text, $totalHits.count, $timing.TotalSeconds
	}
	catch [Exception]
	{
		$errMsg = "Search failed with the following `nException: {0}" -f $_.Exception.ToString()
		Write-Error $errMsg
	}
}

$txtTarget.add_PreviewKeyUp({
	param($sender, $keyArgs)

    if($keyArgs.Key -eq 'Enter') {
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
		$txtStatus.text = "[{0}] Indexing..." -f (Get-Date)
        [System.Windows.Forms.Application]::DoEvents()
		DoIndex $txtTarget.Text -ErrorAction SilentlyContinue
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
})

$query.add_PreviewKeyUp({
    param($sender,$keyArgs)

    if($keyArgs.Key -eq 'Enter') {
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

		if ($txtTarget.Text -ne $null -and ([String]::IsNullOrWhiteSpace($txtTarget.Text) -ne $true)) {
			DoIndex $txtTarget.Text -ErrorAction SilentlyContinue
		}

        $adding=$true
		$script:totalDocs = DoSearch $query.Text -ErrorAction SilentlyContinue

        $hits.items.Clear()
		$OutputPane.Text = $null

        for ($i = 0; $i -lt $totalDocs.count; $i++) {
			$hitDocPath = $isearcher.Doc($script:totalDocs[$i].Doc).Get("filepath")
            $hits.Items.Add($hitDocPath)
        }

		$adding = $false

        if($totalDocs.Count -ge 1) {
            $hits.Focus()
            $hits.SelectedItem = $hits.Items[0]
        }

        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
})

$hits.add_SelectionChanged({
	if($adding) { return }
    $hitDoc = $isearcher.Doc($script:totalDocs[$hits.SelectedIndex].Doc)
    $OutputPane.Text = $hitDoc.Get("fulltext")
    $txtPath.Content = $hitDoc.Get("filepath")
	$hitDoc
})

$txtPath.add_MouseEnter({
    $txtPath.Cursor = [System.Windows.Input.Cursors]::Hand
})

$txtPath.add_MouseLeftButtonDown({
    $fPath = $txtPath.Content

    if (Test-Path -Path $fPath) {
       Start-Process -FilePath "$env:windir\explorer.exe" -ArgumentList "/select, ""$fPath"""
    }
})

[void]$Window.ShowDialog()

if($script:isearcher) { $script:isearcher.Close() }
if($directory) { $directory.Close() }