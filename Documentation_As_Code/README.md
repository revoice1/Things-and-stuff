# Documentation as Code

## Publish-PSTableToConfluence

This is a custom function that allows users to publish the content of a powershell table-like object (array, psCustomObject, etc..) to a table in an existing confluence page.

This function can update Confluence tables in the following sceneries:

1. Complete page update
   - The only data on the page will be the table published by the automation
   - Example: `Publish-PSTableToConfluence -PageID $PageID -ConfluenceServerName $ConfluenceServerName -Credential $ConfluenceCreds -PSTable $DomainControllerInfo -IncludeFooter`
2. Replace content of existing table within section
   - This will replace the content of a table that already exists on a confluence page under a specific heading
   - If there are more than one tables under the specified heading the first table will always be updated
   - If there are no tables under the specified heading, the script will traverse to the end of the page and replace the next table it finds
   - Use a blank placeholder table for initial populating
   - Example: `Publish-PSTableToConfluence -PageID $PageID -ConfluenceServerName $ConfluenceServerName -Credential $ConfluenceCreds -PSTable $DomainControllerInfo -IncludeFooter -SectionHeader "Prod Domain Controller List"`
