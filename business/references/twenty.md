# Twenty CRM

Use the [local Compose template](../engines/twenty/README.md) or set `TWENTY_URL` to your Twenty server URL. The default is `http://127.0.0.1:3319`. A remote server needs HTTPS and the owner's `cloud_ok` consent.

In Twenty, create a custom object with singular API name `kaitoLead` and plural API name `kaitoLeads`. Use the built-in text `name` and add four Text fields with API names `email`, `company`, `stage` and `kaitoOwner`. Assign the owner ID to records you want to import. Set stage to `qualify`, `outreach`, `review` or `retro`. Use a role that can read, create and update this object. Save the API token in a private text file and set `keys.twenty` in that owner's `owner.json` to the file path.

```sh
node business/scripts/kaito-twenty.mjs sync --owner lumen-tea
node business/scripts/kaito-twenty.mjs sync --owner lumen-tea --apply
```

The first command previews counts. Apply creates missing leads and updates the four lead fields in the same ledger that sales uses. It matches initial records by owner and normalized email, then follows the stable Twenty ID. Each changed field is compared with its last synced value. If both sides edited the same field differently, the newer record timestamp wins and the choice goes to the local `twenty_conflicts` table. A tie keeps the ledger value. The shadow and conflict log contain lead data and stay in the owner-scoped ledger.

A missing linked record is reported as `missing`. Review deletions and owner changes in Twenty before restoring or relinking records. Sync leaves deletions and sales notes out of the transfer.

If a lead's address was reassigned, sync frees the old address before assigning it to another lead. For an email swap, give one lead a temporary unused address, sync, then set the final addresses. A recorded conflict preserves the observed values and decision even if a remote response is lost. Run sync again to converge after an interrupted request.

See [Twenty's workspace REST API](https://github.com/twentyhq/twenty/blob/main/packages/twenty-docs/developers/extend/api.mdx).
