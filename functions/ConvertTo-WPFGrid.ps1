
Function ConvertTo-WPFGrid {

    [cmdletbinding(DefaultParameterSetName = "input")]
    [Alias("cwg")]
    [outputtype("none")]

    Param(
        [Parameter(ValueFromPipeline, ParameterSetName = "Input")]
        [ValidateNotNullOrEmpty()]
        [psobject]$InputObject,

        [Parameter(ParameterSetName = "scriptblock", HelpMessage = "Enter a scriptblock that will generate data to be populated in the form")]
        [ValidateNotNullOrEmpty()]
        [Scriptblock]$Scriptblock,

        [string]$Title = "ConvertTo-WPFGrid",
        [ValidateScript( {$_ -ge 5})]
        [int]$Timeout,

        [switch]$Refresh,

        [Parameter(HelpMessage = "Control how grid lines are displayed")]
        [ValidateSet("All","Horizontal","None","Vertical")]
        [ValidateNotNullOrEmpty()]
        [string]$Gridlines = "All",

        [Parameter(HelpMessage = "Run this scriptblock to initialize the background runspace")]
        [scriptblock]$InitializationScript,

        [Parameter(HelpMessage = "Load locally defined variables into the background runspace")]
        [alias("var")]
        [string[]]$UseLocalVariable,

        [Parameter(HelpMessage = "Load your PowerShell profiles into the background runspace")]
        [alias("profile")]
        [switch]$UseProfile
    )

    Begin {

        Write-Verbose "Starting $($MyInvocation.MyCommand)"

        if ($Refresh -AND $timeout -le 5) {
            Throw "You must specify a timeout value when using -Refresh"
        }

        $InitialSessionState = [InitialSessionState]::CreateDefault()
        $InitialSessionState.ApartmentState = "STA"
        $InitialSessionState.ThreadOptions = "ReuseThread"

        if ($UseLocalVariable) {
            Write-Verbose "Using local variables"
            Get-Variable -include $UseLocalVariable |
                ForEach-Object {
                Write-Verbose "...Adding $($_.name)"
                $var = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry($_.name, $_.value, $null)
                $InitialSessionState.Variables.Add($var)
            }
        }
        Write-Verbose "Define new runspace"
        $newRunspace = [RunspaceFactory]::CreateRunspace($host, $InitialSessionState)
        Write-Verbose "Opening new runspace"
        $newRunspace.Open()

        Write-Verbose "Defining script command"
        $psCmd = [PowerShell]::Create()
        #code to display the WPF form
        $gridScript = {
            Param(
                [string]$Title = "ConvertTo-WPFGrid",
                [ValidateScript( {$_ -ge 5})]
                [int]$Timeout = 0,
                [object[]]$Data,
                [scriptblock]$cmd,
                [switch]$Refresh,
                [string]$Gridlines
            )

            # It may not be necessary to add these types but it doesn't hurt to include them
            Add-Type -AssemblyName PresentationFramework
            Add-Type -AssemblyName PresentationCore
            Add-Type -AssemblyName WindowsBase

            #get maximum available working area on the screen
            $s = [System.Windows.SystemParameters]::WorkArea

            $form = New-Object System.Windows.Window
            $form.Title = $Title
            $form.MaxHeight = $s.Height
            $form.MaxWidth = $s.Width

            $form.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight

            #define a handler when the form is loaded. The scriptblock uses variables defined later
            #in the script
            $form.add_Loaded( {
                    $datagrid.UpdateLayout()

                    foreach ($col in $datagrid.Columns) {
                        #because of the way I am loading data into the grid
                        #it appears I need to set the sorting on each column
                        $col.CanUserSort = $True
                        $col.SortMemberPath = $col.Header
                    }

                    If ($Timeout -gt 0) {
                        $timer.IsEnabled = $True
                        $Timer.Start()
                    }

                    #calculate screen dimensions to center the form
                    $s = [System.Windows.SystemParameters]::WorkArea
                    $form.top = $s.Height / 2 - $form.ActualHeight / 2
                    $form.left = $s.width / 2 - $form.ActualWidth / 2
                    $form.UpdateLayout()
                    $form.focus

                })

            $Form.Add_closing( {
                    #reserved for future use
                })
            $Form.Add_closed( {
                    #reserved for future use
                })
            #Create a grid to hold the datagrid
            $Grid = new-object System.Windows.Controls.Grid

            $Grid.HorizontalAlignment = "stretch"
            $grid.VerticalAlignment = "stretch"

            #add buttons to close and manually refresh (Issue #34)
            $btnRefresh = New-Object System.Windows.Controls.Button
            $btnRefresh.Content = "Refresh Now"
            $btnRefresh.Height = 25
            $btnRefresh.Width = 80
            $btnRefresh.HorizontalAlignment = "left"
            $btnRefresh.VerticalAlignment = "Top"
            $btnRefresh.Margin = "15,10,0,0"
            $btnRefresh.ToolTip = "click to refresh data from the command"

            $btnRefresh.add_click( {
                    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

                    $form.Title = "$Title ...refreshing content. Please wait."

                    $timer.stop()
                    start-sleep -seconds 3

                    $datagrid.itemssource = Invoke-Command -ScriptBlock $cmd

                    foreach ($col in $datagrid.Columns) {
                        #because of the way I am loading data into the grid
                        #it appears I need to set the sorting on each column
                        $col.CanUserSort = $True
                        $col.SortMemberPath = $col.Header
                    }

                    $script:Now = Get-Date

                    if ($script:count) {
                        $script:count = $Timeout
                        [datetime]$script:terminate = $now.AddSeconds($timeout)
                        $ts = New-TimeSpan -Seconds $script:count
                        $status.text = " Last updated $script:Now - refresh in $($ts.tostring())"
                    }
                    else {
                        $status.text = " last updated $Script:Now"
                    }
                    if ($refresh) {
                        $timer.start()
                    }
                    $form.title = $Title
                    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Arrow
                })

            $grid.AddChild($btnRefresh)

            $btnClose = New-Object System.Windows.Controls.Button
            $btnClose.Content = "Close"
            $btnClose.Height = 25
            $btnClose.Width = 80
            $btnClose.HorizontalAlignment = "Right"
            $btnClose.VerticalAlignment = "Top"
            $btnClose.Margin = "0,10,15,0"
            $btnClose.ToolTip = "close the form and quit"

            $btnClose.add_click( {
                    $form.Close()
                })
            $grid.AddChild($btnClose)

            #create a datagrid
            $datagrid = New-Object System.Windows.Controls.DataGrid
            $datagrid.width = "Auto"
            $datagrid.Height = "Auto"
            $datagrid.VerticalAlignment = "stretch"
            $datagrid.HorizontalAlignment = "stretch"
            $datagrid.margin = "0,50,0,25"

            $datagrid.ColumnWidth = "Auto"
            $datagrid.GridLinesVisibility = $Gridlines
            $datagrid.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
            $datagrid.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
            $datagrid.CanUserSortColumns = $True
            $datagrid.CanUserResizeColumns = $True
            $datagrid.CanUserReorderColumns = $True
            $datagrid.AutoGenerateColumns = $True
            $datagrid.CanUserAddRows = $false
            $datagrid.CanUserDeleteRows = $false
            $datagrid.IsReadOnly = $True
            #enable alternating color rows
            $datagrid.AlternatingRowBackground = "gainsboro"
            $datagrid.ItemsSource = $data

            foreach ($col in $datagrid.Columns) {
                #because of the way I am loading data into the grid
                #it appears I need to set the sorting on each column
                $col.CanUserSort = $True
                $col
                $col.SortMemberPath = $col.Header
            }
            $Grid.AddChild($datagrid)

            $status = New-Object System.Windows.Controls.TextBlock
            $status.Height = 20
            $status.Background = "lightgray"
            $status.VerticalAlignment = "bottom"
            $status.HorizontalAlignment = "stretch"
            $status.Width = "Auto"

            $Grid.AddChild($status)

            $form.AddChild($Grid)

            $script:Now = Get-Date
            # define a timer to automatically dismiss the form. The timer uses a 1 second interval tick
            if ($Timeout -gt 0) {
                [int]$script:count = $Timeout
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                [datetime]$script:terminate = $now.AddSeconds($timeout)
                $timer.Interval = [TimeSpan]"0:0:1.00"

                $timer.add_tick( {

                        $ts = new-timespan -seconds $script:count
                        if ((Get-Date) -lt $script:terminate -AND $Refresh) {
                            $status.text = " Last updated $script:Now - refresh in $($ts.tostring())"
                            $script:count--
                        }
                        elseif ( (Get-Date) -lt $script:terminate) {

                            $status.text = " Last updated $script:Now - closing in $($ts.tostring())"
                            $script:count--
                        }
                        else {
                            $timer.stop()
                            if ($Refresh) {
                                $form.Title = "$Title ...refreshing content. Please wait."
                                [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                                $datagrid.itemssource = Invoke-Command -ScriptBlock $cmd

                                foreach ($col in $datagrid.Columns) {
                                    #because of the way I am loading data into the grid
                                    #it appears I need to set the sorting on each column
                                    $col.CanUserSort = $True
                                    $col.SortMemberPath = $col.Header
                                }
                                $script:count = $timeout
                                $script:now = Get-Date
                                [datetime]$script:terminate = $now.AddSeconds($timeout)
                                $ts = new-timespan -Seconds $script:count
                                $status.text = " Last updated $script:Now - refresh in $($ts.tostring()) seconds"
                                $Timer.Start()
                                $form.title = $Title
                                [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Arrow
                            }
                            else {
                                $form.close()
                            }
                        }
                    })
            }
            else {
                $status.text = " last updated $Script:Now"
            }

            $form.ShowDialog()
        }

        If ($UseProfile) {
            Write-Verbose "Loading user profiles"
            $profiles = $profile.AllUsersAllHosts, $profile.AllUsersCurrentHost,
            $profile.CurrentUserAllHosts, $profile.CurrentUserCurrentHost
            foreach ($file in $profiles) {
                if (Test-Path -path $file) {
                    $psCmd.AddScript($file) | Out-Null
                }
            }
        }
        if ($InitializationScript) {
            Write-Verbose "Loading an initialization scriptblock"
            $pscmd.AddScript($InitializationScript) | Out-Null
        }

        $pscmd.AddScript($gridScript) | Out-Null

        #initialize an array to hold all processed objects
        $data = @()
    } #begin

    Process {
        #add each incoming object to the data array
        if ($psCmdlet.ParameterSetName -eq 'Input') {
            $data += $Inputobject
        }
        else {
            Write-Verbose "Invoking scriptblock"
            $data = Invoke-Command -ScriptBlock $Scriptblock
        }
    } #process

    End {
        Write-Verbose "Updating PSBoundparameters"
        $PSBoundParameters.Data = $data
        $PSBoundParameters.remove("Inputobject") | Out-Null
        if ($PSBoundParameters.ContainsKey("UseProfile")) {
            $PSBoundParameters.Remove("UseProfile") | Out-Null
        }

        if ($psCmdlet.ParameterSetName -eq 'input') {

            #parse the invocation to get the pipelined expression up to this command
            #Write-verbose $($myinvocation | Out-string)
            Write-Verbose "Parsing $($myinvocation.line) into a scriptblock"
            Try {
                $cmd = [scriptblock]::Create($myinvocation.line.substring(0, $myinvocation.line.LastIndexOf("|")))
            }
            Catch {
                write-warning "Error created the cmd scriptblock: $($_.exception.message)"
                if ($Refresh) {
                    Write-Warning "Failed create an invocation scriptblock. In order to refresh run your pipelined expression as a single expression with no breaks."
                }
            }
        }
        else {
            $cmd = $Scriptblock
        }

        $psboundparameters.cmd = $cmd
        Write-Verbose "Refresh command: $cmd"

        Write-Verbose "Sending PSBoundparameters to runspace"

        $psCmd.AddParameters($PSBoundParameters) | Out-Null
        $psCmd.Runspace = $newRunspace
        Write-Verbose "Begin Invoke()"
        $psCmd.BeginInvoke() | Out-Null

        Write-Verbose "Ending $($MyInvocation.MyCommand)"

    } #end

} #close function