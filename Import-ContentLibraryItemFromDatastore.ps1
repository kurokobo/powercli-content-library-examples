Function Import-ContentLibraryItemFromDatastore {
    param(
        [Parameter(Mandatory = $true)][String]$Username,
        [Parameter(Mandatory = $true)][String]$Password,
        [Parameter(Mandatory = $true)][String]$Item,
        [Parameter(Mandatory = $true)][String]$DestinationLibraryName,
        [Switch]$Recurse = $false
    )

    $destinationLibrary = Get-ContentLibrary -Name $DestinationLibraryName
    if ($null -eq $destinationLibrary) {
        Write-Host -ForegroundColor Red "Unable to find Content Library named $DestinationLibraryName"
        break
    }
    $destinationLibraryId = $destinationLibrary.Id

    $datastoreItems = Get-ChildItem "$Item" -Recurse:$Recurse | Where-Object { "IsoImageFile" -eq $_.ItemType }
    if (@($datastoreItems).Length -eq 0) {
        Write-Host -ForegroundColor Red "Unable to find ISO files in the specified path $Item"
        break
    }
    
    foreach ($datastoreItem in $datastoreItems) {

        $uri = "https://"
        $uri += [uri]::EscapeDataString($Username) + ":" + [uri]::EscapeDataString($Password) + "@"
        $uri += $datastoreItem.FullName -Replace "vmstores:\\(.+?)@(.+?)\\(.+?)\\.*", '$1:$2/folder/'
        $uri += $datastoreItem.FolderPath -Replace "^\[.+\] (.*)", '$1/'
        $uri += $datastoreItem.Name
        $uri += $datastoreItem.FullName -Replace "vmstores:\\(.+?)\\(.+?)\\.*", '?dcPath=$2'
        $uri += $datastoreItem.FolderPath -Replace "^\[(.+?)\] .*", '&dsName=$1'

        # Create New Item
        $UniqueChangeId = [guid]::NewGuid().tostring()
        $contentLibraryItemService = Get-CisService com.vmware.content.library.item
        $createItemSpec = $contentLibraryItemService.Help.create.create_spec.Create()
        $createItemSpec.library_id = $destinationLibraryId
        $createItemSpec.name = [System.IO.Path]::GetFileNameWithoutExtension($datastoreItem.Name)
        $createItemSpec.size = $datastoreItem.Length

        try {
            Write-Host -ForegroundColor Cyan "Creating" $datastoreItem.Name "..."
            $createItemResult = $contentLibraryItemService.create($UniqueChangeId, $createItemSpec)
        }
        catch {
            Write-Host -ForegroundColor Red "Failed to create" $datastoreItem.Name
            $Error[0]
            break
        }

        # Create Update Session
        $UniqueChangeId = [guid]::NewGuid().tostring()
        $contentLibraryItemUpdateSessionService = Get-CisService com.vmware.content.library.item.update_session

        $createSessionSpec = $contentLibraryItemUpdateSessionService.Help.create.create_spec.Create()
        $createSessionSpec.library_item_id = $createItemResult.Value

        try {
            Write-Host -ForegroundColor Cyan "Creating Update Session for" $datastoreItem.Name "..."
            $createSessionResult = $contentLibraryItemUpdateSessionService.create($UniqueChangeId, $createSessionSpec)
        }
        catch {
            Write-Host -ForegroundColor Red "Failed to create update session for" $datastoreItem.Name
            $Error[0]
            break
        }

        # Add File
        $contentLibraryItemUpdateSessionFileService = Get-CisService com.vmware.content.library.item.updatesession.file
        $fileSpec = $contentLibraryItemUpdateSessionFileService.Help.add.file_spec.Create()
        $fileSpec.name = $datastoreItem.Name
        $fileSpec.source_type = "PULL"
        # Referring to the document, the format of the datastore URI "ds:///vmfs/volumes/uuid/path" is supported but does not work correctly.
        # Once the file transferred from datastore, its size displayed as 4 KB and cannot be fixed.
        # $fileSpec.source_endpoint.uri = "ds:///vmfs/volumes/uuid/path"
        $fileSpec.source_endpoint.uri = $uri
        $fileSpec.size = $datastoreItem.Length
        $updateSessionId = $createSessionResult.Value
        
        try {
            Write-Host -ForegroundColor Cyan "Pulling File" $datastoreItem.Name "from Datastore ..."
            $addResult = $contentLibraryItemUpdateSessionFileService.add($updateSessionId, $fileSpec)
        }
        catch {
            Write-Host -ForegroundColor Red "Failed to pull" $datastoreItem.Name
            $Error[0]
            break
        }

        while ($true) {
            $null = $contentLibraryItemUpdateSessionService.keep_alive($updateSessionId)
            $currentFileStatus = $contentLibraryItemUpdateSessionFileService.list($updateSessionId)

            if ("WAITING_FOR_TRANSFER" -eq $currentFileStatus.status) {
                Write-Host -ForegroundColor DarkGray "  Waiting for Transfer ..."
            }
            elseif ("TRANSFERRING" -eq $currentFileStatus.status) {
                Write-Host -ForegroundColor DarkGray "  Transferring ..." $currentFileStatus.bytes_transferred "of" $currentFileStatus.size "bytes"
            }
            elseif ("VALIDATING" -eq $currentFileStatus.status) {
                Write-Host -ForegroundColor DarkGray "  Validating ..."
            }
            elseif ("READY" -eq $currentFileStatus.status) {
                Write-Host -ForegroundColor DarkGray "  Completed."
                break;
            }
            else {
                Write-Host -ForegroundColor Red "Failed to transfer" $datastoreItem.Name
                $Error[0]
                break
            }
            Start-Sleep -Seconds 1
        }

        # Complete and Delete Update Session
        try {
            Write-Host -ForegroundColor Cyan "Completing the Session ..."
            $completeResult = $contentLibraryItemUpdateSessionService.complete($updateSessionId)
        }
        catch {
            Write-Host -ForegroundColor Red "Failed to complete session"
            $Error[0]
            break
        }

        while ($true) {
            $currentSessionStatus = $contentLibraryItemUpdateSessionService.get($updateSessionId)
            if ("ACTIVE" -eq $currentSessionStatus.state) {
                Write-Host -ForegroundColor DarkGray "  Waiting for Complete ..."
            }
            elseif ("DONE" -eq $currentSessionStatus.state) {
                Write-Host -ForegroundColor DarkGray "  Completed."
                break;
            }
            else {
                Write-Host -ForegroundColor Red "Failed to complete session"
                $Error[0]
                break
            }
            Start-Sleep -Seconds 1
        }
        
        try {
            Write-Host -ForegroundColor Cyan "Deleting the Session ..."
            $deleteResult = $contentLibraryItemUpdateSessionService.delete($updateSessionId)
        }
        catch {
            Write-Host -ForegroundColor Red "Failed to delete session"
            $Error[0]
            break
        }
    }
}
