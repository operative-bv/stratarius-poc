-- T-009: named views over bridge_hierarchie per hiërarchie-flavor.
--
-- Per PDF Laag 1: "één benoemde view: statutair, business, geografisch,
-- kostenplaats". Elke view filtert bridge_hierarchie op z'n flavor en projecteert
-- de closure met org_unit context erbij zodat consumers geen extra joins hoeven.
--
-- SECURITY INVOKER (Postgres 15+ default) — RLS op bridge_hierarchie én
-- dim_org_unit fires automatisch bij view-queries met de rechten van de
-- aanroepende role. Expliciet vastgelegd via WITH (security_invoker = true)
-- als defense-in-depth tegen toekomstige Postgres-defaults veranderen.


create view public.view_hierarchie_statutair
    with (security_invoker = true) as
select
    bh.ancestor_org_unit_id,
    a.name as ancestor_name,
    a.kind as ancestor_kind,
    bh.descendant_org_unit_id,
    d.name as descendant_name,
    d.kind as descendant_kind,
    bh.afstamming
from public.bridge_hierarchie bh
join public.dim_org_unit a on a.org_unit_id = bh.ancestor_org_unit_id
join public.dim_org_unit d on d.org_unit_id = bh.descendant_org_unit_id
where bh.hierarchie_id = 'statutair';

comment on view public.view_hierarchie_statutair is
    'Statutaire hiërarchie: closure over dim_org_unit per PDF Laag 1. Juridische org-structuur (legale entiteit → BU → dept → team).';


create view public.view_hierarchie_business
    with (security_invoker = true) as
select
    bh.ancestor_org_unit_id,
    a.name as ancestor_name,
    a.kind as ancestor_kind,
    bh.descendant_org_unit_id,
    d.name as descendant_name,
    d.kind as descendant_kind,
    bh.afstamming
from public.bridge_hierarchie bh
join public.dim_org_unit a on a.org_unit_id = bh.ancestor_org_unit_id
join public.dim_org_unit d on d.org_unit_id = bh.descendant_org_unit_id
where bh.hierarchie_id = 'business';

comment on view public.view_hierarchie_business is
    'Business hiërarchie: closure over dim_org_unit per PDF Laag 1. Product/service-lines organisatie.';


create view public.view_hierarchie_geografisch
    with (security_invoker = true) as
select
    bh.ancestor_org_unit_id,
    a.name as ancestor_name,
    a.kind as ancestor_kind,
    bh.descendant_org_unit_id,
    d.name as descendant_name,
    d.kind as descendant_kind,
    bh.afstamming
from public.bridge_hierarchie bh
join public.dim_org_unit a on a.org_unit_id = bh.ancestor_org_unit_id
join public.dim_org_unit d on d.org_unit_id = bh.descendant_org_unit_id
where bh.hierarchie_id = 'geografisch';

comment on view public.view_hierarchie_geografisch is
    'Geografische hiërarchie: closure over dim_org_unit per PDF Laag 1. Regio/locatie-gebaseerde structuur.';


create view public.view_hierarchie_kostenplaats
    with (security_invoker = true) as
select
    bh.ancestor_org_unit_id,
    a.name as ancestor_name,
    a.kind as ancestor_kind,
    bh.descendant_org_unit_id,
    d.name as descendant_name,
    d.kind as descendant_kind,
    bh.afstamming
from public.bridge_hierarchie bh
join public.dim_org_unit a on a.org_unit_id = bh.ancestor_org_unit_id
join public.dim_org_unit d on d.org_unit_id = bh.descendant_org_unit_id
where bh.hierarchie_id = 'kostenplaats';

comment on view public.view_hierarchie_kostenplaats is
    'Kostenplaats hiërarchie: closure over dim_org_unit per PDF Laag 1. Cost-center topologie voor rapportage. Note: flavor ''kostenplaats'' distinct van dim_org_unit.kind=''kostenplaats'' (node-type).';
