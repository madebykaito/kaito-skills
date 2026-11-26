# Money CLI

Run `node <store>/business/scripts/kaito-money.mjs`, where `<store>` is the checkout or `$KAITO_HOME/store` after setup. Every command takes `--owner <id>` and returns JSON. Run `--help` for the full interface.

## Owner settings and input

In `$KAITO_HOME/owners/<id>/money.json` set the business address and, for exports, `"export_mode": "lut"` or `"export_mode": "igst-paid"`. Set a billing label such as `"billing": "billing@example.test"` in `owner.json` under `channels`. `propose --account` names that channel value. The issuer's name, GSTIN and INR currency come from `owner.json`. An owner without a GSTIN issues a plain domestic invoice.

Provide a JSON file for `draft invoice|quote --input <file>` and `revise <id> --input <file>`.

```json
{
  "client": {
    "name": "Example Buyer",
    "address": "10 Example Road, Kolkata",
    "state_code": "19",
    "country": "IN",
    "email": "buyer@example.test"
  },
  "due_date": "2027-02-15",
  "lines": [
    {
      "description": "Loose tea",
      "quantity": "1.5",
      "unit": "kg",
      "unit_paise": 103,
      "hsn_sac": "0902",
      "gst_bps": 1800
    }
  ]
}
```

The client GSTIN, client email and document `terms` are optional. An invoice needs a due date. An Indian buyer needs a two-digit GST state code. For a foreign buyer provide the country code and foreign address. Registered owners supply a 4, 6 or 8 digit HSN/SAC and integer rate basis points per line. `unit_paise` is the net unit price before GST. Quantities are positive decimal strings with up to six fractional places. The renderer takes only the named public fields. Review the description and terms as client copy.

## Tax and rounding

Domestic place of supply uses the buyer state code. Same-state supplies use equal CGST and SGST components, or CGST and UTGST for union territories subject to UTGST. Different states use IGST. Exports are zero-rated. The owner chooses LUT with IGST shown as nil, or an IGST-paid endorsement with the supplied rate. This workflow covers transactions where the buyer state determines place of supply. Confirm rate, export eligibility, any separate delivery address and statutory extras such as reverse charge or e-invoicing before using it for a live invoice. [CBIC invoice rules](https://cbic-gst.gov.in/gst-invoice-rules.html)

Money uses exact integer arithmetic. Multiply unit paise by the quantity and round half up to a paise per line. Apply the full rate for IGST or half the rate to each CGST and SGST/UTGST component and round each separately, half up. Add rounded amounts across lines. The example has net 155 paise, CGST 14 and SGST 14, for 183 paise in total. INR output displays two decimals.

## Issue and revision

- `check <id> [--html <path>] [--pdf <path>]` reports totals and can render a draft preview. PDF printing needs Chromium, Chrome or Brave. Set `KAITO_MONEY_CHROME` to the executable when auto-detection misses it.
- `revise <id> --input <file>` saves a new immutable revision and retires pending approvals on the previous revision. `credit <issued-invoice-id> --reason <text>` drafts a full reversal using the original tax and amounts. The issued original stays in the ledger. Refund settlement is separate from the credit note.
- `propose <id> --account <channel> [--pdf]` puts the candidate HTML, and optionally PDF, in the ledger's artifact store. Open both client artifacts listed under `media` in `kaito-ledger.mjs status <ref> --json` before approval. Copy to a private temporary file with the matching extension if the viewer needs one. `kaito-approve.mjs <ref> --show` prints the approval card. Use the founder's normal approval path.
- `issue <id> --ref <ref> --digest <full-sha256>` claims the action, allocates the series number, and records success in one SQLite transaction. The Indian financial year starts on April 1 in IST. Each owner has an independent invoice series such as `INV-2026-000001`. Quotes and credit notes use their own series. Drafts and proposals consume zero numbers. An issue at a new date or behind another issue for the same series needs a fresh proposal and approval. Repeating a committed issue with the original ref and digest returns its receipt.
- `export <issued-id> [--html <path>] [--pdf <path>]` copies the verified approved bytes to new files. PDF export requires PDF approval at proposal time.

## Collections

`aging [--as-of <date>]` lists unpaid balances due on or before that date in the owner's timezone. Buckets are 0–30, 31–60, 61–90 and over 90 days. `aging --sync` adds a Today item for each collectible invoice once. Run it as part of the collections routine. Full payment or an issued full credit note closes its open item. If an item is closed manually, sync respects that decision.

`payment <id> --paise <integer> --reference <receipt-id>` records a confirmed receipt, including partial payments. Reusing the same receipt ID and amount on that invoice is safe.

`chase <id>` returns `to`, `subject` and `body` for the current balance. Save the body to a private file, recheck the balance, then propose the reviewed fields in [email-send](../../email-send/SKILL.md).

```sh
node "$B/kaito-email.mjs" propose --owner "$OWNER" --to "$TO" --subject "$SUBJECT" --body-file "$BODY_FILE"
```

Show the email approval card and use the standard email-send approval and delivery flow.
