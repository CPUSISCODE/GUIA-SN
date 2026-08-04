-- ============================================================
-- FAROL-GUIA — dados de referência da base fiscal unificada
-- Idempotente: pode ser reexecutado sobre um banco já populado.
-- Rode depois de schema.sql. Os 10.687 NCMs vêm de seed/ncm.json
-- (ver README.md).
-- ============================================================

insert into public.segmento_st (id, nome) values
  (0, 'Alimentícios'),
  (1, 'Autopeças'),
  (2, 'Barbear/depilar'),
  (3, 'Bebidas alcoólicas'),
  (4, 'Cigarros/fumo'),
  (5, 'Cimento'),
  (6, 'Combustíveis'),
  (7, 'Discos/mídias'),
  (8, 'Eletro'),
  (9, 'Energia elétrica'),
  (10, 'Farmácia/drogaria'),
  (11, 'Higiene/perfumaria'),
  (12, 'Lâmpadas'),
  (13, 'Material construção'),
  (14, 'Material elétrico'),
  (15, 'Material limpeza'),
  (16, 'Motos'),
  (17, 'Papelaria'),
  (18, 'Pneus'),
  (19, 'Rações pet'),
  (20, 'Refrigerantes/cervejas/águas'),
  (21, 'Sorvetes'),
  (22, 'Tintas'),
  (23, 'Veículos')
on conflict (id) do update set nome = excluded.nome;

insert into public.grupo_monofasico (id, nome) values
  (0, 'Autopeças'),
  (1, 'Bebidas frias'),
  (2, 'Biodiesel'),
  (3, 'Cigarros'),
  (4, 'Combustíveis'),
  (5, 'Farmacêuticos'),
  (6, 'Higiene bucal/escovas'),
  (7, 'Motocicletas'),
  (8, 'Perfumaria'),
  (9, 'Pneus'),
  (10, 'Veículos'),
  (11, 'Álcool')
on conflict (id) do update set nome = excluded.nome;
-- Cesta básica do Acre — Arts. 184-G e 184-H do RICMS/AC
insert into public.cesta_basica_ac (prefixo, nome, somente_producao_interna, excecao) values
  ('1006', 'Arroz', false, null),
  ('07133', 'Feijão', false, null),
  ('0201', 'Carne bovina', true, null),
  ('0202', 'Carne bovina congelada', true, null),
  ('0203', 'Carne suína', true, null),
  ('0204', 'Carne caprina/ovina', true, null),
  ('02061000', 'Miudezas bovinas', true, null),
  ('02062', 'Miudezas bovinas congeladas', true, null),
  ('02071100', 'Frango inteiro fresco', true, null),
  ('02071200', 'Frango inteiro congelado', true, null),
  ('040210', 'Leite em pó', false, null),
  ('04022110', 'Leite em pó integral', false, null),
  ('04022120', 'Leite em pó desnatado', false, null),
  ('19011010', 'Composto lácteo', false, null),
  ('19019090', 'Composto lácteo', false, null),
  ('1905', 'Pão, bolacha e biscoito', true, null),
  ('09012', 'Café', true, null),
  ('1701', 'Açúcar de cana comum', false, 'exclui confeiteiro, orgânico, demerara, mascavo e light'),
  ('11062000', 'Farinha de mandioca', true, null),
  ('15079011', 'Óleo de soja', false, null),
  ('04072100', 'Ovos de galinha', true, null),
  ('19021100', 'Macarrão espaguete', false, null),
  ('19021900', 'Macarrão espaguete', false, null),
  ('25010020', 'Sal de cozinha', false, null),
  ('0302', 'Peixes frescos', true, null),
  ('0303', 'Peixes congelados', true, null),
  ('07', 'Hortícolas in natura', false, null),
  ('08', 'Frutas in natura', false, null),
  ('0401', 'Lácteos', true, null),
  ('0402', 'Lácteos', true, null),
  ('0403', 'Lácteos', true, null),
  ('0404', 'Lácteos', true, null),
  ('0405', 'Lácteos', true, null),
  ('0406', 'Queijos', true, null),
  ('11010010', 'Farinha de trigo 25/50kg', false, null),
  ('19012000', 'Pré-mistura p/ pão francês', false, null),
  ('48202000', 'Caderno escolar', false, null),
  ('96081000', 'Caneta esferográfica', false, null),
  ('96091000', 'Lápis escolar', false, null),
  ('40169200', 'Borracha de apagar', false, null),
  ('30049045', 'Paracetamol', false, null)
on conflict (prefixo) do update set nome=excluded.nome, somente_producao_interna=excluded.somente_producao_interna, excecao=excluded.excecao;

