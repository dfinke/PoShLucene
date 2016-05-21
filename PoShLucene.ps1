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
        WindowStartupLocation="CenterScreen"
        Title="Lucene" Height="500" Width="850">

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="75" />
            <RowDefinition />
            <RowDefinition Height="45" />
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="50"/>
                <ColumnDefinition />            
            </Grid.ColumnDefinitions>

            <Grid.RowDefinitions>
                <RowDefinition/>
                <RowDefinition/>
            </Grid.RowDefinitions>

            <Label Content="_Target" Grid.Row="0" Grid.Column="0" Margin="3"   />
            <TextBox Name="txtTarget" Grid.Row="0" Grid.Column="1" Margin="3"  />

            <Label Content="_Query" Grid.Row="1" Grid.Column="0" Margin="3" />
            <TextBox Name="query" Grid.Row="1" Grid.Column="1" Margin="3"/>            

        </Grid>

        <Grid Grid.Row="1" Margin="5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="150"/>
                <ColumnDefinition />
            </Grid.ColumnDefinitions>
            
            <ListBox Name="hits" Grid.Column="0" Margin="5" />
            <TextBox Name="OutputPane" Grid.Column="1" Margin="5" VerticalScrollBarVisibility="Auto"  HorizontalScrollBarVisibility="Auto"/>
        </Grid>

        <TextBlock Name="txtStatus" Grid.Row="2" Margin="8" />

    </Grid>
</Window>
'@

$Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$XAML)))

$txtTarget  = $Window.FindName("txtTarget")
$query      = $Window.FindName("query")
$hits       = $Window.FindName("hits")
$OutputPane = $Window.FindName("OutputPane")
$txtStatus  = $Window.FindName("txtStatus")

$txtTarget.Text = "C:\Users\Douglas\Documents\GitHub\vscode-powershell\*.ts,C:\Users\Douglas\Documents\GitHub\PowerShellEditorServices\*.cs"
$query.Text = "expandalias"

$null=$txtTarget.Focus()

$analyzer  = [StandardAnalyzer]::new("LUCENE_CURRENT")
$directory = [RAMDirectory]::new()

function DoIndex ($targetFileList) {

    $timing = Measure-Command {
    $iwriter=[IndexWriter]::new($directory,$analyzer,$true,[IndexWriter+MaxFieldLength]::new(25000))

    $count=0
    $cmd = "ls -rec {0} | % fullname " -f $targetFileList
    foreach ($file in ($cmd | iex)) {

        $doc = [Document]::new()
        $text=[io.file]::ReadAllText($file)

        $doc.Add([Field]::new("fulltext",$text,"YES","ANALYZED"))
        $iwriter.AddDocument($doc)
        $count++
    } }

    $txtStatus.text="{0} files indexed in {1} seconds" -f $count, $timing.TotalSeconds

    $iwriter.close()
}

function DoSearch ($q) {

    $timing = Measure-Command {
        $script:isearcher = [IndexSearcher]::new($directory, $true) # read-only-true
        $parser = [QueryParser]::new("LUCENE_CURRENT", "fulltext", $analyzer)    
        $query = $parser.Parse($q)    
        $totalHits=$isearcher.Search($query,$null,1000).ScoreDocs
    }

    $totalHits
    $txtStatus.text="{0} hits found in {1} seconds" -f $totalHits.count, $timing.TotalSeconds
}

$txtTarget.add_PreviewKeyUp({
    param($sender,$keyArgs)
    
    if($keyArgs.Key -eq 'Enter') {        
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        $txtStatus.text="[{0}] Indexing..." -f (Get-Date)
        [System.Windows.Forms.Application]::DoEvents()
        DoIndex $txtTarget.Text
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }    
})

$query.add_PreviewKeyUp({
    param($sender,$keyArgs)

    if($keyArgs.Key -eq 'Enter') {
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

        $adding=$true
        $script:totalDocs = DoSearch $query.Text
        
        $hits.items.Clear()  
        $OutputPane.Text=$null
        for ($i = 0; $i -lt $totalDocs.count; $i++) { 
            $hits.Items.Add("Doc $($i+1)")        
        }
        $adding=$false

        if($totalDocs.Count -ge 1) {
            $hits.Focus()
            $hits.SelectedItem = $hits.Items[0]
        }
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
})

$hits.add_SelectionChanged({
    if($adding) {return}
    $hitDoc = $isearcher.Doc($script:totalDocs[$hits.SelectedIndex].Doc)
    $OutputPane.Text = $hitDoc.Get("fulltext")
})

[void]$Window.ShowDialog()

if($script:isearcher) { $script:isearcher.Close() }
if($directory)        { $directory.Close() }