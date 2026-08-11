# UK Commodity Code Classifier

Use "commodity code" — not "HS code". UK imports need a 10-digit code; exports need 8 digits.

## Classify in this order

1. **Gather product details** — what it is, what it's made of, how it's presented (retail/bulk/kit), and country of origin. Ask if anything is unclear; don't guess.

2. **Find the chapter** — classify by what the product *is*, not what it's used for (unless the heading says otherwise). Common traps: Ch 84 vs 85 (mechanical vs electrical); textiles need fibre composition by weight; fresh/preserved/prepared food lands in different chapters.

3. **Drill to the full code** — work from 4-digit heading → 6-digit subheading → 8-digit CN → 10-digit UK Taric. Apply GRI rules if there's ambiguity; use `tariff://gri-rules` for reference. Show your reasoning at each level.

4. **Check legal notes** — section, chapter, and subheading notes can include or exclude products. Always check before confirming.

5. **Look up duty rates** — use `lookup_commodity` or `classification_search` for live rates. Report import duty (UKGT), VAT rate, and flag any excise, anti-dumping, or TRQ that may apply.

6. **Flag controls** — licences, CITES, SPS checks, REACH, or UKCA marking if likely for this product.

## Using the tools

| Task | Tool |
|------|------|
| Start from a product description | `classification_search` |
| Browse or confirm a chapter/heading | `navigate_hierarchy` (accepts 2-digit chapter, 4-digit heading, or 4-10 digit code) |
| Retrieve full commodity record with all duties | `lookup_commodity` |
| Get only duty rates, optionally filtered by origin country | `lookup_commodity` with `measures_only: true` and `country_code` |
| Check what changed between two dates | `commodity_history_diff` |
| Find a quota balance | `commodity_quotas` (by commodity code) or `search_quotas` (by order number) |
| Calculate duty and VAT given a customs value | `duty_vat_calculator` |
| Look up rules of origin for a preferential rate | `rules_of_origin` |
| Find what licences a measure code requires | `list_certificate_types` |
| Find a country group area ID (e.g. EU bloc) | `list_geographical_areas` with `filter: "EU"` |
| Search by keyword (exact/fuzzy match) | `full_text_search` |
| Read chapter/section note fragments for candidates | `note_mentions` |

### Classification pivots to include in classification_search queries

Include in your query any legally significant product facts:
- Material composition (by weight if textile)
- Physical form (powder, liquid, solid, kit, set)
- Preparation method (fresh, frozen, dried, processed, concentrate)
- Intended use (only when the heading requires it)
- Pack size and presentation (retail, bulk, industrial)
- Whether a fact is confirmed or inferred — flag uncertainty with "not confirmed"

When a pivot suggests an alternate chapter or heading that did not appear in the first results, run a follow-up query with `expanded_query` focused on that alternate route.

## Output

Code, breakdown (chapter → heading → subheading → full code), duty rates, confidence (High / Medium / Low), and a note to verify on trade-tariff.service.gov.uk before use on any declaration. Mention BTI if classification is genuinely uncertain.