-- Reforma Tributária — CST IBS/CBS + cClassTrib (IT 2025.002 / LC 214/2025)
insert into public.rt_regra (id, ordem, cst, cclasstrib, rotulo, ressalva) values
  (1, 1, '200', '200003', 'Cesta básica — alíquota zero (Anexo I, LC 214/2025)', 'o Anexo I tem exceções pontuais dentro dessas posições (ex.: foie gras, salmão, ovas, queijos finos importados) — se o produto for uma dessas exceções, usar 200034 (red. 60%) ou 000001.'),
  (2, 2, '200', '200014', 'Hortícolas, frutas e ovos — alíquota zero (Anexo XV)', 'vale para produtos in natura; se industrializado/processado, verificar enquadramento no Anexo VII (200034, red. 60%).'),
  (3, 3, '200', '200034', 'Alimentos p/ consumo humano — redução de 60% (Anexo VII)', 'conferir o NCM exato na lista do Anexo VII; itens fora dela vão para 000001.'),
  (4, 4, '200', '200035', 'Higiene pessoal e limpeza — redução de 60% (Anexo VIII)', null),
  (5, 5, '200', '200013', 'Absorventes/tampões higiênicos — alíquota zero', 'a posição 9619 também abriga fraldas — para fraldas o código é 200035 (higiene, red. 60%), não 200013.'),
  (6, 6, '200', '200032', 'Medicamentos c/ registro Anvisa — redução de 60%', 'se o princípio ativo constar na lista do Anexo XIV (LC 214/2025), o código passa a ser 200009 (alíquota zero); soros e vacinas usam 200053.'),
  (7, 7, '200', '200004', 'Dispositivos médicos — redução de 60% (Anexo XII)', 'confirmar presença do NCM no Anexo XII; fora dele, 000001.'),
  (8, 8, '410', '410008', 'Livros, jornais e periódicos — imunidade constitucional', null),
  (9, 9, '620', '620001', 'Combustíveis — tributação monofásica', null)
on conflict (id) do update set ordem=excluded.ordem, cst=excluded.cst, cclasstrib=excluded.cclasstrib, rotulo=excluded.rotulo, ressalva=excluded.ressalva;

insert into public.rt_regra_prefixo (regra_id, prefixo) values
  (1, '1006'),
  (1, '0401'),
  (1, '0402'),
  (1, '190110'),
  (1, '040510'),
  (1, '151710'),
  (1, '07133'),
  (1, '0901'),
  (1, '110620'),
  (1, '1903'),
  (1, '1101'),
  (1, '1102'),
  (1, '170114'),
  (1, '170199'),
  (1, '19021'),
  (1, '100590'),
  (1, '110412'),
  (1, '0201'),
  (1, '0202'),
  (1, '0203'),
  (1, '0204'),
  (1, '0206'),
  (1, '0207'),
  (1, '0209'),
  (1, '0210'),
  (1, '0302'),
  (1, '0303'),
  (1, '0304'),
  (1, '0406'),
  (1, '2501'),
  (1, '0903'),
  (2, '07'),
  (2, '08'),
  (2, '0407'),
  (3, '1507'),
  (3, '1508'),
  (3, '1512'),
  (3, '1514'),
  (3, '1515'),
  (3, '0403'),
  (3, '0409'),
  (3, '1103'),
  (3, '1108'),
  (3, '2002'),
  (3, '2009'),
  (3, '0306'),
  (3, '1902'),
  (4, '340111'),
  (4, '330610'),
  (4, '960321'),
  (4, '481810'),
  (4, '282890'),
  (4, '340119'),
  (5, '9619'),
  (6, '3003'),
  (6, '3004'),
  (7, '9018'),
  (7, '9019'),
  (7, '9021'),
  (7, '300510'),
  (7, '300590'),
  (7, '300610'),
  (8, '4901'),
  (8, '4902'),
  (8, '4903'),
  (8, '4904'),
  (8, '4905'),
  (9, '2710'),
  (9, '2711'),
  (9, '382600'),
  (9, '382700'),
  (9, '220710')
on conflict (regra_id, prefixo) do nothing;

-- Alíquota interestadual e antecipação por grupo de origem (destino: Acre)
insert into public.grupo_origem (grupo, aliq_interestadual, pct_antecipacao) values
  ('exterior',     4.00, 17.00),
  ('sul-sudeste',  7.00, 14.00),
  ('norte',       12.00,  9.00),
  ('nordeste',    12.00,  9.00),
  ('centro-oeste',12.00,  9.00),
  ('sudeste-es',  12.00,  9.00)
on conflict (grupo) do update set aliq_interestadual=excluded.aliq_interestadual, pct_antecipacao=excluded.pct_antecipacao;

