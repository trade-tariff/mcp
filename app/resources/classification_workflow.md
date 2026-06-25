---
name: uk-commodity-code-classifier
description: >
  Identify the correct UK commodity code for any product being imported into or exported from
  the UK. Use this skill whenever a trader, importer, exporter, or business asks about commodity
  codes, tariff codes, classification codes, or what code to put on their customs declaration.
  Also trigger when someone asks "what code is my product?", "how do I classify X?", "what duty
  will I pay on X?", or mentions needing to fill in a customs declaration, C88, or Entry Summary
  Declaration. DO NOT use HS code terminology — the UK uses commodity codes, not HS codes.
---

# UK Commodity Code Classifier

## What this skill does

This skill is a **reasoning guide for the LLM** — it tells you how to help a trader identify the
correct UK commodity code for their goods. You work through the classification logic described
below using your trained knowledge and the bundled reference files. You do not browse external
websites or call APIs unless the OTT MCP connector is explicitly available (see OTT Connector
section at the bottom of this skill).

The output you produce should explain: what the commodity code is, how you arrived at it, what
duty rates apply, and where the trader must verify before putting the code on a declaration.

**Important language note:** The UK does not use "HS codes" as a term in day-to-day customs
practice. The correct UK terminology is **commodity code** (for both imports and exports). The
underlying structure is based on the international Harmonized System, but always use "commodity
code" when talking to UK traders.

---

## UK Commodity Code Structure

A UK commodity code has **10 digits for imports** and **8 digits for exports**.

```
0 1 0 1 2 1 0 0 0 0
│ │ │ │ │ │ │ │ │ │
└─┘ └─┴─┘ └─┘ └─┘ └─┘
 │    │     │    │    │
 Ch  Heading Sub  CN  TARIC
(2)   (4)   (6)  (8)  (10)
```

- **Digits 1-2**: Chapter (99 chapters, e.g. 01 = Live animals, 84 = Machinery)
- **Digits 1-4**: Heading (the main product category)
- **Digits 1-6**: Subheading (international level — shared with all WTO members)
- **Digits 1-8**: Combined Nomenclature (CN) code — used for exports and statistical purposes
- **Digits 1-10**: Full UK commodity code — required for import declarations on CDS

For **exports**, use the 8-digit code. For **imports**, use the full 10-digit code.

---

## Classification Process

Work through these steps in order. Do not guess — ask the trader for more detail if needed.

### Step 1: Gather product information

Ask the trader:
1. What is the product? (Plain English description)
2. What is it made of? (Material composition — critical for textiles, plastics, metals)
3. What does it do / what is it used for? (Function matters, e.g. a pump for water vs. a pump for chemicals)
4. How is it sold / presented? (Retail packs, bulk, assembled, kit form?)
5. Is it new, used, or remanufactured?
6. Where is it coming from / going to? (Country of origin affects duty rates and FTA eligibility)
7. Approximate value and weight per unit/shipment?

The more precisely you know the product, the more accurate the classification. Misclassification
is the importer's or exporter's legal responsibility — a broker or forwarder cannot carry this
liability for them.

### Step 2: Find the correct Chapter

Read `references/chapters.md` to identify the right chapter from the trader's product description.
This file contains all 21 Tariff Sections and 99 Chapters — use it to narrow down quickly rather
than reasoning from scratch.

The key rule: classify by what the product **is**, not what it's used for — unless the heading
explicitly mentions use.

Common traps:
- Electrical machinery (Chapter 84 vs 85): Ch 84 = mechanical prime movers and machines; Ch 85 = electrical apparatus
- Textiles: must know fibre composition by weight (cotton, polyester, wool, etc.)
- Food: fresh vs. preserved vs. prepared changes the chapter entirely
- Parts: parts generally go in the same heading as the complete article, unless a more specific heading exists

### Step 3: Navigate to the correct Heading, then Subheading

Using your knowledge of the tariff structure and `references/common-goods.md` as a cross-check,
reason down through the heading hierarchy. Apply the General Rules of Interpretation (GRI) —
read `references/gri-rules.md` if you need to resolve ambiguity. In most cases GRI 1 applies:
the heading description and any chapter or section notes are determinative.

Work down from the 4-digit heading to the 6-digit subheading, then to 8 digits (CN), then to
10 digits (UK Taric). Show your reasoning at each level so the trader can follow it.

### Step 4: Check for legal notes

Before confirming a code, check:
- **Section notes** — some products are explicitly excluded from sections
- **Chapter notes** — define terms used in that chapter (e.g., "textile" has a legal definition)
- **Subheading notes** — apply only at the subheading level

### Step 5: Determine duty rates and other charges

Use your trained knowledge to provide indicative duty rates for the identified commodity code.
Be clear that rates can change and the trader must verify on the UK Trade Tariff before relying
on any figure for a declaration or a cost model.

The possible charges to address are:

