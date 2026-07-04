# Handover — Phase 3 4/5 done (T-010, T-011, T-013, T-014)

**Session**: f05acd52 (targeted auto, 4 tickets)
**Commits**: d6e9be2 (T-010), 9c4ffa2 (T-011), 78b6a63 (T-013), 3b2f34b (T-014)

## Wat is er gebeurd

**T-010** dim_sz_behandeling: 5 canonieke SZ-regimes (normaal, VIN forfaitair, VIN bijzondere formule, vrijgesteld, gunstregime met cap) met grondslag_type enum + cap_param_plafond_id forward-ref naar T-015. Ook T-015 description updated met ALTER TABLE ADD CONSTRAINT obligation.

**T-011** dim_looncomponent: schema-only met 4 boolean gedragstags (rsz_plichtig, is_werkgeverskost, telt_voor_vakantiegeld, telt_voor_mu) NOT NULL zonder default. FK naar dim_sz_behandeling. Geen seed — T-012 (nu unblocked) doet dat inclusief VAA-valkuil test.

**T-013** dim_prestatiecode: 12 canonieke codes met kritische Principe IV invariant op tijdelijke_urenvermindering (telt_voor_mu=false). **Principe II violation ontdekt en gefixt in R1 review**: overuren_50 vs overuren_100 differde alleen op naam — toegevoegd toeslag_pct numeric(4,2) behavioral tag zodat cascade leest via kolom, niet via prestatiecode identity.

**T-014** dim_scenario: uuid PK, tenant-scoped via legale_entiteit transitive tenant (T-006 pattern), kind enum (actual/what_if/forecast/baseline). Prepares Phase 5 fact-tables voor multiple scenarios per contract×periode.

## Belangrijke ontdekkingen

1. **Principe II live catch (T-013 F2)**: reviewer ving name-based switching op overuren—klassieke Principe II violation. `toeslag_pct` als behavioral tag lost het op. Deze soort issue is precies waarom Constitution v1.0.1 explicit was over 'no if component_id == X in cascade'.

2. **Forward-ref pattern werkt**: dim_sz_behandeling.cap_param_plafond_id verwijst naar param_plafond dat pas in T-015 wordt aangemaakt. Text-NULL kolom + inline SQL comment + T-015 ticket description update = clean forward-reference. ALTER TABLE ADD CONSTRAINT komt bij T-015 aan.

3. **col_type_is + col_not_null combo** voor booleans (T-011/T-013) verhindert schema-drift naar text/int als toekomstige migration typing verandert.

## Volgende stappen

**Phase 3 4/5 done — alleen T-012 rest** (dim_looncomponent seed + VAA-valkuil test, nu unblocked door T-011).

✅ T-010 dim_sz_behandeling
✅ T-011 dim_looncomponent schema
⏬ T-012 dim_looncomponent seed + VAA-valkuil test — unblocked
✅ T-013 dim_prestatiecode
✅ T-014 dim_scenario

**Recommended next**: `/story auto T-012` — sluit Phase 3 (Componenten & SZ). Klein ticket, VAA-valkuil test is kritisch (bedrijfswagen VAA is_werkgeverskost=false vs TCO=true).

Daarna Phase 4 parameter-layer. **HERINNERING**: bij T-015 (param_rsz + param_plafond) moet de ALTER TABLE dim_sz_behandeling ADD CONSTRAINT dim_sz_behandeling_cap_fk statement toegevoegd — T-015 description bijgewerkt in T-010 sessie.

**Phase 4-5 hebben Constitution Principe V TDD requirement**. Vanaf T-015 mogelijk overwegen om speckit-flow te gebruiken i.p.v. storybloq auto—zeker voor T-026+ rekencascade tickets waar test-first echt niet-onderhandelbaar is.

## Cijfers

4 tickets in 1 sessie, gemiddeld 6-8min per ticket. T-013 had R1 revise (Principe II fix), rest first-round approve. Alle 4 tickets committed en gepushed lokaal (nog niet naar GitHub deze sessie — user kan push doen).