insert into public.uf (sigla, nome, grupo) values
  ('AC', 'Acre', 'norte'),
  ('AL', 'Alagoas', 'nordeste'),
  ('AP', 'Amapá', 'norte'),
  ('AM', 'Amazonas', 'norte'),
  ('BA', 'Bahia', 'nordeste'),
  ('CE', 'Ceará', 'nordeste'),
  ('DF', 'Distrito Federal', 'centro-oeste'),
  ('ES', 'Espírito Santo', 'sudeste-es'),
  ('GO', 'Goiás', 'centro-oeste'),
  ('MA', 'Maranhão', 'nordeste'),
  ('MT', 'Mato Grosso', 'centro-oeste'),
  ('MS', 'Mato Grosso do Sul', 'centro-oeste'),
  ('MG', 'Minas Gerais', 'sul-sudeste'),
  ('PA', 'Pará', 'norte'),
  ('PB', 'Paraíba', 'nordeste'),
  ('PR', 'Paraná', 'sul-sudeste'),
  ('PE', 'Pernambuco', 'nordeste'),
  ('PI', 'Piauí', 'nordeste'),
  ('RJ', 'Rio de Janeiro', 'sul-sudeste'),
  ('RN', 'Rio Grande do Norte', 'nordeste'),
  ('RS', 'Rio Grande do Sul', 'sul-sudeste'),
  ('RO', 'Rondônia', 'norte'),
  ('RR', 'Roraima', 'norte'),
  ('SC', 'Santa Catarina', 'sul-sudeste'),
  ('SP', 'São Paulo', 'sul-sudeste'),
  ('SE', 'Sergipe', 'nordeste'),
  ('TO', 'Tocantins', 'norte'),
  ('EXT', 'Exterior (importado)', 'exterior')
on conflict (sigla) do update set nome=excluded.nome, grupo=excluded.grupo;

-- Constantes gerais
insert into public.parametro_fiscal (chave, valor, descricao) values
  ('ALIQ_INTERNA_AC', 19.0000, 'Alíquota interna geral do Acre (Art. 17, I, RICMS/AC), em %'),
  ('ALIQ_CESTA_AC',   17.0000, 'Alíquota interna da cesta básica do Acre (Arts. 184-G/184-H, RICMS/AC), em %'),
  ('RT_CBS_TESTE',     0.9000, 'CBS — alíquota de teste 2026 (regime normal), em %'),
  ('RT_IBS_TESTE',     0.1000, 'IBS — alíquota de teste 2026 (regime normal), em %')
on conflict (chave) do update set valor=excluded.valor, descricao=excluded.descricao;

-- Simples Nacional — Anexo I (Comércio), LC 123/2006
insert into public.sn_anexo_i_faixa (numero, teto, aliq_nominal, parcela_deduzir, pct_cofins, pct_pis, pct_icms) values
  (1, 180000, 4.00, 0, 12.74, 2.76, 34.00),
  (2, 360000, 7.30, 5940, 12.74, 2.76, 34.00),
  (3, 720000, 9.50, 13860, 12.74, 2.76, 33.50),
  (4, 1800000, 10.70, 22500, 12.74, 2.76, 33.50),
  (5, 3600000, 14.30, 87300, 12.74, 2.76, 33.50),
  (6, 4800000, 19.00, 378000, 28.27, 6.13, null)
on conflict (numero) do update set teto=excluded.teto, aliq_nominal=excluded.aliq_nominal, parcela_deduzir=excluded.parcela_deduzir, pct_cofins=excluded.pct_cofins, pct_pis=excluded.pct_pis, pct_icms=excluded.pct_icms;

-- Lucro Presumido
insert into public.lp_regime_pis_cofins (regime, pis, cofins, rotulo) values
  ('cumulativo',      0.65, 3.00, 'Cumulativo (0,65% + 3%)'),
  ('nao-cumulativo',  1.65, 7.60, 'Não cumulativo (1,65% + 7,6%)')
on conflict (regime) do update set pis=excluded.pis, cofins=excluded.cofins, rotulo=excluded.rotulo;

insert into public.lp_parametro (chave, valor, descricao) values
  ('IRPJ_PCT',            1.2000, 'IRPJ efetivo sobre a receita bruta no comércio (15% x 8% de presunção), em %'),
  ('CSLL_PCT',            1.0800, 'CSLL efetiva sobre a receita bruta no comércio (9% x 12% de presunção), em %'),
  ('PRESUNCAO_IRPJ',      8.0000, 'Base de presunção do IRPJ no comércio (Lei 9.249/1995, art. 15), em %'),
  ('PRESUNCAO_CSLL',     12.0000, 'Base de presunção da CSLL no comércio (Lei 9.249/1995, art. 20), em %'),
  ('IRPJ_ALIQUOTA',      15.0000, 'Alíquota do IRPJ sobre a base presumida, em %'),
  ('CSLL_ALIQUOTA',       9.0000, 'Alíquota da CSLL sobre a base presumida, em %'),
  ('IRPJ_ADICIONAL',     10.0000, 'Adicional de IRPJ sobre o excesso da base no trimestre, em %'),
  ('IRPJ_LIMITE_TRIM', 60000.0000, 'Limite trimestral da base presumida sem adicional de IRPJ, em R$')
on conflict (chave) do update set valor=excluded.valor, descricao=excluded.descricao;