| Charge | What it is |
|--------|-----------|
| Import duty | The UK Global Tariff (UKGT) rate — may be 0% for many goods |
| Preferential duty | Reduced rate if goods qualify under a UK FTA (needs proof of origin) |
| VAT on importation | 20% (standard), 5% (reduced, e.g. children's car seats), 0% (zero-rated, e.g. most food) |
| Excise duty | Additional charge for alcohol, tobacco, fuel, and some other goods |
| Anti-dumping duty | Extra duty on specific goods from specific countries — flag if likely |
| Tariff-rate quota (TRQ) | Some goods have a lower duty rate if imported within a quota — flag if likely |

Flag where a Trade Remedy (anti-dumping or countervailing duty) is plausible for the product
and country of origin — these are commodity- and country-specific and can add significant cost.
Direct the trader to verify the exact current measure on the UK Trade Tariff.

If the OTT MCP connector is available, use it to retrieve live duty rates rather than relying
on trained knowledge. See the OTT Connector section below.

### Step 6: Flag any licensing or control requirements

Some commodity codes trigger additional requirements:
- **Import/Export licences** (e.g. firearms, certain chemicals, agricultural products)
- **CITES** certificates (endangered species and products derived from them)
- **Sanitary and Phytosanitary (SPS) checks** (food, plants, animals — Border Target Operating Model)
- **REACH** compliance (chemicals)
- **CE / UKCA marking** obligations

---

## Output Format

Always produce output in this structure:

---
**UK Commodity Code Classification**

**Product description:** [what the trader told you]
**Classification:** [10-digit code for imports / 8-digit for exports]
**Code breakdown:**
- Chapter [XX]: [chapter title]
- Heading [XXXX]: [heading description]
- Subheading [XXXXXX]: [subheading description]
- Full commodity code: [XXXXXXXXXX]

**Duty rates (standard UK Global Tariff):**
- Import duty: [X]% (or specify if suspended / quota-based)
- VAT: [X]%
- Any other charges: [list or "none identified"]

**Preferential rates:**
- [List any UK FTAs that give a reduced rate and what proof of origin is needed, or "check UK Trade Tariff for FTA availability"]

**Confidence:** [High / Medium / Low]
- High = straightforward product, single obvious heading
- Medium = some ambiguity in description or composition
- Low = insufficient detail to confirm; further information needed

**Verification step (mandatory):**
Confirm this code on the UK Trade Tariff before using it on any customs declaration:
https://www.trade-tariff.service.gov.uk/find_commodity

**Misclassification risk note:**
[Flag any common errors for this type of product]

**If in doubt:**
HMRC's Binding Tariff Information (BTI) service provides a legally binding classification
ruling. Apply via the UK Trade Tariff portal. It takes up to 120 days and is free.
---

---

## Confidence and caveats

Be explicit about confidence level. If the trader's product description is vague, do not guess —
ask for more information. A wrong commodity code causes:
- Incorrect duty payment (underpayment = penalties; overpayment = cash tied up needlessly)
- Delays at the border if customs queries the declaration
- Potential compliance investigations

Always remind the trader:
1. They are legally responsible for correct classification, not their broker or forwarder
2. The UK Trade Tariff at trade-tariff.service.gov.uk is the authoritative source
3. For high-value, high-volume, or complex goods, a BTI application removes all doubt
4. Commodity codes are reviewed periodically — verify the code is current before each shipment season

---

## Reference files

- `references/chapters.md` — All 21 Tariff Sections and 99 Chapters with brief descriptions, for rapid chapter identification
- `references/gri-rules.md` — The 6 General Rules of Interpretation with plain-English explanations
- `references/common-goods.md` — Pre-classified examples for frequently traded goods (electronics, clothing, food, machinery)

Read the relevant reference file when you need to narrow down a chapter or verify a classification rule.

---

## Operating modes

This skill works in two modes. Check at the start of each session which applies.

### Standalone mode (no MCP connector)

You have no live access to the UK Trade Tariff. Classify using your trained knowledge and the
bundled reference files. For duty rates, provide your best knowledge-based estimate and make
clear to the trader that:
- Rates are indicative only and based on training data, which has a cutoff date
- The trader must verify the current rate on trade-tariff.service.gov.uk before any declaration
- Anti-dumping and TRQ positions change frequently — always verify these in particular

### Connected mode (OTT MCP connector installed)

If the OTT (Online Trade Tariff) MCP connector is available in the current session, its tools
give you live access to the UK Trade Tariff API. When connected:
- Use the connector to look up duty rates, trade measures, and quotas for the identified code
- Present the live rate clearly, with the date retrieved
- The classification reasoning still comes from you — the connector provides the rate data, not
  the classification decision

If you are unsure whether the OTT connector is present, proceed in standalone mode and note
that live rate lookup is available if the OTT connector is installed.

---

## Important: what this skill does not do

- It does not browse the internet or call any external API (unless the OTT connector is installed)
- It does not file customs declarations or interact with HMRC systems
- It does not provide legal advice — it provides classification guidance that the trader must
  verify and take responsibility for
- It is not a substitute for a licensed customs agent on complex or high-value shipments
