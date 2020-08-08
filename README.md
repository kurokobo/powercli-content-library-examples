# Import ISO files to Content Library from Datastore

Currently, the supported ways that can be imported into the Content Library are only Local Files or HTTP. There is no feature to import files directly from the datastore.

This repository contains some helpful information to solve this problem.


## Environment

| Product | Version|
|-|-|
| PowerShell | 5.1 |
| PowerCLI | 12.0 |
| vCenter Server | 7.0 |
| vSphere ESXi | 7.0 |


## Architecture

By default, all contents on the datastore are exposed via HTTP via the vSphere Web Services API.

Therefore, every file on the datastore can be located by its unique URL.
By specifying this URL, any files can be imported into the Content Library without having to go through the local computer.

The only thing to do is to embed your credentials in the URL to pass the BASIC authentication.


## Notice and Disclaimer

The username and password must be contained as plain text in the URL.

For security reasons, it is recommended that we create a temporary user to work with, as the username and password may be recorded in some log files.


## Import ISO files using PowerCLI

The `Import-ContentLibraryItemFromDatastore.ps1` file in this repository contains a function `Import-ContentLibraryItemFromDatastore` for this purpose.

```powershell
> Import-ContentLibraryItemFromDatastore -Username temporary-user-01@vsphere.local -Password my-password -Item vmstore:\sandbox-dc01\sandbox-ds01\ISO -DestinationLibraryName "ISO Images"

Creating Sample_ISO_File.iso ...
Creating Update Session for Sample_ISO_File.iso ...
Pulling File Sample_ISO_File.iso from Datastore ...
  Waiting for Transfer ...
  Transferring ... 29570480 of 367654912 bytes
  Transferring ... 91598704 of 367654912 bytes
  Transferring ... 154513184 of 367654912 bytes
  Transferring ... 215776424 of 367654912 bytes
  Transferring ... 271944344 of 367654912 bytes
  Transferring ... 322272864 of 367654912 bytes
  Completed.
Completing the Session ...
  Waiting for Complete ...
  Completed.
Deleting the Session ...
```


## Achieve in manually

Identify the URL of the file on our datastore that we want to import into the Content Library.

We can access the following URL to locate the file through your browser.

* `https://<vcenter-server>/folder`

For example, an unique URL for an ISO file may be formatted as:

* `https://<vcenter-server>/folder/<PATH/TO/DIRECTORY>/<FILE>?dcPath=<datacenter>&dsName=<datastore>`

So the actual URL is:

* `https://sandbox-vc01.sandbox.lab/folder/ISO/Sample_ISO_File.iso?dcPath=sandbox-dc01&dsName=sandbox-ds01`

Then add our credentials into this URL as follows:

* `https://<username>:<password>@<vcenter-server>/folder/<PATH/TO/DIRECTORY>/<FILE>?dcPath=<datacenter>&dsName=<datastore>`

If the username or password contains `@`, we have to replace `@` with `%40` like this:

* `https://temporary-user-01%40vsphere.local:my-password@sandbox-vc01.sandbox.lab/folder/ISO/Sample_ISO_File.iso?dcPath=sandbox-dc01&dsName=sandbox-ds01`

This is the URL that can be used as an import source. 
Now we can import any files on your datastore directly by specifying this URL as the import source for our Content Library.

Even as the file imported, the source files remain on the datastore. We can delete the source file if required.


## Alternative way (I tried but not works...)

Referring to the [API reference](https://developer.vmware.com/docs/vsphere-automation/latest/content/data-structures/Library/Item/TransferEndpoint/), there is a way to specify the URI on the datastore directory by using `ds://` scheme, 

However, in my environment, this doesn't work. Once the file transferred from datastore, its size displayed as 4 KB and cannot be fixed.

For this reason, I had to implement the way I described above, although it is not secure.
