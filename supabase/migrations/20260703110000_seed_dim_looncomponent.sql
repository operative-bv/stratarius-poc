-- T-012: seed dim_looncomponent voor 12 canonieke Belgische loonvormen.
--
-- KRITISCH: bedrijfswagen levert TWEE aparte componenten met OPPOSITE
-- is_werkgeverskost (VAA-valkuil per PDF Laag 2):
--   bedrijfswagen_vaa = fiscale waardering werknemer, GEEN werkgeverskost
--   bedrijfswagen_tco = Total Cost of Ownership, ECHTE werkgeverskost
--
-- Seeds zijn VOORBEELDEN van gedragstags per Principe II — rekencascade
-- leest tags via fact_looncomponent → dim_looncomponent join, NOOIT via
-- component_id switching. Nieuwe componenten (cafetariaplan, warrants,
-- etc.) toevoegen = SQL insert, geen code-wijziging.
--
-- Bron: PDF Laag 2 loonvormen-tabel + RSZ instructiegids.


insert into public.dim_looncomponent (component_id, name, familie, rsz_plichtig, is_werkgeverskost, telt_voor_vakantiegeld, sz_behandeling_id, telt_voor_mu, bron_url) values
    ('basisloon', 'Basisloon', 'basisloon', true, true, true, 'normaal', true, 'https://www.socialsecurity.be/employer/instructions/'),
    ('premie_maandelijks', 'Maandelijkse premie', 'premie', true, true, true, 'normaal', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('eindejaarspremie', 'Eindejaarspremie', 'premie', true, true, true, 'normaal', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('bedrijfswagen_vaa', 'Bedrijfswagen — Voordeel in Natura (VAA)', 'bedrijfswagen', false, false, false, 'vrijgesteld', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('bedrijfswagen_tco', 'Bedrijfswagen — Total Cost of Ownership', 'bedrijfswagen', false, true, false, 'vrijgesteld', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('co2_solidariteitsbijdrage', 'CO2-solidariteitsbijdrage bedrijfswagen', 'bedrijfswagen', false, true, false, 'vin_bijzondere_formule', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('gsm_prive', 'Privé-gebruik GSM/PC', 'extralegaal', true, true, false, 'vin_forfaitair', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('groepsverzekering', 'Groepsverzekering', 'extralegaal', false, true, false, 'vrijgesteld', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('ecocheques', 'Ecocheques', 'extralegaal', false, true, false, 'vrijgesteld', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('mobiliteitsbudget', 'Mobiliteitsbudget', 'extralegaal', false, true, false, 'vrijgesteld', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('maaltijdcheques', 'Maaltijdcheques', 'extralegaal', false, true, false, 'vrijgesteld', false, 'https://www.socialsecurity.be/employer/instructions/'),
    ('overloon_50', 'Overloon 50%', 'overuren', true, true, true, 'normaal', true, 'https://www.socialsecurity.be/employer/instructions/')
on conflict (component_id) do nothing;
